import 'dart:async';
import 'dart:typed_data';
import 'package:logging/logging.dart';

class ChunkedTransferManager {
  static final Logger _log = Logger('ChunkedTransferManager');
  static final Map<String, Map<int, Uint8List>> _buffers = {};
  static final Map<String, Timer> _cleanupTimers = {};
  static const int chunkTimeoutSeconds = 60;

  static final StreamController<Map<String, dynamic>> _completedPayloads =
      StreamController.broadcast();
  static Stream<Map<String, dynamic>> get onPayloadComplete =>
      _completedPayloads.stream;

  static void handleIncomingChunk({
    required int senderStableId,
    required Uint8List data,
  }) {
    if (data.length < 3) return;

    final messageId = data[0];
    final totalChunks = data[1];
    final chunkIndex = data[2];
    final payload = data.sublist(3);

    final transferKey = "${senderStableId}_$messageId";

    _buffers.putIfAbsent(transferKey, () => {});
    _buffers[transferKey]![chunkIndex] = payload;

    _cleanupTimers[transferKey]?.cancel();
    _cleanupTimers[transferKey] =
        Timer(const Duration(seconds: chunkTimeoutSeconds), () {
      _buffers.remove(transferKey);
      _cleanupTimers.remove(transferKey);
      _log.warning('Transfer $transferKey timed out and was cleared.');
    });

    // Check completion (Simple mode for now, FEC/Parity requires complex matrix math)
    if (_buffers[transferKey]!.length == totalChunks) {
      _cleanupTimers[transferKey]?.cancel();
      _cleanupTimers.remove(transferKey);

      final builder = BytesBuilder();
      for (int i = 0; i < totalChunks; i++) {
        if (_buffers[transferKey]![i] == null) {
          _log.severe('Missing chunk $i for transfer $transferKey');
          return;
        }
        builder.add(_buffers[transferKey]![i]!);
      }

      _buffers.remove(transferKey);
      _completedPayloads.add({
        'senderStableId': senderStableId,
        'payload': builder.toBytes(),
      });
    }
  }

  static List<Uint8List> generateChunks(Uint8List payload, int messageId,
      {int maxChunkSize = 200}) {
    final List<Uint8List> chunks = [];
    int offset = 0;
    int chunkIndex = 0;
    final totalChunks = (payload.length / maxChunkSize).ceil();

    if (totalChunks > 255) {
      throw Exception("Payload too large, exceeds 255 chunks limit.");
    }

    while (offset < payload.length) {
      final end = (offset + maxChunkSize > payload.length)
          ? payload.length
          : offset + maxChunkSize;
      final chunkPayload = payload.sublist(offset, end);

      final chunk = Uint8List(3 + chunkPayload.length);
      chunk[0] = messageId;
      chunk[1] = totalChunks;
      chunk[2] = chunkIndex;
      chunk.setRange(3, chunk.length, chunkPayload);

      chunks.add(chunk);
      offset += maxChunkSize;
      chunkIndex++;
    }

    return chunks;
  }
}
