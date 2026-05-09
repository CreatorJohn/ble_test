import 'dart:convert';
import 'package:ble_test/data/isar_service.dart';
import 'package:ble_test/data/message.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io';
import 'package:logging/logging.dart';

class MessageHandler {
  static final Logger _log = Logger('MessageHandler');
  static String? _deviceId;

  static Future<String> getDeviceId() async {
    if (_deviceId != null) return _deviceId!;
    
    final deviceInfo = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      final androidInfo = await deviceInfo.androidInfo;
      _deviceId = androidInfo.model; // Or use androidId if available via other means
    } else if (Platform.isIOS) {
      final iosInfo = await deviceInfo.iosInfo;
      _deviceId = iosInfo.identifierForVendor;
    } else {
      _deviceId = 'Unknown Device';
    }
    return _deviceId!;
  }

  static Future<void> handleIncomingMessage({
    required String senderId,
    required List<int> data,
  }) async {
    try {
      final content = utf8.decode(data);
      final receiverId = await getDeviceId();
      
      final message = Message()
        ..senderId = senderId
        ..receiverId = receiverId
        ..content = content
        ..timestamp = DateTime.now();

      await IsarService().putMessage(message);
      _log.info('Received message from $senderId: $content');
    } catch (e) {
      _log.severe('Failed to handle incoming message: $e');
    }
  }

  static Future<void> handleOutgoingMessage({
    required String receiverId,
    required String content,
  }) async {
    final senderId = await getDeviceId();
    
    final message = Message()
      ..senderId = senderId
      ..receiverId = receiverId
      ..content = content
      ..timestamp = DateTime.now();

    await IsarService().putMessage(message);
    _log.info('Sent message to $receiverId: $content');
  }
}
