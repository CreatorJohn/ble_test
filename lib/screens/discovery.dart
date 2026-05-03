import 'package:ble_test/components/scaffold_wrapper.dart';
import 'package:ble_test/data/found_device.dart';
import 'package:ble_test/main.dart';
import 'package:ble_test/router.dart';
import 'package:flutter/material.dart';
import 'package:isar_community/isar.dart';

class DiscoveryScreen extends StatelessWidget {
  const DiscoveryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ScaffoldWrapper(
      screen: DiscoveryRoute().location,
      centered: true,
      withLog: true,
      padding: const EdgeInsets.all(8.0),
      body: StreamBuilder<List<FoundDevice>>(
        stream: isar.foundDevices.where().sortByLastSeenDesc().watch(
          fireImmediately: true,
        ),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const CircularProgressIndicator();

          final devices = snapshot.data!;

          if (devices.isEmpty) return const Text("No devices found...");

          return ListView.builder(
            itemCount: devices.length,
            itemBuilder: (context, index) {
              final item = devices[index];

              return ListTile(
                leading: const Icon(Icons.bluetooth),
                title: Text(item.name ?? "Unknown"),
                subtitle: Text(item.remoteId),
                trailing: Text("${item.rssi} dBm"),
              );
            },
          );
        },
      ),
    );
  }
}
