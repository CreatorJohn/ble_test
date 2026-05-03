import 'package:ble_test/background_service.dart';
import 'package:ble_test/data/isar_service.dart';
import 'package:ble_test/router.dart';
import 'package:ble_test/watch_log.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await WatchLog.initialize();

  // 1. Request foreground permissions first
  await [
    Permission.bluetoothScan,
    Permission.bluetoothConnect,
    Permission.bluetoothAdvertise,
    Permission.location,
    Permission.notification,
  ].request();

  // 2. Request background location separately (Mandatory for Android 11+)
  if (await Permission.location.isGranted) {
    await Permission.locationAlways.request();
  }

  // 3. Safety delay for Chromebook/Android stabilization after dialogs close
  await Future.delayed(const Duration(milliseconds: 500));

  await IsarService().initialize();

  runApp(const ProviderScope(child: MainApp()));

  // 3. Start service AFTER UI is up and permission confirmed
  Future.delayed(const Duration(seconds: 3), () async {
    if (await Permission.notification.isGranted) {
      await initializeBackgroundService();
    }
  });
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      routerConfig: router,
    );
  }
}
