import 'dart:convert';
import 'package:ble_test/background_service.dart';
import 'package:ble_test/ble_advertiser.dart';
import 'package:ble_test/components/scaffold_wrapper.dart';
import 'package:ble_test/components/system_health_card.dart';
import 'package:ble_test/data/found_device.dart';
import 'package:ble_test/data/isar_service.dart';
import 'package:ble_test/message_handler.dart';
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
                _StatusIndicator(isRunning: isRunning),
              ],
            ),
          ),
          if (isRunning)
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 32.0, vertical: 8.0),
              child: Column(
                children: [
                  LinearProgressIndicator(value: progress),
                  const SizedBox(height: 4),
                  Text(
                    progress > 0 ? "Scanning..." : "Waiting for next cycle...",
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
                          title: Row(
                            children: [
                              Text(item.name ?? "Unknown"),
                              const SizedBox(width: 8),
                              StreamBuilder<BluetoothConnectionState>(
                                stream: BluetoothDevice.fromId(item.remoteId)
                                    .connectionState,
                                builder: (context, snapshot) {
                                  final state = snapshot.data ??
                                      BluetoothConnectionState.disconnected;
                                  if (state == BluetoothConnectionState.connected) {
                                    return const Badge(
                                      label: Text("CONNECTED"),
                                      backgroundColor: Colors.green,
                                    );
                                  }
                                  return const SizedBox.shrink();
                                },
                              ),
                              const SizedBox(width: 4),
                              StreamBuilder<BluetoothBondState>(
                                stream: BluetoothDevice.fromId(item.remoteId).bondState,
                                builder: (context, snapshot) {
                                  final state = snapshot.data ?? BluetoothBondState.none;
                                  if (state == BluetoothBondState.bonded) {
                                    return const Badge(
                                      label: Text("BONDED"),
                                      backgroundColor: Colors.blue,
                                    );
                                  }
                                  return const SizedBox.shrink();
                                },
                              ),
                            ],
                          ),
                          subtitle: Text(item.remoteId),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text("${item.rssi} dBm"),
                              IconButton(
                                icon: const Icon(Icons.send),
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

  void _sendMessageDialog(
      BuildContext context, WidgetRef ref, FoundDevice device) {
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
      BuildContext context, FoundDevice device, String content) async {
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
          final payload = utf8.encode(content);
          final messageId = Random().nextInt(256);
          final chunks = ChunkedTransferManager.generateChunks(
              Uint8List.fromList(payload), messageId);

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
            SnackBar(content: Text("Message sent! ($sent chunks)")),
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
                      content: Text("Service reset and data cleared")),
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

class _StatusIndicator extends StatelessWidget {
  final bool isRunning;

  const _StatusIndicator({required this.isRunning});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isRunning
            ? Colors.green.withOpacity(0.1)
            : Colors.grey.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isRunning ? Colors.green : Colors.grey,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: isRunning ? Colors.green : Colors.grey,
              shape: BoxShape.circle,
              boxShadow: isRunning
                  ? [
                      BoxShadow(
                        color: Colors.green.withOpacity(0.5),
                        blurRadius: 4,
                        spreadRadius: 1,
                      )
                    ]
                  : null,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            isRunning ? "ACTIVE" : "INACTIVE",
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: isRunning ? Colors.green : Colors.grey,
            ),
          ),
        ],
      ),
    );
  }
}
