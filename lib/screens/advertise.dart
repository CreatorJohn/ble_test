import 'package:ble_test/components/scaffold_wrapper.dart';
import 'package:ble_test/profile_manager.dart';
import 'package:ble_test/providers/advertising_name.dart';
import 'package:ble_test/providers/found_devices.dart';
import 'package:ble_test/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:typed_data';

class AdvertiseScreen extends ConsumerStatefulWidget {
  const AdvertiseScreen({super.key});

  @override
  ConsumerState<AdvertiseScreen> createState() => _AdvertiseScreenState();
}

class _AdvertiseScreenState extends ConsumerState<AdvertiseScreen> {
  final TextEditingController _controller = TextEditingController();
  Uint8List? _profilePic;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final bytes = await ProfileManager.getProfilePicture();
    if (mounted) {
      setState(() => _profilePic = bytes);
    }
  }

  Future<void> _pickImage() async {
    await ProfileManager.pickAndSaveProfilePicture();
    await _loadProfile();
    // Notify background service that hash changed
    FlutterBackgroundService().invoke("updateLocalProfile");
  }

  @override
  Widget build(BuildContext context) {
    final isServiceRunning = ref.watch(isServiceRunningProvider).value ?? false;

    ref.listen(advertisingNameProvider, (previous, next) {
      if (next.hasError || !next.hasValue) return;
      if (next.requireValue != _controller.text) {
        _controller.text = next.requireValue;
      }
    });

    return ScaffoldWrapper(
      screen: AdvertiseRoute().location,
      withLog: true,
      centered: true,
      padding: const EdgeInsets.all(16.0),
      body: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            GestureDetector(
              onTap: _pickImage,
              child: Stack(
                alignment: Alignment.bottomRight,
                children: [
                  CircleAvatar(
                    radius: 60,
                    backgroundColor:
                        Theme.of(context).colorScheme.primaryContainer,
                    backgroundImage:
                        _profilePic != null ? MemoryImage(_profilePic!) : null,
                    child: _profilePic == null
                        ? const Icon(Icons.person, size: 60)
                        : null,
                  ),
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    child: const Icon(
                      Icons.edit,
                      size: 18,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            TextField(
              maxLength: 8,
              controller: _controller,
              decoration: InputDecoration(
                labelText: "Advertising Name",
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
                  final newName = _controller.text.trim();
                  ref.read(advertisingNameProvider.notifier).change(newName);
                  FlutterBackgroundService().invoke("setAdvertisingName", {
                    "name": newName,
                  });
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
      ),
    );
  }
}
