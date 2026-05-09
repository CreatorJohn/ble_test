import 'dart:convert';
import 'package:ble_test/chunked_transfer_manager.dart';
import 'package:ble_test/data/isar_service.dart';
import 'package:ble_test/data/message.dart';
import 'package:ble_test/profile_manager.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:logging/logging.dart';

class MessageHandler {
  static final Logger _log = Logger('MessageHandler');

  static void initialize() {
    ChunkedTransferManager.onPayloadComplete.listen((event) async {
      final senderStableId = event['senderStableId'] as int;
      final data = event['payload'] as Uint8List;

      try {
        final content = utf8.decode(data);
        final myStableId = await ProfileManager.getStableDeviceId();

        final message = Message()
          ..senderStableId = senderStableId
          ..receiverStableId = myStableId
          ..content = content
          ..timestamp = DateTime.now()
          ..isReceived = true;

        await IsarService().putMessage(message);
        _log.info('Reassembled and saved message from $senderStableId: $content');
      } catch (e) {
        _log.severe('Failed to decode reassembled message: $e');
      }
    });
  }

  static Future<void> handleIncomingMessage({
    required int senderStableId,
    required List<int> data,
  }) async {
    ChunkedTransferManager.handleIncomingChunk(
      senderStableId: senderStableId,
      data: Uint8List.fromList(data),
    );
  }

  static Future<void> handleOutgoingMessage({
    required int receiverStableId,
    required String content,
  }) async {
    final myStableId = await ProfileManager.getStableDeviceId();

    final message = Message()
      ..senderStableId = myStableId
      ..receiverStableId = receiverStableId
      ..content = content
      ..timestamp = DateTime.now()
      ..isReceived = false;

    await IsarService().putMessage(message);
    _log.info('Sent message to $receiverStableId: $content');
  }
}
