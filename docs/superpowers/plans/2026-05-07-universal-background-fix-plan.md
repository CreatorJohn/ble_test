# Universal Background Service Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ensure the BLE background scanner remains active on Android 11-16, specifically targeting Xiaomi Poco X6 Pro 5G by handling battery optimizations and mandatory Android 14 foreground service types.

**Architecture:** A `SystemHealth` state notifier will monitor device-specific and OS-level restrictions. A conditional UI component on the Discovery screen will guide users to fix any "Red" status indicators.

**Tech Stack:** 
- `flutter_background_service`
- `permission_handler`
- `device_info_plus`
- `disable_battery_optimization`
- `flutter_riverpod`

---

### Task 1: Android Platform Configuration

**Files:**
- Modify: `android/app/src/main/AndroidManifest.xml`

- [ ] **Step 1: Add required permissions and update service declaration**

Update the manifest to include battery optimization requests and specify `location` for the foreground service type.

```xml
<!-- android/app/src/main/AndroidManifest.xml -->
<manifest ...>
    <uses-permission android:name="android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS" />
    <uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION" />

    <application ...>
        <service
            android:name="id.flutter.flutter_background_service.BackgroundService"
            android:foregroundServiceType="location|specialUse" />
    </application>
</manifest>
```

- [ ] **Step 2: Commit changes**

```bash
git add android/app/src/main/AndroidManifest.xml
git commit -m "chore(android): add background location and battery optimization permissions"
```

---

### Task 2: System Health Provider

**Files:**
- Create: `lib/providers/system_health.dart`

- [ ] **Step 1: Define the SystemHealth state and notifier**

Implement a provider that checks battery optimization, location permissions, and hardware manufacturer.

```dart
// lib/providers/system_health.dart
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:disable_battery_optimization/disable_battery_optimization.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

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

  bool get isOptimal => !isBatteryOptimized && hasLocationAlways && hasNotificationPermission;
}

class SystemHealthNotifier extends StateNotifier<SystemHealthState> {
  SystemHealthNotifier() : super(SystemHealthState(
    isBatteryOptimized: false,
    hasLocationAlways: true,
    hasNotificationPermission: true,
    isXiaomi: false,
    isChecking: true,
  )) {
    checkHealth();
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
      isXiaomi = manufacturer.contains('xiaomi') || manufacturer.contains('poco') || manufacturer.contains('redmi');
    }

    final isOptimized = await DisableBatteryOptimization.isBatteryOptimizationDisabled ?? false;
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

final systemHealthProvider = StateNotifierProvider<SystemHealthNotifier, SystemHealthState>((ref) {
  return SystemHealthNotifier();
});
```

- [ ] **Step 2: Commit**

```bash
git add lib/providers/system_health.dart
git commit -m "feat: add SystemHealth provider for monitoring background restrictions"
```

---

### Task 3: Background Service Configuration Update

**Files:**
- Modify: `lib/background_service.dart`

- [ ] **Step 1: Update foreground service types in initialization**

```dart
// lib/background_service.dart
// ... inside initializeBackgroundService
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: true,
      isForegroundMode: true,
      notificationChannelId: "scanning_status",
      initialNotificationTitle: "BLE Scanner",
      initialNotificationContent: "Monitoring nearby devices",
      // Add location to types
      foregroundServiceTypes: [
        AndroidForegroundType.location,
        AndroidForegroundType.connectedDevice,
      ],
    ),
// ...
```

- [ ] **Step 2: Commit**

```bash
git add lib/background_service.dart
git commit -m "fix(service): add location foreground service type for Android 14 compatibility"
```

---

### Task 4: System Health UI Card

**Files:**
- Create: `lib/components/system_health_card.dart`
- Modify: `lib/screens/discovery.dart`

- [ ] **Step 1: Create the Health Card component**

```dart
// lib/components/system_health_card.dart
import 'package:ble_test/providers/system_health.dart';
import 'package:disable_battery_optimization/disable_battery_optimization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

class SystemHealthCard extends ConsumerWidget {
  const SystemHealthCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final health = ref.watch(systemHealthProvider);

    if (health.isChecking || health.isOptimal) return const SizedBox.shrink();

    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning, color: Theme.of(context).colorScheme.error),
                const SizedBox(width: 8),
                Text(
                  "Background Service at Risk",
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text("Your system settings may kill the background scanner."),
            const SizedBox(height: 12),
            if (health.isBatteryOptimized)
              _ActionItem(
                label: "Battery Optimization is ON",
                buttonLabel: "Fix",
                onPressed: () async {
                  await DisableBatteryOptimization.showDisableBatteryOptimizationSettings();
                  ref.read(systemHealthProvider.notifier).checkHealth();
                },
              ),
            if (!health.hasLocationAlways)
              _ActionItem(
                label: "Always-On Location Missing",
                buttonLabel: "Grant",
                onPressed: () async {
                  await Permission.locationAlways.request();
                  ref.read(systemHealthProvider.notifier).checkHealth();
                },
              ),
            if (health.isXiaomi)
              _ActionItem(
                label: "Xiaomi/Poco: Enable Autostart",
                buttonLabel: "Settings",
                onPressed: () async {
                  await DisableBatteryOptimization.showEnableAutoStartSettings(
                    "Enable Autostart", 
                    "Please find this app and enable Autostart."
                  );
                  ref.read(systemHealthProvider.notifier).checkHealth();
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _ActionItem extends StatelessWidget {
  final String label;
  final String buttonLabel;
  final VoidCallback onPressed;

  const _ActionItem({required this.label, required this.buttonLabel, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
          FilledButton.tonal(
            onPressed: onPressed,
            style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
            child: Text(buttonLabel),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Add card to DiscoveryScreen**

```dart
// lib/screens/discovery.dart
// ... imports
import 'package:ble_test/components/system_health_card.dart';

// ... inside DiscoveryScreen Column children
        children: [
          const SystemHealthCard(), // Add this line
          ElevatedButton.icon(
// ...
```

- [ ] **Step 3: Commit**

```bash
git add lib/components/system_health_card.dart lib/screens/discovery.dart
git commit -m "feat: display SystemHealthCard on Discovery screen when restrictions detected"
```
