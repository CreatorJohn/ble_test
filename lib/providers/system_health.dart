import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:disable_battery_optimization/disable_battery_optimization.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'system_health.g.dart';

class SystemHealthState {
  final bool isBatteryOptimized;
  final bool hasLocationAlways;
  final bool hasNotificationPermission;
  final bool isXiaomi;
  final bool isChecking;

  SystemHealthState({
    required this.isBatteryOptimized,
    required this.hasLocationAlways,
    required this.hasNotificationPermission,
    required this.isXiaomi,
    this.isChecking = false,
  });

  bool get isOptimal =>
      !isBatteryOptimized && hasLocationAlways && hasNotificationPermission;
}

@riverpod
class SystemHealth extends _$SystemHealth {
  @override
  SystemHealthState build() {
    checkHealth();
    return SystemHealthState(
      isBatteryOptimized: false,
      hasLocationAlways: true,
      hasNotificationPermission: true,
      isXiaomi: false,
      isChecking: true,
    );
  }

  Future<void> checkHealth() async {
    state = SystemHealthState(
      isBatteryOptimized: state.isBatteryOptimized,
      hasLocationAlways: state.hasLocationAlways,
      hasNotificationPermission: state.hasNotificationPermission,
      isXiaomi: state.isXiaomi,
      isChecking: true,
    );

    final deviceInfo = DeviceInfoPlugin();
    bool isXiaomi = false;
    if (Platform.isAndroid) {
      final androidInfo = await deviceInfo.androidInfo;
      final manufacturer = androidInfo.manufacturer.toLowerCase();
      isXiaomi = manufacturer.contains('xiaomi') ||
          manufacturer.contains('poco') ||
          manufacturer.contains('redmi');
    }

    final isOptimized =
        await DisableBatteryOptimization.isBatteryOptimizationDisabled ?? false;
    final locationStatus = await Permission.locationAlways.status;
    final notificationStatus = await Permission.notification.status;

    state = SystemHealthState(
      isBatteryOptimized: !isOptimized,
      hasLocationAlways: locationStatus.isGranted,
      hasNotificationPermission: notificationStatus.isGranted,
      isXiaomi: isXiaomi,
      isChecking: false,
    );
  }
}
