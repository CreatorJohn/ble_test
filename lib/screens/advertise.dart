import 'package:ble_test/ble_advertiser.dart';
import 'package:ble_test/components/scaffold_wrapper.dart';
import 'package:ble_test/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AdvertiseScreen extends ConsumerWidget {
  AdvertiseScreen({super.key});

  final BLEAdvertiser _service = BLEAdvertiser();
  final TextEditingController _controller = TextEditingController.fromValue(
    TextEditingValue(text: "BLE Test"),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ScaffoldWrapper(
      screen: AdvertiseRoute().location,
      withLog: true,
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        spacing: 8.0,
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
          StreamBuilder(
            stream: _service.advertisingStatusStream,
            builder: (context, snapshot) {
              final advertising = snapshot.data;

              if (advertising == true) {
                return ElevatedButton(
                  onPressed: () => _service.startAdvertising(
                    localName: _controller.text.trim(),
                  ),
                  child: const Text("Advertise"),
                );
              } else {
                return ElevatedButton(
                  onPressed: () => _service.stopAdvertising(),
                  child: const Text("Stop advertising"),
                );
              }
            },
          ),
        ],
      ),
    );
  }
}
