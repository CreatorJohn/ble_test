import 'package:disable_battery_optimization/disable_battery_optimization.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'system_health.g.dart';

class SystemHealthState {
  final bool isBatteryOptimized;
  final bool hasLocationAlways;
  final bool hasNotificationPermission;
  final bool isChecking;

  SystemHealthState({
    required this.isBatteryOptimized,
    required this.hasLocationAlways,
    required this.hasNotificationPermission,
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
      isBatteryOptimized: true, // Pessimistic default
      hasLocationAlways: false,
      hasNotificationPermission: false,
      isChecking: true,
    );
  }

  Future<void> checkHealth() async {
    state = SystemHealthState(
      isBatteryOptimized: state.isBatteryOptimized,
      hasLocationAlways: state.hasLocationAlways,
      hasNotificationPermission: state.hasNotificationPermission,
      isChecking: true,
    );

    final isOptimized =
        await DisableBatteryOptimization.isBatteryOptimizationDisabled ?? false;
    final locationStatus = await Permission.locationAlways.status;
    final notificationStatus = await Permission.notification.status;

    state = SystemHealthState(
      isBatteryOptimized: !isOptimized,
      hasLocationAlways: locationStatus.isGranted,
      hasNotificationPermission: notificationStatus.isGranted,
      isChecking: false,
    );
  }
}
