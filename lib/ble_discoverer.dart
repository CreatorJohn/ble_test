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
  final Set<int> _activeSyncs = {};

  bool _isScanOperationInProgress = false;
  DateTime? _lastScanStartTime;
  DateTime? _lastCycleFinishedTime;
  Timer? _discoveryTimer;
  Duration _currentWaitDuration = Duration(
    seconds: MessageHandler.waitDurationSeconds,
  );

  bool get isScanOperationInProgress => _isScanOperationInProgress;
  DateTime? get lastScanStartTime => _lastScanStartTime;

  void start(ServiceInstance service, IsarService isar, int myStableId) {
    _log.info('Discovery Engine started');

    // Listen for scan results
    FlutterBluePlus.scanResults.listen((results) async {
      if (!isar.isOpen) return;

      for (final r in results) {
        _log.info(
          'Filtered Scan Result: ${r.device.remoteId} Name: "${r.advertisementData.advName}", '
          'Services: ${r.advertisementData.serviceUuids.length}, '
          'MFD IDs: ${r.advertisementData.manufacturerData.keys.toList()}',
        );
      }

      // Safety: Inbound active, pause scan processing
      if (BLEAdvertiser.hasInboundConnections &&
          FlutterBluePlus.isScanningNow) {
        _log.info('Inbound active, pausing scan processing');
        FlutterBluePlus.stopScan();
        return;
      }

      await _processScanResults(
        results: results,
        isar: isar,
        myStableId: myStableId,
        service: service,
      );
    });

    _runDiscoveryCycle(service, isar, myStableId);

    // Progress Reporting Timer
    Timer.periodic(const Duration(milliseconds: 500), (t) {
      final now = DateTime.now();

      if (FlutterBluePlus.isScanningNow) {
        if (_lastScanStartTime == null) return;
        final elapsed = now.difference(_lastScanStartTime!);
        final scanDuration = Duration(
          seconds: MessageHandler.scanDurationSeconds,
        );
        service.invoke('updateProgress', {
          'value': (elapsed.inMilliseconds / scanDuration.inMilliseconds).clamp(
            0.0,
            1.0,
          ),
          'status': 'Scanning...',
        });
      } else if (_isScanOperationInProgress) {
        service.invoke('updateProgress', {
          'value': 1.0,
          'status': 'Syncing...',
        });
      } else {
        if (_lastCycleFinishedTime == null) return;
        final waitElapsed = now.difference(_lastCycleFinishedTime!);
        final rem =
            _currentWaitDuration.inMilliseconds - waitElapsed.inMilliseconds;
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
    required ServiceInstance service,
  }) async {
    for (final r in results) {
      final mfd = r.advertisementData.manufacturerData;
      final meshDataRaw = mfd[MeshConstants.manufacturerId];

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
          (meshData[0] << 16) | (meshData[1] << 8) | meshData[2],
          true,
        );
        lon = MeshPacketEncoder.decodeCoordinate(
          (meshData[3] << 16) | (meshData[4] << 8) | meshData[5],
          false,
        );
        profileHash = meshData
            .sublist(6, 12)
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join();
      } else if (meshData.length >= 17) {
        final bd = ByteData.view(meshData.buffer);
        stableId = bd.getUint32(0, Endian.big);
        versionTag = (meshData[4] >> 2) & 0x3F;
        lat = MeshPacketEncoder.decodeCoordinate(
          (meshData[5] << 16) | (meshData[6] << 8) | meshData[7],
          true,
        );
        lon = MeshPacketEncoder.decodeCoordinate(
          (meshData[8] << 16) | (meshData[9] << 8) | meshData[10],
          false,
        );
        profileHash = meshData
            .sublist(11, 17)
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join();
      }

      if (stableId == null) {
        final dev = await isar.db.foundDevices
            .where()
            .remoteIdEqualTo(r.device.remoteId.toString())
            .findFirst();
        if (dev != null) stableId = dev.stableId;
      }

      if (stableId == null || stableId == myStableId) continue;

      final dev =
          (await isar.db.foundDevices
              .where()
              .stableIdEqualTo(stableId)
              .findFirst()) ??
          (FoundDevice()..stableId = stableId);

      dev.remoteId = r.device.remoteId.toString();
      dev.rssi = r.rssi;
      dev.lastSeen = DateTime.now();
      if (r.advertisementData.advName.isNotEmpty) {
        dev.name = r.advertisementData.advName;
      }
      if (versionTag != null) dev.versionTag = versionTag;
      if (profileHash != null) dev.profileHash = profileHash;
      if (lat != null) dev.latitude = lat;
      if (lon != null) dev.longitude = lon;

      bool needsUpdate =
          dev.profilePicture == null ||
          (versionTag != null && dev.versionTag != versionTag) ||
          (dev.lastPictureSync == null ||
              DateTime.now().difference(dev.lastPictureSync!).inHours >= 24);

      await isar.putFoundDevice(dev);

      if (needsUpdate) {
        final last = _lastSyncAttempt[stableId];
        if (last == null || DateTime.now().difference(last).inMinutes >= 5) {
          if (!_activeSyncs.contains(stableId)) {
            _syncQueue[stableId] = r.device;
          }
        }
      }
    }
  }

  void _runDiscoveryCycle(
    ServiceInstance service,
    IsarService isar,
    int myStableId,
  ) async {
    _lastCycleFinishedTime = null;
    final cycleStart = DateTime.now();

    await _startSafeScan(service, isar, myStableId);

    _lastCycleFinishedTime = DateTime.now();
    final totalDuration = _lastCycleFinishedTime!.difference(cycleStart);

    // Dynamic Wait Logic
    if (totalDuration.inSeconds >= 60) {
      _currentWaitDuration = const Duration(seconds: 10);
      _log.info(
        'Sync took long (${totalDuration.inSeconds}s), shortening next wait to 10s',
      );
    } else {
      _currentWaitDuration = Duration(
        seconds: MessageHandler.waitDurationSeconds,
      );
    }

    _discoveryTimer = Timer(
      _currentWaitDuration,
      () => _runDiscoveryCycle(service, isar, myStableId),
    );
  }

  Future<void> _startSafeScan(
    ServiceInstance service,
    IsarService isar,
    int myStableId,
  ) async {
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
      final needsSync = await isar.db.foundDevices
          .filter()
          .publicKeyIsNull()
          .findAll();
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
      final scanDuration = Duration(
        seconds: MessageHandler.scanDurationSeconds,
      );

      await FlutterBluePlus.startScan(
        timeout: scanDuration,
        withServices: [Guid(BLEAdvertiser.serviceUuid)],
        androidScanMode: AndroidScanMode.balanced,
        androidUsesFineLocation: true,
      );

      await FlutterBluePlus.isScanning.where((s) => s == false).first;
      await Future.delayed(const Duration(seconds: 3));

      if (_syncQueue.isNotEmpty) {
        for (final entry in _syncQueue.entries) {
          await Future.delayed(
            Duration(milliseconds: 1000 + Random().nextInt(2000)),
          );
          _lastSyncAttempt[entry.key] = DateTime.now();
          _activeSyncs.add(entry.key);

          service.invoke('updateProgress', {
            'value': 1.0,
            'status': 'Syncing...',
            'deviceStatus': 'Initiating Sync...',
            'syncingStableId': entry.key,
          });

          try {
            await _fetchFullMetadata(entry.value, isar, entry.key, _log);
          } finally {
            _activeSyncs.remove(entry.key);
          }
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
    bool connectionAttempted = false;
    BluetoothCharacteristic? messageChar;
    StreamSubscription? messageSub;

    try {
      // 1. A connects to B
      MessageHandler.updateUiProgress('Connecting to $stableId...',
          syncingStableId: stableId, value: 0.1);
      if (BLEAdvertiser.isDeviceConnected(remoteId)) {
        log.info('Using existing connection for $stableId');
      } else {
        await Future.delayed(const Duration(seconds: 1)); // Breathe after scan
        int attempts = 0;
        while (attempts < 2 && !establishedByUs) {
          attempts++;
          connectionAttempted = true;
          try {
            await device.connect(
              autoConnect: false,
              license: License.free,
              timeout: const Duration(seconds: 15),
            );

            establishedByUs = true;
            log.info('Connected to $stableId as Central');
          } catch (e) {
            if (e.toString().contains('already_connected')) {
              establishedByUs = true;
            } else {
              // Forced disconnect on fail to free GATT slot (Fixes 257)
              await device.disconnect().catchError((_) {});
              await Future.delayed(const Duration(seconds: 2));
            }
            if (attempts >= 2 && !establishedByUs) rethrow;
          }
        }
      }

      await Future.delayed(const Duration(milliseconds: 1000));
      if (Platform.isAndroid) {
        try {
          await device.requestMtu(517);
          await device.mtu.first.timeout(
            const Duration(seconds: 3),
            onTimeout: () => 23,
          );
        } catch (_) {}
      }
      final services = await device.discoverServices().timeout(
        const Duration(seconds: 20),
      );
      MessageHandler.updateUiProgress('Discovering Services...',
          syncingStableId: stableId, value: 0.3);
      await Future.delayed(const Duration(milliseconds: 500));

      for (final s in services) {
        if (s.uuid.toString().toLowerCase() ==
            BLEAdvertiser.serviceUuid.toLowerCase()) {
          for (final c in s.characteristics) {
            final id = c.uuid.toString().toLowerCase();
            if (id == BLEAdvertiser.messageCharUuid.toLowerCase()) {
              messageChar = c;
            }
          }
        }
      }

      // --- START BIDIRECTIONAL SYNC (Zero-Read Handshake) ---
      if (messageChar != null) {
        try {
          await messageChar
              .setNotifyValue(true)
              .timeout(const Duration(seconds: 5));
          final syncDoneCompleter = MessageHandler.createSyncCompleter(
            stableId,
          );

          messageSub = messageChar.onValueReceived.listen((v) {
            if (v.isNotEmpty) {
              if (v[0] == MeshPacket.typeRequestProfilePic) {
                log.info('Peer $stableId requested our profile picture');
                MessageHandler.streamOurProfilePic(
                  remoteId,
                  stableId,
                  messageChar,
                );
              } else {
                MessageHandler.handleIncomingMessage(
                  senderStableId: stableId,
                  data: v,
                  remoteId: remoteId,
                );
              }
            }
          });

          final myId = await ProfileManager.getStableDeviceId();
          final myHash = await ProfileManager.getProfileHash();
          final myPubKey =
              (await (await ProfileManager.getKeyPair()).extractPublicKey())
                  .bytes;
          final myName =
              (await SharedPreferences.getInstance()).getString(
                'advertising_name_v2',
              ) ??
              "BLE Node";

          log.info('Sending our identity to $stableId...');
          MessageHandler.updateUiProgress('Sending Identity...',
              syncingStableId: stableId, value: 0.5);
          final idPacket = IdentityPacket(
            stableId: myId,
            profileHash: myHash,
            publicKey: Uint8List.fromList(myPubKey),
            name: myName,
          );

          final chunks = ChunkedTransferManager.generateChunks(
            idPacket.toBytes(),
            Random().nextInt(256),
          );
          for (final c in chunks) {
            await messageChar.write(c, withoutResponse: false);
          }

          // 2. A sends identity (already sent above)
          // 3. A sends profile picture if requested (handled by messageSub listener)
          // 4. A sends messages and ACKs for device B
          MessageHandler.updateUiProgress('Syncing Messages...',
              syncingStableId: stableId, value: 0.7);
          await MessageHandler.pushQueuedDataToPeer(
            stableId,
            useNotifications: false,
            centralWriteChar: messageChar,
          );

          // 5. A signals it is DONE with its turn
          log.info('A is done, signaling SyncDone to $stableId');
          MessageHandler.updateUiProgress('Waiting for Peer turn...',
              syncingStableId: stableId, value: 0.9);
          final done = SyncDonePacket();
          final doneChunks = ChunkedTransferManager.generateChunks(
            done.toBytes(),
            Random().nextInt(256),
          );
          for (final c in doneChunks) {
            await messageChar.write(c, withoutResponse: false);
          }

          log.info('Waiting for B ($stableId) to complete its turn...');
          await syncDoneCompleter.future.timeout(const Duration(seconds: 45));
          log.info('B ($stableId) signaled SyncDone. Full Handshake Complete.');
          MessageHandler.updateUiProgress('Sync Complete',
              syncingStableId: stableId, value: 1.0);
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
        await messageChar
            .setNotifyValue(false)
            .timeout(const Duration(seconds: 5))
            .catchError((_) => false);
      }
      if (establishedByUs || (connectionAttempted && !establishedByUs)) {
        try {
          log.info('Disconnecting from $stableId...');
          await device.disconnect().timeout(const Duration(seconds: 10));
          log.info('Disconnected from $stableId.');
        } catch (e) {
          log.warning('Disconnect fail: $e');
        }
      }
    }
  }
}
