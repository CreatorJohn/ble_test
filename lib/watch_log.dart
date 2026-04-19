import 'dart:async';

import 'package:flutter/services.dart';
import 'package:logging/logging.dart';

typedef LogListener =
    void Function(DateTime time, Level level, String name, String message);

class WatchLog {
  static bool _initialized = false;
  static final Logger _log = Logger('WatchLog');
  static final WatchLog _instance = WatchLog._internal();
  static final List<(String content, Level level)> _logBuffer = [];
  static final List<LogListener> _listeners = [];
  static StreamController<(String content, Level level)> _logStreamController =
      StreamController.broadcast();

  factory WatchLog() => _instance;

  WatchLog._internal();

  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    // Initialize logging
    Logger.root.level = Level.ALL; // Log all messages
    Logger.root.onRecord.listen((record) {
      for (var listener in _listeners) {
        _logBuffer.add((
          '[${record.time}] [${record.level.name}] ${record.loggerName}: ${record.message}',
          record.level,
        ));
        listener(record.time, record.level, record.loggerName, record.message);
      }
    });
  }

  static List<(String content, Level level)> get logs =>
      List.unmodifiable(_logBuffer);

  static Stream<(String content, Level level)> get logStream async* {
    addListener((time, level, name, message) {
      _logStreamController.add(('[$time] [$level] $name: $message', level));
    });

    for (var log in _logBuffer) {
      _logStreamController.add(log);
    }

    yield* _logStreamController.stream;
  }

  static void clearLogs() {
    _logBuffer.clear();

    _logStreamController.close();
    _logStreamController = StreamController.broadcast();

    _log.info('Logs cleared');
  }

  static void addListener(LogListener listener) {
    _listeners.add(listener);
  }

  static void removeListener(LogListener listener) {
    _listeners.remove(listener);
  }

  static void clearListeners() {
    _listeners.clear();
  }

  static Future<void> copyLogsToClipboard() async {
    // This is a placeholder implementation. In a real app, you would use
    // the clipboard package to copy logs to the clipboard.
    final logs = await _logStreamController.stream.toList();
    final allLogs = logs.map((it) => it.$1).join('\n');
    await Clipboard.setData(ClipboardData(text: allLogs));

    _log.info('Logs copied to clipboard:\n$allLogs');
  }
}
