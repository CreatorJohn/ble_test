import 'package:ble_test/background_service.dart';
import 'package:ble_test/components/scaffold_wrapper.dart';
import 'package:ble_test/components/system_health_card.dart';
import 'package:ble_test/data/isar_service.dart';
import 'package:ble_test/providers/found_devices.dart';
import 'package:ble_test/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_background_service/flutter_background_service.dart';

class DiscoveryScreen extends ConsumerWidget {
  const DiscoveryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isRunning = ref.watch(isServiceRunningProvider).value ?? false;
    final progress = ref.watch(scanProgressProvider).value ?? 0.0;

    return ScaffoldWrapper(
      screen: DiscoveryRoute().location,
      centered: true,
      withLog: true,
      padding: const EdgeInsets.all(8.0),
      body: Column(
        children: [
          const SystemHealthCard(),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: isRunning
                      ? null
                      : () async {
                          await initializeBackgroundService();
                        },
                  icon: const Icon(Icons.play_arrow),
                  label: const Text("Start Background Scanner"),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  onPressed: () => _showResetConfirmation(context, ref),
                  icon: const Icon(Icons.refresh),
                  tooltip: "Reset Service & Data",
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(width: 8),
                _StatusIndicator(isRunning: isRunning),
              ],
            ),
          ),
          if (isRunning)
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 32.0, vertical: 8.0),
              child: Column(
                children: [
                  LinearProgressIndicator(value: progress),
                  const SizedBox(height: 4),
                  Text(
                    progress > 0 ? "Scanning..." : "Waiting for next cycle...",
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
            ),
          const Divider(),
          Expanded(
            child: ref.watch(discoveredDevicesProvider).when(
                  data: (devices) {
                    if (devices.isEmpty) {
                      return const Center(child: Text("No devices found..."));
                    }

                    return ListView.builder(
                      itemCount: devices.length,
                      itemBuilder: (context, index) {
                        final item = devices[index];
                        return ListTile(
                          title: Text(item.name ?? "Unknown"),
                          subtitle: Text(item.remoteId),
                          trailing: Text("${item.rssi} dBm"),
                        );
                      },
                    );
                  },
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (err, stack) => Center(child: Text('Error: $err')),
                ),
          ),
        ],
      ),
    );
  }

  void _showResetConfirmation(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Reset Background Service?"),
        content: const Text(
          "This will stop the background scanner and delete all discovered devices. This action cannot be undone.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () async {
              // 1. Stop the service
              final service = FlutterBackgroundService();
              service.invoke("stopService");

              // 2. Clear the database
              await IsarService().clearDevices();

              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text("Service reset and data cleared")),
                );
              }
            },
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text("Reset Everything"),
          ),
        ],
      ),
    );
  }
}

class _StatusIndicator extends StatelessWidget {
  final bool isRunning;

  const _StatusIndicator({required this.isRunning});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isRunning
            ? Colors.green.withOpacity(0.1)
            : Colors.grey.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isRunning ? Colors.green : Colors.grey,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: isRunning ? Colors.green : Colors.grey,
              shape: BoxShape.circle,
              boxShadow: isRunning
                  ? [
                      BoxShadow(
                        color: Colors.green.withOpacity(0.5),
                        blurRadius: 4,
                        spreadRadius: 1,
                      )
                    ]
                  : null,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            isRunning ? "ACTIVE" : "INACTIVE",
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: isRunning ? Colors.green : Colors.grey,
            ),
          ),
        ],
      ),
    );
  }
}
