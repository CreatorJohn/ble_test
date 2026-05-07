import 'package:ble_test/background_service.dart';
import 'package:ble_test/components/scaffold_wrapper.dart';
import 'package:ble_test/components/system_health_card.dart';
import 'package:ble_test/data/found_device.dart';
import 'package:ble_test/data/isar_service.dart';
import 'package:ble_test/router.dart';
import 'package:flutter/material.dart';

class DiscoveryScreen extends StatelessWidget {
  const DiscoveryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ScaffoldWrapper(
      screen: DiscoveryRoute().location,
      centered: true,
      withLog: true,
      padding: const EdgeInsets.all(8.0),
      body: Column(
        children: [
          const SystemHealthCard(),
          ElevatedButton.icon(
            onPressed: () async {
              await initializeBackgroundService();
            },
            icon: const Icon(Icons.play_arrow),
            label: const Text("Start Background Scanner"),
          ),
          const Divider(),
          Expanded(
            child: StreamBuilder<List<FoundDevice>>(
              stream: IsarService().watchFoundDevices(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final devices = snapshot.data!;

                if (devices.isEmpty) return const Text("No devices found...");

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
            ),
          ),
        ],
      ),
    );
  }
}
