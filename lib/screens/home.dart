import 'package:ble_test/components/scaffold_wrapper.dart';
import 'package:ble_test/providers/advertising_name.dart';
import 'package:ble_test/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canAdvertise = ref.watch(canAdvertiseProvider);
    String advertiseValue = "?";

    if (canAdvertise == true) advertiseValue = "Yes";
    if (canAdvertise == false) advertiseValue = "No";

    return ScaffoldWrapper(
      centered: true,
      withLog: true,
      padding: EdgeInsets.all(8.0),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        spacing: 8.0,
        children: [
          const Text("Select app mode"),
          Text("Can advertise: $advertiseValue"),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadiusGeometry.all(Radius.circular(8.0)),
              ),
            ),
            onPressed: () => context.push(const ProfileRoute().location),
            child: const Text("Profile"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadiusGeometry.all(Radius.circular(8.0)),
              ),
            ),
            onPressed: () => context.push(DiscoveryRoute().location),
            child: const Text("Discovery"),
          ),
        ],
      ),
    );
  }
}
