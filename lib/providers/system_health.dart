import 'package:battery_plus/battery_plus.dart';
import 'package:disable_battery_optimization/disable_battery_optimization.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'system_health.g.dart';

class SystemHealthState {
  final bool isBatteryOptimized;
  final bool isBatterySaverOn;
  final bool hasLocationAlways;
  final bool hasNotificationPermission;
  final bool isLocationEnabled;
  final bool isBluetoothOn;
  final bool isChecking;

  SystemHealthState({
    required this.isBatteryOptimized,
    required this.isBatterySaverOn,
    required this.hasLocationAlways,
    required this.hasNotificationPermission,
    required this.isLocationEnabled,
    required this.isBluetoothOn,
    this.isChecking = false,
  });

  bool get isOptimal =>
      !isBatteryOptimized &&
      !isBatterySaverOn &&
      hasLocationAlways &&
      hasNotificationPermission &&
      isLocationEnabled &&
      isBluetoothOn;
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
      isLocationEnabled: false,
      isBluetoothOn: false,
      isChecking: true,
    );
  }

  Future<void> checkHealth() async {
    state = SystemHealthState(
      isBatteryOptimized: state.isBatteryOptimized,
      isBatterySaverOn: state.isBatterySaverOn,
      hasLocationAlways: state.hasLocationAlways,
      hasNotificationPermission: state.hasNotificationPermission,
      isLocationEnabled: state.isLocationEnabled,
      isBluetoothOn: state.isBluetoothOn,
      isChecking: true,
    );

    final battery = Battery();
    final isBatterySaverOn = await battery.isInBatterySaveMode;
    final isOptimized =
        await DisableBatteryOptimization.isBatteryOptimizationDisabled ?? false;
    final locationStatus = await Permission.locationAlways.status;
    final notificationStatus = await Permission.notification.status;
    final isLocationEnabled = await Geolocator.isLocationServiceEnabled();
    final bluetoothStatus = await FlutterBluePlus.adapterState.first == BluetoothAdapterState.on;

    state = SystemHealthState(
      isBatteryOptimized: !isOptimized,
      isBatterySaverOn: isBatterySaverOn,
      hasLocationAlways: locationStatus.isGranted,
      hasNotificationPermission: notificationStatus.isGranted,
      isLocationEnabled: isLocationEnabled,
      isBluetoothOn: bluetoothStatus,
      isChecking: false,
    );
  }
}
