import 'dart:async';
import 'package:ble_test/data/found_device.dart';
import 'package:ble_test/data/isar_service.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'found_devices.g.dart';

@riverpod
IsarService isarService(Ref ref) => IsarService();

@riverpod
Stream<bool> isScanning(Ref ref) {
  return FlutterBluePlus.isScanning;
}

@riverpod
Stream<bool> isServiceRunning(Ref ref) {
  final service = FlutterBackgroundService();
  return Stream.periodic(const Duration(seconds: 1)).asyncMap((_) => service.isRunning());
}

@riverpod
Stream<double> scanProgress(Ref ref) {
  final service = FlutterBackgroundService();
  return service.on('updateProgress').map((event) {
    final value = event?['value'];
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return 0.0;
  });
}

@riverpod
Stream<List<FoundDevice>> discoveredDevices(Ref ref) {
  return ref.watch(isarServiceProvider).watchFoundDevices();
}
