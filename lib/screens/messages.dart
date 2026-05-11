import 'package:ble_test/components/scaffold_wrapper.dart';
import 'package:ble_test/providers/found_devices.dart';
import 'package:ble_test/router.dart';
import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

class MessagesScreen extends ConsumerWidget {
  const MessagesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final messagesAsync = ref.watch(messagesProvider);

    return ScaffoldWrapper(
      screen: MessagesRoute().location,
      withLog: true,
      padding: const EdgeInsets.all(8.0),
      body: messagesAsync.when(
        data: (messages) {
          if (messages.isEmpty) {
            return const Center(child: Text("No messages yet."));
          }

          return ListView.builder(
            itemCount: messages.length,
            itemBuilder: (context, index) {
              final msg = messages[index];
              final isReceived = msg.isReceived;

              return ListTile(
                title: msg.isImage && msg.data != null
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("[Image Received]"),
                          const SizedBox(height: 4),
                          GestureDetector(
                            onTap: () => _showFullImage(context, msg.data!),
                            child: Container(
                              height: 150,
                              width: 150,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                image: DecorationImage(
                                  image: MemoryImage(
                                      Uint8List.fromList(msg.data!)),
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                          ),
                        ],
                      )
                    : Text(msg.content),
                subtitle: Text(
                  "${DateFormat('HH:mm:ss').format(msg.timestamp)} - ${isReceived ? 'From: ${msg.senderStableId}' : 'To: ${msg.receiverStableId}'}",
                  style: const TextStyle(fontSize: 10),
                ),
                leading: Icon(
                  isReceived ? Icons.call_received : Icons.call_made,
                  color: isReceived ? Colors.green : Colors.blue,
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error: $err')),
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
}
