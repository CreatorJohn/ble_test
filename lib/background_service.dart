import 'dart:async';
import 'dart:typed_data';
import 'dart:ui';

import 'package:ble_test/ble_advertiser.dart';
import 'package:ble_test/data/found_device.dart';
import 'package:ble_test/data/isar_service.dart';
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

@pragma("vm:entry-point")
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  // 1. Setup isolate-level logging
  final Logger log = Logger('BackgroundService');
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((record) {
    service.invoke('log', {
      'message':
          '[BG] [${record.time}] [${record.level.name}] ${record.loggerName}: ${record.message}',
      'level': record.level.name,
    });
  });

  log.info('Service isolate started');

  await Future.delayed(const Duration(seconds: 1));

  final advertiser = BLEAdvertiser();
  try {
    log.info('Initializing BLEAdvertiser...');
    await advertiser.initialize(ignorePermissions: true);
    log.info('BLEAdvertiser initialized');
  } catch (e) {
    log.severe('BLEAdvertiser initialization failed: $e');
  }

  final prefs = await SharedPreferences.getInstance();
  String currentName = prefs.getString('advertising_name_v2') ?? "BLE Test";
  double currentLat = 0.0;
  double currentLon = 0.0;
  bool isOnline = false;
  bool advertisingOn = false;

  Future<void> updateAd() async {
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

  FlutterBluePlus.scanResults.listen((results) async {
    if (!isarService.isOpen) return;

    for (final ScanResult result in results) {
      final advData = result.advertisementData;

      // Manufacturer ID 0xFFFF is used for our custom mesh payload
      final meshData = advData.manufacturerData[0xFFFF];
      if (meshData == null || meshData.length < 5) continue;

      final buffer = ByteData.view(Uint8List.fromList(meshData).buffer);
      final stableId = buffer.getUint32(0, Endian.big);
      // Byte 4 contains the version tag (top 6 bits)
      final discoveredVersionTag = (meshData[4] >> 2) & 0x3F;

      Uint8List? scanResponseData;
      String displayName = "Unknown device";

      if (advData.advName.length >= 12) {
        scanResponseData = Uint8List.fromList(
          advData.advName.substring(0, 12).codeUnits,
        );
        displayName = advData.advName.substring(12);
      } else if (advData.advName.isNotEmpty) {
        displayName = advData.advName;
      }

      final device = FoundDevice()
        ..stableId = stableId
        ..remoteId = result.device.remoteId.toString()
        ..name = displayName
        ..rssi = result.rssi
        ..lastSeen = DateTime.now()
        ..versionTag = discoveredVersionTag;

      if (scanResponseData != null) {
        final fullHashBytes = scanResponseData.sublist(6, 12);
        device.profileHash = fullHashBytes
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join();
      }

      try {
        final existing = await isarService.db.foundDevices
            .where()
            .stableIdEqualTo(stableId)
            .findFirst();

        bool needsMetadataUpdate = false;

        if (existing != null) {
          device.id = existing.id;
          device.profilePicture = existing.profilePicture;
          device.publicKey = existing.publicKey;
          device.lastPictureSync = existing.lastPictureSync;

          bool versionChanged = existing.versionTag != discoveredVersionTag;
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

        if (needsMetadataUpdate) {
          log.info(
            'Syncing metadata for $stableId (Reason: ${existing == null ? "New" : "Stale/Changed"})',
          );
          _fetchFullMetadata(result.device, isarService, stableId, log);
        }

        await isarService.putFoundDevice(device);
      } catch (e) {
        log.warning('Error processing scan result for $stableId: $e');
      }
    }
  });

  const scanDuration = Duration(seconds: 20);
  const waitDuration = Duration(seconds: 80);
  DateTime? lastScanStartTime;

  Future<void> startSafeScan() async {
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
        log.info('Bluetooth state is $state');
      }

      final isScanning = FlutterBluePlus.isScanningNow;
      if (isScanning) {
        log.info('Scan already in progress, stopping first...');
        await FlutterBluePlus.stopScan();
        await Future.delayed(const Duration(milliseconds: 500));
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

      // If we got the specific NPE or PlatformException,
      // it might be because the stack is "stuck".
      // A small delay before the next cycle might help.
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

  service.on('setAdvertisingName').listen((event) {
    final name = event?['name'];
    advertisingOn = true;
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
      timeout: const Duration(seconds: 8),
      license: License.free,
    );
    log.info('Connected to $stableId');

    final services = await device.discoverServices();
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

    if (hashChar != null) {
      log.info('Reading full hash from $stableId...');
      final hashBytes = await hashChar.read();
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
          existing.publicKey = await keyChar.read();
        }

        if (picChar != null &&
            (existing.profilePicture == null ||
                existing.profileHash != hashHex)) {
          log.info('Downloading profile picture for $stableId...');
          existing.profilePicture = await picChar.read();
        }

        if (locChar != null) {
          await locChar.read();
        }

        existing.lastPictureSync = DateTime.now();
        await isar.putFoundDevice(existing);
        log.info('Metadata sync complete for $stableId');
      }
    }
  } catch (e) {
    log.warning('Failed to fetch full metadata for $stableId: $e');
  } finally {
    await device.disconnect();
  }
}
