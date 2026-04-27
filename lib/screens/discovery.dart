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
      padding: EdgeInsets.all(8.0),
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
              icon: Icon(Icons.refresh),
            );
          },
        ),
      ],
      body: switch (deviceState) {
        AsyncLoading(progress: final progress) => Center(
          child: CircularProgressIndicator.adaptive(
            value: progress?.toDouble(),
          ),
        ),
        AsyncData(value: final devices) =>
          deviceState.isLoading
              ? CircularProgressIndicator.adaptive(
                  value: deviceState.progress?.toDouble(),
                )
              : devices.isNotEmpty
              ? ListView.builder(
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
              : const Text("No devices found..."),
        AsyncError(error: final error, stackTrace: _) => Center(
          child: Text(
            error.toString(),
            style: TextStyle(color: Colors.red.shade800),
          ),
        ),
      },
    );
  }
}
