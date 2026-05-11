import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:ble_test/background_service.dart';
import 'package:ble_test/ble_advertiser.dart';
import 'package:ble_test/chunked_transfer_manager.dart';
import 'package:ble_test/components/scaffold_wrapper.dart';
import 'package:ble_test/components/system_health_card.dart';
import 'package:ble_test/data/found_device.dart';
import 'package:ble_test/data/isar_service.dart';
import 'package:ble_test/message_handler.dart';
import 'package:ble_test/providers/advertising_name.dart';
import 'package:ble_test/providers/found_devices.dart';
import 'package:ble_test/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_background_service/flutter_background_service.dart';

class DiscoveryScreen extends ConsumerWidget {
  const DiscoveryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isRunning = ref.watch(isServiceRunningProvider).value ?? false;
    final isScanning = ref.watch(isScanningProvider).value ?? false;
    final progress = ref.watch(scanProgressProvider).value ?? 0.0;

    return ScaffoldWrapper(
      screen: DiscoveryRoute().location,
      centered: true,
      withLog: true,
      padding: const EdgeInsets.all(8.0),
      body: Column(
        children: [
          const SystemHealthCard(),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: isRunning
                      ? null
                      : () async {
                          await initializeBackgroundService();
                        },
                  icon: const Icon(Icons.play_arrow),
                  label: const Text("Start Background Scanner"),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  onPressed: () => _showResetConfirmation(context, ref),
                  icon: const Icon(Icons.refresh),
                  tooltip: "Reset Service & Data",
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(width: 8),
                StreamBuilder(
                  stream: BLEAdvertiser().advertisingStatusStream,
                  builder: (context, snapshot) {
                    final advertising = snapshot.data ?? false;

                    return IconButton.filledTonal(
                      onPressed: () {
                        if (advertising) {
                          FlutterBackgroundService().invoke("stopAdvertising");
                          ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("Stopping broadcast")),
                        );
                      } else {
                        final adName =
                            ref.read(advertisingNameProvider).value ??
                            "BLE Test";
                        FlutterBackgroundService().invoke(
                          "setAdvertisingName",
                          {"name": adName},
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              "Attempting manual broadcast start with: $adName",
                            ),
                          ),
                        );
                      }
                    },
                    icon: Icon(
                      advertising
                          ? Icons.record_voice_over
                          : Icons.play_disabled,
                    ),
                    tooltip:
                        "Force Broadcast ${advertising ? "Start" : "Stop"}",
                  );
                  },
                ),
                const SizedBox(width: 8),
                _StatusIndicator(
                  isRunning: isRunning,
                  isScanning: isScanning,
                  progress: progress,
                ),
              ],
            ),
          ),
          if (isRunning)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 32.0,
                vertical: 8.0,
              ),
              child: Column(
                children: [
                  LinearProgressIndicator(
                    value: progress,
                    color: isScanning ? null : Colors.orange,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isScanning ? "Scanning..." : "Waiting for next cycle...",
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
            ),
          const Divider(),
          Expanded(
            child: ref.watch(discoveredDevicesProvider).when(
                  data: (devices) {
                    if (devices.isEmpty) {
                      return const Center(child: Text("No devices found..."));
                    }

                    return ListView.builder(
                      itemCount: devices.length,
                      itemBuilder: (context, index) {
                        final item = devices[index];
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Theme.of(
                              context,
                            ).colorScheme.primaryContainer,
                            backgroundImage: item.profilePicture != null
                                ? MemoryImage(
                                    Uint8List.fromList(item.profilePicture!),
                                  )
                                : null,
                            child: item.profilePicture == null
                                ? const Icon(Icons.person)
                                : null,
                          ),
                          title: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.name ?? "Unknown",
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Row(
                                children: [
                                  StreamBuilder<BluetoothConnectionState>(
                                    stream: BluetoothDevice.fromId(
                                      item.remoteId,
                                    ).connectionState,
                                    builder: (context, snapshot) {
                                      final state = snapshot.data ??
                                          BluetoothConnectionState.disconnected;
                                      if (state ==
                                          BluetoothConnectionState.connected) {
                                        return const Padding(
                                          padding: EdgeInsets.only(right: 4.0),
                                          child: Badge(
                                            label: Text("CONNECTED"),
                                            backgroundColor: Colors.green,
                                          ),
                                        );
                                      }
                                      return const SizedBox.shrink();
                                    },
                                  ),
                                  StreamBuilder<BluetoothBondState>(
                                    stream: BluetoothDevice.fromId(
                                      item.remoteId,
                                    ).bondState,
                                    builder: (context, snapshot) {
                                      final state = snapshot.data ??
                                          BluetoothBondState.none;
                                      if (state == BluetoothBondState.bonded) {
                                        return const Padding(
                                          padding: EdgeInsets.only(right: 4.0),
                                          child: Badge(
                                            label: Text("BONDED"),
                                            backgroundColor: Colors.blue,
                                          ),
                                        );
                                      }
                                      return const SizedBox.shrink();
                                    },
                                  ),
                                ],
                              ),
                            ],
                          ),
                          subtitle: Text(
                            "Stable ID: ${item.stableId}\nMAC: ${item.remoteId}",
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    "${item.rssi} dBm",
                                    style: const TextStyle(fontSize: 10),
                                  ),
                                  const SizedBox(height: 4),
                                  const Icon(
                                    Icons.signal_cellular_alt,
                                    size: 16,
                                  ),
                                ],
                              ),
                              IconButton(
                                icon: const Icon(Icons.info_outline),
                                tooltip: "View Profile",
                                onPressed: () =>
                                    _showProfileDialog(context, item),
                              ),
                              IconButton(
                                icon: const Icon(Icons.send),
                                tooltip: "Send Message",
                                onPressed: () =>
                                    _sendMessageDialog(context, ref, item),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (err, stack) => Center(child: Text('Error: $err')),
                ),
          ),
        ],
      ),
    );
  }

  void _showProfileDialog(BuildContext context, FoundDevice device) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(device.name ?? "Unknown Device"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (device.profilePicture != null)
              Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  image: DecorationImage(
                    image: MemoryImage(
                      Uint8List.fromList(device.profilePicture!),
                    ),
                    fit: BoxFit.cover,
                  ),
                ),
              )
            else
              const Icon(Icons.account_circle, size: 100, color: Colors.grey),
            const SizedBox(height: 16),
            _ProfileInfo(label: "Stable ID", value: device.stableId.toString()),
            _ProfileInfo(label: "MAC Address", value: device.remoteId),
            _ProfileInfo(
              label: "Last Seen",
              value: device.lastSeen.toLocal().toString(),
            ),
            if (device.profileHash != null)
              _ProfileInfo(label: "Profile Hash", value: device.profileHash!),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Close"),
          ),
        ],
      ),
    );
  }

  void _sendMessageDialog(
    BuildContext context,
    WidgetRef ref,
    FoundDevice device,
  ) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Message to ${device.name ?? 'Device'}"),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: "Enter message"),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () async {
              final content = controller.text.trim();
              if (content.isEmpty) return;

              Navigator.pop(context);
              _performSendMessage(context, device, content);
            },
            child: const Text("Send"),
          ),
        ],
      ),
    );
  }

  Future<void> _performSendMessage(
    BuildContext context,
    FoundDevice device,
    String content,
  ) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    try {
      final bleDevice = BluetoothDevice.fromId(device.remoteId);

      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text("Connecting to ${device.name ?? 'device'}...")),
      );

      await bleDevice.connect(license: License.free);

      try {
        final services = await bleDevice.discoverServices();
        BluetoothCharacteristic? messageChar;

        for (final service in services) {
          if (service.uuid.toString().toLowerCase() ==
              BLEAdvertiser.serviceUuid.toLowerCase()) {
            for (final char in service.characteristics) {
              if (char.uuid.toString().toLowerCase() ==
                  BLEAdvertiser.messageCharUuid.toLowerCase()) {
                messageChar = char;
                break;
              }
            }
          }
        }

        if (messageChar != null) {
          final encryptedPayload = await MessageHandler.getEncryptedPayload(
            device.stableId,
            content,
          );

          if (encryptedPayload == null) {
            scaffoldMessenger.showSnackBar(
              const SnackBar(
                content: Text("Encryption failed: Public key missing."),
              ),
            );
            return;
          }

          final messageId = Random().nextInt(256);
          final chunks = ChunkedTransferManager.generateChunks(
            encryptedPayload,
            messageId,
          );

          int sent = 0;
          for (final chunk in chunks) {
            // writeWithoutResponse is faster for "blasting" mesh data
            await messageChar.write(chunk, withoutResponse: true);
            sent++;
            // Small delay to prevent radio congestion
            await Future.delayed(const Duration(milliseconds: 10));
          }

          await MessageHandler.handleOutgoingMessage(
            receiverStableId: device.stableId,
            content: content,
          );
          scaffoldMessenger.showSnackBar(
            SnackBar(content: Text("Encrypted message sent! ($sent chunks)")),
          );
        } else {
          scaffoldMessenger.showSnackBar(
            const SnackBar(content: Text("Messaging service not found.")),
          );
        }
      } finally {
        await bleDevice.disconnect();
      }
    } catch (e) {
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text("Error sending message: $e")),
      );
    }
  }

  void _showResetConfirmation(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Reset Background Service?"),
        content: const Text(
          "This will stop the background scanner and delete all discovered devices. This action cannot be undone.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () async {
              // 1. Stop the service
              final service = FlutterBackgroundService();
              service.invoke("stopService");

              // 2. Clear the database
              await IsarService().clearDevices();

              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Service reset and data cleared"),
                  ),
                );
              }
            },
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text("Reset Everything"),
          ),
        ],
      ),
    );
  }
}

class _ProfileInfo extends StatelessWidget {
  final String label;
  final String value;

  const _ProfileInfo({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          ),
          Text(value, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}

class _StatusIndicator extends StatelessWidget {
  final bool isRunning;
  final bool isScanning;
  final double progress;

  const _StatusIndicator({
    required this.isRunning,
    required this.isScanning,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    final String label;
    final Color color;

    if (!isRunning) {
      label = "INACTIVE";
      color = Colors.grey;
    } else if (isScanning) {
      label = "SCANNING";
      color = Colors.green;
    } else {
      label = "WAITING";
      color = Colors.orange;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: label != "INACTIVE"
                  ? [
                      BoxShadow(
                        color: color.withOpacity(0.5),
                        blurRadius: 4,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
