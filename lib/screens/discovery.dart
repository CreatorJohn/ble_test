import 'package:ble_test/components/scaffold_wrapper.dart';
import 'package:ble_test/providers/found_devices.dart';
import 'package:ble_test/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DiscoveryScreen extends ConsumerWidget {
  const DiscoveryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deviceState = ref.watch(foundDevicesStateProvider);

    return ScaffoldWrapper(
      screen: DiscoveryRoute().location,
      centered: true,
      withLog: true,
      padding: EdgeInsets.all(8.0),
      body: switch (deviceState) {
        AsyncLoading(progress: final progress) => Center(
          child: CircularProgressIndicator.adaptive(
            value: progress?.toDouble(),
          ),
        ),
        AsyncData(value: final devices) => ListView.builder(
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
        ),
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
