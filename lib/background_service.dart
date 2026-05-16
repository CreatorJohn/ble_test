import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';

import 'package:ble_test/ble_advertiser.dart';
import 'package:ble_test/data/found_device.dart';
import 'package:ble_test/data/isar_service.dart';
import 'package:ble_test/mesh_packet_encoder.dart';
import 'package:ble_test/message_handler.dart';
import 'package:ble_test/profile_manager.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:isar_community/isar.dart';
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> initializeBackgroundService() async {
  final service = FlutterBackgroundService();
  if (await service.isRunning()) return;

  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'scanning_status',
    'BLE Status',
    importance: Importance.low,
  );
  final notificationPlugin = FlutterLocalNotificationsPlugin();
  await notificationPlugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.createNotificationChannel(channel);

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: true,
      isForegroundMode: true,
      notificationChannelId: "scanning_status",
      initialNotificationTitle: "BLE Mesh Active",
      initialNotificationContent: "Monitoring mesh network",
      foregroundServiceTypes: [
        AndroidForegroundType.location,
        AndroidForegroundType.connectedDevice,
      ],
    ),
    iosConfiguration: IosConfiguration(
      autoStart: true,
      onForeground: onStart,
      onBackground: (_) async => true,
    ),
  );
}

final Logger log = Logger('BackgroundService');

@pragma("vm:entry-point")
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  final advertiser = BLEAdvertiser();

  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen(
    (r) => service.invoke('log', {
      'message':
          '[BG] [${r.time.hour}:${r.time.minute}:${r.time.second}] [${r.level.name}] ${r.loggerName}: ${r.message}',
      'level': r.level.name,
      'loggerName': r.loggerName,
    }),
  );

  log.info('Service isolate started');
  if (!BLEAdvertiser.initialized) {
    await advertiser
        .initialize(ignorePermissions: true)
        .then((_) {
          log.info("BLEAdvertiser initialized!");
        })
        .catchError((_) {
          log.severe("Failed to initialized BLEAdvertiser!");
        });
  } else {
    log.info("BLEAdvertiser already initialized!");
  }

  runZonedGuarded(
    () async => await _startServiceLogic(service, advertiser),
    (error, stack) => log.severe('Top-level error: $error', error, stack),
  );
}

Future<void> _startServiceLogic(
  ServiceInstance service,
  BLEAdvertiser advertiser,
) async {
  await Future.delayed(const Duration(seconds: 1));
  final prefs = await SharedPreferences.getInstance();
  String currentName = prefs.getString('advertising_name_v2') ?? "BLE Node";
  bool advertisingOn = prefs.getBool('advertising_on') ?? false;
  double currentLat = 0.0, currentLon = 0.0;
  bool isOnline = false,
      isAdUpdating = false,
      needsTrailingUpdate = false,
      isScanOperationInProgress = false;

  Future<void> updateAd() async {
    if (!advertisingOn || !BLEAdvertiser.initialized) return;
    if (isAdUpdating ||
        isScanOperationInProgress ||
        BLEAdvertiser.hasInboundConnections) {
      needsTrailingUpdate = true;
      return;
    }
    isAdUpdating = true;
    needsTrailingUpdate = false;
    try {
      await advertiser.startAdvertising(
        localName: currentName,
        latitude: currentLat,
        longitude: currentLon,
        isOnline: isOnline,
      );
      service.invoke("advertisingChange", {"active": true});
    } catch (e) {
      log.severe('Ad update fail: $e');
    }
    Timer(const Duration(seconds: 5), () {
      isAdUpdating = false;
      if (needsTrailingUpdate && advertisingOn) updateAd();
    });
  }

  BLEAdvertiser.connectionStream.listen((event) {
    if (!event.values.first && needsTrailingUpdate && advertisingOn) updateAd();
  });

  Geolocator.getPositionStream(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5,
    ),
  ).listen(
    (p) {
      currentLat = p.latitude;
      currentLon = p.longitude;
      if (advertisingOn) updateAd();
    },
    onError: (e) {
      log.warning('Loc error: $e');
    },
  );

  final isar = IsarService();
  await isar.initialize();
  await isar.pruneDatabase();
  MessageHandler.initialize();

  final myStableId = await ProfileManager.getStableDeviceId();
  final Map<int, BluetoothDevice> syncQueue = {};
  final Map<int, DateTime> lastSyncAttempt = {};
  final List<Map<String, dynamic>> messageQueue = [];

  Future<void> processMessageQueue() async {
    if (isScanOperationInProgress || messageQueue.isEmpty) return;
    final toSend = List<Map<String, dynamic>>.from(messageQueue);
    messageQueue.clear();
    for (final msg in toSend) {
      try {
        await MessageHandler.sendMessage(
          targetStableId: msg['targetId'],
          content: msg['content'],
        );
      } catch (e) {
        log.warning('Failed to send queued message to ${msg['targetId']}: $e');
      }
    }
  }

  FlutterBluePlus.scanResults.listen((results) async {
    if (!isar.isOpen) return;
    if (BLEAdvertiser.hasInboundConnections && FlutterBluePlus.isScanningNow) {
      log.info('Inbound active, pausing scan');
      FlutterBluePlus.stopScan();
      return;
    }

    for (final r in results) {
      final meshDataRaw = r.advertisementData.manufacturerData[0xFFFF];
      if (meshDataRaw == null || meshDataRaw.length < 5) continue;
      final meshData = Uint8List.fromList(meshDataRaw);
      int? stableId, versionTag;
      String? profileHash;
      double? lat, lon;

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
        final last = lastSyncAttempt[stableId];
        if (last == null || DateTime.now().difference(last).inMinutes >= 5) {
          syncQueue[stableId] = r.device;
        }
      }
    }
  });

  const scanDuration = Duration(seconds: 10),
      waitDuration = Duration(seconds: 50);
  DateTime? lastScanStartTime;

  Future<void> startSafeScan() async {
    if (isScanOperationInProgress) return;
    int defer = 0;
    while (BLEAdvertiser.hasInboundConnections && defer < 6) {
      await Future.delayed(const Duration(seconds: 5));
      defer++;
    }
    if (BLEAdvertiser.hasInboundConnections) return;

    isScanOperationInProgress = true;
    try {
      if (!await FlutterBluePlus.isSupported) return;

      // Handle Bluetooth "Off" State Gracefully
      if (FlutterBluePlus.adapterStateNow != BluetoothAdapterState.on) {
        log.info('Bluetooth is OFF, skipping scan...');
        return;
      }

      final needsSync = await isar.db.foundDevices
          .filter()
          .publicKeyIsNull()
          .or()
          .nameEqualTo("Connecting Device...")
          .findAll();
      for (final dev in needsSync) {
        if (!syncQueue.containsKey(dev.stableId)) {
          syncQueue[dev.stableId] = BluetoothDevice.fromId(dev.remoteId);
        }
      }

      if (FlutterBluePlus.isScanningNow) {
        await FlutterBluePlus.stopScan();
        await Future.delayed(const Duration(seconds: 1));
      }

      lastScanStartTime = DateTime.now();
      await FlutterBluePlus.startScan(
        timeout: scanDuration,
        withServices: [Guid(BLEAdvertiser.serviceUuid)],
        androidScanMode: AndroidScanMode.balanced,
        oneByOne: true,
      );
      await FlutterBluePlus.isScanning.where((s) => s == false).first;
      await Future.delayed(const Duration(seconds: 3));

      if (syncQueue.isNotEmpty) {
        for (final entry in syncQueue.entries) {
          await Future.delayed(
            Duration(milliseconds: 1000 + Random().nextInt(2000)),
          );
          lastSyncAttempt[entry.key] = DateTime.now();
          await _fetchFullMetadata(entry.value, isar, entry.key, log);
        }
        syncQueue.clear();
      }
    } finally {
      isScanOperationInProgress = false;
      await processMessageQueue();
      if (needsTrailingUpdate && advertisingOn) updateAd();
    }
  }

  Timer.periodic(const Duration(milliseconds: 500), (t) {
    if (lastScanStartTime == null) return;
    final now = DateTime.now(), total = scanDuration + waitDuration;
    final elapsed = now.difference(lastScanStartTime!);
    if (FlutterBluePlus.isScanningNow) {
      service.invoke('updateProgress', {
        'value': (elapsed.inMilliseconds / scanDuration.inMilliseconds).clamp(
          0.0,
          1.0,
        ),
      });
    } else {
      final rem = total.inMilliseconds - elapsed.inMilliseconds;
      service.invoke('updateProgress', {
        'value': (rem / waitDuration.inMilliseconds).clamp(0.0, 1.0),
        'remainingSeconds': (rem / 1000).ceil().clamp(0, 60),
      });
    }
  });

  Timer.periodic(waitDuration + scanDuration, (_) => startSafeScan());
  
  // Periodically check for ACK timeouts (every 2 minutes)
  Timer.periodic(const Duration(minutes: 2), (_) => MessageHandler.checkExpiredMessages());
  
  await startSafeScan();

  service.on('stopService').listen((_) async {
    await advertiser.stopAdvertising();
    service.stopSelf();
  });
  service.on('startAdvertising').listen((e) {
    final name = e?['name'];
    advertisingOn = true;
    prefs.setBool('advertising_on', true);
    if (name is String) {
      currentName = name;
      updateAd();
    }
  });
  service.on('setOnlineStatus').listen((e) {
    final status = e?['isOnline'];
    if (status is bool) {
      isOnline = status;
      if (advertisingOn) updateAd();
    }
  });
  service.on("stopAdvertising").listen((_) async {
    advertisingOn = false;
    prefs.setBool('advertising_on', false);
    await advertiser.stopAdvertising();
    service.invoke("advertisingChange", {"active": false});
  });
  service.on("updateLocalProfile").listen((_) => updateAd());
  service.on('sendMessage').listen((e) async {
    final targetId = e?['targetId'];
    final content = e?['content'];
    if (targetId is int && content is String) {
      messageQueue.add({'targetId': targetId, 'content': content});
      if (!isScanOperationInProgress) await processMessageQueue();
    }
  });
}

Future<void> _fetchFullMetadata(
  BluetoothDevice device,
  IsarService isar,
  int stableId,
  Logger log,
) async {
  final remoteId = device.remoteId.toString();
  bool establishedByUs = false;
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
        await device.mtu.first.timeout(
          const Duration(seconds: 3),
          onTimeout: () => 23,
        );
      } catch (_) {}
    }
    final services = await device.discoverServices();
    await Future.delayed(const Duration(milliseconds: 500));

    BluetoothCharacteristic? picChar,
        hashChar,
        locChar,
        keyChar,
        nameChar,
        messageChar;
    for (final s in services) {
      if (s.uuid.toString().toLowerCase() ==
          BLEAdvertiser.serviceUuid.toLowerCase()) {
        for (final c in s.characteristics) {
          final id = c.uuid.toString().toLowerCase();
          if (id == BLEAdvertiser.profilePicCharUuid.toLowerCase()) {
            picChar = c;
          } else if (id == BLEAdvertiser.fullHashCharUuid.toLowerCase()) {
            hashChar = c;
          } else if (id == BLEAdvertiser.locationCharUuid.toLowerCase()) {
            locChar = c;
          } else if (id == BLEAdvertiser.publicKeyCharUuid.toLowerCase()) {
            keyChar = c;
          } else if (id == BLEAdvertiser.nameCharUuid.toLowerCase()) {
            nameChar = c;
          } else if (id == BLEAdvertiser.messageCharUuid.toLowerCase()) {
            messageChar = c;
          }
        }
      }
    }

    if (messageChar != null) {
      try {
        await messageChar.setNotifyValue(true);
        messageChar.onValueReceived.listen((v) {
          if (v.isNotEmpty) {
            MessageHandler.handleIncomingMessage(
              senderStableId: stableId,
              data: v,
            );
          }
        });
      } catch (_) {}
    }

    if (hashChar != null) {
      final hashBytes = await robustRead(hashChar);
      if (hashBytes.isEmpty) return;
      final hashHex = hashBytes
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();

      final dev = await isar.db.foundDevices
          .where()
          .stableIdEqualTo(stableId)
          .findFirst();
      if (dev != null) {
        bool mismatched = dev.profileHash != hashHex,
            missing = dev.profilePicture == null;
        dev.profileHash = hashHex;

        if (nameChar != null &&
            (dev.name == null || dev.name == "Connecting Device...")) {
          final nb = await robustRead(nameChar);
          if (nb.isNotEmpty) dev.name = utf8.decode(nb, allowMalformed: true);
        }
        if (keyChar != null) {
          final kb = await robustRead(keyChar);
          if (kb.isNotEmpty) dev.publicKey = kb;
        }

        if (picChar != null && (missing || mismatched)) {
          try {
            await picChar.setNotifyValue(true);
            final h = await picChar.read().timeout(const Duration(seconds: 10));
            if (h.length >= 5 && h[0] == 0xAA) {
              final bd = ByteData.view(Uint8List.fromList(h).buffer);
              final expected = bd.getUint16(1, Endian.big);
              final buffer = <int>[];
              final comp = Completer<void>();
              final sub = picChar.onValueReceived.listen((v) {
                buffer.addAll(v);
                if (buffer.length >= expected) {
                  if (!comp.isCompleted) comp.complete();
                }
              });
              try {
                await comp.future.timeout(const Duration(seconds: 30));
                if (buffer.length >= expected) {
                  dev.profilePicture = Uint8List.fromList(
                    buffer.sublist(0, expected),
                  );
                }
              } finally {
                await sub.cancel();
                await picChar.setNotifyValue(false).catchError((_) => false);
              }
            }
          } catch (_) {}
        }

        if (locChar != null) {
          final lb = await robustRead(locChar);
          if (lb.length == 6) {
            dev.latitude = MeshPacketEncoder.decodeCoordinate(
              (lb[0] << 16) | (lb[1] << 8) | lb[2],
              true,
            );
            dev.longitude = MeshPacketEncoder.decodeCoordinate(
              (lb[3] << 16) | (lb[4] << 8) | lb[5],
              false,
            );
          }
        }
        dev.lastPictureSync = DateTime.now();
        dev.lastSeen = DateTime.now();

        final latest = await isar.db.foundDevices
            .where()
            .stableIdEqualTo(stableId)
            .findFirst();
        if (latest != null) {
          latest.profileHash = dev.profileHash;
          latest.publicKey = dev.publicKey;
          latest.lastPictureSync = dev.lastPictureSync;
          latest.name = dev.name;
          latest.latitude = dev.latitude;
          latest.longitude = dev.longitude;
          latest.profilePicture = dev.profilePicture;
          await isar.putFoundDevice(latest);
        } else {
          await isar.putFoundDevice(dev);
        }
      }
    }
  } catch (e) {
    log.warning('Sync fail for $stableId: $e');
  } finally {
    if (establishedByUs) {
      try {
        await device.disconnect();
      } catch (_) {}
    }
  }
}

Future<Uint8List> robustRead(BluetoothCharacteristic char) async {
  for (int i = 0; i < 3; i++) {
    try {
      return Uint8List.fromList(
        await char.read().timeout(const Duration(seconds: 5)),
      );
    } catch (_) {
      await Future.delayed(const Duration(seconds: 1));
    }
  }
  return Uint8List.fromList([]);
}
