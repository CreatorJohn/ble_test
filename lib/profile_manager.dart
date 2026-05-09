import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class ProfileManager {
  static const String _hashKey = 'profile_hash_6';
  static const String _imageFileName = 'profile_pic.png';

  /// Gets the 6-byte hash of the current profile picture.
  /// If no picture exists, it returns a default hash.
  static Future<Uint8List> getProfileHash() async {
    final bytes = await getProfilePicture();
    if (bytes == null || bytes.isEmpty) {
      // Default hash for "no picture"
      return Uint8List.fromList([0, 0, 0, 0, 0, 0]);
    }
    
    final digest = sha256.convert(bytes);
    return Uint8List.fromList(digest.bytes.sublist(0, 6));
  }

  /// Saves a new profile picture and updates the cached hash.
  static Future<void> saveProfilePicture(Uint8List bytes) async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$_imageFileName');
    await file.writeAsBytes(bytes);
    
    // Calculate and cache the new hash
    final digest = sha256.convert(bytes);
    final hashHex = digest.bytes.sublist(0, 6).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_hashKey, hashHex);
  }

  /// Reads the raw bytes of the profile picture from local storage.
  static Future<Uint8List?> getProfilePicture() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$_imageFileName');
    if (await file.exists()) {
      return await file.readAsBytes();
    }
    return null;
  }
}
