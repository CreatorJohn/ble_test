import 'package:ble_test/advertise_widget.dart';
import 'package:ble_test/ble_advertiser.dart';
import 'package:ble_test/watch_log.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await WatchLog.initialize();
  runApp(MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final BLEAdvertiser _bleAdvertiser = BLEAdvertiser();
  bool? _advertising;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('BLE Test')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          spacing: 16.0,
          children: [
            Text(
              'BLE Advertising is ${_advertising == null ? 'checking...' : (_advertising! ? 'ON' : 'OFF')}',
              style: const TextStyle(fontSize: 18),
            ),
            ElevatedButton(
              onPressed: () async {
                await _bleAdvertiser.initialize();

                if (!context.mounted) return;

                setState(() => _advertising = false);

                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('BLE Advertising initialized')),
                );
              },
              child: const Text('Advertise'),
            ),
            ElevatedButton(
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => LayoutBuilder(
                    builder: (context, constrains) {
                      return AlertDialog(
                        constraints: BoxConstraints(
                          maxWidth: constrains.maxWidth * 0.9,
                          maxHeight: constrains.maxHeight * 0.9,
                        ),
                        insetPadding: const EdgeInsets.all(4.0),
                        title: Row(
                          spacing: 4.0,
                          children: [
                            const Expanded(
                              child: Text(
                                'Log Output',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            IconButton(
                              style: IconButton.styleFrom(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8.0),
                                ),
                              ),
                              icon: const Icon(Icons.delete, color: Colors.red),
                              tooltip: 'Clear logs',
                              onPressed: WatchLog.clearLogs,
                            ),
                            IconButton(
                              style: IconButton.styleFrom(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8.0),
                                ),
                              ),
                              icon: const Icon(Icons.copy),
                              tooltip: 'Copy logs',
                              onPressed: WatchLog.copyLogsToClipboard,
                            ),
                            IconButton(
                              style: IconButton.styleFrom(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8.0),
                                ),
                              ),
                              icon: const Icon(Icons.close),
                              tooltip: 'Close',
                              onPressed: Navigator.of(context).pop,
                            ),
                          ],
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                        content: SizedBox(
                          width: double.maxFinite,
                          height: double.maxFinite,
                          child: const LogViewer(),
                        ),
                      );
                    },
                  ),
                );
              },
              child: const Text('Show Logs'),
            ),
            if (_advertising != null)
              AdvertiseWidget(
                advertising: _advertising!,
                onStart: (localName) async {
                  await _bleAdvertiser.startAdvertising(localName: localName);
                  setState(() => _advertising = true);
                },
                onStop: () async {
                  await _bleAdvertiser.stopAdvertising();
                  setState(() => _advertising = false);
                },
              ),
          ],
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
  late final List<(String content, Level level)> logs;
  late final LogListener _logListener;

  @override
  void initState() {
    super.initState();
    logs = WatchLog.logs.toList();
    _logListener = (time, level, name, message) {
      setState(() {
        logs.add(('[$time] [$level] $name: $message', level));
      });
    };
    WatchLog.addListener(_logListener);
  }

  Color _getColor(Level level) {
    if (level == Level.INFO) return Colors.green;
    if (level == Level.WARNING) return Colors.yellow;
    if (level == Level.SEVERE) return Colors.red;
    if (level == Level.FINE || level == Level.FINER || level == Level.FINEST) {
      return Colors.blue;
    }
    if (level == Level.CONFIG) return Colors.purple;
    if (level == Level.SHOUT) return Colors.orange;
    return Colors.black;
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: logs.length,
      itemBuilder: (context, index) {
        final log = logs[index];
        return Text(
          log.$1,
          style: TextStyle(color: _getColor(log.$2), fontSize: 12),
        );
      },
    );
  }

  @override
  void dispose() {
    WatchLog.removeListener(_logListener);
    super.dispose();
  }
}
