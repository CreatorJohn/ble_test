import 'dart:convert';
import 'dart:typed_data';

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
}

class SyncDonePacket extends MeshPacket {
  SyncDonePacket();

  @override
  int get type => MeshPacket.typeSyncDone;

  @override
  Uint8List toBytes() => Uint8List.fromList([type]);

  factory SyncDonePacket.fromBytes(Uint8List data) => SyncDonePacket();
}

class RequestProfilePicPacket extends MeshPacket {
  RequestProfilePicPacket();

  @override
  int get type => MeshPacket.typeRequestProfilePic;

  @override
  Uint8List toBytes() => Uint8List.fromList([type]);

  factory RequestProfilePicPacket.fromBytes(Uint8List data) =>
      RequestProfilePicPacket();
}
