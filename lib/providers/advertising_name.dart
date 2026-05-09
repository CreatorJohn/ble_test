import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'advertising_name.g.dart';

@riverpod
class AdvertisingName extends _$AdvertisingName {
  final String _defaultName = "BLE Test";
  final FlutterBackgroundService _bgService = FlutterBackgroundService();

  @override
  Future<String> build() async {
    _bgService.on("updateAdvertisingName").forEach((data) {
      final name = data?["name"];

      if (name is String) state = AsyncData(name);
    });

    return _defaultName;
  }

  void change(String newName) {
    if (newName.trim().length > 8) {
      state = AsyncError("New name is too long!", StackTrace.empty);
    } else {
      state = AsyncData(newName.trim());
    }
  }

  void reset() => state = AsyncData(_defaultName);
}
