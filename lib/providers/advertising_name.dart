import 'package:ble_test/ble_advertiser.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'advertising_name.g.dart';

@riverpod
class AdvertisingName extends _$AdvertisingName {
  static const String _storageKey = 'advertising_name_v2';
  final String _defaultName = "BLE Test";
  final FlutterBackgroundService _bgService = FlutterBackgroundService();

  @override
  Future<String> build() async {
    final prefs = await SharedPreferences.getInstance();
    
    _bgService.on("updateAdvertisingName").forEach((data) {
      final name = data?["name"];
      if (name is String) state = AsyncData(name);
    });

    return prefs.getString(_storageKey) ?? _defaultName;
  }

  Future<void> change(String newName) async {
    final trimmed = newName.trim();
    if (trimmed.length > BLEAdvertiser.maxNameLength) {
      state = AsyncError("Name exceeds BLE advertisement limits (max ${BLEAdvertiser.maxNameLength})", StackTrace.current);
      return;
    }
    
    state = AsyncData(trimmed);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, trimmed);
  }

  Future<void> reset() async {
    state = AsyncData(_defaultName);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }
}
