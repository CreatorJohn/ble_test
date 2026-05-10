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

  static void initialize() {
    ChunkedTransferManager.onPayloadComplete.listen((event) async {
      final senderStableId = event['senderStableId'] as int;
      final data = event['payload'] as Uint8List;

      try {
        final decryptedData = await _decryptMessage(senderStableId, data);
        if (decryptedData == null) return;

        final content = utf8.decode(decryptedData);
        final myStableId = await ProfileManager.getStableDeviceId();

        final message = Message()
          ..senderStableId = senderStableId
          ..receiverStableId = myStableId
          ..content = content
          ..timestamp = DateTime.now()
          ..isReceived = true;

        await IsarService().putMessage(message);
        _log.info('Decrypted and saved message from $senderStableId: $content');
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
  }) async {
    try {
      final isar = IsarService();
      final device = await isar.db.foundDevices
          .where()
          .stableIdEqualTo(receiverStableId)
          .findFirst();

      if (device == null || device.publicKey == null) {
        _log.warning('Cannot encrypt: Public key missing for $receiverStableId');
        return;
      }

      final cleartext = utf8.encode(content);
      final encryptedData = await _encryptMessage(
        Uint8List.fromList(cleartext),
        Uint8List.fromList(device.publicKey!),
      );

      final myStableId = await ProfileManager.getStableDeviceId();
      final message = Message()
        ..senderStableId = myStableId
        ..receiverStableId = receiverStableId
        ..content = content // We save cleartext locally for our own display
        ..timestamp = DateTime.now()
        ..isReceived = false;

      await isar.putMessage(message);
      
      // Note: The encryptedData should be sent via GATT chunks.
      // This is handled in the UI call to _performSendMessage.
      _log.info('Encrypted and queued message to $receiverStableId');
    } catch (e) {
      _log.severe('Encryption failed: $e');
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

  /// Helper to get encrypted bytes for the UI to send
  static Future<Uint8List?> getEncryptedPayload(int receiverStableId, String content) async {
    final isar = IsarService();
    final device = await isar.db.foundDevices
        .where()
        .stableIdEqualTo(receiverStableId)
        .findFirst();

    if (device == null || device.publicKey == null) return null;

    return await _encryptMessage(
      Uint8List.fromList(utf8.encode(content)),
      Uint8List.fromList(device.publicKey!),
    );
  }
}
