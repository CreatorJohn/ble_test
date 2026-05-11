import 'dart:async';
import 'dart:typed_data';
import 'package:logging/logging.dart';

class ChunkedTransferManager {
  static final Logger _log = Logger('ChunkedTransferManager');
  static final Map<String, Map<int, Uint8List>> _buffers = {};
  static final Map<String, Timer> _cleanupTimers = {};
  static const int chunkTimeoutSeconds = 60;
  static const int parityInterval = 5; // 1 parity chunk for every 5 data chunks

  static final StreamController<Map<String, dynamic>> _completedPayloads =
      StreamController.broadcast();
  static Stream<Map<String, dynamic>> get onPayloadComplete =>
      _completedPayloads.stream;

  static void handleIncomingChunk({
    required int senderStableId,
    required Uint8List data,
  }) {
    if (data.length < 4) return; // Invalid header

    final messageId = data[0];
    final dataChunksCount = data[1];
    final chunkIndex = data[2];
    final totalChunksCount = data[3]; // Data + Parity
    final payload = data.sublist(4);

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

    // Attempt reassembly if we have enough chunks
    _attemptReassembly(transferKey, senderStableId, dataChunksCount, totalChunksCount);
  }

  static void _attemptReassembly(String key, int senderId, int dataCount, int totalCount) {
    final buffer = _buffers[key];
    if (buffer == null) return;

    // 1. Check if we have all data chunks (Perfect success)
    bool hasAllData = true;
    for (int i = 0; i < dataCount; i++) {
      if (!buffer.containsKey(i)) {
        hasAllData = false;
        break;
      }
    }

    if (hasAllData) {
      _finalizeTransfer(key, senderId, dataCount);
      return;
    }

    // 2. Check if we can recover missing chunks using parity
    // For every block of 5, we can recover if only 1 is missing
    bool canRecover = true;
    for (int blockStart = 0; blockStart < dataCount; blockStart += parityInterval) {
      int missingInData = 0;
      int missingIndex = -1;
      
      for (int i = blockStart; i < blockStart + parityInterval && i < dataCount; i++) {
        if (!buffer.containsKey(i)) {
          missingInData++;
          missingIndex = i;
        }
      }

      if (missingInData == 1) {
        // We have exactly one missing. Do we have the corresponding parity chunk?
        final parityIndex = dataCount + (blockStart ~/ parityInterval);
        if (buffer.containsKey(parityIndex)) {
          // YES! Recover missingIndex using XOR
          buffer[missingIndex] = _recoverChunk(buffer, blockStart, dataCount, parityIndex);
          _log.info('Recovered missing chunk $missingIndex for transfer $key using FEC');
        } else {
          canRecover = false;
        }
      } else if (missingInData > 1) {
        canRecover = false;
      }
    }

    // 3. Final check after recovery attempt
    if (canRecover) {
      // Re-verify we actually have all data chunks now
      for (int i = 0; i < dataCount; i++) {
        if (!buffer.containsKey(i)) return;
      }
      _finalizeTransfer(key, senderId, dataCount);
    }
  }

  static Uint8List _recoverChunk(Map<int, Uint8List> buffer, int blockStart, int dataCount, int parityIndex) {
    final parity = buffer[parityIndex]!;
    final result = Uint8List.fromList(parity);

    for (int i = blockStart; i < blockStart + parityInterval && i < dataCount; i++) {
      final chunk = buffer[i];
      if (chunk != null) {
        for (int b = 0; b < chunk.length; b++) {
          result[b] ^= chunk[b];
        }
      }
    }
    return result;
  }

  static void _finalizeTransfer(String key, int senderId, int dataCount) {
    final buffer = _buffers[key]!;
    final builder = BytesBuilder();
    for (int i = 0; i < dataCount; i++) {
      builder.add(buffer[i]!);
    }

    _buffers.remove(key);
    _cleanupTimers[key]?.cancel();
    _cleanupTimers.remove(key);
    
    _completedPayloads.add({
      'senderStableId': senderId,
      'payload': builder.toBytes(),
    });
  }

  static List<Uint8List> generateChunks(Uint8List payload, int messageId,
      {int maxChunkSize = 200}) {
    final List<Uint8List> dataChunks = [];
    int offset = 0;
    
    // 1. Generate Data Chunks
    while (offset < payload.length) {
      final end = (offset + maxChunkSize > payload.length)
          ? payload.length
          : offset + maxChunkSize;
      dataChunks.add(payload.sublist(offset, end));
      offset += maxChunkSize;
    }

    final int dataCount = dataChunks.length;
    final List<Uint8List> finalChunks = [];

    // 2. Generate Parity Chunks
    final List<Uint8List> parityChunks = [];
    for (int i = 0; i < dataCount; i += parityInterval) {
      final parity = Uint8List(maxChunkSize);
      for (int j = i; j < i + parityInterval && j < dataCount; j++) {
        final chunk = dataChunks[j];
        for (int b = 0; b < chunk.length; b++) {
          parity[b] ^= chunk[b];
        }
      }
      parityChunks.add(parity);
    }

    final int totalCount = dataCount + parityChunks.length;

    // 3. Package Everything with Header
    // Header format: [MsgId, DataCount, Index, TotalCount]
    for (int i = 0; i < dataCount; i++) {
      final chunk = Uint8List(4 + dataChunks[i].length);
      chunk[0] = messageId;
      chunk[1] = dataCount;
      chunk[2] = i;
      chunk[3] = totalCount;
      chunk.setRange(4, chunk.length, dataChunks[i]);
      finalChunks.add(chunk);
    }

    for (int i = 0; i < parityChunks.length; i++) {
      final chunk = Uint8List(4 + parityChunks[i].length);
      chunk[0] = messageId;
      chunk[1] = dataCount;
      chunk[2] = dataCount + i;
      chunk[3] = totalCount;
      chunk.setRange(4, chunk.length, parityChunks[i]);
      finalChunks.add(chunk);
    }

    return finalChunks;
  }
}
