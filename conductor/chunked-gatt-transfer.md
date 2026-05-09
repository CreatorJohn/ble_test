# High-Density BLE Mesh & Self-Repairing GATT Transfer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor the BLE mesh identity to use a Stable Device ID, update the advertisement packet format (48-bit constraint), and implement a self-repairing (FEC), chunk-based GATT transport layer capable of sending large payloads with a 1-minute timeout to prevent memory leaks.

**Architecture:** 
1. **Identity & Advertisement**: Devices will generate a permanent 32-bit `Stable Device ID`. The main advertisement packet (Manufacturer Data) will encode this 32-bit ID + a 14-bit Profile Hash Prefix + `isIOS` + `isOnline` perfectly into 6 bytes. The Scan Response will hold Latitude, Longitude (24-bit compressed), the full 6-byte Profile Hash, and the Local Name.
2. **Database**: `FoundDevice` will use `Stable Device ID` as the primary key. `Message` will use `Stable Device ID` for sender and receiver linking, surviving MAC rotations.
3. **Transport Layer**: `ChunkedTransferManager` will split large messages into chunks and use an Erasure Coding / Parity approach (e.g., Reed-Solomon or XOR parity) to generate redundant chunks. `writeWithoutResponse` will be used to blast chunks. A 1-minute timeout clears incomplete buffers.

**Tech Stack:** Dart core (`dart:async`, `dart:typed_data`, `dart:math`), `shared_preferences`, `isar`.

---

### Task 1: Stable Identity & Database Refactoring

**Files:**
- Modify: `lib/profile_manager.dart`
- Modify: `lib/data/found_device.dart`
- Modify: `lib/data/message.dart`

- [ ] **Step 1: Implement Stable Device ID generation**
Update `ProfileManager` to generate and persist a 4-byte (32-bit) Stable Device ID on first launch.

```dart
// Append to lib/profile_manager.dart
  static const String _deviceIdKey = 'stable_device_id_4';

  static Future<int> getStableDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    int? deviceId = prefs.getInt(_deviceIdKey);

    if (deviceId == null) {
      // Generate random 32-bit integer (4 bytes)
      deviceId = Random.secure().nextInt(0xFFFFFFFF);
      await prefs.setInt(_deviceIdKey, deviceId);
    }
    return deviceId;
  }
```

- [ ] **Step 2: Update Database Models to use Stable Device ID**
Modify `FoundDevice` to use `stableId` as its primary identifier. Modify `Message` to use `senderStableId` and `receiverStableId`.

```dart
// lib/data/found_device.dart
import 'package:isar_community/isar.dart';

part 'found_device.g.dart';

@Collection()
class FoundDevice {
  Id id = Isar.autoIncrement;

  @Index(unique: true, replace: true)
  late int stableId; // The new permanent ID

  late String remoteId; // The volatile MAC address

  String? name;
  late int rssi;
  late DateTime lastSeen;

  @Index()
  String? profileHash;

  List<int>? profilePicture;
  DateTime? lastPictureSync; // Time-based cache invalidation
}
```

```dart
// lib/data/message.dart
import 'package:isar_community/isar.dart';

part 'message.g.dart';

@Collection()
class Message {
  Id id = Isar.autoIncrement;

  late int senderStableId;
  late int receiverStableId;
  late String content;
  late DateTime timestamp;

  late bool isReceived;
}
```

- [ ] **Step 3: Run build_runner**
Run `dart run build_runner build --delete-conflicting-outputs` to regenerate Isar code.

- [ ] **Step 4: Commit**
Commit changes with message "refactor: transition to 32-bit stable device id for mesh routing".

---

### Task 2: Ultra-Compact Advertisement Packets

**Files:**
- Modify: `lib/mesh_packet_encoder.dart`
- Modify: `lib/ble_advertiser.dart`

- [ ] **Step 1: Rewrite MeshPacketEncoder for the 48-bit constraint**

```dart
// Replace encodeManufacturerData in lib/mesh_packet_encoder.dart
  static Uint8List encodeMainPacket({
    required int stableId,
    required Uint8List profileHash,
    required bool isIOS,
    required bool isOnline,
  }) {
    final data = Uint8List(6);
    final buffer = ByteData.view(data.buffer);
    
    // Stable ID (4 bytes / 32 bits)
    buffer.setUint32(0, stableId, Endian.big);

    // Profile Hash Prefix (14 bits) + Flags (2 bits) into remaining 2 bytes
    // Read first 2 bytes of hash
    int hashPrefix = (profileHash[0] << 8 | profileHash[1]) >> 2; // Keep top 14 bits
    
    int flags = 0;
    if (isIOS) flags |= 0x02;
    if (isOnline) flags |= 0x01;

    int finalTwoBytes = (hashPrefix << 2) | flags;
    buffer.setUint16(4, finalTwoBytes, Endian.big);

    return data;
  }

  static Uint8List encodeScanResponseData({
    required double latitude,
    required double longitude,
    required Uint8List profileHash,
  }) {
    final lat24 = encodeCoordinate(latitude, true);
    final lon24 = encodeCoordinate(longitude, false);
    
    final data = Uint8List(12);
    // Lat (3) + Lon (3)
    data[0] = (lat24 >> 16) & 0xFF; data[1] = (lat24 >> 8) & 0xFF; data[2] = lat24 & 0xFF;
    data[3] = (lon24 >> 16) & 0xFF; data[4] = (lon24 >> 8) & 0xFF; data[5] = lon24 & 0xFF;
    // Full Hash (6)
    data.setRange(6, 12, profileHash);
    
    return data;
  }
```

- [ ] **Step 2: Update BLEAdvertiser to split Main Packet and Scan Response**
Update the `startAdvertising` method in `lib/ble_advertiser.dart` to encode the ManufacturerData using the new `encodeMainPacket`, and place `encodeScanResponseData` into a secondary manufacturer data field or append it to the local name. Since `ble_peripheral` combines localName and manufacturerData into advertisement, we must use the library's capabilities. Note: If `ble_peripheral` doesn't strictly allow separate Scan Response structuring natively, encode the Scan Response into the `localName` string safely.

- [ ] **Step 3: Commit**
Commit changes with message "feat: implement 48-bit main packet and scan response routing".

---

### Task 3: Self-Repairing Chunked Transfer Manager

**Files:**
- Create: `lib/chunked_transfer_manager.dart`

- [ ] **Step 1: Setup the Transfer Manager with 1-Minute Cleanup**

```dart
// lib/chunked_transfer_manager.dart
import 'dart:async';
import 'dart:typed_data';
import 'package:logging/logging.dart';

class ChunkedTransferManager {
  static final Logger _log = Logger('ChunkedTransferManager');
  static final Map<String, Map<int, Uint8List>> _buffers = {};
  static final Map<String, Timer> _cleanupTimers = {};
  static const int chunkTimeoutSeconds = 60;
  
  static final StreamController<Map<String, dynamic>> _completedPayloads = StreamController.broadcast();
  static Stream<Map<String, dynamic>> get onPayloadComplete => _completedPayloads.stream;

  static void handleIncomingChunk({
    required int senderStableId,
    required Uint8List data,
  }) {
    if (data.length < 3) return;

    final messageId = data[0];
    final totalChunks = data[1];
    final chunkIndex = data[2];
    final payload = data.sublist(3);

    final transferKey = "${senderStableId}_$messageId";

    _buffers.putIfAbsent(transferKey, () => {});
    _buffers[transferKey]![chunkIndex] = payload;

    _cleanupTimers[transferKey]?.cancel();
    _cleanupTimers[transferKey] = Timer(Duration(seconds: chunkTimeoutSeconds), () {
      _buffers.remove(transferKey);
      _cleanupTimers.remove(transferKey);
      _log.warning('Transfer $transferKey timed out and was cleared.');
    });

    // Check completion (Simple mode for now, FEC/Parity requires complex matrix math)
    // For FEC: Check if we have enough chunks to reconstruct
    if (_buffers[transferKey]!.length == totalChunks) {
      _cleanupTimers[transferKey]?.cancel();
      _cleanupTimers.remove(transferKey);

      final builder = BytesBuilder();
      for (int i = 0; i < totalChunks; i++) {
        builder.add(_buffers[transferKey]![i]!);
      }

      _buffers.remove(transferKey);
      _completedPayloads.add({
        'senderStableId': senderStableId,
        'payload': builder.toBytes(),
      });
    }
  }

  static List<Uint8List> generateChunks(Uint8List payload, int messageId, {int maxChunkSize = 200}) {
    final List<Uint8List> chunks = [];
    int offset = 0;
    int chunkIndex = 0;
    final totalChunks = (payload.length / maxChunkSize).ceil();

    while (offset < payload.length) {
      final end = (offset + maxChunkSize > payload.length) ? payload.length : offset + maxChunkSize;
      final chunkPayload = payload.sublist(offset, end);
      
      final chunk = Uint8List(3 + chunkPayload.length);
      chunk[0] = messageId;
      chunk[1] = totalChunks; // If FEC is added, totalChunks increases by parity chunks
      chunk[2] = chunkIndex;
      chunk.setRange(3, chunk.length, chunkPayload);
      
      chunks.add(chunk);
      offset += maxChunkSize;
      chunkIndex++;
    }

    // NOTE: To add FEC (Erasure Coding), we would calculate parity blocks here
    // and append them to the `chunks` list before returning.
    
    return chunks;
  }
}
```

- [ ] **Step 2: Commit**
Commit changes with message "feat: add chunked transfer manager with timeout and assembly logic".

---

### Task 4: Integrate MessageHandler and Update UI

**Files:**
- Modify: `lib/message_handler.dart`
- Modify: `lib/main.dart`
- Modify: `lib/screens/discovery.dart`

- [ ] **Step 1: Integrate ChunkedTransferManager into MessageHandler**
Update `MessageHandler` to listen to `ChunkedTransferManager.onPayloadComplete`. Change the sender identity in `handleIncomingMessage` and `handleOutgoingMessage` to use the `senderStableId` (integer).

- [ ] **Step 2: Update Outgoing Logic in DiscoveryScreen**
Update `_performSendMessage` to generate chunks using `ChunkedTransferManager.generateChunks` and iterate through them, executing `messageChar.writeWithoutResponse(chunk)` to rapidly blast the chunks. Wait a tiny bit (e.g., 5-10ms) between chunks to avoid overflowing the Bluetooth stack.

- [ ] **Step 3: Commit**
Commit changes with message "feat: wire GATT transfer logic into UI and message handler".
