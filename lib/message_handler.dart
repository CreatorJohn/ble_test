import 'dart:convert';
import 'package:ble_test/chunked_transfer_manager.dart';
import 'package:ble_test/data/isar_service.dart';
import 'package:ble_test/data/message.dart';
import 'package:ble_test/profile_manager.dart';
import 'dart:typed_data';
import 'package:logging/logging.dart';
import 'package:cryptography/cryptography.dart';
import 'package:ble_test/data/found_device.dart';
import 'package:isar_community/isar.dart';

class MessageHandler {
  static final Logger _log = Logger('MessageHandler');
  static final _cipher = Chacha20.poly1305Aead();
  static final _exchangeAlgorithm = X25519();

  static const int typeText = 0x01;
  static const int typeImage = 0x02;

  static void initialize() {
    ChunkedTransferManager.onPayloadComplete.listen((event) async {
      final senderStableId = event['senderStableId'] as int;
      final data = event['payload'] as Uint8List;

      try {
        final decryptedData = await _decryptMessage(senderStableId, data);
        if (decryptedData == null || decryptedData.isEmpty) return;

        // Header: Byte 0 = Type
        final type = decryptedData[0];
        final payload = decryptedData.sublist(1);

        final myStableId = await ProfileManager.getStableDeviceId();
        final message = Message()
          ..senderStableId = senderStableId
          ..receiverStableId = myStableId
          ..timestamp = DateTime.now()
          ..isReceived = true;

        if (type == typeText) {
          message.content = utf8.decode(payload);
          message.isImage = false;
        } else if (type == typeImage) {
          message.content = "[Image]";
          message.isImage = true;
          message.data = payload;
        } else {
          _log.warning('Unknown message type received: $type');
          return;
        }

        await IsarService().putMessage(message);
        _log.info('Decrypted and saved message from $senderStableId (Type: $type)');
      } catch (e) {
        _log.severe('Failed to decrypt or decode message: $e');
      }
    });
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

  static Future<Uint8List?> getEncryptedPayload(int receiverStableId, {
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
}
