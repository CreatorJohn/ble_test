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
    String? remoteId,
  }) {
    if (data.length < 4) return; // Invalid header

    final messageId = data[0];
    final dataChunksCount = data[1];
    final chunkIndex = data[2];
    // Byte 3 (totalCount) is now redundant but kept for 4-byte header consistency
    final payload = data.sublist(4);

    final transferKey = "${senderStableId}_$messageId";

    _buffers.putIfAbsent(transferKey, () => {});
    _buffers[transferKey]![chunkIndex] = payload;

    _cleanupTimers[transferKey]?.cancel();
    _cleanupTimers[transferKey] = Timer(
      const Duration(seconds: chunkTimeoutSeconds),
      () {
        _buffers.remove(transferKey);
        _cleanupTimers.remove(transferKey);
        _log.warning('Transfer $transferKey timed out and was cleared.');
      },
    );

    // Reassembly check: do we have all data chunks?
    final buffer = _buffers[transferKey]!;
    if (buffer.length == dataChunksCount) {
      _finalizeTransfer(
        key: transferKey,
        senderId: senderStableId,
        dataCount: dataChunksCount,
        remoteId: remoteId,
      );
    }
  }

  static void _finalizeTransfer({
    required String key,
    required int senderId,
    required int dataCount,
    String? remoteId,
  }) {
    final buffer = _buffers[key]!;
    final builder = BytesBuilder();
    for (int i = 0; i < dataCount; i++) {
      if (!buffer.containsKey(i)) {
        _log.severe('Finalizing transfer $key but missing chunk $i');
        return;
      }
      builder.add(buffer[i]!);
    }

    _buffers.remove(key);
    _cleanupTimers[key]?.cancel();
    _cleanupTimers.remove(key);

    _completedPayloads.add({
      'senderStableId': senderId,
      'payload': builder.toBytes(),
      'remoteId': remoteId,
    });
  }

  static List<Uint8List> generateChunks(
    Uint8List payload,
    int messageId, {
    int maxChunkSize = 200,
  }) {
    final List<Uint8List> finalChunks = [];
    int offset = 0;
    int index = 0;

    // 1. Calculate how many chunks we need
    final int dataCount = (payload.length / maxChunkSize).ceil();

    // 2. Generate Data Chunks
    while (offset < payload.length) {
      final end = (offset + maxChunkSize > payload.length)
          ? payload.length
          : offset + maxChunkSize;
      final chunkData = payload.sublist(offset, end);

      // Header format: [MsgId, DataCount, Index, TotalCount (unused)]
      final chunk = Uint8List(4 + chunkData.length);
      chunk[0] = messageId;
      chunk[1] = dataCount;
      chunk[2] = index;
      chunk[3] = dataCount; // Total count same as data count
      chunk.setRange(4, chunk.length, chunkData);

      finalChunks.add(chunk);
      offset += maxChunkSize;
      index++;
    }

    return finalChunks;
  }
}
