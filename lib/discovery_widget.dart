import 'package:ble_test/ble_discoverer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class DiscoveryWidget extends StatefulWidget {
  const DiscoveryWidget({
    super.key,
    required this.resultsStream,
    this.discovering = false,
    this.initialResults = const [],
    this.onSelect,
  });

  final bool discovering;
  final List<DiscoveredDevice> initialResults;
  final Stream<List<DiscoveredDevice>> resultsStream;
  final void Function(BluetoothDevice device)? onSelect;

  @override
  State<DiscoveryWidget> createState() => _DiscoveryWidgetState();
}

class _DiscoveryWidgetState extends State<DiscoveryWidget> {
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constrains) {
        return StreamBuilder<List<DiscoveredDevice>>(
          initialData: widget.initialResults,
          stream: widget.resultsStream,
          builder: (context, snapshot) {
            final state = snapshot.connectionState;

            if (state == ConnectionState.done && snapshot.hasData) {
              final results = snapshot.requireData;

              return ListView.builder(
                itemCount: results.length,
                itemBuilder: (context, index) {
                  final DiscoveredDevice discovered = results[index];
                  final BluetoothDevice device = discovered.result.device;

                  String name = "Random device";
                  int serviceCount = discovered.services.length;
                  bool hasTargetService = discovered.hasTargetService;

                  if (device.advName.isNotEmpty) {
                    name = device.advName;
                  } else if (device.platformName.isNotEmpty) {
                    name = device.platformName;
                  }

                  return ListTile(
                    enableFeedback: true,
                    title: Text(
                      "Device: $name (${discovered.remoteId})",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      "Service count: $serviceCount | Has targeted service: $hasTargetService",
                    ),
                    trailing: IconButton.filled(
                      onPressed: () => widget.onSelect?.call(device),
                      icon: const Icon(Icons.chat_bubble),
                      color: Colors.blue,
                    ),
                  );
                },
              );
            }

            return SizedBox.shrink();
          },
        );
      },
    );
  }
}
