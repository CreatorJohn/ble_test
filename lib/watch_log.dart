import 'dart:async';

import 'package:flutter/services.dart';
import 'package:logging/logging.dart' show Logger, Level;

typedef LogListener =
    void Function(DateTime time, Level level, String name, String message);

typedef LogRecord = (String content, Level level);

class WatchLog {
  static bool _initialized = false;
  static final Logger _log = Logger('WatchLog');
  static final WatchLog _instance = WatchLog._internal();
  static final List<LogRecord> _logBuffer = [];
  static StreamController<LogRecord> _logStream = StreamController.broadcast();

  factory WatchLog() => _instance;

  WatchLog._internal();

  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    // Initialize logging
    Logger.root.level = Level.ALL; // Log all messages
    Logger.root.onRecord.listen((record) {
      _logStream.add((
        '[${record.time}] [${record.level.name}] ${record.loggerName}: ${record.message}',
        record.level,
      ));
      _logBuffer.add((
        '[${record.time}] [${record.level.name}] ${record.loggerName}: ${record.message}',
        record.level,
      ));
    });
  }

  static List<LogRecord> get logs => List.unmodifiable(_logBuffer);

  static Stream<LogRecord> get logStream => _logStream.stream;

  static void clearLogs() {
    _logBuffer.clear();
  }

  static Future<void> copyLogsToClipboard() async {
    // This is a placeholder implementation. In a real app, you would use
    // the clipboard package to copy logs to the clipboard.
    final logs = List.from(_logBuffer);
    final allLogs = logs.map((it) => it.$1).join('\n');
    await Clipboard.setData(ClipboardData(text: allLogs));

    _log.info('Logs copied to clipboard');
  }
}
