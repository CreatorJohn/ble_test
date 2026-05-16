import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:ble_test/ble_advertiser.dart';
import 'package:ble_test/chunked_transfer_manager.dart';
import 'package:ble_test/data/isar_service.dart';
import 'package:ble_test/data/message.dart';
import 'package:ble_test/data/relay_task.dart';
import 'package:ble_test/profile_manager.dart';
import 'package:ble_test/utils/geo_utils.dart';
import 'dart:typed_data';
import 'package:logging/logging.dart';
import 'package:cryptography/cryptography.dart';
import 'package:ble_test/data/found_device.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:isar_community/isar.dart';

class PendingAck {
  final Set<int> upstreamNodeIds;
  final DateTime timestamp;
  PendingAck(this.upstreamNodeIds, this.timestamp);
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

      // Cleanup persistent RelayTasks (30 minutes TTL)
      final isar = IsarService();
      if (isar.isOpen) {
        () async {
          try {
            await isar.db.writeTxn(() async {
              final relayThreshold = now.subtract(const Duration(minutes: 30));
              final expiredTasks = await isar.db.relayTasks
                  .filter()
                  .createdAtLessThan(relayThreshold)
                  .findAll();
              if (expiredTasks.isNotEmpty) {
                await isar.db.relayTasks
                    .deleteAll(expiredTasks.map((t) => t.id).toList());
              }
            });
          } catch (e) {
            _log.warning('RelayTask cleanup fail: $e');
          }
        }();
      }
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
          if (fullData.length < 11) return;
          final buffer = ByteData.view(fullData.buffer);
          final targetId = buffer.getUint32(1, Endian.big);
          originSenderId = buffer.getUint32(5, Endian.big);
          final msgId = fullData[9];
          int ttl = fullData[10];

          final cacheKey = (originSenderId << 8) | msgId;
          final myId = await ProfileManager.getStableDeviceId();

          if (_seenRelayMessageIds.containsKey(cacheKey)) {
            if (targetId == myId) {
              _pushAck(directSenderId, originSenderId, msgId).catchError((e) {
                _log.warning('Failed to re-send inbound ACK for $msgId: $e');
              });
            } else {
              _pendingAcks[cacheKey]?.upstreamNodeIds.add(directSenderId);
            }
            return;
          }
          _seenRelayMessageIds[cacheKey] = DateTime.now();

          if (targetId == myId) {
            _log.info('We are the target for relay message $msgId');
            _pushAck(directSenderId, originSenderId, msgId).catchError((e) {
              _log.warning('Failed to send inbound ACK for $msgId: $e');
            });

            final innerPayload = fullData.sublist(11);
            decryptedData = await _decryptMessage(originSenderId, innerPayload);
            if (decryptedData == null || decryptedData.isEmpty) return;
            payloadToProcess = decryptedData;
          } else if (ttl > 1) {
            _log.info('Enqueuing relay message $msgId for forwarding');
            _pendingAcks[cacheKey] =
                PendingAck({directSenderId}, DateTime.now());
            fullData[10] = ttl - 1;
            _forwardRelayPayload(fullData, targetId, originSenderId, msgId);
            return;
          } else {
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
          _syncDoneCompleters[directSenderId]?.completeError('request_pic');
          return;
        } else if (type == typeAck) {
          await handleIncomingAck(fullData);
          return;
        } else {
          decryptedData = await _decryptMessage(originSenderId, fullData);
          if (decryptedData == null || decryptedData.isEmpty) return;
          payloadToProcess = decryptedData;
        }

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
          return;
        }

        await IsarService().putMessage(message);
      } catch (e) {
        _log.severe('Failed to process message: $e');
      }
    });
  }

  static Future<void> sendMessage({
    required int targetStableId,
    required String content,
  }) async {
    final relayPayload = await getRelayWrappedPayload(
      targetStableId,
      text: content,
    );

    if (relayPayload == null) throw Exception("Encryption handshake required");

    final messageId = relayPayload[9];

    await handleOutgoingMessage(
      receiverStableId: targetStableId,
      content: content,
      messageId: messageId,
      wasSent: false,
    );
  }

  static Future<void> handleIncomingAck(Uint8List ackPayload) async {
    final buffer = ByteData.view(ackPayload.buffer);
    final targetId = buffer.getUint32(1, Endian.big);
    final originId = buffer.getUint32(5, Endian.big);
    final msgId = ackPayload[9];

    final myId = await ProfileManager.getStableDeviceId();
    if (targetId != myId) return;

    if (originId == myId) {
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

    final cacheKey = (originId << 8) | msgId;
    final pendingAck = _pendingAcks[cacheKey];

    if (pendingAck != null) {
      _log.info('Enqueuing ACK fan-back for $msgId');
      final isar = IsarService();
      final task = RelayTask()
        ..messageId = msgId
        ..originId = originId
        ..targetId = 0
        ..type = typeAck
        ..data = ackPayload
        ..pendingNeighborIds = pendingAck.upstreamNodeIds.toList()
        ..createdAt = DateTime.now();

      await isar.db.writeTxn(() async => await isar.db.relayTasks.put(task));
      _pendingAcks.remove(cacheKey);
      _seenRelayMessageIds.remove(cacheKey);
    }
  }

  static Future<void> _forwardRelayPayload(
    Uint8List payload,
    int targetId,
    int originId,
    int msgId,
  ) async {
    final isar = IsarService();
    final task = RelayTask()
      ..messageId = msgId
      ..originId = originId
      ..targetId = targetId
      ..type = typeRelay
      ..data = payload
      ..pendingNeighborIds = []
      ..createdAt = DateTime.now();

    await isar.db.writeTxn(() async => await isar.db.relayTasks.put(task));
  }

  static Future<void> pushQueuedDataToPeer(
    int peerStableId, {
    required bool useNotifications,
    BluetoothCharacteristic? centralWriteChar,
  }) async {
    final isar = IsarService();

    // 1. Direct Messages
    final unsent = await isar.db.messages
        .filter()
        .receiverStableIdEqualTo(peerStableId)
        .wasSentEqualTo(false)
        .findAll();

    for (final msg in unsent) {
      final payload = await getRelayWrappedPayload(
        peerStableId,
        text: msg.content,
        image: msg.isImage ? msg.data as Uint8List? : null,
      );

      if (payload != null) {
        await _pushOrNotify(
          peerStableId,
          payload,
          payload[9],
          useNotifications,
          centralWriteChar,
        );
        msg.wasSent = true;
        await isar.putMessage(msg);
      }
    }

    // 2. Relay Tasks & ACKs
    final tasks = await isar.db.relayTasks.where().findAll();
    final myId = await ProfileManager.getStableDeviceId();

    for (final task in tasks) {
      bool shouldSend = false;

      if (task.type == typeAck) {
        if (task.pendingNeighborIds.contains(peerStableId)) shouldSend = true;
      } else if (task.type == typeRelay) {
        if (task.pendingNeighborIds.contains(peerStableId)) continue;

        final peerDevice = await isar.db.foundDevices
            .where()
            .stableIdEqualTo(peerStableId)
            .findFirst();
        final targetDevice = await isar.db.foundDevices
            .where()
            .stableIdEqualTo(task.targetId)
            .findFirst();

        if (targetDevice != null &&
            targetDevice.latitude != null &&
            peerDevice != null &&
            peerDevice.latitude != null) {
          final ourDevice = await isar.db.foundDevices
              .where()
              .stableIdEqualTo(myId)
              .findFirst();
          final ourDist = ourDevice?.latitude != null
              ? GeoUtils.calculateDistance(
                  ourDevice!.latitude!,
                  ourDevice.longitude!,
                  targetDevice.latitude!,
                  targetDevice.longitude!,
                )
              : double.infinity;

          final peerDist = GeoUtils.calculateDistance(
            peerDevice.latitude!,
            peerDevice.longitude!,
            targetDevice.latitude!,
            targetDevice.longitude!,
          );

          if (peerDist < ourDist) shouldSend = true;
        } else {
          shouldSend = true;
        }
      }

      if (shouldSend) {
        try {
          await _pushOrNotify(
            peerStableId,
            Uint8List.fromList(task.data),
            task.messageId,
            useNotifications,
            centralWriteChar,
          );

          await isar.db.writeTxn(() async {
            if (task.type == typeAck) {
              task.pendingNeighborIds = task.pendingNeighborIds
                  .where((id) => id != peerStableId)
                  .toList();
              if (task.pendingNeighborIds.isEmpty) {
                await isar.db.relayTasks.delete(task.id);
              } else {
                await isar.db.relayTasks.put(task);
              }
            } else {
              task.sentCount++;
              if (task.sentCount >= 1) {
                await isar.db.relayTasks.delete(task.id);
              } else {
                task.pendingNeighborIds = [
                  ...task.pendingNeighborIds,
                  peerStableId
                ];
                await isar.db.relayTasks.put(task);
              }
            }
          });
        } catch (_) {}
      }
    }

    if (useNotifications) {
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

  static Future<void> _pushOrNotify(
    int peerStableId,
    Uint8List payload,
    int messageId,
    bool useNotifications,
    BluetoothCharacteristic? centralWriteChar,
  ) async {
    if (useNotifications) {
      final dev = await IsarService()
          .db
          .foundDevices
          .where()
          .stableIdEqualTo(peerStableId)
          .findFirst();
      if (dev != null) {
        await _notifyData(dev.remoteId, payload, messageId);
      }
    } else if (centralWriteChar != null) {
      final chunks = ChunkedTransferManager.generateChunks(payload, messageId);
      for (final c in chunks) {
        await centralWriteChar.write(c, withoutResponse: false);
      }
    }
  }

  static Future<void> _pushAck(
    int targetNodeId,
    int originId,
    int msgId,
  ) async {
    final ackPayload = Uint8List(10);
    final buffer = ByteData.view(ackPayload.buffer);
    ackPayload[0] = typeAck;
    buffer.setUint32(1, targetNodeId, Endian.big);
    buffer.setUint32(5, originId, Endian.big);
    ackPayload[9] = msgId;

    final isar = IsarService();
    final neighbor = await isar.db.foundDevices
        .where()
        .stableIdEqualTo(targetNodeId)
        .findFirst();

    if (neighbor != null) {
      await _notifyData(neighbor.remoteId, ackPayload, msgId);
    }
  }

  static Future<void> handlePeerIdentity(
    int peerStableId,
    Uint8List payload,
  ) async {
    try {
      if (payload.length < 43) return;
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
        dev = FoundDevice()
          ..stableId = id
          ..name = name
          ..profileHash = hashHex
          ..publicKey = pubKey
          ..lastSeen = DateTime.now();
        needsPic = true;
      } else {
        if (dev.profileHash != hashHex) {
          dev.profileHash = hashHex;
          needsPic = true;
        }
        dev.name = name;
        dev.publicKey = pubKey;
        dev.lastSeen = DateTime.now();
      }
      await isar.putFoundDevice(dev);

      if (needsPic) {
        final req = Uint8List(1);
        req[0] = typeRequestProfilePic;
        _waitingForImageFrom = id;
        await BLEAdvertiser.sendNotification(
          characteristicUuid: BLEAdvertiser.messageCharUuid,
          value: req,
          deviceId: dev.remoteId,
        );
      } else {
        await pushQueuedDataToPeer(id, useNotifications: true);
      }
    } catch (e) {
      _log.severe('Error handling peer identity: $e');
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

    final payloadWithType = Uint8List(1 + pic.length);
    payloadWithType[0] = typeProfilePic;
    payloadWithType.setRange(1, payloadWithType.length, pic);

    final chunks = ChunkedTransferManager.generateChunks(payloadWithType, 0);

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

  static Future<void> checkExpiredMessages() async {
    final isar = IsarService();
    if (!isar.isOpen) return;

    final threshold = DateTime.now().subtract(const Duration(minutes: 10));

    final expired = await isar.db.messages
        .filter()
        .wasSentEqualTo(true)
        .isDeliveredEqualTo(false)
        .wasFailedEqualTo(false)
        .timestampLessThan(threshold)
        .findAll();

    if (expired.isNotEmpty) {
      await isar.db.writeTxn(() async {
        for (final msg in expired) {
          msg.wasFailed = true;
          await isar.db.messages.put(msg);
        }
      });
    }
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

    if (device == null || device.publicKey == null) return null;

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

  static Future<void> handleIncomingMessage({
    required int senderStableId,
    required List<int> data,
  }) async {
    ChunkedTransferManager.handleIncomingChunk(
      senderStableId: senderStableId,
      data: Uint8List.fromList(data),
    );
  }
}
