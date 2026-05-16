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
  static const int typeIdentity = 0x06;
  static const int typeSyncDone = 0x07;
  static const int typeRequestProfilePic = 0x08;

  static const int maxTTL = 10;
  static const int scanDurationSeconds = 10;
  static const int waitDurationSeconds = 50;

  static final Map<int, DateTime> _seenRelayMessageIds = {};
  static final Map<int, PendingAck> _pendingAcks = {};
  static final Map<int, Completer<void>> _syncDoneCompleters = {};
  static int? _waitingForImageFrom;
  static Timer? _cacheCleanupTimer;

  static void _startCacheCleanupTimer() {
    _cacheCleanupTimer?.cancel();
    _cacheCleanupTimer = Timer.periodic(const Duration(seconds: 60), (timer) {
      final now = DateTime.now();

      // Formula: maxTTL * (scanDuration + waitDuration) + 20
      const cacheLifetimeSeconds =
          maxTTL * (scanDurationSeconds + waitDurationSeconds) + 20;

      _seenRelayMessageIds.removeWhere(
        (id, timestamp) =>
            now.difference(timestamp).inSeconds > cacheLifetimeSeconds,
      );

      // Cleanup breadcrumbs (2x cache lifetime)
      _pendingAcks.removeWhere(
        (key, pendingAck) =>
            now.difference(pendingAck.timestamp).inSeconds >
            (cacheLifetimeSeconds * 2),
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

            // Generate and push ACK (don't await to avoid blocking message processing, but handle errors)
            _pushAck(directSenderId, originSenderId, msgId).catchError((e) {
              _log.warning('Failed to send inbound ACK for $msgId: $e');
            });

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
        } else if (type == typeIdentity) {
          _log.info('Received Identity Message from $directSenderId');
          await handlePeerIdentity(directSenderId, fullData);
          return;
        } else if (type == typeSyncDone) {
          _log.info('Received SyncDone from $directSenderId');
          _syncDoneCompleters[directSenderId]?.complete();
          return;
        } else if (type == typeRequestProfilePic) {
          _log.info('Peer $directSenderId requested our profile picture');
          // This will be handled by the listener in _fetchFullMetadata (Device A)
          // or we trigger it if we are Device A.
          _syncDoneCompleters[directSenderId]?.completeError('request_pic');
          return;
        } else {
          decryptedData = await _decryptMessage(originSenderId, fullData);
          if (decryptedData == null || decryptedData.isEmpty) return;
          payloadToProcess = decryptedData;
        }

        // Processing Logic (decrypted inner or direct payload)
        final innerType = payloadToProcess[0];
        final payload = payloadToProcess.sublist(1);

        if (innerType == typeProfilePic) {
          _log.info(
            'Received profile picture payload (${payload.length} bytes) from $originSenderId',
          );
          final isar = IsarService();
          final device = await isar.db.foundDevices
              .where()
              .stableIdEqualTo(originSenderId)
              .findFirst();
          if (device != null) {
            _log.info(
              'Updating Isar record for device $originSenderId with new profile picture',
            );
            device.profilePicture = payload;
            device.lastPictureSync = DateTime.now();
            await isar.putFoundDevice(device);
            _log.info('Isar record updated successfully for $originSenderId');
          } else {
            _log.warning(
              'Received profile picture for unknown device $originSenderId',
            );
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

  static Future<void> sendMessage({
    required int targetStableId,
    required String content,
  }) async {
    final isar = IsarService();
    final device = await isar.db.foundDevices
        .where()
        .stableIdEqualTo(targetStableId)
        .findFirst();

    if (device == null) {
      throw Exception("Device not found in database");
    }

    final relayPayload = await getRelayWrappedPayload(
      targetStableId,
      text: content,
    );

    if (relayPayload == null) {
      throw Exception("Encryption handshake required");
    }

    final messageId = relayPayload[9];

    try {
      // _pushData handles the "if connected" logic
      await _pushData(device.remoteId, targetStableId, relayPayload, messageId);

      await handleOutgoingMessage(
        receiverStableId: targetStableId,
        content: content,
        messageId: messageId,
        wasSent: true,
      );
    } catch (e) {
      _log.severe('Failed to send message: $e');
      await handleOutgoingMessage(
        receiverStableId: targetStableId,
        content: content,
        messageId: messageId,
        wasSent: false,
        wasFailed: true,
      );
    }
  }

  static Future<void> checkExpiredMessages() async {
    final isar = IsarService();
    if (!isar.isOpen) return;

    // TTL 10 * 3 = 30 hops. Let's assume 20s per hop max (conservative)
    // 30 * 20s = 600s = 10 minutes
    final threshold = DateTime.now().subtract(const Duration(minutes: 10));

    final expired = await isar.db.messages
        .filter()
        .wasSentEqualTo(true)
        .isDeliveredEqualTo(false)
        .wasFailedEqualTo(false)
        .timestampLessThan(threshold)
        .findAll();

    if (expired.isNotEmpty) {
      _log.info('Marking ${expired.length} messages as failed (ACK timeout)');
      await isar.db.writeTxn(() async {
        for (final msg in expired) {
          msg.wasFailed = true;
          await isar.db.messages.put(msg);
        }
      });
    }
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
    int messageId,
  ) async {
    final device = BluetoothDevice.fromId(remoteId);
    bool alreadyConnected = false;

    try {
      final state = await device.connectionState.first.timeout(
        const Duration(seconds: 1),
        onTimeout: () => BluetoothConnectionState.disconnected,
      );
      alreadyConnected = state == BluetoothConnectionState.connected;

      if (!alreadyConnected) {
        _log.info('Connecting to neighbor $stableId for push...');
        await device.connect(
          timeout: const Duration(seconds: 15),
          autoConnect: false,
          license: License.free,
        );
      }

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
      rethrow;
    } finally {
      if (!alreadyConnected) {
        try {
          await device.disconnect();
        } catch (_) {}
      }
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
    bool wasSent = false,
    bool wasFailed = false,
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
        ..messageId = messageId
        ..wasSent = wasSent
        ..wasFailed = wasFailed;

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

  static Future<void> _pushAck(
    int targetNodeId,
    int originId,
    int msgId,
  ) async {
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

  static Future<void> handlePeerIdentity(
    int peerStableId,
    Uint8List payload,
  ) async {
    try {
      if (payload.length < 43) return; // 1+4+6+32 + name
      final buffer = ByteData.view(payload.buffer);
      final id = buffer.getUint32(1, Endian.big);
      final hash = payload.sublist(5, 11);
      final pubKey = payload.sublist(11, 43);
      final name = utf8.decode(payload.sublist(43), allowMalformed: true);
      final hashHex =
          hash.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

      final isar = IsarService();
      var dev =
          await isar.db.foundDevices.where().stableIdEqualTo(id).findFirst();

      bool needsPic = false;
      if (dev == null) {
        _log.info('New peer identified: $name ($id)');
        dev = FoundDevice()
          ..stableId = id
          ..name = name
          ..profileHash = hashHex
          ..publicKey = pubKey
          ..lastSeen = DateTime.now();
        needsPic = true;
      } else {
        if (dev.profileHash != hashHex) {
          _log.info('Peer $id updated profile hash');
          dev.profileHash = hashHex;
          needsPic = true;
        }
        dev.name = name;
        dev.publicKey = pubKey;
        dev.lastSeen = DateTime.now();
      }
      await isar.putFoundDevice(dev);

      if (needsPic) {
        _log.info('Requesting profile picture from $id');
        _waitingForImageFrom = id;
        final req = Uint8List(1);
        req[0] = typeRequestProfilePic;
        // Find remoteId for this peer
        final remoteId = dev.remoteId;
        await BLEAdvertiser.sendNotification(
          characteristicUuid: BLEAdvertiser.messageCharUuid,
          value: req,
          deviceId: remoteId,
        );
      } else {
        // No picture needed, push queue immediately
        await pushQueuedDataToPeer(id, useNotifications: true);
      }
    } catch (e) {
      _log.severe('Error handling peer identity: $e');
    }
  }

  static Future<void> pushQueuedDataToPeer(
    int peerStableId, {
    required bool useNotifications,
    BluetoothCharacteristic? centralWriteChar,
  }) async {
    final isar = IsarService();
    final unsent = await isar.db.messages
        .filter()
        .receiverStableIdEqualTo(peerStableId)
        .wasSentEqualTo(false)
        .findAll();

    _log.info(
        'Pushing ${unsent.length} queued messages to $peerStableId (Notifications: $useNotifications)');

    for (final msg in unsent) {
      final payload = await getRelayWrappedPayload(
        peerStableId,
        text: msg.content,
        image: msg.isImage ? msg.data as Uint8List? : null,
      );

      if (payload != null) {
        final msgId = payload[9];
        if (useNotifications) {
          final dev = await isar.db.foundDevices
              .where()
              .stableIdEqualTo(peerStableId)
              .findFirst();
          if (dev != null) {
            await _notifyData(dev.remoteId, payload, msgId);
          }
        } else if (centralWriteChar != null) {
          final chunks = ChunkedTransferManager.generateChunks(payload, msgId);
          for (final c in chunks) {
            await centralWriteChar.write(c, withoutResponse: false);
          }
        }
        msg.wasSent = true;
        await isar.putMessage(msg);
      }
    }

    if (useNotifications) {
      _log.info('Sending SyncDone to $peerStableId');
      final done = Uint8List(1);
      done[0] = typeSyncDone;
      final dev = await isar.db.foundDevices
          .where()
          .stableIdEqualTo(peerStableId)
          .findFirst();
      if (dev != null) {
        await BLEAdvertiser.sendNotification(
          characteristicUuid: BLEAdvertiser.messageCharUuid,
          value: done,
          deviceId: dev.remoteId,
        );
      }
    }
  }

  static Future<void> _notifyData(
    String remoteId,
    Uint8List payload,
    int messageId,
  ) async {
    final chunks = ChunkedTransferManager.generateChunks(payload, messageId);
    for (final chunk in chunks) {
      await BLEAdvertiser.sendNotification(
        characteristicUuid: BLEAdvertiser.messageCharUuid,
        value: chunk,
        deviceId: remoteId,
      );
    }
  }

  static Future<void> streamOurProfilePic(
    String remoteId,
    int peerStableId,
    BluetoothCharacteristic? centralWriteChar,
  ) async {
    final pic = await ProfileManager.getProfilePicture();
    if (pic == null || pic.isEmpty) return;

    _log.info('Streaming our profile picture to $peerStableId');
    final payloadWithType = Uint8List(1 + pic.length);
    payloadWithType[0] = typeProfilePic;
    payloadWithType.setRange(1, payloadWithType.length, pic);

    final chunks = ChunkedTransferManager.generateChunks(
      payloadWithType,
      0, // MsgId for pic transfer usually doesn't matter here
    );

    for (final chunk in chunks) {
      if (centralWriteChar != null) {
        await centralWriteChar.write(chunk, withoutResponse: false);
      } else {
        await BLEAdvertiser.sendNotification(
          characteristicUuid: BLEAdvertiser.messageCharUuid,
          value: chunk,
          deviceId: remoteId,
        );
      }
    }

    // After streaming pic, if we are peripheral, we should now push our queue
    if (_waitingForImageFrom == peerStableId) {
      _waitingForImageFrom = null;
      await pushQueuedDataToPeer(peerStableId, useNotifications: true);
    }
  }

  static Completer<void> createSyncCompleter(int peerStableId) {
    final c = Completer<void>();
    _syncDoneCompleters[peerStableId] = c;
    return c;
  }

  static void removeSyncCompleter(int peerStableId) {
    _syncDoneCompleters.remove(peerStableId);
  }
}
