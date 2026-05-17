import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:ble_test/ble_advertiser.dart';
import 'package:ble_test/chunked_transfer_manager.dart';
import 'package:ble_test/data/found_device.dart';
import 'package:ble_test/data/isar_service.dart';
import 'package:ble_test/data/mesh_packet.dart';
import 'package:ble_test/mesh_packet_encoder.dart';
import 'package:ble_test/message_handler.dart';
import 'package:ble_test/profile_manager.dart';
import 'package:ble_test/utils/constants.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:isar_community/isar.dart';
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BLEDiscoverer {
  static final BLEDiscoverer _instance = BLEDiscoverer._internal();
  factory BLEDiscoverer() => _instance;
  BLEDiscoverer._internal();

  final Logger _log = Logger('BLEDiscoverer');
  final Map<int, BluetoothDevice> _syncQueue = {};
  final Map<int, DateTime> _lastSyncAttempt = {};
  
  bool _isScanOperationInProgress = false;
  DateTime? _lastScanStartTime;
  DateTime? _lastCycleFinishedTime;
  Timer? _discoveryTimer;
  Duration _currentWaitDuration = Duration(seconds: MessageHandler.waitDurationSeconds);

  bool get isScanOperationInProgress => _isScanOperationInProgress;
  DateTime? get lastScanStartTime => _lastScanStartTime;

  void start(ServiceInstance service, IsarService isar, int myStableId) {
    _log.info('Discovery Engine started');
    
    // Listen for scan results
    FlutterBluePlus.scanResults.listen((results) async {
      if (!isar.isOpen) return;
      
      // Safety: Inbound active, pause scan processing
      if (BLEAdvertiser.hasInboundConnections && FlutterBluePlus.isScanningNow) {
        _log.info('Inbound active, pausing scan processing');
        FlutterBluePlus.stopScan();
        return;
      }

      await _processScanResults(
        results: results,
        isar: isar,
        myStableId: myStableId,
      );
    });

    _runDiscoveryCycle(service, isar, myStableId);

    // Progress Reporting Timer
    Timer.periodic(const Duration(milliseconds: 500), (t) {
      final now = DateTime.now();

      if (FlutterBluePlus.isScanningNow) {
        if (_lastScanStartTime == null) return;
        final elapsed = now.difference(_lastScanStartTime!);
        final scanDuration = Duration(seconds: MessageHandler.scanDurationSeconds);
        service.invoke('updateProgress', {
          'value': (elapsed.inMilliseconds / scanDuration.inMilliseconds).clamp(0.0, 1.0),
        });
      } else if (_isScanOperationInProgress) {
        service.invoke('updateProgress', {
          'value': 1.0,
          'status': 'Fetching Metadata...',
        });
      } else {
        if (_lastCycleFinishedTime == null) return;
        final waitElapsed = now.difference(_lastCycleFinishedTime!);
        final rem = _currentWaitDuration.inMilliseconds - waitElapsed.inMilliseconds;
        service.invoke('updateProgress', {
          'value': (rem / _currentWaitDuration.inMilliseconds).clamp(0.0, 1.0),
          'remainingSeconds': (rem / 1000).ceil().clamp(0, 60),
        });
      }
    });
  }

  void stop() {
    _discoveryTimer?.cancel();
    _isScanOperationInProgress = false;
  }

  Future<void> _processScanResults({
    required List<ScanResult> results,
    required IsarService isar,
    required int myStableId,
  }) async {
    for (final r in results) {
      final meshDataRaw = r.advertisementData.manufacturerData[MeshConstants.manufacturerId] ??
          r.advertisementData.manufacturerData[0xFFFF];
      
      if (meshDataRaw == null || meshDataRaw.length < 5) continue;
      final meshData = Uint8List.fromList(meshDataRaw);
      int? stableId, versionTag;
      String? profileHash;
      double? lat, lon;

      // Extract metadata from advertisement
      if (meshData.length == 5) {
        final bd = ByteData.view(meshData.buffer);
        stableId = bd.getUint32(0, Endian.big);
        versionTag = (meshData[4] >> 2) & 0x3F;
      } else if (meshData.length == 12) {
        lat = MeshPacketEncoder.decodeCoordinate(
          (meshData[0] << 16) | (meshData[1] << 8) | meshData[2], true);
        lon = MeshPacketEncoder.decodeCoordinate(
          (meshData[3] << 16) | (meshData[4] << 8) | meshData[5], false);
        profileHash = meshData.sublist(6, 12).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      } else if (meshData.length >= 17) {
        final bd = ByteData.view(meshData.buffer);
        stableId = bd.getUint32(0, Endian.big);
        versionTag = (meshData[4] >> 2) & 0x3F;
        lat = MeshPacketEncoder.decodeCoordinate(
          (meshData[5] << 16) | (meshData[6] << 8) | meshData[7], true);
        lon = MeshPacketEncoder.decodeCoordinate(
          (meshData[8] << 16) | (meshData[9] << 8) | meshData[10], false);
        profileHash = meshData.sublist(11, 17).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      }

      if (stableId == null) {
        final dev = await isar.db.foundDevices.where().remoteIdEqualTo(r.device.remoteId.toString()).findFirst();
        if (dev != null) stableId = dev.stableId;
      }

      if (stableId == null || stableId == myStableId) continue;
      
      final dev = (await isar.db.foundDevices.where().stableIdEqualTo(stableId).findFirst()) ??
          (FoundDevice()..stableId = stableId);
      
      dev.remoteId = r.device.remoteId.toString();
      dev.rssi = r.rssi;
      dev.lastSeen = DateTime.now();
      if (r.advertisementData.advName.isNotEmpty) dev.name = r.advertisementData.advName;
      if (versionTag != null) dev.versionTag = versionTag;
      if (profileHash != null) dev.profileHash = profileHash;
      if (lat != null) dev.latitude = lat;
      if (lon != null) dev.longitude = lon;

      bool needsUpdate = dev.profilePicture == null ||
          (versionTag != null && dev.versionTag != versionTag) ||
          (dev.lastPictureSync == null || DateTime.now().difference(dev.lastPictureSync!).inHours >= 24);

      await isar.putFoundDevice(dev);
      
      if (needsUpdate) {
        final last = _lastSyncAttempt[stableId];
        if (last == null || DateTime.now().difference(last).inMinutes >= 5) {
          _syncQueue[stableId] = r.device;
        }
      }
    }
  }

  void _runDiscoveryCycle(ServiceInstance service, IsarService isar, int myStableId) async {
    _lastCycleFinishedTime = null;
    final cycleStart = DateTime.now();
    
    await _startSafeScan(service, isar, myStableId);
    
    _lastCycleFinishedTime = DateTime.now();
    final totalDuration = _lastCycleFinishedTime!.difference(cycleStart);

    // Dynamic Wait Logic
    if (totalDuration.inSeconds >= 60) {
      _currentWaitDuration = const Duration(seconds: 10);
      _log.info('Sync took long (${totalDuration.inSeconds}s), shortening next wait to 10s');
    } else {
      _currentWaitDuration = Duration(seconds: MessageHandler.waitDurationSeconds);
    }

    _discoveryTimer = Timer(_currentWaitDuration, () => _runDiscoveryCycle(service, isar, myStableId));
  }

  Future<void> _startSafeScan(ServiceInstance service, IsarService isar, int myStableId) async {
    if (_isScanOperationInProgress) return;

    if (BLEAdvertiser.hasInboundConnections) {
      _log.info('Scanning with active inbound connections...');
    }

    _isScanOperationInProgress = true;
    try {
      if (!await FlutterBluePlus.isSupported) return;
      if (FlutterBluePlus.adapterStateNow != BluetoothAdapterState.on) {
        _log.info('Bluetooth is OFF, skipping scan...');
        return;
      }

      // Sync existing devices that are missing critical metadata (Zero-Read fallback)
      final needsSync = await isar.db.foundDevices.filter().publicKeyIsNull().findAll();
      for (final dev in needsSync) {
        if (!_syncQueue.containsKey(dev.stableId)) {
          _syncQueue[dev.stableId] = BluetoothDevice.fromId(dev.remoteId);
        }
      }

      if (FlutterBluePlus.isScanningNow) {
        await FlutterBluePlus.stopScan();
        await Future.delayed(const Duration(seconds: 1));
      }

      _lastScanStartTime = DateTime.now();
      final scanDuration = Duration(seconds: MessageHandler.scanDurationSeconds);
      
      await FlutterBluePlus.startScan(
        timeout: scanDuration,
        withServices: [Guid(BLEAdvertiser.serviceUuid)],
        androidScanMode: AndroidScanMode.balanced,
        oneByOne: true,
      );
      
      await FlutterBluePlus.isScanning.where((s) => s == false).first;
      await Future.delayed(const Duration(seconds: 3));

      if (_syncQueue.isNotEmpty) {
        for (final entry in _syncQueue.entries) {
          await Future.delayed(Duration(milliseconds: 1000 + Random().nextInt(2000)));
          _lastSyncAttempt[entry.key] = DateTime.now();
          
          service.invoke('updateProgress', {
            'value': 1.0,
            'status': 'Fetching Metadata...',
            'syncingStableId': entry.key,
          });
          
          await _fetchFullMetadata(entry.value, isar, entry.key, _log);
        }
        _syncQueue.clear();
      }
    } finally {
      _isScanOperationInProgress = false;
    }
  }

  Future<void> _fetchFullMetadata(
    BluetoothDevice device,
    IsarService isar,
    int stableId,
    Logger log,
  ) async {
    final remoteId = device.remoteId.toString();
    bool establishedByUs = false;
    BluetoothCharacteristic? picChar, messageChar;
    StreamSubscription? messageSub;

    try {
      if (BLEAdvertiser.isDeviceConnected(remoteId)) {
        log.info('Using existing connection for $stableId');
      } else {
        try {
          await device.disconnect();
          await Future.delayed(const Duration(seconds: 1));
        } catch (_) {}
        int attempts = 0;
        while (attempts < 3 && !establishedByUs) {
          attempts++;
          try {
            await device.connect(
              autoConnect: false,
              license: License.free,
              timeout: const Duration(seconds: 30),
            );

            establishedByUs = true;
            log.info('Connected to $stableId as Central');
          } catch (e) {
            if (e.toString().contains('already_connected')) {
              establishedByUs = true;
            } else if (e.toString().contains('257')) {
              await Future.delayed(const Duration(seconds: 5));
            } else {
              await Future.delayed(const Duration(seconds: 2));
            }
            if (attempts >= 3 && !establishedByUs) rethrow;
          }
        }
      }

      await Future.delayed(const Duration(milliseconds: 1000));
      if (Platform.isAndroid) {
        try {
          await device.requestMtu(517);
          await device.mtu.first.timeout(const Duration(seconds: 3), onTimeout: () => 23);
        } catch (_) {}
      }
      final services = await device.discoverServices().timeout(const Duration(seconds: 20));
      await Future.delayed(const Duration(milliseconds: 500));

      for (final s in services) {
        if (s.uuid.toString().toLowerCase() == BLEAdvertiser.serviceUuid.toLowerCase()) {
          for (final c in s.characteristics) {
            final id = c.uuid.toString().toLowerCase();
            if (id == BLEAdvertiser.profilePicCharUuid.toLowerCase()) {
              picChar = c;
            } else if (id == BLEAdvertiser.messageCharUuid.toLowerCase()) {
              messageChar = c;
            }
          }
        }
      }

      final dev = await isar.db.foundDevices.where().stableIdEqualTo(stableId).findFirst();

      // Zero-Read Optimization: Only pull Profile Picture via GATT
      bool missing = dev?.profilePicture == null;
      bool shouldPullPic = picChar != null && (missing || (dev?.lastPictureSync == null));

      if (shouldPullPic) {
        try {
          await picChar.setNotifyValue(true).timeout(const Duration(seconds: 5));
          final h = await picChar.read().timeout(const Duration(seconds: 10));
          if (h.length >= 5 && h[0] == 0xAA) {
            final bd = ByteData.view(Uint8List.fromList(h).buffer);
            final expected = bd.getUint16(1, Endian.big);
            final buffer = <int>[];
            final comp = Completer<void>();
            final sub = picChar.onValueReceived.listen((v) {
              buffer.addAll(v);
              if (buffer.length >= expected) if (!comp.isCompleted) comp.complete();
            });
            try {
              await comp.future.timeout(const Duration(seconds: 30));
              if (buffer.length >= expected && dev != null) {
                dev.profilePicture = Uint8List.fromList(buffer.sublist(0, expected));
                dev.lastPictureSync = DateTime.now();
                await isar.putFoundDevice(dev);
                log.info('Successfully pulled profile picture via GATT');
              }
            } finally {
              await sub.cancel();
              await picChar.setNotifyValue(false).timeout(const Duration(seconds: 5)).catchError((_) => false);
            }
          }
        } catch (e) { log.warning('Pic pull fail: $e'); }
      }

      // --- START BIDIRECTIONAL SYNC (Zero-Read Handshake) ---
      if (messageChar != null) {
        try {
          await messageChar.setNotifyValue(true).timeout(const Duration(seconds: 5));
          final syncDoneCompleter = MessageHandler.createSyncCompleter(stableId);

          messageSub = messageChar.onValueReceived.listen((v) {
            if (v.isNotEmpty) {
              if (v[0] == MeshPacket.typeRequestProfilePic) {
                log.info('Peer $stableId requested our profile picture');
                MessageHandler.streamOurProfilePic(remoteId, stableId, messageChar);
              } else {
                MessageHandler.handleIncomingMessage(senderStableId: stableId, data: v);
              }
            }
          });

          final myId = await ProfileManager.getStableDeviceId();
          final myHash = await ProfileManager.getProfileHash();
          final myPubKey = (await (await ProfileManager.getKeyPair()).extractPublicKey()).bytes;
          final myName = (await SharedPreferences.getInstance()).getString('advertising_name_v2') ?? "BLE Node";

          log.info('Sending our identity to $stableId...');
          final idPacket = IdentityPacket(
            stableId: myId,
            profileHash: myHash,
            publicKey: Uint8List.fromList(myPubKey),
            name: myName,
          );

          final chunks = ChunkedTransferManager.generateChunks(idPacket.toBytes(), Random().nextInt(256));
          for (final c in chunks) {
            await messageChar.write(c, withoutResponse: false);
          }

          await MessageHandler.pushQueuedDataToPeer(stableId, useNotifications: false, centralWriteChar: messageChar);

          log.info('Waiting for peer $stableId to signal SyncDone...');
          await syncDoneCompleter.future.timeout(const Duration(seconds: 30));
          log.info('Peer $stableId signaled SyncDone.');
        } catch (e) {
          log.warning('Bidirectional sync failed/timed out: $e');
        } finally {
          MessageHandler.removeSyncCompleter(stableId);
        }
      }
    } catch (e) {
      log.warning('Sync fail for $stableId: $e');
    } finally {
      if (messageSub != null) await messageSub.cancel();
      if (messageChar != null) {
        await messageChar.setNotifyValue(false).timeout(const Duration(seconds: 5)).catchError((_) => false);
      }
      if (establishedByUs) {
        try {
          log.info('Disconnecting from $stableId...');
          await device.disconnect().timeout(const Duration(seconds: 10));
          log.info('Disconnected from $stableId.');
        } catch (e) { log.warning('Disconnect fail: $e'); }
      }
    }
  }
}
