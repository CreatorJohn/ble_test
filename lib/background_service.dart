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

  final dir = await getApplicationDocumentsDirectory();
  final isar = await Isar.open([FoundDeviceSchema], directory: dir.path);

  FlutterBluePlus.scanResults.listen((results) async {
    for (final ScanResult result in results) {
      final device = FoundDevice()
        ..remoteId = result.device.remoteId.toString()
        ..name = result.device.platformName.isNotEmpty
            ? result.device.platformName
            : "Unknown device"
        ..rssi = result.rssi
        ..lastSeen = DateTime.now();

      await isar.writeTxn(() async {
        await isar.foundDevices.put(device);
      });
    }
  });

  Timer.periodic(const Duration(seconds: 80), (timer) async {
    if (FlutterBluePlus.isScanningNow == false) {
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 20));
    }
  });
}
