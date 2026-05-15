import 'dart:typed_data';
import 'package:ble_test/background_service.dart';
import 'package:ble_test/components/scaffold_wrapper.dart';
import 'package:ble_test/components/system_health_card.dart';
import 'package:ble_test/data/found_device.dart';
import 'package:ble_test/data/isar_service.dart';
import 'package:ble_test/providers/advertising_name.dart';
import 'package:ble_test/providers/found_devices.dart';
import 'package:ble_test/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:intl/intl.dart';

class DiscoveryScreen extends ConsumerWidget {
  const DiscoveryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isRunning = ref.watch(isServiceRunningProvider).value ?? false;
    final isScanning = ref.watch(isScanningProvider).value ?? false;
    final progress = ref.watch(scanProgressProvider).value ?? 0.0;
    final scanStatus = ref.watch(scanStatusProvider).value ?? {};
    final isAdvertising = ref.watch(isAdvertisingProvider);
    final remainingSeconds = scanStatus['remainingSeconds'] as int?;

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
                IconButton.filledTonal(
                  onPressed: () => _showResetConfirmation(context, ref),
                  icon: const Icon(Icons.refresh),
                  tooltip: "Reset Service & Data",
                  color: Theme.of(context).colorScheme.error,
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
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 32.0,
              vertical: 8.0,
            ),
            child: Text("Advertising ${isAdvertising ? "on" : "off"}"),
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
                    color: progress > 0.0 ? null : Colors.orange,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isScanning
                        ? "Scanning..."
                        : "Waiting for next cycle...${remainingSeconds != null ? ' ($remainingSeconds s)' : ''}",
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
            ),
          const Divider(),
          Expanded(
            child: ref
                .watch(discoveredDevicesProvider)
                .when(
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
                            backgroundImage:
                                item.profilePicture != null &&
                                    item.profilePicture!.isNotEmpty
                                ? MemoryImage(
                                    Uint8List.fromList(item.profilePicture!),
                                  )
                                : null,
                            child:
                                (item.profilePicture == null ||
                                    item.profilePicture!.isEmpty)
                                ? const Icon(Icons.person)
                                : null,
                          ),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  item.name ?? "Unknown",
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              if (item.publicKey != null)
                                const Padding(
                                  padding: EdgeInsets.only(left: 4.0),
                                  child: Tooltip(
                                    message: "End-to-End Encrypted",
                                    child: Icon(
                                      Icons.lock,
                                      size: 14,
                                      color: Colors.green,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  StreamBuilder<BluetoothConnectionState>(
                                    stream: BluetoothDevice.fromId(
                                      item.remoteId,
                                    ).connectionState,
                                    builder: (context, snapshot) {
                                      final state =
                                          snapshot.data ??
                                          BluetoothConnectionState.disconnected;
                                      final color =
                                          state ==
                                              BluetoothConnectionState.connected
                                          ? Colors.green
                                          : Colors.grey;
                                      return Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: color.withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          border: Border.all(
                                            color: color.withValues(alpha: 0.5),
                                          ),
                                        ),
                                        child: Text(
                                          state.name.toUpperCase(),
                                          style: TextStyle(
                                            fontSize: 8,
                                            fontWeight: FontWeight.bold,
                                            color: color,
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    "ID: ${item.stableId}",
                                    style: const TextStyle(fontSize: 10),
                                  ),
                                ],
                              ),
                              Text(
                                "MAC: ${item.remoteId}",
                                style: const TextStyle(fontSize: 10),
                              ),
                              if (item.publicKey == null)
                                Text(
                                  "Security: Pending Handshake...",
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Theme.of(context).colorScheme.error,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (item.publicKey == null ||
                                  item.lastPictureSync == null ||
                                  DateTime.now()
                                          .difference(item.lastPictureSync!)
                                          .inHours >=
                                      24)
                                Padding(
                                  padding: const EdgeInsets.only(right: 8.0),
                                  child: Tooltip(
                                    message: "Metadata sync pending",
                                    child: Icon(
                                      Icons.sync_problem,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.secondary,
                                      size: 20,
                                    ),
                                  ),
                                ),
                              IconButton(
                                icon: const Icon(Icons.info_outline),
                                tooltip: "View Profile",
                                onPressed: () =>
                                    _showProfileDialog(context, item),
                              ),
                              IconButton(
                                icon: const Icon(Icons.message_outlined),
                                tooltip: item.publicKey == null
                                    ? "Handshake pending..."
                                    : "Messages",
                                onPressed: item.publicKey == null
                                    ? null
                                    : () => _showMessageHistoryDialog(
                                          context,
                                          ref,
                                          item,
                                        ),
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
              value: DateFormat(
                'dd.MM.yyyy HH:mm:ss',
              ).format(device.lastSeen.toLocal()),
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

  void _showMessageHistoryDialog(
    BuildContext context,
    WidgetRef ref,
    FoundDevice device,
  ) {
    final controller = TextEditingController();
    final scrollController = ScrollController();

    showDialog(
      context: context,
      builder: (context) => Dialog.fullscreen(
        child: Column(
          children: [
            AppBar(
              title: Text("Chat with ${device.name ?? 'Device'}"),
              actions: [
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            Expanded(
              child: ref.watch(messagesWithDeviceProvider(device.stableId)).when(
                    data: (messages) {
                      if (messages.isEmpty) {
                        return const Center(child: Text("No messages yet."));
                      }
                      // Auto-scroll to bottom
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (scrollController.hasClients) {
                          scrollController.jumpTo(
                            scrollController.position.maxScrollExtent,
                          );
                        }
                      });
                      return ListView.builder(
                        controller: scrollController,
                        padding: const EdgeInsets.all(8),
                        itemCount: messages.length,
                        itemBuilder: (context, index) {
                          final msg = messages[index];
                          final isReceived = msg.isReceived;
                          return ListTile(
                            title: msg.isImage && msg.data != null
                                ? Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text("[Image Received]"),
                                      const SizedBox(height: 4),
                                      GestureDetector(
                                        onTap: () =>
                                            _showFullImage(context, msg.data!),
                                        child: Container(
                                          height: 150,
                                          width: 150,
                                          decoration: BoxDecoration(
                                            borderRadius:
                                                BorderRadius.circular(8),
                                            image: DecorationImage(
                                              image: MemoryImage(
                                                Uint8List.fromList(msg.data!),
                                              ),
                                              fit: BoxFit.cover,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  )
                                : Text(msg.content),
                            subtitle: Text(
                              DateFormat('HH:mm:ss').format(msg.timestamp),
                              style: const TextStyle(fontSize: 10),
                            ),
                            leading: Icon(
                              isReceived ? Icons.call_received : Icons.call_made,
                              color: isReceived ? Colors.green : Colors.blue,
                            ),
                            trailing: !isReceived
                                ? Icon(
                                    msg.wasFailed
                                        ? Icons.error_outline
                                        : (!msg.wasSent
                                            ? Icons.schedule
                                            : (msg.isDelivered
                                                ? Icons.done_all
                                                : Icons.check)),
                                    size: 16,
                                    color: msg.wasFailed
                                        ? Colors.red
                                        : (msg.isDelivered
                                            ? Colors.blue
                                            : Colors.grey),
                                  )
                                : null,
                          );
                        },
                      );
                    },
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (err, stack) => Center(child: Text('Error: $err')),
                  ),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: controller,
                      decoration: const InputDecoration(
                        hintText: "Enter message...",
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: () {
                      final content = controller.text.trim();
                      if (content.isNotEmpty) {
                        FlutterBackgroundService().invoke('sendMessage', {
                          'targetId': device.stableId,
                          'content': content,
                        });
                        controller.clear();
                      }
                    },
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showFullImage(BuildContext context, List<int> data) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.memory(Uint8List.fromList(data)),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Close"),
            ),
          ],
        ),
      ),
    );
  }

  void _showResetConfirmation(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Reset Background Service?"),
        content: const Text(
          "This will stop the background scanner and delete all discovered devices and messages. This action cannot be undone.",
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
              await IsarService().clearAllData();

              // 3. Restart the service
              await initializeBackgroundService();

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
        color: color.withValues(alpha: 0.1),
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
                        color: color.withValues(alpha: 0.5),
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
