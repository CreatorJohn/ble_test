import 'package:ble_test/ble_advertiser.dart';
import 'package:ble_test/components/scaffold_wrapper.dart';
import 'package:ble_test/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AdvertiseScreen extends ConsumerWidget {
  AdvertiseScreen({super.key});

  final TextEditingController _controller = TextEditingController();
  final BLEAdvertiser _service = BLEAdvertiser();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ScaffoldWrapper(
      subPage: DiscoveryRoute().location.substring(1),
      withLog: true,
      body: Center(
        child: Column(
          children: [
            TextField(
              maxLength: 8,
              controller: _controller,
              decoration: InputDecoration(
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8.0),
                ),
              ),
            ),
            if (_service.isAdvetising)
              ElevatedButton(
                onPressed: () => _service.startAdvertising(
                  localName: _controller.text.trim(),
                ),
                child: const Text("Advertise"),
              )
            else
              ElevatedButton(
                onPressed: () => _service.stopAdvertising(),
                child: const Text("Stop advertising"),
              ),
          ],
        ),
      ),
    );
  }
}
