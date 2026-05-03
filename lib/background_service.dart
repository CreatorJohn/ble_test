import 'dart:async';
import 'dart:ui';

import 'package:ble_test/data/found_device.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:isar_community/isar.dart';
import 'package:path_provider/path_provider.dart';

Future<void> initializeBackgroundService() async {
  final service = FlutterBackgroundService();

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: true,
      isForegroundMode: true,
      notificationChannelId: "ble_scanning_channel",
      initialNotificationTitle: "BLE Test App",
      initialNotificationContent: "Scanning for nearby devices...",
      foregroundServiceTypes: [AndroidForegroundType.connectedDevice],
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

  Isar? isar;
  try {
    final dir = await getApplicationDocumentsDirectory();
    isar = await Isar.open([FoundDeviceSchema], directory: dir.path);
  } catch (e) {
    // If we can't open Isar, we might as well stop or log heavily
    if (service is AndroidServiceInstance) {
      service.setForegroundNotificationInfo(
        title: "BLE Test App - Error",
        content: "Failed to initialize database: $e",
      );
    }
    return;
  }

  FlutterBluePlus.scanResults.listen((results) async {
    if (isar == null || !isar.isOpen) return;

    for (final ScanResult result in results) {
      final device = FoundDevice()
        ..remoteId = result.device.remoteId.toString()
        ..name = result.device.platformName.isNotEmpty
            ? result.device.platformName
            : "Unknown device"
        ..rssi = result.rssi
        ..lastSeen = DateTime.now();

      try {
        await isar.writeTxn(() async {
          await isar!.foundDevices.put(device);
        });
      } catch (e) {
        // Log or handle write error
      }
    }
  });

  Timer.periodic(const Duration(seconds: 80), (timer) async {
    try {
      if (await FlutterBluePlus.isSupported == false) return;

      if (FlutterBluePlus.isScanningNow == false) {
        await FlutterBluePlus.startScan(timeout: const Duration(seconds: 20));
      }
    } catch (e) {
      // Handle scan start error
    }
  });
}
