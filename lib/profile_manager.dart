import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;

class ProfileManager {
  static const String _hashKey = 'profile_hash_6';
  static const String _deviceIdKey = 'stable_device_id_4';
  static const String _imageFileName = 'profile_pic.png';
  static const String _privateKeyKey = 'secure_private_key_v1';
  static const String _publicKeyKey = 'public_key_v1';

  static const _secureStorage = FlutterSecureStorage();

  static Future<void> pickAndSaveProfilePicture() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
    );

    if (image == null) return;

    final bytes = await image.readAsBytes();
    final decodedImage = img.decodeImage(bytes);

    if (decodedImage == null) return;

    // Resize to 256x256 max while maintaining aspect ratio
    img.Image resized;
    if (decodedImage.width > 256 || decodedImage.height > 256) {
      resized = img.copyResize(
        decodedImage,
        width: decodedImage.width > decodedImage.height ? 256 : null,
        height: decodedImage.height >= decodedImage.width ? 256 : null,
      );
    } else {
      resized = decodedImage;
    }

    final Uint8List pngBytes = Uint8List.fromList(img.encodePng(resized));
    await saveProfilePicture(pngBytes);
  }

  static Future<int> getStableDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    int? deviceId = prefs.getInt(_deviceIdKey);

    if (deviceId == null) {
      deviceId = Random.secure().nextInt(0xFFFFFFFF);
      await prefs.setInt(_deviceIdKey, deviceId);
    }
    return deviceId;
  }

  static Future<SimpleKeyPair> getKeyPair() async {
    final algorithm = X25519();
    final prefs = await SharedPreferences.getInstance();

    String? privBase64 = await _secureStorage.read(key: _privateKeyKey);
    String? pubBase64 = prefs.getString(_publicKeyKey);

    if (privBase64 == null) {
      final oldPrivBase64 = prefs.getString(_privateKeyKey);
      if (oldPrivBase64 != null) {
        await _secureStorage.write(key: _privateKeyKey, value: oldPrivBase64);
        privBase64 = oldPrivBase64;
        await prefs.remove(_privateKeyKey);
      }
    }

    if (privBase64 == null || pubBase64 == null) {
      final keyPair = await algorithm.newKeyPair();
      final privBytes = await keyPair.extractPrivateKeyBytes();
      final pubKey = await keyPair.extractPublicKey();

      final newPrivBase64 = base64Encode(privBytes);
      final newPubBase64 = base64Encode(pubKey.bytes);

      await _secureStorage.write(key: _privateKeyKey, value: newPrivBase64);
      await prefs.setString(_publicKeyKey, newPubBase64);

      return keyPair;
    }

    return SimpleKeyPairData(
      base64Decode(privBase64),
      publicKey:
          SimplePublicKey(base64Decode(pubBase64), type: KeyPairType.x25519),
      type: KeyPairType.x25519,
    );
  }

  static Future<Uint8List> getProfileHash() async {
    final bytes = await getProfilePicture();
    if (bytes == null || bytes.isEmpty) {
      return Uint8List.fromList([0, 0, 0, 0, 0, 0]);
    }

    final digest = sha256.convert(bytes);
    return Uint8List.fromList(digest.bytes.sublist(0, 6));
  }

  static Future<void> saveProfilePicture(Uint8List bytes) async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$_imageFileName');
    await file.writeAsBytes(bytes);

    final digest = sha256.convert(bytes);
    final hashHex = digest.bytes
        .sublist(0, 6)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_hashKey, hashHex);
  }

  static Future<Uint8List?> getProfilePicture() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$_imageFileName');
    if (await file.exists()) {
      return await file.readAsBytes();
    }
    return null;
  }
}
