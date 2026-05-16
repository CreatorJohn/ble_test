import 'dart:async';
import 'dart:math';
import 'package:ble_test/ble_advertiser.dart';
import 'package:ble_test/chunked_transfer_manager.dart';
import 'package:ble_test/data/isar_service.dart';
import 'package:ble_test/data/message.dart';
import 'package:ble_test/data/relay_task.dart';
import 'package:ble_test/data/mesh_packet.dart';
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

      const cacheLifetimeSeconds =
          maxTTL * (scanDurationSeconds + waitDurationSeconds) + 20;

      _seenRelayMessageIds.removeWhere(
        (id, timestamp) =>
            now.difference(timestamp).inSeconds > cacheLifetimeSeconds,
      );

      _pendingAcks.removeWhere(
        (key, pendingAck) =>
            now.difference(pendingAck.timestamp).inSeconds >
            (cacheLifetimeSeconds * 2),
      );

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
        final packet = MeshPacket.parse(fullData);
        Uint8List? decryptedData;
        Uint8List payloadToProcess;
        int originSenderId = directSenderId;

        if (packet is RelayPacket) {
          originSenderId = packet.originId;
          final cacheKey = (originSenderId << 8) | packet.messageId;
          final myId = await ProfileManager.getStableDeviceId();

          if (_seenRelayMessageIds.containsKey(cacheKey)) {
            if (packet.targetId == myId) {
              _enqueueTerminalAck(directSenderId, originSenderId, packet.messageId);
            } else {
              _pendingAcks[cacheKey]?.upstreamNodeIds.add(directSenderId);
            }
            return;
          }
          _seenRelayMessageIds[cacheKey] = DateTime.now();

          if (packet.targetId == myId) {
            _log.info('We are the target for relay message ${packet.messageId}');
            _enqueueTerminalAck(directSenderId, originSenderId, packet.messageId);

            decryptedData = await _decryptMessage(originSenderId, packet.encryptedPayload);
            if (decryptedData == null || decryptedData.isEmpty) return;
            payloadToProcess = decryptedData;
          } else if (packet.ttl > 1) {
            _log.info('Enqueuing relay message ${packet.messageId} for forwarding');
            _pendingAcks[cacheKey] = PendingAck({directSenderId}, DateTime.now());
            
            final nextPacket = RelayPacket(
              targetId: packet.targetId,
              originId: packet.originId,
              messageId: packet.messageId,
              ttl: packet.ttl - 1,
              encryptedPayload: packet.encryptedPayload,
            );
            _forwardRelayPayload(nextPacket.toBytes(), packet.targetId, originSenderId, packet.messageId);
            return;
          } else {
            return;
          }
        } else if (packet is IdentityPacket) {
          _log.info('Received Identity Message from $directSenderId');
          await handlePeerIdentity(directSenderId, packet);
          return;
        } else if (packet is SyncDonePacket) {
          _log.info('Received SyncDone from $directSenderId');
          _syncDoneCompleters[directSenderId]?.complete();
          return;
        } else if (packet is RequestProfilePicPacket) {
          _log.info('Peer $directSenderId requested our profile picture');
          _syncDoneCompleters[directSenderId]?.completeError('request_pic');
          return;
        } else if (packet is AckPacket) {
          await handleIncomingAck(packet);
          return;
        } else {
          decryptedData = await _decryptMessage(originSenderId, fullData);
          if (decryptedData == null || decryptedData.isEmpty) return;
          payloadToProcess = decryptedData;
        }

        final innerPacket = MeshPacket.parse(payloadToProcess);

        if (innerPacket is ProfilePicPacket) {
          final isar = IsarService();
          final device = await isar.db.foundDevices
              .where()
              .stableIdEqualTo(originSenderId)
              .findFirst();
          if (device != null) {
            device.profilePicture = innerPacket.imageData;
            device.lastPictureSync = DateTime.now();
            await isar.putFoundDevice(device);
            _log.info('Saved profile picture for $originSenderId');
          }

          if (_waitingForImageFrom == originSenderId) {
            _waitingForImageFrom = null;
            await pushQueuedDataToPeer(originSenderId, useNotifications: true);
          }
          return;
        }

        final myStableId = await ProfileManager.getStableDeviceId();
        final message = Message()
          ..senderStableId = originSenderId
          ..receiverStableId = myStableId
          ..timestamp = DateTime.now()
          ..isReceived = true;

        if (innerPacket is TextPacket) {
          message.content = innerPacket.text;
          message.isImage = false;
        } else if (innerPacket is ImagePacket) {
          message.content = "[Image]";
          message.isImage = true;
          message.data = innerPacket.imageData;
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

    final packet = RelayPacket.fromBytes(relayPayload);

    await handleOutgoingMessage(
      receiverStableId: targetStableId,
      content: content,
      messageId: packet.messageId,
      wasSent: false,
    );
  }

  static Future<void> handleIncomingAck(AckPacket packet) async {
    final myId = await ProfileManager.getStableDeviceId();
    if (packet.targetId != myId) return;

    if (packet.originId == myId) {
      _log.info('Message ${packet.messageId} delivered!');
      final isar = IsarService();
      final msg = await isar.db.messages
          .filter()
          .messageIdEqualTo(packet.messageId)
          .findFirst();
      if (msg != null && !msg.isDelivered) {
        msg.isDelivered = true;
        await isar.putMessage(msg);
      }
      return;
    }

    final cacheKey = (packet.originId << 8) | packet.messageId;
    final pendingAck = _pendingAcks[cacheKey];

    if (pendingAck != null) {
      _log.info('Enqueuing ACK fan-back for ${packet.messageId}');
      final isar = IsarService();
      final task = RelayTask()
        ..messageId = packet.messageId
        ..originId = packet.originId
        ..targetId = 0
        ..type = MeshPacket.typeAck
        ..data = packet.toBytes()
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
      ..type = MeshPacket.typeRelay
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
    final myId = await ProfileManager.getStableDeviceId();

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
        final relayPacket = RelayPacket.fromBytes(payload);
        await _pushOrNotify(
          peerStableId,
          payload,
          relayPacket.messageId,
          useNotifications,
          centralWriteChar,
        );
        msg.wasSent = true;
        await isar.putMessage(msg);
      }
    }

    // 2. Relay Tasks & ACKs
    final tasks = await isar.db.relayTasks.where().findAll();
    tasks.sort((a, b) => b.type.compareTo(a.type));

    for (final task in tasks) {
      bool shouldSend = false;

      if (task.type == MeshPacket.typeAck) {
        if (task.pendingNeighborIds.contains(peerStableId)) shouldSend = true;
      } else if (task.type == MeshPacket.typeRelay) {
        if (task.pendingNeighborIds.contains(peerStableId)) continue;
        if (task.sentCount >= 3) continue;

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
          final dev = await isar.db.foundDevices
              .where()
              .stableIdEqualTo(peerStableId)
              .findFirst();
          final mtu = (dev != null)
              ? BLEAdvertiser.getMtuForDevice(dev.remoteId)
              : 23;

          await _pushOrNotify(
            peerStableId,
            Uint8List.fromList(task.data),
            task.messageId,
            useNotifications,
            centralWriteChar,
            negotiatedMtu: mtu,
          );

          await isar.db.writeTxn(() async {
            if (task.type == MeshPacket.typeAck) {
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
              task.pendingNeighborIds = [
                ...task.pendingNeighborIds,
                peerStableId
              ];
              if (task.sentCount >= 3) {
                await isar.db.relayTasks.delete(task.id);
              } else {
                await isar.db.relayTasks.put(task);
              }
            }
          });
        } catch (_) {}
      }
    }

    if (useNotifications) {
      final done = SyncDonePacket();
      final dev = await isar.db.foundDevices
          .where()
          .stableIdEqualTo(peerStableId)
          .findFirst();
      if (dev != null) {
        await BLEAdvertiser.sendNotification(
          characteristicUuid: BLEAdvertiser.messageCharUuid,
          value: done.toBytes(),
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
    BluetoothCharacteristic? centralWriteChar, {
    int negotiatedMtu = 23,
  }) async {
    final maxChunkSize = (negotiatedMtu - 10).clamp(20, 500);

    if (useNotifications) {
      final dev = await IsarService()
          .db
          .foundDevices
          .where()
          .stableIdEqualTo(peerStableId)
          .findFirst();
      if (dev != null) {
        await _notifyData(dev.remoteId, payload, messageId,
            maxChunkSize: maxChunkSize);
      }
    } else if (centralWriteChar != null) {
      final chunks = ChunkedTransferManager.generateChunks(
        payload,
        messageId,
        maxChunkSize: maxChunkSize,
      );
      for (final c in chunks) {
        await centralWriteChar.write(c, withoutResponse: false);
      }

    }
  }

  static void _enqueueTerminalAck(int neighborId, int originId, int msgId) async {
    final myId = await ProfileManager.getStableDeviceId();
    final packet = AckPacket(
      targetId: originId,
      originId: myId,
      messageId: msgId,
    );

    final isar = IsarService();
    if (isar.isOpen) {
      final task = RelayTask()
        ..messageId = msgId
        ..originId = myId
        ..targetId = originId
        ..type = MeshPacket.typeAck
        ..data = packet.toBytes()
        ..pendingNeighborIds = [neighborId]
        ..createdAt = DateTime.now();

      try {
        await isar.db.writeTxn(() async => await isar.db.relayTasks.put(task));
      } catch (e) {
        _log.warning('Failed to enqueue terminal ACK: $e');
      }
    }
  }

  static Future<void> handlePeerIdentity(
    int peerStableId,
    IdentityPacket packet,
  ) async {
    try {
      final isar = IsarService();
      var dev =
          await isar.db.foundDevices.where().stableIdEqualTo(packet.stableId).findFirst();

      bool needsPic = false;
      if (dev == null) {
        final hashHex = packet.profileHash
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join();
        dev = FoundDevice()
          ..stableId = packet.stableId
          ..name = packet.name
          ..profileHash = hashHex
          ..publicKey = packet.publicKey
          ..lastSeen = DateTime.now();
        needsPic = true;
      } else {
        final hashHex = packet.profileHash
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join();
        if (dev.profileHash != hashHex) {
          dev.profileHash = hashHex;
          needsPic = true;
        }
        dev.name = packet.name;
        dev.publicKey = packet.publicKey;
        dev.lastSeen = DateTime.now();
      }
      await isar.putFoundDevice(dev);

      if (needsPic) {
        final req = RequestProfilePicPacket();
        _waitingForImageFrom = packet.stableId;
        await BLEAdvertiser.sendNotification(
          characteristicUuid: BLEAdvertiser.messageCharUuid,
          value: req.toBytes(),
          deviceId: dev.remoteId,
        );
      } else {
        await pushQueuedDataToPeer(packet.stableId, useNotifications: true);
      }
    } catch (e) {
      _log.severe('Error handling peer identity: $e');
    }
  }

  static Future<void> _notifyData(
    String remoteId,
    Uint8List payload,
    int messageId, {
    int maxChunkSize = 200,
  }) async {
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
  }

  static Future<void> streamOurProfilePic(
    String remoteId,
    int peerStableId,
    BluetoothCharacteristic? centralWriteChar,
  ) async {
    final pic = await ProfileManager.getProfilePicture();
    if (pic == null || pic.isEmpty) return;

    final mtu = BLEAdvertiser.getMtuForDevice(remoteId);
    final maxChunkSize = (mtu - 10).clamp(20, 500);

    final packet = ProfilePicPacket(pic);

    final chunks = ChunkedTransferManager.generateChunks(
      packet.toBytes(),
      0,
      maxChunkSize: maxChunkSize,
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

    final MeshPacket clearPacket;
    if (image != null) {
      clearPacket = ImagePacket(image);
    } else {
      clearPacket = TextPacket(text ?? "");
    }

    return await _encryptMessage(
      clearPacket.toBytes(),
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

    final relayPacket = RelayPacket(
      targetId: targetStableId,
      originId: myId,
      messageId: msgId,
      ttl: ttl,
      encryptedPayload: encrypted,
    );

    return relayPacket.toBytes();
  }
}
