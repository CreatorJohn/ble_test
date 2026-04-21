import 'package:ble_test/components/scaffold_wrapper.dart';
import 'package:ble_test/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ScaffoldWrapper(
      withLog: true,
      body: Center(
        child: Column(
          spacing: 8.0,
          children: [
            const Text("Select app mode"),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadiusGeometry.all(Radius.circular(8.0)),
                ),
              ),
              onPressed: () => context.push(AdvertiseRoute().location),
              child: const Text("Advertise"),
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
      ),
    );
  }
}
