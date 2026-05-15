import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:logging/logging.dart' show Logger, Level;

typedef LogListener =
    void Function(DateTime time, Level level, String name, String message);

typedef LogRecord = (String content, Level level, String loggerName);

class WatchLog {
  static bool _initialized = false;
  static final Logger _log = Logger('WatchLog');
  static final WatchLog _instance = WatchLog._internal();
  static final List<LogRecord> _logBuffer = [];
  static final StreamController<LogRecord> _logStream =
      StreamController.broadcast();

  factory WatchLog() => _instance;

  WatchLog._internal();

  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    // 1. Initialize local logging
    Logger.root.level = Level.ALL;
    Logger.root.onRecord.listen((record) {
      final message =
          '[${record.time}] [${record.level.name}] ${record.loggerName}: ${record.message}';

      _addLog(message, record.level, record.loggerName);
    });

    // 2. Listen for logs from the background service
    FlutterBackgroundService().on('log').listen((event) {
      final message = event?['message'] as String?;
      final levelName = event?['level'] as String?;
      final loggerName = event?['loggerName'] as String? ?? 'Unknown';
      if (message != null) {
        final level = _parseLevel(levelName);
        _addLog(message, level, loggerName);
      }
    });
  }

  static void _addLog(String message, Level level, String loggerName) {
    _logStream.add((message, level, loggerName));
    _logBuffer.add((message, level, loggerName));
    // Keep buffer manageable
    if (_logBuffer.length > 1000) {
      _logBuffer.removeAt(0);
    }
  }

  static Level _parseLevel(String? name) {
    if (name == 'SEVERE') return Level.SEVERE;
    if (name == 'WARNING') return Level.WARNING;
    if (name == 'CONFIG') return Level.CONFIG;
    if (name == 'FINE') return Level.FINE;
    if (name == 'FINER') return Level.FINER;
    if (name == 'FINEST') return Level.FINEST;
    return Level.INFO;
  }

  static List<LogRecord> get logs => List.unmodifiable(_logBuffer);

  static Stream<LogRecord> get logStream => _logStream.stream;

  static void clearLogs() {
    _logBuffer.clear();
  }

  static Future<void> copyLogsToClipboard() async {
    final logs = List.from(_logBuffer);
    final allLogs = logs.map((it) => it.$1).join('\n');
    await Clipboard.setData(ClipboardData(text: allLogs));

    _log.info('Logs copied to clipboard');
  }
}
