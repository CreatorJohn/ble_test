import 'package:ble_test/ble_discoverer.dart';
import 'package:ble_test/components/scaffold_wrapper.dart';
import 'package:ble_test/providers/found_devices.dart';
import 'package:ble_test/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DiscoveryScreen extends ConsumerWidget {
  const DiscoveryScreen({super.key});

  final BLEDiscoverer _service = const BLEDiscoverer();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deviceState = ref.watch(foundDevicesStateProvider);

    return ScaffoldWrapper(
      screen: DiscoveryRoute().location,
      centered: true,
      withLog: true,
      padding: const EdgeInsets.all(8.0),
      actions: [
        StreamBuilder(
          stream: _service.isDiscoveringStream,
          builder: (context, snapshot) {
            final discovering = snapshot.data ?? false;

            if (discovering) {
              return IconButton(
                onPressed: _service.stopDiscovering,
                icon: const Icon(Icons.square, color: Colors.red),
              );
            }

            return IconButton(
              onPressed: ref.read(foundDevicesStateProvider.notifier).discover,
              icon: const Icon(Icons.refresh),
            );
          },
        ),
      ],
      body: deviceState.isLoading
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator.adaptive(
                    value: deviceState.progress?.toDouble(),
                  ),
                  if (deviceState.progress != null) ...[
                    const SizedBox(height: 16),
                    Text("${(deviceState.progress! * 100).toInt()}%"),
                  ],
                ],
              ),
            )
          : deviceState.when(
              data: (devices) => devices.isNotEmpty
                  ? ListView.builder(
                      itemCount: devices.length,
                      itemBuilder: (context, index) {
                        final item = devices[index];
                        final subtitle = item.hasTargetService ? "Yes" : "No";

                        return ListTile(
                          title: Text(
                            "${item.result.device.advName} | ${item.result.device.remoteId.str}",
                          ),
                          subtitle: Text(
                            "Number of services: ${item.services.length} | Has targeted service? $subtitle",
                          ),
                          isThreeLine: true,
                        );
                      },
                    )
                  : const Center(child: Text("No devices found...")),
              error: (error, stackTrace) => Center(
                child: Text(
                  error.toString(),
                  style: TextStyle(color: Colors.red.shade800),
                ),
              ),
              loading: () => const SizedBox.shrink(),
            ),
    );
  }
}
