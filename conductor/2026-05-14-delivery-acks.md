# Delivery ACKs (Breadcrumb Routing) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement reliable "Delivered" receipts (ACKs) using stateless Breadcrumb Reverse Path Forwarding.

**Architecture:** A new 10-byte unencrypted packet (`typeAck = 0x05`) hops back from the destination to the origin. Relay nodes map `(OriginId + MsgId)` to the upstream node (`directSenderId`) that handed them the message, deleting the entry once the first ACK passes through.

**Tech Stack:** Dart, Isar, Flutter Blue Plus.

---

### Task 1: Database Schema & Constant Updates

**Files:**
- Modify: `lib/data/message.dart`
- Modify: `lib/message_handler.dart`

- [ ] **Step 1: Add isDelivered and messageId to Schema**

```dart
// lib/data/message.dart
import 'package:isar_community/isar.dart';

part 'message.g.dart';

@Collection()
class Message {
  Id id = Isar.autoIncrement;
  
  @Index()
  late int senderStableId;
  
  @Index()
  late int receiverStableId;
  
  String? content;
  bool isImage = false;
  List<int>? data;
  late DateTime timestamp;
  bool isReceived = false;

  bool isDelivered = false; // Added
  
  @Index()
  int? messageId; // Added for ACK mapping
}
```

- [ ] **Step 2: Add typeAck constant to MessageHandler**

```dart
// lib/message_handler.dart
  static const int typeText = 0x01;
  static const int typeImage = 0x02;
  static const int typeProfilePic = 0x03;
  static const int typeRelay = 0x04;
  static const int typeAck = 0x05; // Added
```

- [ ] **Step 3: Run build_runner**

Run: `dart run build_runner build --delete-conflicting-outputs`
Expected: `message.g.dart` generated successfully.

- [ ] **Step 4: Commit**

```bash
git add lib/data/message.dart lib/data/message.g.dart lib/message_handler.dart
git commit -m "feat(db): add isDelivered and messageId to Message schema for ACKs"
```

---

### Task 2: Routing Table (Breadcrumbs) Infrastructure

**Files:**
- Modify: `lib/message_handler.dart`

- [ ] **Step 1: Define PendingAck class and State Map**

```dart
// lib/message_handler.dart (Put at top of class or outside)
class PendingAck {
  final int upstreamNodeId;
  final DateTime timestamp;
  PendingAck(this.upstreamNodeId, this.timestamp);
}

// Inside MessageHandler class:
  static final Map<int, PendingAck> _pendingAcks = {};
```

- [ ] **Step 2: Update Cleanup Timer**

Update the existing `_startCacheCleanupTimer` to also clean `_pendingAcks`.

```dart
// lib/message_handler.dart
  static void _startCacheCleanupTimer() {
    _cacheCleanupTimer?.cancel();
    _cacheCleanupTimer = Timer.periodic(const Duration(seconds: 60), (timer) {
      final now = DateTime.now();
      _seenRelayMessageIds.removeWhere((id, timestamp) =>
          now.difference(timestamp) > const Duration(seconds: 1020));
      
      // Cleanup breadcrumbs (50 minutes)
      _pendingAcks.removeWhere((key, pendingAck) => 
          now.difference(pendingAck.timestamp) > const Duration(minutes: 50));
    });
  }
```

- [ ] **Step 3: Drop Breadcrumbs on Forwarding**

In `initialize()`, before calling `_forwardRelayPayload`:

```dart
// lib/message_handler.dart : initialize()
          } else if (ttl > 1) {
            _log.info('Forwarding relay message $msgId to $targetId (TTL: $ttl)');
            
            // Drop Breadcrumb
            _pendingAcks[cacheKey] = PendingAck(directSenderId, DateTime.now());
            
            fullData[10] = ttl - 1;
            _forwardRelayPayload(fullData, targetId, directSenderId);
            return;
```

- [ ] **Step 4: Commit**

```bash
git add lib/message_handler.dart
git commit -m "feat(mesh): add breadcrumb routing table for delivery ACKs"
```

---

### Task 3: ACK Generation (Terminal Node)

**Files:**
- Modify: `lib/message_handler.dart`

- [ ] **Step 1: Generate ACK when payload received**

Update the terminal node logic in `initialize()` to fire an ACK back to the `directSenderId`.

```dart
// lib/message_handler.dart : initialize()
          if (targetId == myId) {
            _log.info('We are the destination for relay message $msgId from $originSenderId');
            
            // Generate and push ACK
            _pushAck(directSenderId, originSenderId, msgId);
            
            final innerPayload = fullData.sublist(11);
            decryptedData = await _decryptMessage(originSenderId, innerPayload);
            if (decryptedData == null || decryptedData.isEmpty) return;
            payloadToProcess = decryptedData;
```

- [ ] **Step 2: Implement _pushAck helper**

```dart
// lib/message_handler.dart
  static Future<void> _pushAck(int targetNodeId, int originId, int msgId) async {
    final isar = IsarService();
    final neighbor = await isar.db.foundDevices.where().stableIdEqualTo(targetNodeId).findFirst();
    if (neighbor == null) return;

    final ackPayload = Uint8List(10);
    final buffer = ByteData.view(ackPayload.buffer);
    ackPayload[0] = typeAck;
    buffer.setUint32(1, targetNodeId, Endian.big);
    buffer.setUint32(5, originId, Endian.big);
    ackPayload[9] = msgId;

    final device = BluetoothDevice.fromId(neighbor.remoteId);
    try {
      _log.info('Pushing ACK to $targetNodeId...');
      await device.connect(timeout: const Duration(seconds: 15), autoConnect: false, license: License.free);
      
      final services = await device.discoverServices();
      BluetoothCharacteristic? messageChar;
      for (final s in services) {
        if (s.uuid.toString().toLowerCase() == BLEAdvertiser.serviceUuid.toLowerCase()) {
          for (final c in s.characteristics) {
            if (c.uuid.toString().toLowerCase() == BLEAdvertiser.messageCharUuid.toLowerCase()) {
              messageChar = c;
              break;
            }
          }
        }
      }

      if (messageChar != null) {
        await messageChar.write(ackPayload, withoutResponse: false);
        _log.info('ACK pushed successfully.');
      }
    } catch (e) {
      _log.warning('Failed to push ACK: $e');
    } finally {
      await device.disconnect();
    }
  }
```

- [ ] **Step 3: Commit**

```bash
git add lib/message_handler.dart
git commit -m "feat(mesh): generate and send delivery ACK from terminal node"
```

---

### Task 4: ACK Relaying & Receiving (Reverse Path)

**Files:**
- Modify: `lib/ble_advertiser.dart`

- [ ] **Step 1: Intercept typeAck in GATT Server**

In `ble_advertiser.dart`, inside `setWriteRequestCallback`, intercept small payloads starting with `0x05`.

```dart
// lib/ble_advertiser.dart : setWriteRequestCallback
  if (charUuidLower == messageCharUuid.toLowerCase()) {
    if (value.isNotEmpty && value[0] == 0x05 && value.length == 10) {
      // It's a raw ACK packet, skip ChunkedTransferManager
      MessageHandler.handleIncomingAck(value);
      return WriteRequestResult();
    }
    // ... existing ChunkedTransferManager call ...
```

- [ ] **Step 2: Implement handleIncomingAck in MessageHandler**

```dart
// lib/message_handler.dart
  static Future<void> handleIncomingAck(Uint8List ackPayload) async {
    final buffer = ByteData.view(ackPayload.buffer);
    final targetId = buffer.getUint32(1, Endian.big);
    final originId = buffer.getUint32(5, Endian.big);
    final msgId = ackPayload[9];

    final myId = await ProfileManager.getStableDeviceId();

    if (targetId != myId) {
      return; // Not meant for us to relay
    }

    if (originId == myId) {
      // We are the original sender! Message delivered.
      _log.info('Message $msgId was delivered successfully!');
      final isar = IsarService();
      final msg = await isar.db.messages.filter().messageIdEqualTo(msgId).findFirst();
      if (msg != null && !msg.isDelivered) {
        msg.isDelivered = true;
        await isar.putMessage(msg);
      }
      return;
    }

    // We are a relay. Look up breadcrumb.
    final cacheKey = (originId << 8) | msgId;
    final pendingAck = _pendingAcks[cacheKey];
    
    if (pendingAck != null) {
      _log.info('Relaying ACK for $msgId to upstream node ${pendingAck.upstreamNodeId}');
      _pushAck(pendingAck.upstreamNodeId, originId, msgId);
      _pendingAcks.remove(cacheKey); // First ACK wins
    } else {
      _log.info('Dropped orphan ACK for $msgId');
    }
  }
```

- [ ] **Step 3: Commit**

```bash
git add lib/ble_advertiser.dart lib/message_handler.dart
git commit -m "feat(mesh): implement ACK reverse path relaying and delivery confirmation"
```

---

### Task 5: UI Integration and Sender Updates

**Files:**
- Modify: `lib/message_handler.dart`
- Modify: `lib/screens/discovery.dart`

- [ ] **Step 1: Save messageId to Isar when sending**

```dart
// lib/message_handler.dart : handleOutgoingMessage
  static Future<void> handleOutgoingMessage({
    required int receiverStableId,
    required String content,
    bool isImage = false,
    Uint8List? imageData,
    int? messageId, // Added parameter
  }) async {
    // ...
      final message = Message()
        ..senderStableId = myStableId
        ..receiverStableId = receiverStableId
        ..content = content
        ..timestamp = DateTime.now()
        ..isReceived = false
        ..isImage = isImage
        ..data = imageData
        ..messageId = messageId; // Save it

      await isar.putMessage(message);
```

- [ ] **Step 2: Pass messageId from DiscoveryScreen**

```dart
// lib/screens/discovery.dart : _performSendMessage
          // ...
          await MessageHandler.handleOutgoingMessage(
            receiverStableId: device.stableId,
            content: content,
            messageId: messageId, // Pass the ID we used in getRelayWrappedPayload
          );
```

- [ ] **Step 3: Update Chat UI to show double checkmarks**

Find the `ListView.builder` inside the Chat/Discovery screen where messages are rendered (e.g., `_buildMessageBubble`).

```dart
// lib/screens/discovery.dart (or equivalent file where messages are drawn)
// Inside the widget building the message bubble for sent messages:

    // If it's a sent message, show the status icon
    if (!message.isReceived)
      Icon(
        message.isDelivered ? Icons.done_all : Icons.check,
        size: 16,
        color: message.isDelivered ? Colors.blue : Colors.grey,
      ),
```
*(Note: Apply this UI change specifically to where sent messages display their timestamp/status).*

- [ ] **Step 4: Commit**

```bash
git add lib/message_handler.dart lib/screens/discovery.dart
git commit -m "feat(ui): display delivery receipts in chat and map message IDs"
```

---

### Task 6: Final Verification

- [ ] **Step 1: Analysis check**
Run: `dart analyze`
Expected: No errors.

- [ ] **Step 2: Push to Github**
Only when user confirms.
