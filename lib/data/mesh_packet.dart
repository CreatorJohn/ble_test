import 'dart:convert';
import 'dart:typed_data';
import 'package:logging/logging.dart';
import 'package:ble_test/data/isar_service.dart';
import 'package:ble_test/message_handler.dart';
import 'package:ble_test/data/found_device.dart';
import 'package:ble_test/data/message.dart';
import 'package:ble_test/ble_advertiser.dart';
import 'package:isar_community/isar.dart';

class PacketContext {
  final int directSenderId;
  final String? remoteId;
  final IsarService isar;
  final int myId;
  final Logger log;
  final Future<void> Function(int senderId, Uint8List data) processInnerPayload;

  PacketContext({
    required this.directSenderId,
    this.remoteId,
    required this.isar,
    required this.myId,
    required this.log,
    required this.processInnerPayload,
  });
}

abstract class MeshPacket {
  static const int typeText = 0x01;
  static const int typeImage = 0x02;
  static const int typeProfilePic = 0x03;
  static const int typeRelay = 0x04;
  static const int typeAck = 0x05;
  static const int typeIdentity = 0x06;
  static const int typeSyncDone = 0x07;
  static const int typeRequestProfilePic = 0x08;

  int get type;
  Uint8List toBytes();
  Future<void> handle(PacketContext context);

  static MeshPacket parse(Uint8List data) {
    if (data.isEmpty) throw Exception("Empty packet data");
    final type = data[0];

    switch (type) {
      case typeText:
        return TextPacket.fromBytes(data);
      case typeImage:
        return ImagePacket.fromBytes(data);
      case typeProfilePic:
        return ProfilePicPacket.fromBytes(data);
      case typeRelay:
        return RelayPacket.fromBytes(data);
      case typeAck:
        return AckPacket.fromBytes(data);
      case typeIdentity:
        return IdentityPacket.fromBytes(data);
      case typeSyncDone:
        return SyncDonePacket.fromBytes(data);
      case typeRequestProfilePic:
        return RequestProfilePicPacket.fromBytes(data);
      default:
        throw Exception("Unknown packet type: 0x${type.toRadixString(16)}");
    }
  }
}

class TextPacket extends MeshPacket {
  final String text;
  TextPacket(this.text);

  @override
  int get type => MeshPacket.typeText;

  @override
  Uint8List toBytes() {
    final bytes = utf8.encode(text);
    final result = Uint8List(1 + bytes.length);
    result[0] = type;
    result.setRange(1, result.length, bytes);
    return result;
  }

  factory TextPacket.fromBytes(Uint8List data) {
    return TextPacket(utf8.decode(data.sublist(1)));
  }

  @override
  Future<void> handle(PacketContext context) async {
    final message = Message()
      ..senderStableId = context.directSenderId
      ..receiverStableId = context.myId
      ..content = text
      ..timestamp = DateTime.now()
      ..isReceived = true
      ..isImage = false;
    await context.isar.putMessage(message);
  }
}

class ImagePacket extends MeshPacket {
  final Uint8List imageData;
  ImagePacket(this.imageData);

  @override
  int get type => MeshPacket.typeImage;

  @override
  Uint8List toBytes() {
    final result = Uint8List(1 + imageData.length);
    result[0] = type;
    result.setRange(1, result.length, imageData);
    return result;
  }

  factory ImagePacket.fromBytes(Uint8List data) {
    return ImagePacket(data.sublist(1));
  }

  @override
  Future<void> handle(PacketContext context) async {
    final message = Message()
      ..senderStableId = context.directSenderId
      ..receiverStableId = context.myId
      ..content = "[Image]"
      ..timestamp = DateTime.now()
      ..isReceived = true
      ..isImage = true
      ..data = imageData;
    await context.isar.putMessage(message);
  }
}

class ProfilePicPacket extends MeshPacket {
  final Uint8List imageData;
  ProfilePicPacket(this.imageData);

  @override
  int get type => MeshPacket.typeProfilePic;

  @override
  Uint8List toBytes() {
    final result = Uint8List(1 + imageData.length);
    result[0] = type;
    result.setRange(1, result.length, imageData);
    return result;
  }

  factory ProfilePicPacket.fromBytes(Uint8List data) {
    return ProfilePicPacket(data.sublist(1));
  }

  @override
  Future<void> handle(PacketContext context) async {
    final device = await context.isar.db.foundDevices
        .where()
        .stableIdEqualTo(context.directSenderId)
        .findFirst();
    if (device != null) {
      device.profilePicture = imageData;
      device.lastPictureSync = DateTime.now();
      await context.isar.putFoundDevice(device);
      context.log.info('Saved profile picture for ${context.directSenderId}');
    }

    if (MessageHandler.isWaitingForImage(context.directSenderId)) {
      MessageHandler.clearWaitingForImage();
      await MessageHandler.pushQueuedDataToPeer(context.directSenderId,
          useNotifications: true);
    }
  }
}

class RelayPacket extends MeshPacket {
  final int targetId;
  final int originId;
  final int messageId;
  final int ttl;
  final Uint8List encryptedPayload;

  RelayPacket({
    required this.targetId,
    required this.originId,
    required this.messageId,
    required this.ttl,
    required this.encryptedPayload,
  });

  @override
  int get type => MeshPacket.typeRelay;

  @override
  Uint8List toBytes() {
    final result = Uint8List(11 + encryptedPayload.length);
    final buffer = ByteData.view(result.buffer);
    result[0] = type;
    buffer.setUint32(1, targetId, Endian.big);
    buffer.setUint32(5, originId, Endian.big);
    result[9] = messageId;
    result[10] = ttl;
    result.setRange(11, result.length, encryptedPayload);
    return result;
  }

  factory RelayPacket.fromBytes(Uint8List data) {
    if (data.length < 11) throw Exception("Relay packet too short");
    final buffer = ByteData.view(data.buffer);
    return RelayPacket(
      targetId: buffer.getUint32(1, Endian.big),
      originId: buffer.getUint32(5, Endian.big),
      messageId: data[9],
      ttl: data[10],
      encryptedPayload: data.sublist(11),
    );
  }

  @override
  Future<void> handle(PacketContext context) async {
    final cacheKey = (originId << 8) | messageId;

    if (MessageHandler.hasSeenMessage(cacheKey)) {
      if (targetId == context.myId) {
        MessageHandler.enqueueTerminalAck(
            context.directSenderId, originId, messageId);
      } else {
        MessageHandler.addNeighborToBreadcrumb(cacheKey, context.directSenderId);
      }
      return;
    }
    MessageHandler.markMessageSeen(cacheKey);

    if (targetId == context.myId) {
      context.log.info('We are the target for relay message $messageId');
      MessageHandler.enqueueTerminalAck(
          context.directSenderId, originId, messageId);

      final decrypted =
          await MessageHandler.decryptMessage(originId, encryptedPayload);
      if (decrypted != null) {
        await context.processInnerPayload(originId, decrypted);
      }
    } else if (ttl > 1) {
      context.log.info('Enqueuing relay message $messageId for forwarding');
      MessageHandler.dropBreadcrumb(cacheKey, context.directSenderId);

      final nextPacket = RelayPacket(
        targetId: targetId,
        originId: originId,
        messageId: messageId,
        ttl: ttl - 1,
        encryptedPayload: encryptedPayload,
      );
      MessageHandler.enqueueForward(
          nextPacket.toBytes(), targetId, originId, messageId);
    }
  }
}

class AckPacket extends MeshPacket {
  final int targetId;
  final int originId;
  final int messageId;

  AckPacket({
    required this.targetId,
    required this.originId,
    required this.messageId,
  });

  @override
  int get type => MeshPacket.typeAck;

  @override
  Uint8List toBytes() {
    final result = Uint8List(10);
    final buffer = ByteData.view(result.buffer);
    result[0] = type;
    buffer.setUint32(1, targetId, Endian.big);
    buffer.setUint32(5, originId, Endian.big);
    result[9] = messageId;
    return result;
  }

  factory AckPacket.fromBytes(Uint8List data) {
    if (data.length < 10) throw Exception("ACK packet too short");
    final buffer = ByteData.view(data.buffer);
    return AckPacket(
      targetId: buffer.getUint32(1, Endian.big),
      originId: buffer.getUint32(5, Endian.big),
      messageId: data[9],
    );
  }

  @override
  Future<void> handle(PacketContext context) async {
    await MessageHandler.handleIncomingAck(this);
  }
}

class IdentityPacket extends MeshPacket {
  final int stableId;
  final Uint8List profileHash;
  final Uint8List publicKey;
  final String name;

  IdentityPacket({
    required this.stableId,
    required this.profileHash,
    required this.publicKey,
    required this.name,
  });

  @override
  int get type => MeshPacket.typeIdentity;

  @override
  Uint8List toBytes() {
    final nameBytes = utf8.encode(name);
    final result = Uint8List(43 + nameBytes.length);
    final buffer = ByteData.view(result.buffer);
    result[0] = type;
    buffer.setUint32(1, stableId, Endian.big);
    result.setRange(5, 11, profileHash);
    result.setRange(11, 43, publicKey);
    result.setRange(43, result.length, nameBytes);
    return result;
  }

  factory IdentityPacket.fromBytes(Uint8List data) {
    if (data.length < 43) throw Exception("Identity packet too short");
    final buffer = ByteData.view(data.buffer);
    return IdentityPacket(
      stableId: buffer.getUint32(1, Endian.big),
      profileHash: data.sublist(5, 11),
      publicKey: data.sublist(11, 43),
      name: utf8.decode(data.sublist(43), allowMalformed: true),
    );
  }

  @override
  Future<void> handle(PacketContext context) async {
    context.log.info('Received Identity Message from ${context.directSenderId}');
    await MessageHandler.handlePeerIdentity(
      context.directSenderId,
      this,
      remoteId: context.remoteId,
    );
  }
}

class SyncDonePacket extends MeshPacket {
  SyncDonePacket();

  @override
  int get type => MeshPacket.typeSyncDone;

  @override
  Uint8List toBytes() => Uint8List.fromList([type]);

  factory SyncDonePacket.fromBytes(Uint8List data) => SyncDonePacket();

  @override
  Future<void> handle(PacketContext context) async {
    context.log.info('Received SyncDone from ${context.directSenderId}');
    
    // If we are the peripheral (advertiser), this means A is done, so it's our turn to reciprocate.
    if (BLEAdvertiser.isDeviceConnected(context.remoteId ?? "")) {
      context.log.info('Triggering B\'s reciprocal turn for ${context.directSenderId}');
      MessageHandler.pushReciprocalSync(context.directSenderId, context.remoteId!);
    } else {
      // If we are the central, this means B is done, handshake complete.
      MessageHandler.completeSync(context.directSenderId);
    }
  }
}

class RequestProfilePicPacket extends MeshPacket {
  RequestProfilePicPacket();

  @override
  int get type => MeshPacket.typeRequestProfilePic;

  @override
  Uint8List toBytes() => Uint8List.fromList([type]);

  factory RequestProfilePicPacket.fromBytes(Uint8List data) =>
      RequestProfilePicPacket();

  @override
  Future<void> handle(PacketContext context) async {
    context.log.info('Peer ${context.directSenderId} requested our profile picture');
    MessageHandler.completeSyncWithError(context.directSenderId, 'request_pic');
  }
}
