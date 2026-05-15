import 'dart:async';

import 'package:ble_test/watch_log.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart' hide LogRecord;

class LogViewer extends StatefulWidget {
  const LogViewer({super.key});

  @override
  State<LogViewer> createState() => _LogViewerState();
}

class _LogViewerState extends State<LogViewer> {
  final List<LogRecord> logs = [];
  late StreamSubscription<LogRecord> _logListener;

  @override
  void initState() {
    super.initState();

    logs.addAll(WatchLog.logs);

    _logListener = WatchLog.logStream.listen((log) {
      setState(() => logs.add(log));
    });
  }

  Color _getColor(Level level, String loggerName) {
    if (level >= Level.SEVERE) return Colors.red;
    if (level >= Level.WARNING) return Colors.deepOrange;

    if (loggerName.contains('MessageHandler')) return Colors.blue;
    if (loggerName.contains('BLEAdvertiser')) return Colors.orange[800]!;
    if (loggerName.contains('BackgroundService') ||
        loggerName.contains('BLEDiscoverer')) {
      return Colors.teal;
    }
    if (loggerName.contains('ChunkedTransferManager')) return Colors.indigo;
    if (loggerName.contains('ProfileManager')) return Colors.deepPurple;

    if (level == Level.INFO) return Colors.green[700]!;
    if (level <= Level.FINE) return Colors.grey;

    return Colors.black;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
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
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
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
                onPressed: () {
                  WatchLog.clearLogs();
                  setState(() => logs.clear());
                },
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
            child: ListView.builder(
              itemCount: logs.length,
              itemBuilder: (context, index) {
                final log = logs[index];
                return Text(
                  log.$1,
                  style: TextStyle(
                    color: _getColor(log.$2, log.$3),
                    fontSize: 12,
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _logListener.cancel();
    super.dispose();
  }
}
