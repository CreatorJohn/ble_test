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

  await updateAd();

  Geolocator.getPositionStream(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5,
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
    return;
  }

  FlutterBluePlus.scanResults.listen((results) async {
    if (!isarService.isOpen) return;

    for (final ScanResult result in results) {
      final advData = result.advertisementData;

      // Manufacturer ID 0xFFFF used in our BLEAdvertiser
      final meshData = advData.manufacturerData[0xFFFF];
      if (meshData == null || meshData.length < 5) continue;

      final buffer = ByteData.view(Uint8List.fromList(meshData).buffer);
      final stableId = buffer.getUint32(0, Endian.big);
      // Version Tag is the top 6 bits of the 5th byte (index 4)
      final currentVersionTag = (meshData[4] >> 2) & 0x3F;

      final device = FoundDevice()
        ..stableId = stableId
        ..remoteId = result.device.remoteId.toString()
        ..name = advData.advName.isNotEmpty ? advData.advName : "Unknown device"
        ..rssi = result.rssi
        ..lastSeen = DateTime.now();

      try {
        final existing = await isarService.db.foundDevices
            .where()
            .stableIdEqualTo(stableId)
            .findFirst();

        bool needsMetadataUpdate = false;

        if (existing != null) {
          device.id = existing.id;
          device.profilePicture = existing.profilePicture;
          device.lastPictureSync = existing.lastPictureSync;
          device.profileHash = existing.profileHash;

          // Compare stored hash's prefix with currentVersionTag
          int prevVersionTag = -1;
          if (existing.profileHash != null) {
            final hex = existing.profileHash!;
            if (hex.length >= 2) {
              final b1 = int.parse(hex.substring(0, 2), radix: 16);
              prevVersionTag = (b1 >> 2) & 0x3F;
            }
          }

          bool hashChanged = prevVersionTag != currentVersionTag;
          bool needsForcedSync = existing.lastPictureSync == null ||
              DateTime.now().difference(existing.lastPictureSync!).inHours >= 24;

          if (hashChanged || needsForcedSync) {
            needsMetadataUpdate = true;
          }
        } else {
          needsMetadataUpdate = true;
        }

        if (needsMetadataUpdate) {
          _fetchFullMetadata(result.device, isarService, stableId);
        }

        await isarService.putFoundDevice(device);
      } catch (e) {
        // Handle error
      }
    }
  });

  const scanDuration = Duration(seconds: 20);
  const waitDuration = Duration(seconds: 80);
  DateTime? scanStartTime;

  Timer.periodic(const Duration(milliseconds: 500), (t) {
    if (FlutterBluePlus.isScanningNow && scanStartTime != null) {
      final elapsed = DateTime.now().difference(scanStartTime!);
      final progress = elapsed.inMilliseconds / scanDuration.inMilliseconds;
      final clamped = progress.clamp(0.0, 1.0);
      service.invoke('updateProgress', {'value': clamped});
    } else {
      service.invoke('updateProgress', {'value': 0.0});
      service.invoke("updateBackgroundServiceStatus", {"active": false});
    }
  });

  Future<void> startSafeScan() async {
    try {
      // Chromebook fix: Ensure location service is enabled
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (service is AndroidServiceInstance) {
          service.setForegroundNotificationInfo(
            title: "BLE Scanner - Inactive",
            content: "Please enable system location services.",
          );
        }
        return;
      }

      service.invoke("updateAdvertisingName", {"name": currentName});
      service.invoke("updateBackgroundServiceStatus", {"active": true});

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
  }

  Timer.periodic(waitDuration + scanDuration, (timer) async {
    await startSafeScan();
  });

  await startSafeScan();

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

Future<void> _fetchFullMetadata(
  BluetoothDevice device,
  IsarService isar,
  int stableId,
) async {
  try {
    await device.connect(
      timeout: const Duration(seconds: 8),
      license: License.free,
    );
    final services = await device.discoverServices();
    BluetoothCharacteristic? picChar;
    BluetoothCharacteristic? hashChar;

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
        }
      }
    }

    if (hashChar != null) {
      final hashBytes = await hashChar.read();
      final hashHex =
          hashBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

      final existing = await isar.db.foundDevices
          .where()
          .stableIdEqualTo(stableId)
          .findFirst();

      if (existing != null) {
        if (picChar != null &&
            (existing.profilePicture == null ||
                existing.profileHash != hashHex)) {
          existing.profilePicture = await picChar.read();
        }

        existing.profileHash = hashHex;
        existing.lastPictureSync = DateTime.now();
        await isar.putFoundDevice(existing);
      }
    }
  } catch (e) {
  } finally {
    await device.disconnect();
  }
}
