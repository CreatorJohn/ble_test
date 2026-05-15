import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

class ProfileManager {
  static const String _hashKey = 'profile_hash_6';
  static const String _deviceIdKey = 'stable_device_id_4';
  static const String _imageFileName = 'profile_pic.webp';
  static const String _privateKeyKey = 'secure_private_key_v1';
  static const String _publicKeyKey = 'public_key_v1';

  static const _secureStorage = FlutterSecureStorage();
  static final _log = Logger('ProfileManager');

  static Future<void> pickAndSaveProfilePicture() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);

    if (image == null) return;
    _log.info('Picked image: ${image.path}');

    final croppedFile = await ImageCropper().cropImage(
      sourcePath: image.path,
      aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Crop Profile Picture',
          toolbarColor: const Color(0xFF6750A4),
          toolbarWidgetColor: Colors.white,
          initAspectRatio: CropAspectRatioPreset.square,
          lockAspectRatio: true,
        ),
        IOSUiSettings(
          title: 'Crop Profile Picture',
          aspectRatioLockEnabled: true,
        ),
      ],
    );

    if (croppedFile == null) {
      _log.info('Image cropping cancelled');
      return;
    }

    final bytes = await croppedFile.readAsBytes();
    _log.info('Original cropped size: ${bytes.length} bytes');

    // Compress and resize to 128x128 WebP using native library
    try {
      _log.info('Compressing to 128x128 WebP...');
      final webpBytes = await FlutterImageCompress.compressWithList(
        bytes,
        minWidth: 128,
        minHeight: 128,
        quality: 75,
        format: CompressFormat.webp,
      );

      _log.info('Processed WebP size: ${webpBytes.length} bytes');
      await saveProfilePicture(Uint8List.fromList(webpBytes));
    } catch (e) {
      _log.severe('Failed to compress image: $e');
    }
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
      publicKey: SimplePublicKey(
        base64Decode(pubBase64),
        type: KeyPairType.x25519,
      ),
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

    _log.info('Saved profile picture: ${file.path} (Hash: $hashHex)');

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_hashKey, hashHex);
  }

  static Future<Uint8List?> getProfilePicture() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$_imageFileName');
    if (await file.exists()) {
      final bytes = await file.readAsBytes();
      _log.info('Loaded profile picture: ${file.path} (${bytes.length} bytes)');
      return bytes;
    }
    _log.info('No profile picture file found at ${file.path}');
    return null;
  }
}
