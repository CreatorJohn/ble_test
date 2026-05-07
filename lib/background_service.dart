import 'dart:async';
import 'dart:ui';

import 'package:ble_test/data/found_device.dart';
import 'package:ble_test/data/isar_service.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

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
      final device = FoundDevice()
        ..remoteId = result.device.remoteId.toString()
        ..name = result.device.platformName.isNotEmpty
            ? result.device.platformName
            : "Unknown device"
        ..rssi = result.rssi
        ..lastSeen = DateTime.now();

      try {
        await isarService.putFoundDevice(device);
      } catch (e) {
        // Log or handle write error
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
      if (await FlutterBluePlus.isSupported == false) return;

      if (FlutterBluePlus.isScanningNow == false) {
        scanStartTime = DateTime.now();
        await FlutterBluePlus.startScan(timeout: scanDuration);
      }
    } catch (e) {
      scanStartTime = null;
    }
  });

  // Start first scan immediately
  if (await FlutterBluePlus.isSupported) {
    scanStartTime = DateTime.now();
    FlutterBluePlus.startScan(timeout: scanDuration);
  }

  service.on('stopService').listen((event) {
    service.stopSelf();
  });
}
