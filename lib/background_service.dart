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

Future<void> initializeBackgroundService() async {
  final service = FlutterBackgroundService();

  if (await service.isRunning()) return;

  // Create the notification channel for Android
  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'scanning_status', // id
    'BLE Scanning Status', // title
    description: 'This channel is used for BLE scanning status.', // description
    importance: Importance.low,
  );

  final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
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

  // Give the system a moment to stabilize
  await Future.delayed(const Duration(seconds: 1));

  final advertiser = BLEAdvertiser();
  await advertiser.initialize(ignorePermissions: true);

  String currentName = "BLE Test";
  double currentLat = 0.0;
  double currentLon = 0.0;
  bool isOnline = false;

  Future<void> updateAd() async {
    await advertiser.startAdvertising(
      localName: currentName,
      latitude: currentLat,
      longitude: currentLon,
      isOnline: isOnline,
    );
  }

  // Initial Ad
  await updateAd();

  // Location tracking
  Geolocator.getPositionStream(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5, // Update every 5 meters
    ),
  ).listen((Position position) {
    currentLat = position.latitude;
    currentLon = position.longitude;
    updateAd();
  });

  final isarService = IsarService();
  try {
    await isarService.initialize();
  } catch (e) {
    if (service is AndroidServiceInstance) {
      service.setForegroundNotificationInfo(
        title: "BLE Test App - Error",
        content: "Failed to initialize database: $e",
      );
    }
    return;
  }

  FlutterBluePlus.scanResults.listen((results) async {
    if (!isarService.isOpen) return;

    for (final ScanResult result in results) {
      final advData = result.advertisementData;
      
      // Look for our specific Manufacturer Data block (ID 0xFFFF, 6 bytes payload)
      final meshData = advData.manufacturerData[0xFFFF];
      if (meshData == null || meshData.length < 6) continue;

      final buffer = ByteData.view(Uint8List.fromList(meshData).buffer);
      final stableId = buffer.getUint32(0, Endian.big);

      // Extract scan response data from local name if possible
      // In this prototype, we prepend 12 bytes of scan response data to the name
      Uint8List? scanResponseData;
      String displayName = "Unknown device";
      
      if (advData.advName.length >= 12) {
        scanResponseData = Uint8List.fromList(advData.advName.substring(0, 12).codeUnits);
        displayName = advData.advName.substring(12);
      } else if (advData.advName.isNotEmpty) {
        displayName = advData.advName;
      }

      final device = FoundDevice()
        ..stableId = stableId
        ..remoteId = result.device.remoteId.toString()
        ..name = displayName
        ..rssi = result.rssi
        ..lastSeen = DateTime.now();

      if (scanResponseData != null) {
        // Full hash is bytes 6-11 of scanResponseData
        final fullHashBytes = scanResponseData.sublist(6, 12);
        device.profileHash = fullHashBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      }

      try {
        // Upsert by stableId
        final existing = await isarService.db.foundDevices
            .where()
            .stableIdEqualTo(stableId)
            .findFirst();

        if (existing != null) {
          device.id = existing.id; // Keep Isar internal ID
          device.profilePicture = existing.profilePicture;
          device.lastPictureSync = existing.lastPictureSync;
          
          // Check for picture update
          bool hashChanged = device.profileHash != null && existing.profileHash != device.profileHash;
          bool needsForcedSync = existing.lastPictureSync == null || 
              DateTime.now().difference(existing.lastPictureSync!).inHours >= 24;

          if (hashChanged || needsForcedSync) {
             _fetchProfilePicture(result.device, isarService, stableId);
          }
        } else {
          // New device discovered
          _fetchProfilePicture(result.device, isarService, stableId);
        }

        await isarService.putFoundDevice(device);
      } catch (e) {
        // Log error
      }
    }
  });

  const scanDuration = Duration(seconds: 20);
  const waitDuration = Duration(seconds: 80);
  DateTime? scanStartTime;

  // Progress emitter
  Timer.periodic(const Duration(milliseconds: 500), (t) {
    if (FlutterBluePlus.isScanningNow && scanStartTime != null) {
      final elapsed = DateTime.now().difference(scanStartTime!);
      final progress = elapsed.inMilliseconds / scanDuration.inMilliseconds;
      service.invoke('updateProgress', {'value': progress.clamp(0.0, 1.0)});
    } else {
      service.invoke('updateProgress', {'value': 0.0});
    }
  });

  // Scanning loop
  Timer.periodic(waitDuration + scanDuration, (timer) async {
    try {
      service.invoke("updateAdvertisingName", {"name": currentName});

      if (await FlutterBluePlus.isSupported == false) return;

      if (FlutterBluePlus.isScanningNow == false) {
        scanStartTime = DateTime.now();
        await FlutterBluePlus.startScan(
          timeout: scanDuration,
          withServices: [Guid(BLEAdvertiser.serviceUuid)],
          androidScanMode: AndroidScanMode.lowPower,
        );
      }
    } catch (e) {
      scanStartTime = null;
    }
  });

  // Start first scan immediately
  if (await FlutterBluePlus.isSupported) {
    scanStartTime = DateTime.now();
    await FlutterBluePlus.startScan(
      timeout: scanDuration,
      withServices: [Guid(BLEAdvertiser.serviceUuid)],
      androidScanMode: AndroidScanMode.lowPower,
    );
  }

  service.on('stopService').listen((event) async {
    await advertiser.stopAdvertising();
    service.stopSelf();
  });

  service.on('setAdvertisingName').listen((event) {
    final name = event?['name'];
    if (name is String) {
      currentName = name;
      updateAd();
    }
  });

  service.on('setOnlineStatus').listen((event) {
    final status = event?['isOnline'];
    if (status is bool) {
      isOnline = status;
      updateAd();
    }
  });
}

Future<void> _fetchProfilePicture(
    BluetoothDevice device, IsarService isar, int stableId) async {
  try {
    await device.connect(
        timeout: const Duration(seconds: 5), license: License.free);
    final services = await device.discoverServices();
    BluetoothCharacteristic? picChar;

    for (final s in services) {
      if (s.uuid.toString().toLowerCase() ==
          BLEAdvertiser.serviceUuid.toLowerCase()) {
        for (final c in s.characteristics) {
          if (c.uuid.toString().toLowerCase() ==
              BLEAdvertiser.profilePicCharUuid.toLowerCase()) {
            picChar = c;
            break;
          }
        }
      }
    }

    if (picChar != null) {
      final value = await picChar.read();
      if (value.isNotEmpty) {
        final existing = await isar.db.foundDevices
            .where()
            .stableIdEqualTo(stableId)
            .findFirst();
        if (existing != null) {
          existing.profilePicture = value;
          existing.lastPictureSync = DateTime.now();
          await isar.putFoundDevice(existing);
        }
      }
    }
  } catch (e) {
    // Silent fail
  } finally {
    await device.disconnect();
  }
}
