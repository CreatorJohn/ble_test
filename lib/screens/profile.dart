import 'package:ble_test/components/scaffold_wrapper.dart';
import 'package:ble_test/profile_manager.dart';
import 'package:ble_test/providers/advertising_name.dart';
import 'package:ble_test/providers/found_devices.dart';
import 'package:ble_test/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:typed_data';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final TextEditingController _controller = TextEditingController();
  Uint8List? _profilePic;

  // Max length calculated: 31 (Scan Response) - 2 (AD Header) - 12 (Mesh Metadata) = 17
  static const int _maxNameLength = 17;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final bytes = await ProfileManager.getProfilePicture();
    final name = ref.read(advertisingNameProvider).value ?? "BLE Test";
    if (mounted) {
      setState(() {
        _profilePic = bytes;
        _controller.text = name;
      });
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
      screen: const ProfileRoute().location,
      withLog: true,
      centered: true,
      padding: const EdgeInsets.all(24.0),
      body: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              "Your Profile",
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 32),
            GestureDetector(
              onTap: _pickImage,
              child: Stack(
                alignment: Alignment.bottomRight,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Theme.of(context).colorScheme.primary,
                        width: 4,
                      ),
                    ),
                    child: CircleAvatar(
                      radius: 80,
                      backgroundColor:
                          Theme.of(context).colorScheme.primaryContainer,
                      backgroundImage: _profilePic != null
                          ? MemoryImage(_profilePic!)
                          : null,
                      child: _profilePic == null
                          ? const Icon(Icons.person, size: 80)
                          : null,
                    ),
                  ),
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    child: const Icon(
                      Icons.camera_alt,
                      size: 22,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 48),
            TextField(
              maxLength: _maxNameLength,
              controller: _controller,
              decoration: InputDecoration(
                labelText: "Mesh Display Name",
                hintText: "Enter your name",
                prefixIcon: const Icon(Icons.badge),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.0),
                ),
                helperText: isServiceRunning
                    ? "Name will update in background mesh"
                    : "Start service to see your name on other devices",
              ),
              onChanged: (value) {
                // Real-time update if user stops typing
              },
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                onPressed: () {
                  final newName = _controller.text.trim();
                  if (newName.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Name cannot be empty")),
                    );
                    return;
                  }
                  
                  ref.read(advertisingNameProvider.notifier).change(newName);
                  
                  if (isServiceRunning) {
                    FlutterBackgroundService().invoke("setAdvertisingName", {
                      "name": newName,
                    });
                  }
                  
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Profile updated")),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.save),
                label: const Text("Save Profile"),
              ),
            ),
            const SizedBox(height: 16),
            if (!isServiceRunning)
              const Text(
                "Note: Background Scanner must be active for others to discover you.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
          ],
        ),
      ),
    );
  }
}
