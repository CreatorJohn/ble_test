import 'dart:async';
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
    'BLE Scanning Status',
    description: 'This channel is used for BLE scanning status.',
    importance: Importance.low,
  );

  final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  await flutterLocalNotificationsPlugin
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
      initialNotificationTitle: "BLE Scanner",
      initialNotificationContent: "Monitoring nearby devices",
      foregroundServiceTypes: [
        AndroidForegroundType.location,
        AndroidForegroundType.connectedDevice,
      ],
    ),
    iosConfiguration: IosConfiguration(
      autoStart: true,
      onForeground: onStart,
      onBackground: onIosBackground,
    ),
  );
}

@pragma("vm:entry-point")
Future<bool> onIosBackground(ServiceInstance service) async {
  return true;
}

final Logger log = Logger('BackgroundService');

@pragma("vm:entry-point")
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  final advertiser = BLEAdvertiser();

  // 1. Setup isolate-level logging
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((record) {
    service.invoke('log', {
      'message':
          '[BG] [${record.time.hour}:${record.time.minute}:${record.time.second}] [${record.level.name}] ${record.loggerName}: ${record.message}',
      'level': record.level.name,
    });
  });

  log.info('Service isolate started');

  // Catch unhandled errors in the background isolate
  runZonedGuarded(
    () async {
      await _startServiceLogic(service, advertiser);
    },
    (error, stack) {
      log.severe('Top-level background error: $error', error, stack);
    },
  );
}

Future<void> _startServiceLogic(
  ServiceInstance service,
  BLEAdvertiser advertiser,
) async {
  await Future.delayed(const Duration(seconds: 1));

  try {
    log.info('Initializing BLEAdvertiser...');
    await advertiser.initialize(ignorePermissions: true);
    log.info('BLEAdvertiser initialized');
  } catch (e) {
    log.severe('BLEAdvertiser initialization failed: $e');
  }

  final prefs = await SharedPreferences.getInstance();
  String currentName = prefs.getString('advertising_name_v2') ?? "BLE Test";
  bool advertisingOn = prefs.getBool('advertising_on') ?? false;
  double currentLat = 0.0;
  double currentLon = 0.0;
  bool isOnline = false;

  bool isAdUpdating = false;
  bool needsTrailingUpdate = false;

  Future<void> updateAd() async {
    if (!advertisingOn) return;

    if (isAdUpdating) {
      // Already in cooldown, mark for trailing update
      needsTrailingUpdate = true;
      return;
    }

    isAdUpdating = true;
    needsTrailingUpdate = false;

    try {
      log.info('Updating advertisement: name=$currentName, online=$isOnline');
      await advertiser.startAdvertising(
        localName: currentName,
        latitude: currentLat,
        longitude: currentLon,
        isOnline: isOnline,
      );
    } catch (e) {
      log.severe('updateAd failed: $e');
    }

    // Start 5-second cooldown
    Timer(const Duration(seconds: 5), () {
      isAdUpdating = false;
      // If data changed during cooldown, perform one final sync
      if (needsTrailingUpdate && advertisingOn) {
        updateAd();
      }
    });
  }

  log.info('Setting up location stream...');
  Geolocator.getPositionStream(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5,
    ),
  ).listen(
    (Position position) {
      log.fine('Location update: ${position.latitude}, ${position.longitude}');
      currentLat = position.latitude;
      currentLon = position.longitude;

      if (advertisingOn) updateAd();
    },
    onError: (e) {
      log.warning('Location stream error: $e');
    },
  );

  final isarService = IsarService();
  try {
    log.info('Initializing IsarService...');
    await isarService.initialize();
    log.info('IsarService initialized');
  } catch (e) {
    log.severe('IsarService initialization failed: $e');
    return;
  }

  // Ensure MessageHandler is listening to ChunkedTransferManager in background isolate
  MessageHandler.initialize();

  final myStableId = await ProfileManager.getStableDeviceId();
  final Set<int> activeSyncIds = {};

  FlutterBluePlus.scanResults.listen((results) async {
    if (!isarService.isOpen) return;

    for (final ScanResult result in results) {
      final advData = result.advertisementData;
      final remoteId = result.device.remoteId.toString();

      // Manufacturer ID 0xFFFF is used for our custom mesh payload
      final meshDataRaw = advData.manufacturerData[0xFFFF];
      if (meshDataRaw == null || meshDataRaw.length < 5) continue;

      final meshData = Uint8List.fromList(meshDataRaw);

      int? stableId;
      int? versionTag;
      String? profileHash;
      double? lat;
      double? lon;

      if (meshData.length == 5) {
        // Main Packet: [ID(4)][Version/Flags(1)]
        final buffer = ByteData.view(meshData.buffer);
        stableId = buffer.getUint32(0, Endian.big);
        versionTag = (meshData[4] >> 2) & 0x3F;
      } else if (meshData.length == 12) {
        // Scan Response: [Lat(3)][Lon(3)][Hash(6)]
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
        // Merged: [Main(5)][ScanResponse(12)]
        final buffer = ByteData.view(meshData.buffer);
        stableId = buffer.getUint32(0, Endian.big);
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

      // If we don't have a stableId in this packet, try to find it in the DB by remoteId
      if (stableId == null) {
        final existingByRemote = await isarService.db.foundDevices
            .where()
            .remoteIdEqualTo(remoteId)
            .findFirst();
        if (existingByRemote != null) {
          stableId = existingByRemote.stableId;
        }
      }

      if (stableId == null || stableId == myStableId) {
        continue;
      }

      FoundDevice device;
      final existing = await isarService.db.foundDevices
          .where()
          .stableIdEqualTo(stableId)
          .findFirst();

      if (existing != null) {
        device = existing;
      } else {
        device = FoundDevice()..stableId = stableId;
      }

      // Update volatile fields
      device.remoteId = remoteId;
      device.rssi = result.rssi;
      device.lastSeen = DateTime.now();

      // Only update metadata if present in this packet
      if (advData.advName.isNotEmpty) {
        device.name = advData.advName;
      }
      if (versionTag != null) device.versionTag = versionTag;
      if (profileHash != null) device.profileHash = profileHash;
      if (lat != null) device.latitude = lat;
      if (lon != null) device.longitude = lon;

      try {
        bool needsMetadataUpdate = false;

        if (existing != null) {
          bool versionChanged =
              versionTag != null && existing.versionTag != versionTag;
          bool needsForcedSync =
              existing.lastPictureSync == null ||
              DateTime.now().difference(existing.lastPictureSync!).inHours >=
                  24;

          if (versionChanged || needsForcedSync) {
            needsMetadataUpdate = true;
          }
        } else {
          needsMetadataUpdate = true;
        }

        // Save the basic device info first
        await isarService.putFoundDevice(device);

        if (needsMetadataUpdate) {
          if (!activeSyncIds.contains(stableId)) {
            activeSyncIds.add(stableId);
            log.info(
              'Syncing metadata for $stableId (Reason: ${existing == null ? "New" : "Stale/Changed"})',
            );
            _fetchFullMetadata(result.device, isarService, stableId, log).then((_) {
              activeSyncIds.remove(stableId);
            }).catchError((e) {
              activeSyncIds.remove(stableId);
            });
          }
        }
      } catch (e) {
        log.warning('Error processing scan result for $stableId: $e');
      }
    }
  });

  const scanDuration = Duration(seconds: 20);
  const waitDuration = Duration(seconds: 80);
  DateTime? lastScanStartTime;
  bool isScanOperationInProgress = false;

  Future<void> startSafeScan() async {
    if (isScanOperationInProgress) {
      log.info('Scan operation already in progress, skipping trigger.');
      return;
    }
    isScanOperationInProgress = true;

    try {
      log.info('Attempting startSafeScan...');
      service.invoke("updateAdvertisingName", {"name": currentName});

      if (!await FlutterBluePlus.isSupported) {
        log.warning('Bluetooth not supported on this device');
        return;
      }

      // Ensure adapter is ON
      var state = await FlutterBluePlus.adapterState.first;
      if (state != BluetoothAdapterState.on) {
        log.info('Bluetooth state is $state, waiting for ON...');
        try {
          state = await FlutterBluePlus.adapterState
              .where((s) => s == BluetoothAdapterState.on)
              .first
              .timeout(const Duration(seconds: 15));
        } catch (_) {
          log.warning('Bluetooth did not turn ON in time, skipping scan');
        }
      }

      final isScanning = FlutterBluePlus.isScanningNow;
      if (isScanning) {
        log.info('Scan already in progress, stopping first...');
        await FlutterBluePlus.stopScan();
        await Future.delayed(const Duration(seconds: 1));
      }

      log.info('Starting BLE scan (duration: ${scanDuration.inSeconds}s)...');
      lastScanStartTime = DateTime.now();

      await FlutterBluePlus.startScan(
        timeout: scanDuration,
        withServices: [Guid(BLEAdvertiser.serviceUuid)],
        androidScanMode: AndroidScanMode.lowPower,
        oneByOne: true, // More reliable for background/low-memory
      );
      log.info('BLE scan started successfully');
    } catch (e) {
      log.severe('startSafeScan failed: $e');
      lastScanStartTime = null;
    } finally {
      isScanOperationInProgress = false;
    }
  }

  // Progress and Status emitter
  Timer.periodic(const Duration(milliseconds: 500), (t) {
    final now = DateTime.now();
    if (FlutterBluePlus.isScanningNow && lastScanStartTime != null) {
      final elapsed = now.difference(lastScanStartTime!);
      final progress = elapsed.inMilliseconds / scanDuration.inMilliseconds;
      service.invoke('updateProgress', {'value': progress.clamp(0.0, 1.0)});
    } else if (lastScanStartTime != null) {
      // We are in wait period
      final elapsedSinceScanStart = now.difference(lastScanStartTime!);
      final totalCycle = scanDuration + waitDuration;
      final remainingWaitMs =
          totalCycle.inMilliseconds - elapsedSinceScanStart.inMilliseconds;
      final remainingSeconds = (remainingWaitMs / 1000).ceil();
      final progress = remainingWaitMs / waitDuration.inMilliseconds;
      service.invoke('updateProgress', {
        'value': progress.clamp(0.0, 1.0),
        'remainingSeconds': remainingSeconds.clamp(0, waitDuration.inSeconds),
      });
    } else {
      service.invoke('updateProgress', {'value': 0.0});
    }
  });

  Timer.periodic(waitDuration + scanDuration, (timer) async {
    log.info('Scanning cycle timer fired');
    await startSafeScan();
  });

  log.info('Performing initial scan...');
  await startSafeScan();

  service.on('stopService').listen((event) async {
    log.info('Stop service command received');
    await advertiser.stopAdvertising();
    service.stopSelf();
  });

  service.on('startAdvertising').listen((event) async {
    final name = event?['name'];
    advertisingOn = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('advertising_on', true);
    service.invoke("advertisingChange", {"active": true});

    log.info("Preparing to advertise with $name...");
    if (name is String) {
      log.info('Setting advertising name to: $name');
      currentName = name;
      updateAd();
    }
  });

  service.on('setOnlineStatus').listen((event) {
    final status = event?['isOnline'];
    if (status is bool) {
      log.info('Setting online status to: $status');
      isOnline = status;
      if (advertisingOn) updateAd();
    }
  });

  service.on("stopAdvertising").listen((_) async {
    advertisingOn = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('advertising_on', false);
    service.invoke("advertisingChange", {"active": false});
    await advertiser.stopAdvertising();
  });
}

Future<void> _fetchFullMetadata(
  BluetoothDevice device,
  IsarService isar,
  int stableId,
  Logger log,
) async {
  try {
    log.info('Connecting to $stableId to fetch metadata...');
    await device.connect(
      timeout: const Duration(seconds: 15),
      autoConnect: false,
      license: License.free,
    );
    log.info('Connected to $stableId');

    // Small delay after connection for stability
    await Future.delayed(const Duration(milliseconds: 500));

    final services = await device.discoverServices();

    // Another delay after service discovery
    await Future.delayed(const Duration(milliseconds: 500));

    BluetoothCharacteristic? picChar;
    BluetoothCharacteristic? hashChar;
    BluetoothCharacteristic? locChar;
    BluetoothCharacteristic? keyChar;

    for (final s in services) {
      if (s.uuid.toString().toLowerCase() ==
          BLEAdvertiser.serviceUuid.toLowerCase()) {
        for (final c in s.characteristics) {
          final charId = c.uuid.toString().toLowerCase();
          if (charId == BLEAdvertiser.profilePicCharUuid.toLowerCase()) {
            picChar = c;
          }
          if (charId == BLEAdvertiser.fullHashCharUuid.toLowerCase()) {
            hashChar = c;
          }
          if (charId == BLEAdvertiser.locationCharUuid.toLowerCase()) {
            locChar = c;
          }
          if (charId == BLEAdvertiser.publicKeyCharUuid.toLowerCase()) {
            keyChar = c;
          }
        }
      }
    }

    Future<List<int>> robustRead(BluetoothCharacteristic char) async {
      int attempts = 0;
      while (attempts < 3) {
        try {
          return await char.read().timeout(const Duration(seconds: 5));
        } catch (e) {
          attempts++;
          if (attempts >= 3) rethrow;
          log.warning('Read failed, retrying ($attempts/3)... $e');
          await Future.delayed(const Duration(seconds: 1));
        }
      }
      return [];
    }

    if (hashChar != null) {
      log.info('Reading full hash from $stableId...');
      final hashBytes = await robustRead(hashChar);
      final hashHex = hashBytes
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();

      final existing = await isar.db.foundDevices
          .where()
          .stableIdEqualTo(stableId)
          .findFirst();

      if (existing != null) {
        existing.profileHash = hashHex;

        if (keyChar != null) {
          log.info('Syncing public key for $stableId...');
          existing.publicKey = await robustRead(keyChar);
        }

        if (picChar != null &&
            (existing.profilePicture == null ||
                existing.profileHash != hashHex)) {
          log.info('Downloading profile picture for $stableId...');
          existing.profilePicture = await robustRead(picChar);
        }

        if (locChar != null) {
          await robustRead(locChar);
        }

        existing.lastPictureSync = DateTime.now();

        // Re-fetch to avoid overwriting volatile fields (RSSI, lastSeen) updated by scan
        final latest = await isar.db.foundDevices
            .where()
            .stableIdEqualTo(stableId)
            .findFirst();

        if (latest != null) {
          latest.profileHash = existing.profileHash;
          latest.publicKey = existing.publicKey;
          latest.lastPictureSync = existing.lastPictureSync;
          await isar.putFoundDevice(latest);
        } else {
          await isar.putFoundDevice(existing);
        }
        log.info('Metadata sync complete for $stableId');
      }
    }
  } catch (e) {
    log.warning('Failed to fetch full metadata for $stableId: $e');
  } finally {
    try {
      await device.disconnect();
    } catch (_) {}
  }
}
