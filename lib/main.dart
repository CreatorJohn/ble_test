import 'package:ble_test/background_service.dart';
import 'package:ble_test/data/found_device.dart';
import 'package:ble_test/router.dart';
import 'package:ble_test/watch_log.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar_community/isar.dart';
import 'package:path_provider/path_provider.dart';

late Isar isar;
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await WatchLog.initialize();

  final dir = await getApplicationDocumentsDirectory();
  isar = await Isar.open([FoundDeviceSchema], directory: dir.path);

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
