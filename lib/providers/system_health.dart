import 'package:battery_plus/battery_plus.dart';
import 'package:disable_battery_optimization/disable_battery_optimization.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'system_health.g.dart';

class SystemHealthState {
  final bool isBatteryOptimized;
  final bool isBatterySaverOn;
  final bool hasLocationAlways;
  final bool hasNotificationPermission;
  final bool isChecking;

  SystemHealthState({
    required this.isBatteryOptimized,
    required this.isBatterySaverOn,
    required this.hasLocationAlways,
    required this.hasNotificationPermission,
    this.isChecking = false,
  });

  bool get isOptimal =>
      !isBatteryOptimized &&
      !isBatterySaverOn &&
      hasLocationAlways &&
      hasNotificationPermission;
}

@riverpod
class SystemHealth extends _$SystemHealth {
  @override
  SystemHealthState build() {
    checkHealth();
    return SystemHealthState(
      isBatteryOptimized: true, // Pessimistic default
      isBatterySaverOn: true,
      hasLocationAlways: false,
      hasNotificationPermission: false,
      isChecking: true,
    );
  }

  Future<void> checkHealth() async {
    state = SystemHealthState(
      isBatteryOptimized: state.isBatteryOptimized,
      isBatterySaverOn: state.isBatterySaverOn,
      hasLocationAlways: state.hasLocationAlways,
      hasNotificationPermission: state.hasNotificationPermission,
      isChecking: true,
    );

    final battery = Battery();
    final isBatterySaverOn = await battery.isInBatterySaveMode;
    final isOptimized =
        await DisableBatteryOptimization.isBatteryOptimizationDisabled ?? false;
    final locationStatus = await Permission.locationAlways.status;
    final notificationStatus = await Permission.notification.status;

    state = SystemHealthState(
      isBatteryOptimized: !isOptimized,
      isBatterySaverOn: isBatterySaverOn,
      hasLocationAlways: locationStatus.isGranted,
      hasNotificationPermission: notificationStatus.isGranted,
      isChecking: false,
    );
  }
}
