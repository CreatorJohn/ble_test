import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:ble_test/ble_advertiser.dart';
import 'package:ble_test/chunked_transfer_manager.dart';
import 'package:ble_test/data/isar_service.dart';
import 'package:ble_test/data/message.dart';
import 'package:ble_test/profile_manager.dart';
import 'package:ble_test/utils/geo_utils.dart';
import 'dart:typed_data';
import 'package:logging/logging.dart';
import 'package:cryptography/cryptography.dart';
import 'package:ble_test/data/found_device.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:isar_community/isar.dart';

class PendingAck {
  final int upstreamNodeId;
  final DateTime timestamp;
  PendingAck(this.upstreamNodeId, this.timestamp);
}

class MessageHandler {
  static final Logger _log = Logger('MessageHandler');
  static final _cipher = Chacha20.poly1305Aead();
  static final _exchangeAlgorithm = X25519();

  static const int typeText = 0x01;
  static const int typeImage = 0x02;
  static const int typeProfilePic = 0x03;
  static const int typeRelay = 0x04;
  static const int typeAck = 0x05;

  static final Map<int, DateTime> _seenRelayMessageIds = {};
  static final Map<int, PendingAck> _pendingAcks = {};
  static Timer? _cacheCleanupTimer;

  static void _startCacheCleanupTimer() {
    _cacheCleanupTimer?.cancel();
    _cacheCleanupTimer = Timer.periodic(const Duration(seconds: 60), (timer) {
      final now = DateTime.now();
      // Cache Lifetime = (TTL 10 * 100s) + 20s = 1020s
      _seenRelayMessageIds.removeWhere(
        (id, timestamp) =>
            now.difference(timestamp) > const Duration(seconds: 1020),
      );

      // Cleanup breadcrumbs (50 minutes)
      _pendingAcks.removeWhere(
        (key, pendingAck) =>
            now.difference(pendingAck.timestamp) > const Duration(minutes: 50),
      );
    });
  }

  static void initialize() {
    _startCacheCleanupTimer();
    ChunkedTransferManager.onPayloadComplete.listen((event) async {
      final directSenderId = event['senderStableId'] as int;
      final fullData = event['payload'] as Uint8List;

      try {
        final int type = fullData[0];
        Uint8List? decryptedData;
        Uint8List payloadToProcess;
        int originSenderId = directSenderId;

        if (type == typeRelay) {
          if (fullData.length < 11) {
            return; // Header: Target(4), Origin(4), MsgId(1), TTL(1)
          }
          final buffer = ByteData.view(fullData.buffer);
          final targetId = buffer.getUint32(1, Endian.big);
          originSenderId = buffer.getUint32(5, Endian.big);
          final msgId = fullData[9];
          int ttl = fullData[10];

          // Identity Linking: If this message came directly from the origin,
          // ensure we have their remoteId (MAC) mapped to their stableId.
          // This is critical for non-advertising devices like Chromebooks.
          if (ttl == 10 || ttl == 5) { // Common starting TTLs
             _log.info('Possible direct connection from $originSenderId. Linking identity...');
             _linkIdentity(directSenderId, originSenderId);
          }

          // Cache key: OriginSenderId (32-bit) + MsgId (8-bit)
          final cacheKey = (originSenderId << 8) | msgId;

          if (_seenRelayMessageIds.containsKey(cacheKey)) {
            _log.info(
              'Dropped duplicate relay message $msgId from $originSenderId',
            );
            return;
          }
          _seenRelayMessageIds[cacheKey] = DateTime.now();

          final myId = await ProfileManager.getStableDeviceId();
          if (targetId == myId) {
            _log.info(
              'We are the destination for relay message $msgId from $originSenderId',
            );

            // Generate and push ACK
            _pushAck(directSenderId, originSenderId, msgId);

            final innerPayload = fullData.sublist(11);
            decryptedData = await _decryptMessage(originSenderId, innerPayload);
            if (decryptedData == null || decryptedData.isEmpty) return;
            payloadToProcess = decryptedData;
          } else if (ttl > 1) {
            _log.info(
              'Forwarding relay message $msgId to $targetId (TTL: $ttl)',
            );

            // Drop Breadcrumb
            _pendingAcks[cacheKey] = PendingAck(directSenderId, DateTime.now());

            fullData[10] = ttl - 1;
            _forwardRelayPayload(fullData, targetId, directSenderId);
            return;
          } else {
            _log.info('TTL expired for relay message $msgId');
            return;
          }
        } else {
          _log.info('Direct message from $originSenderId. Linking identity...');
          _linkIdentity(directSenderId, originSenderId);
          decryptedData = await _decryptMessage(originSenderId, fullData);
          if (decryptedData == null || decryptedData.isEmpty) return;
          payloadToProcess = decryptedData;
        }

        // Processing Logic (decrypted inner or direct payload)
        final innerType = payloadToProcess[0];
        final payload = payloadToProcess.sublist(1);

        if (innerType == typeProfilePic) {
          _log.info('Received profile picture payload (${payload.length} bytes) from $originSenderId');
          final isar = IsarService();
          final device = await isar.db.foundDevices
              .where()
              .stableIdEqualTo(originSenderId)
              .findFirst();
          if (device != null) {
            _log.info('Updating Isar record for device $originSenderId with new profile picture');
            device.profilePicture = payload;
            device.lastPictureSync = DateTime.now();
            await isar.putFoundDevice(device);
            _log.info('Isar record updated successfully for $originSenderId');
          } else {
            _log.warning('Received profile picture for unknown device $originSenderId');
          }
          return;
        }

        final myStableId = await ProfileManager.getStableDeviceId();
        final message = Message()
          ..senderStableId = originSenderId
          ..receiverStableId = myStableId
          ..timestamp = DateTime.now()
          ..isReceived = true;

        if (innerType == typeText) {
          message.content = utf8.decode(payload);
          message.isImage = false;
        } else if (innerType == typeImage) {
          message.content = "[Image]";
          message.isImage = true;
          message.data = payload;
        } else {
          _log.warning('Unknown message type received: $innerType');
          return;
        }

        await IsarService().putMessage(message);
        _log.info(
          'Decrypted and saved message from $originSenderId (Type: $innerType)',
        );
      } catch (e) {
        _log.severe('Failed to decrypt or decode message: $e');
      }
    });
  }

  static Future<void> _forwardRelayPayload(
    Uint8List payload,
    int targetId,
    int excludeId,
  ) async {
    final isar = IsarService();
    final neighbors = await isar.findActiveNeighbors(excludeId);
    if (neighbors.isEmpty) {
      _log.info('No active neighbors to forward relay payload');
      return;
    }

    final targetDevice = await isar.db.foundDevices
        .where()
        .stableIdEqualTo(targetId)
        .findFirst();
    final List<FoundDevice> selected;

    if (targetDevice != null && targetDevice.latitude != null) {
      // Scenario A: Directed Beam
      _log.info('Using Directed Beam routing to $targetId');
      neighbors.sort((a, b) {
        if (a.latitude == null || b.latitude == null) return 0;
        return GeoUtils.calculateDistance(
          a.latitude!,
          a.longitude!,
          targetDevice.latitude!,
          targetDevice.longitude!,
        ).compareTo(
          GeoUtils.calculateDistance(
            b.latitude!,
            b.longitude!,
            targetDevice.latitude!,
            targetDevice.longitude!,
          ),
        );
      });
      selected = neighbors.take(3).toList();
    } else {
      // Scenario B: Starburst (Fallback to first 3 for now)
      _log.info('Using Starburst routing (fallback) to $targetId');
      selected = neighbors.take(3).toList();
    }

    for (final neighbor in selected) {
      _pushToNeighbor(neighbor, payload);
    }
  }

  static Future<void> _pushToNeighbor(
    FoundDevice neighbor,
    Uint8List payload,
  ) async {
    final messageId = payload[9]; // MsgId is at index 9 in 11-byte header
    await _pushData(neighbor.remoteId, neighbor.stableId, payload, messageId);
  }

  static Future<void> _pushData(
    String remoteId,
    int stableId,
    Uint8List payload,
    int messageId, {
    int maxChunkSize = 200,
  }) async {
    // 1. Check if they are already connected to US (Inbound)
    if (BLEAdvertiser.isDeviceConnected(remoteId)) {
      _log.info('Using Notify-based push for $stableId (Already connected)');
      final chunks = ChunkedTransferManager.generateChunks(
        payload,
        messageId,
        maxChunkSize: maxChunkSize,
      );
      for (final chunk in chunks) {
        await BLEAdvertiser.sendNotification(
          characteristicUuid: BLEAdvertiser.messageCharUuid,
          value: chunk,
          deviceId: remoteId,
        );
      }
      return;
    }

    // 2. Standard Mesh Push (Connect to THEM)
    final device = BluetoothDevice.fromId(remoteId);
    try {
      _log.info('Connecting to neighbor $stableId for push...');
      await device.connect(
        timeout: const Duration(seconds: 15),
        autoConnect: false,
        license: License.free,
      );

      if (Platform.isAndroid) {
        try {
          await device.requestMtu(517);
        } catch (_) {}
      }

      final mtu = await device.mtu.first.timeout(
        const Duration(seconds: 3),
        onTimeout: () => 23,
      );
      final negotiatedMax = (mtu - 10).clamp(20, 500);

      final services = await device.discoverServices();
      BluetoothCharacteristic? messageChar;
      for (final s in services) {
        if (s.uuid.toString().toLowerCase() ==
            BLEAdvertiser.serviceUuid.toLowerCase()) {
          for (final c in s.characteristics) {
            if (c.uuid.toString().toLowerCase() ==
                BLEAdvertiser.messageCharUuid.toLowerCase()) {
              messageChar = c;
              break;
            }
          }
        }
      }

      if (messageChar != null) {
        final chunks = ChunkedTransferManager.generateChunks(
          payload,
          messageId,
          maxChunkSize: negotiatedMax,
        );

        for (final chunk in chunks) {
          await messageChar.write(chunk, withoutResponse: false);
        }
        _log.info('Data pushed to $stableId successfully.');
      }
    } catch (e) {
      _log.warning('Failed to push data to $stableId: $e');
    } finally {
      try {
        await device.disconnect();
      } catch (_) {}
    }
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
    bool isImage = false,
    Uint8List? imageData,
    int? messageId,
  }) async {
    try {
      final isar = IsarService();
      final myStableId = await ProfileManager.getStableDeviceId();

      final message = Message()
        ..senderStableId = myStableId
        ..receiverStableId = receiverStableId
        ..content = content
        ..timestamp = DateTime.now()
        ..isReceived = false
        ..isImage = isImage
        ..data = imageData
        ..messageId = messageId;

      await isar.putMessage(message);
      _log.info('Saved outgoing message to $receiverStableId');
    } catch (e) {
      _log.severe('Failed to save outgoing message: $e');
    }
  }

  static Future<Uint8List> _encryptMessage(
    Uint8List cleartext,
    Uint8List theirPubKey,
  ) async {
    final myKeyPair = await ProfileManager.getKeyPair();
    final sharedSecret = await _exchangeAlgorithm.sharedSecretKey(
      keyPair: myKeyPair,
      remotePublicKey: SimplePublicKey(theirPubKey, type: KeyPairType.x25519),
    );

    final secretKey = await sharedSecret.extract();
    final secretBox = await _cipher.encrypt(cleartext, secretKey: secretKey);

    // Format: [12-byte Nonce] + [16-byte MAC] + [Ciphertext]
    final result = Uint8List(12 + 16 + secretBox.cipherText.length);
    result.setRange(0, 12, secretBox.nonce);
    result.setRange(12, 28, secretBox.mac.bytes);
    result.setRange(28, result.length, secretBox.cipherText);
    return result;
  }

  static Future<Uint8List?> _decryptMessage(
    int senderStableId,
    Uint8List encryptedData,
  ) async {
    if (encryptedData.length < 28) return null;

    final isar = IsarService();
    final device = await isar.db.foundDevices
        .where()
        .stableIdEqualTo(senderStableId)
        .findFirst();

    if (device == null || device.publicKey == null) {
      _log.warning('Cannot decrypt: Public key missing for $senderStableId');
      return null;
    }

    final myKeyPair = await ProfileManager.getKeyPair();
    final sharedSecret = await _exchangeAlgorithm.sharedSecretKey(
      keyPair: myKeyPair,
      remotePublicKey: SimplePublicKey(
        device.publicKey!,
        type: KeyPairType.x25519,
      ),
    );

    final secretKey = await sharedSecret.extract();

    final nonce = encryptedData.sublist(0, 12);
    final mac = Mac(encryptedData.sublist(12, 28));
    final ciphertext = encryptedData.sublist(28);

    final cleartext = await _cipher.decrypt(
      SecretBox(ciphertext, nonce: nonce, mac: mac),
      secretKey: secretKey,
    );

    return Uint8List.fromList(cleartext);
  }

  static Future<Uint8List?> getEncryptedPayload(
    int receiverStableId, {
    String? text,
    Uint8List? image,
  }) async {
    final isar = IsarService();
    final device = await isar.db.foundDevices
        .where()
        .stableIdEqualTo(receiverStableId)
        .findFirst();

    if (device == null || device.publicKey == null) return null;

    // Build cleartext with header
    final Uint8List cleartext;
    if (image != null) {
      cleartext = Uint8List(1 + image.length);
      cleartext[0] = typeImage;
      cleartext.setRange(1, cleartext.length, image);
    } else {
      final textBytes = utf8.encode(text ?? "");
      cleartext = Uint8List(1 + textBytes.length);
      cleartext[0] = typeText;
      cleartext.setRange(1, cleartext.length, textBytes);
    }

    return await _encryptMessage(
      cleartext,
      Uint8List.fromList(device.publicKey!),
    );
  }

  static Future<Uint8List?> getRelayWrappedPayload(
    int targetStableId, {
    String? text,
    Uint8List? image,
    int ttl = 10,
  }) async {
    final encrypted = await getEncryptedPayload(
      targetStableId,
      text: text,
      image: image,
    );
    if (encrypted == null) return null;

    final myId = await ProfileManager.getStableDeviceId();
    final msgId = Random().nextInt(256);
    final relayPayload = Uint8List(11 + encrypted.length);
    final buffer = ByteData.view(relayPayload.buffer);

    relayPayload[0] = typeRelay;
    buffer.setUint32(1, targetStableId, Endian.big);
    buffer.setUint32(5, myId, Endian.big);
    relayPayload[9] = msgId;
    relayPayload[10] = ttl;
    relayPayload.setRange(11, relayPayload.length, encrypted);

    return relayPayload;
  }

  static Future<void> pushProfilePicture({
    required int targetStableId,
    required String targetRemoteId,
    required Uint8List imageBytes,
  }) async {
    final isar = IsarService();
    final foundDevice = await isar.db.foundDevices
        .where()
        .stableIdEqualTo(targetStableId)
        .findFirst();

    if (foundDevice == null || foundDevice.publicKey == null) {
      _log.warning('Cannot push: Public key missing for $targetStableId');
      return;
    }

    final payload = Uint8List(1 + imageBytes.length);
    payload[0] = typeProfilePic;
    payload.setRange(1, payload.length, imageBytes);

    final encrypted = await _encryptMessage(
      payload,
      Uint8List.fromList(foundDevice.publicKey!),
    );

    final myId = await ProfileManager.getStableDeviceId();
    final msgId = Random().nextInt(256);
    final relayPayload = Uint8List(11 + encrypted.length);
    final buffer = ByteData.view(relayPayload.buffer);

    relayPayload[0] = typeRelay;
    buffer.setUint32(1, targetStableId, Endian.big);
    buffer.setUint32(5, myId, Endian.big);
    relayPayload[9] = msgId;
    relayPayload[10] = 5; // TTL 5 for profile pics
    relayPayload.setRange(11, relayPayload.length, encrypted);

    // 1. Check if they are already connected to US (Inbound)
    if (BLEAdvertiser.isDeviceConnected(targetRemoteId)) {
      _log.info('Using Notify-based profile push for $targetStableId');
      final chunks = ChunkedTransferManager.generateChunks(
        relayPayload,
        msgId,
        maxChunkSize: 200,
      );
      for (final chunk in chunks) {
        await BLEAdvertiser.sendNotification(
          characteristicUuid: BLEAdvertiser.profilePicCharUuid,
          value: chunk,
          deviceId: targetRemoteId,
        );
      }
      return;
    }

    // 2. Standard Mesh Push (Connect to THEM)
    final device = BluetoothDevice.fromId(targetRemoteId);
    try {
      _log.info('Connecting to $targetStableId to push profile picture...');
      await device.connect(
        timeout: const Duration(seconds: 15),
        autoConnect: false,
        license: License.free,
      );

      // --- MTU Negotiation Start ---
      if (Platform.isAndroid) {
        try {
          await device.requestMtu(517);
        } catch (e) {
          _log.warning('MTU Request failed: $e');
        }
      }

      final mtu = await device.mtu.first.timeout(
        const Duration(seconds: 3),
        onTimeout: () => 23,
      );
      final maxChunkSize = (mtu - 10).clamp(20, 500);
      _log.info('Negotiated MTU: $mtu, Chunk size: $maxChunkSize');
      // --- MTU Negotiation End ---

      final services = await device.discoverServices();

      BluetoothCharacteristic? messageChar;
      for (final s in services) {
        if (s.uuid.toString().toLowerCase() ==
            BLEAdvertiser.serviceUuid.toLowerCase()) {
          for (final c in s.characteristics) {
            if (c.uuid.toString().toLowerCase() ==
                BLEAdvertiser.messageCharUuid.toLowerCase()) {
              messageChar = c;
              break;
            }
          }
        }
      }

      if (messageChar != null) {
        final chunks = ChunkedTransferManager.generateChunks(
          relayPayload,
          msgId,
          maxChunkSize: maxChunkSize,
        );

        for (final chunk in chunks) {
          await messageChar.write(chunk, withoutResponse: false);
        }
        _log.info('Profile picture pushed to $targetStableId');
      }
    } catch (e) {
      _log.severe('Failed to push profile picture: $e');
    } finally {
      try {
        await device.disconnect();
      } catch (_) {}
    }
  }

  static Future<void> handleIncomingAck(Uint8List ackPayload) async {
    final buffer = ByteData.view(ackPayload.buffer);
    final targetId = buffer.getUint32(1, Endian.big);
    final originId = buffer.getUint32(5, Endian.big);
    final msgId = ackPayload[9];

    final myId = await ProfileManager.getStableDeviceId();

    if (targetId != myId) {
      return; // Not meant for us to relay
    }

    if (originId == myId) {
      // We are the original sender! Message delivered.
      _log.info('Message $msgId was delivered successfully!');
      final isar = IsarService();
      final msg = await isar.db.messages
          .filter()
          .messageIdEqualTo(msgId)
          .findFirst();
      if (msg != null && !msg.isDelivered) {
        msg.isDelivered = true;
        await isar.putMessage(msg);
      }
      return;
    }

    // We are a relay. Look up breadcrumb.
    final cacheKey = (originId << 8) | msgId;
    final pendingAck = _pendingAcks[cacheKey];

    if (pendingAck != null) {
      _log.info(
        'Relaying ACK for $msgId to upstream node ${pendingAck.upstreamNodeId}',
      );
      _pushAck(pendingAck.upstreamNodeId, originId, msgId);
      _pendingAcks.remove(cacheKey); // First ACK wins
    } else {
      _log.info('Dropped orphan ACK for $msgId');
    }
  }

  static Future<void> _pushAck(int targetNodeId, int originId, int msgId) async {
    final isar = IsarService();
    final neighbor = await isar.db.foundDevices
        .where()
        .stableIdEqualTo(targetNodeId)
        .findFirst();
    if (neighbor == null) return;

    final ackPayload = Uint8List(10);
    final buffer = ByteData.view(ackPayload.buffer);
    ackPayload[0] = typeAck;
    buffer.setUint32(1, targetNodeId, Endian.big);
    buffer.setUint32(5, originId, Endian.big);
    ackPayload[9] = msgId;

    await _pushData(neighbor.remoteId, targetNodeId, ackPayload, msgId);
  }

  static Future<void> _linkIdentity(int directId, int originId) async {
    if (directId == originId) return; // Already same or known

    final isar = IsarService();
    // 1. Find the person who connected (placeholder)
    final placeholder = await isar.db.foundDevices
        .where()
        .stableIdEqualTo(directId)
        .findFirst();
    if (placeholder == null) return;

    // 2. Find the person they claim to be (permanent record)
    final permanent = await isar.db.foundDevices
        .where()
        .stableIdEqualTo(originId)
        .findFirst();

    if (permanent != null) {
      // Merge! Update permanent record with current MAC
      _log.info('Linking MAC ${placeholder.remoteId} to ID $originId');
      permanent.remoteId = placeholder.remoteId;
      permanent.lastSeen = DateTime.now();
      await isar.putFoundDevice(permanent);

      // Clean up placeholder
      await isar.db.writeTxn(() async {
        await isar.db.foundDevices.delete(placeholder.id);
      });
    } else {
      // Create new permanent record with this MAC
      _log.info('Creating new ID record for $originId with MAC ${placeholder.remoteId}');
      final newRecord = FoundDevice()
        ..stableId = originId
        ..remoteId = placeholder.remoteId
        ..name = placeholder.name
        ..lastSeen = DateTime.now();
      await isar.putFoundDevice(newRecord);

      // Clean up placeholder
      await isar.db.writeTxn(() async {
        await isar.db.foundDevices.delete(placeholder.id);
      });
    }
  }
}
