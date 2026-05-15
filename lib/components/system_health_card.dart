import 'package:ble_test/providers/system_health.dart';
import 'package:disable_battery_optimization/disable_battery_optimization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
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
            if (health.isBatterySaverOn)
              _ActionItem(
                label: "System-wide Battery Saver is ON",
                buttonLabel: "Fix",
                onPressed: () async {
                  await DisableBatteryOptimization.showDisableBatteryOptimizationSettings();
                  ref.read(systemHealthProvider.notifier).checkHealth();
                },
              ),
            if (health.isBatteryOptimized)
              _ActionItem(
                label: "App Battery Optimization is ON",
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
            if (!health.isLocationEnabled)
              _ActionItem(
                label: "System Location is OFF",
                buttonLabel: "Enable",
                onPressed: () async {
                  await Geolocator.openLocationSettings();
                  ref.read(systemHealthProvider.notifier).checkHealth();
                },
              ),
            if (!health.isBluetoothOn)
              _ActionItem(
                label: "Bluetooth is OFF",
                buttonLabel: "Enable",
                onPressed: () async {
                  await FlutterBluePlus.turnOn();
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

  const _ActionItem({
    required this.label,
    required this.buttonLabel,
    required this.onPressed,
  });

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
