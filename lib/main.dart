import 'package:ble_test/ble_advertiser.dart';
import 'package:ble_test/watch_log.dart';
import 'package:flutter/material.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await WatchLog.initialize();
  runApp(MainApp());
}

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  final BLEAdvertiser _bleAdvertiser = BLEAdvertiser();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('BLE Test')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton(
                onPressed: () async {
                  await _bleAdvertiser.initialize();

                  if (!context.mounted) return;

                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('BLE Advertising initialized')),
                  );
                },
                child: const Text('Advertise'),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Log Output'),
                      content: SizedBox(
                        width: double.maxFinite,
                        height: 300,
                        child: const LogViewer(),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Close'),
                        ),
                      ],
                    ),
                  );
                },
                child: const Text('Show Logs'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class LogViewer extends StatefulWidget {
  const LogViewer({super.key});

  @override
  State<LogViewer> createState() => _LogViewerState();
}

class _LogViewerState extends State<LogViewer> {
  final List<String> logs = [];

  @override
  void initState() {
    super.initState();
    WatchLog.logStream.listen((log) {
      setState(() {
        logs.add(log);
      });
    });
  }

  Color _getColor(String log) {
    if (log.contains('[INFO]')) return Colors.green;
    if (log.contains('[WARNING]')) return Colors.yellow;
    if (log.contains('[SEVERE]')) return Colors.red;
    if (log.contains('[FINE]') || log.contains('[FINER]') || log.contains('[FINEST]')) return Colors.blue;
    if (log.contains('[CONFIG]')) return Colors.purple;
    if (log.contains('[SHOUT]')) return Colors.orange;
    return Colors.black;
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: logs.length,
      itemBuilder: (context, index) {
        final log = logs[index];
        return Text(
          log,
          style: TextStyle(color: _getColor(log), fontSize: 12),
        );
      },
    );
  }
}
