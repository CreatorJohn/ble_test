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

  // Request permissions before starting background service
  await [
    Permission.bluetoothScan,
    Permission.bluetoothConnect,
    Permission.bluetoothAdvertise,
    Permission.location,
    Permission.locationAlways,
    Permission.notification,
  ].request();

  await IsarService().initialize();

  await initializeBackgroundService();

  runApp(const ProviderScope(child: MainApp()));
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
