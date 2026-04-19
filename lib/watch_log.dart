import 'dart:async';

import 'package:logging/logging.dart';

typedef LogListener =
    void Function(DateTime time, Level level, String name, String message);

class WatchLog {
  static bool _initialized = false;
  static final WatchLog _instance = WatchLog._internal();
  static final List<LogListener> _listeners = [];

  factory WatchLog() => _instance;

  WatchLog._internal();

  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    // Initialize logging
    Logger.root.level = Level.ALL; // Log all messages
    Logger.root.onRecord.listen((record) {
      for (var listener in _listeners) {
        listener(record.time, record.level, record.loggerName, record.message);
      }
    });
  }

  static Stream<String> get logStream async* {
    final controller = StreamController<String>();
    addListener((time, level, name, message) {
      controller.add('[$time] [$level] $name: $message');
    });
    yield* controller.stream;
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
}
