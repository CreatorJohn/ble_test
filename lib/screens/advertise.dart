import 'package:ble_test/components/scaffold_wrapper.dart';
import 'package:ble_test/providers/found_devices.dart';
import 'package:ble_test/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AdvertiseScreen extends ConsumerWidget {
  AdvertiseScreen({super.key});

  final TextEditingController _controller = TextEditingController.fromValue(
    const TextEditingValue(text: "BLE Test"),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isServiceRunning = ref.watch(isServiceRunningProvider).value ?? false;

    return ScaffoldWrapper(
      screen: AdvertiseRoute().location,
      withLog: true,
      centered: true,
      padding: const EdgeInsets.all(8.0),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TextField(
            maxLength: 8,
            controller: _controller,
            decoration: InputDecoration(
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8.0),
              ),
              helperText: isServiceRunning
                  ? "Update name in background"
                  : "Start service to advertise",
            ),
          ),
          const SizedBox(height: 16),
          if (isServiceRunning)
            ElevatedButton.icon(
              onPressed: () {
                FlutterBackgroundService().invoke(
                  "setAdvertisingName",
                  {"name": _controller.text.trim()},
                );
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Advertising name updated")),
                );
              },
              icon: const Icon(Icons.update),
              label: const Text("Update Name"),
            )
          else
            const Text(
              "Start the Background Scanner on the Discovery screen to enable 24/7 advertising.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
        ],
      ),
    );
  }
}
