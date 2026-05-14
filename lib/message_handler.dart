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

class MessageHandler {
  static final Logger _log = Logger('MessageHandler');
  static final _cipher = Chacha20.poly1305Aead();
  static final _exchangeAlgorithm = X25519();

  static const int typeText = 0x01;
  static const int typeImage = 0x02;
  static const int typeProfilePic = 0x03;
  static const int typeRelay = 0x04;

  static final Map<int, DateTime> _seenRelayMessageIds = {};
  static Timer? _cacheCleanupTimer;

  static void _startCacheCleanupTimer() {
    _cacheCleanupTimer?.cancel();
    _cacheCleanupTimer = Timer.periodic(const Duration(seconds: 60), (timer) {
      final now = DateTime.now();
      // Cache Lifetime = (TTL 10 * 100s) + 20s = 1020s
      _seenRelayMessageIds.removeWhere((id, timestamp) =>
          now.difference(timestamp) > const Duration(seconds: 1020));
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
          if (fullData.length < 11) return; // Header: Target(4), Origin(4), MsgId(1), TTL(1)
          final buffer = ByteData.view(fullData.buffer);
          final targetId = buffer.getUint32(1, Endian.big);
          originSenderId = buffer.getUint32(5, Endian.big);
          final msgId = fullData[9];
          int ttl = fullData[10];

          // Cache key: OriginSenderId (32-bit) + MsgId (8-bit)
          final cacheKey = (originSenderId << 8) | msgId;

          if (_seenRelayMessageIds.containsKey(cacheKey)) {
            _log.info('Dropped duplicate relay message $msgId from $originSenderId');
            return;
          }
          _seenRelayMessageIds[cacheKey] = DateTime.now();

          final myId = await ProfileManager.getStableDeviceId();
          if (targetId == myId) {
            _log.info('We are the destination for relay message $msgId from $originSenderId');
            final innerPayload = fullData.sublist(11);
            decryptedData = await _decryptMessage(originSenderId, innerPayload);
            if (decryptedData == null || decryptedData.isEmpty) return;
            payloadToProcess = decryptedData;
          } else if (ttl > 1) {
            _log.info('Forwarding relay message $msgId to $targetId (TTL: $ttl)');
            fullData[10] = ttl - 1;
            _forwardRelayPayload(fullData, targetId, directSenderId);
            return;
          } else {
            _log.info('TTL expired for relay message $msgId');
            return;
          }
        } else {
          decryptedData = await _decryptMessage(originSenderId, fullData);
          if (decryptedData == null || decryptedData.isEmpty) return;
          payloadToProcess = decryptedData;
        }

        // Processing Logic (decrypted inner or direct payload)
        final innerType = payloadToProcess[0];
        final payload = payloadToProcess.sublist(1);

        if (innerType == typeProfilePic) {
          final isar = IsarService();
          final device = await isar.db.foundDevices
              .where()
              .stableIdEqualTo(originSenderId)
              .findFirst();
          if (device != null) {
            device.profilePicture = payload;
            device.lastPictureSync = DateTime.now();
            await isar.putFoundDevice(device);
            _log.info('Updated profile picture for $originSenderId');
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
            'Decrypted and saved message from $originSenderId (Type: $innerType)');
      } catch (e) {
        _log.severe('Failed to decrypt or decode message: $e');
      }
    });
  }

  static Future<void> _forwardRelayPayload(
      Uint8List payload, int targetId, int excludeId) async {
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
        return GeoUtils.calculateDistance(a.latitude!, a.longitude!,
                targetDevice.latitude!, targetDevice.longitude!)
            .compareTo(GeoUtils.calculateDistance(b.latitude!, b.longitude!,
                targetDevice.latitude!, targetDevice.longitude!));
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
      FoundDevice neighbor, Uint8List payload) async {
    final device = BluetoothDevice.fromId(neighbor.remoteId);
    try {
      _log.info('Relaying to ${neighbor.stableId}...');
      await device.connect(
          timeout: const Duration(seconds: 15),
          autoConnect: false,
          license: License.free);

      if (Platform.isAndroid) {
        try {
          await device.requestMtu(517);
        } catch (_) {}
      }

      final mtu = await device.mtu.first
          .timeout(const Duration(seconds: 3), onTimeout: () => 23);
      final maxChunkSize = (mtu - 10).clamp(20, 500);

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
        final messageId = payload[9]; // MsgId is at index 9 in 11-byte header
        final chunks = ChunkedTransferManager.generateChunks(
          payload,
          messageId,
          maxChunkSize: maxChunkSize,
        );

        for (final chunk in chunks) {
          await messageChar.write(chunk, withoutResponse: false);
        }
        _log.info('Relayed message $messageId to ${neighbor.stableId}');
      }
    } catch (e) {
      _log.warning('Failed to relay to ${neighbor.stableId}: $e');
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
        ..data = imageData;

      await isar.putMessage(message);
      _log.info('Saved outgoing message to $receiverStableId');
    } catch (e) {
      _log.severe('Failed to save outgoing message: $e');
    }
  }

  static Future<Uint8List> _encryptMessage(
      Uint8List cleartext, Uint8List theirPubKey) async {
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
      int senderStableId, Uint8List encryptedData) async {
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
      remotePublicKey:
          SimplePublicKey(device.publicKey!, type: KeyPairType.x25519),
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
    final encrypted =
        await getEncryptedPayload(targetStableId, text: text, image: image);
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
    final device = BluetoothDevice.fromId(targetRemoteId);
    try {
      _log.info('Connecting to $targetStableId to push profile picture...');
      await device.connect(
          timeout: const Duration(seconds: 15),
          autoConnect: false,
          license: License.free);

      // --- MTU Negotiation Start ---
      if (Platform.isAndroid) {
        try {
          await device.requestMtu(517);
        } catch (e) {
          _log.warning('MTU Request failed: $e');
        }
      }

      final mtu = await device.mtu.first
          .timeout(const Duration(seconds: 3), onTimeout: () => 23);
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
        final payload = Uint8List(1 + imageBytes.length);
        payload[0] = typeProfilePic;
        payload.setRange(1, payload.length, imageBytes);

        final isar = IsarService();
        final foundDevice = await isar.db.foundDevices
            .where()
            .stableIdEqualTo(targetStableId)
            .findFirst();

        if (foundDevice == null || foundDevice.publicKey == null) {
          _log.warning('Cannot push: Public key missing for $targetStableId');
          return;
        }

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
}
