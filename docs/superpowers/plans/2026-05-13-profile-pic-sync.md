# Request-Based Profile Picture Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Transition profile picture synchronization to a request-based push model using JPG compression for efficiency and reliability.

**Architecture:** Devices will now "request" a profile picture by writing to a peer's characteristic. The peer responds by connecting back and pushing the image as an encrypted chunked message. Image format is switched from PNG to JPG.

**Tech Stack:** 
- `cryptography` (X25519, ChaCha20)
- `image` (JPG encoding)
- `isar` (Local storage)
- `ble_peripheral` (GATT Server)
- `flutter_blue_plus` (GATT Client)

---

### Task 1: Switch to JPG Compression

**Files:**
- Modify: `lib/profile_manager.dart`

- [ ] **Step 1: Update image filename and processing logic**

Change `_imageFileName` to `profile_pic.jpg` and update `_processImage` to use `encodeJpg`.

```dart
// lib/profile_manager.dart
static const String _imageFileName = 'profile_pic.jpg'; // Changed from .png

static Uint8List? _processImage(Uint8List bytes) {
  final decodedImage = img.decodeImage(bytes);
  if (decodedImage == null) return null;

  final img.Image resized = img.copyResize(
    decodedImage,
    width: 256,
    height: 256,
    interpolation: img.Interpolation.linear,
  );

  return Uint8List.fromList(img.encodeJpg(resized, quality: 75)); // Changed from encodePng
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/profile_manager.dart
git commit -m "feat(profile): switch profile picture format from PNG to JPG"
```

---

### Task 2: Enable Profile Sync Requests in BLEAdvertiser

**Files:**
- Modify: `lib/ble_advertiser.dart`

- [ ] **Step 1: Make profilePicCharUuid writeable**

Update the characteristic definition in `startAdvertising`.

```dart
// lib/ble_advertiser.dart
BleCharacteristic(
  uuid: profilePicCharUuid,
  properties: [
    CharacteristicProperties.read.index,
    CharacteristicProperties.write.index, // Added
  ],
  permissions: [
    AttributePermissions.readable.index,
    AttributePermissions.writeable.index, // Added
  ],
  value: profilePic ?? Uint8List.fromList([]),
),
```

- [ ] **Step 2: Handle incoming sync requests**

Update `setWriteRequestCallback` to trigger a push when the profile picture characteristic is written to.

```dart
// lib/ble_advertiser.dart
BlePeripheral.setWriteRequestCallback((
  deviceId,
  characteristicUuid,
  offset,
  value,
) {
  _log.info('Write request from $deviceId for $characteristicUuid');
  
  final charUuidLower = characteristicUuid.toLowerCase();
  
  if (charUuidLower == messageCharUuid.toLowerCase()) {
    // ... existing message handling ...
  } else if (charUuidLower == profilePicCharUuid.toLowerCase()) {
    _log.info('Received profile picture sync request from $deviceId');
    // Trigger async push
    IsarService().findDeviceByRemoteId(deviceId).then((device) {
      if (device != null) {
        ProfileManager.getProfilePicture().then((pic) {
          if (pic != null) {
            MessageHandler.pushProfilePicture(
              targetStableId: device.stableId,
              targetRemoteId: deviceId,
              imageBytes: pic,
            );
          }
        });
      }
    });
  }
  return WriteRequestResult();
});
```

- [ ] **Step 3: Commit**

```bash
git add lib/ble_advertiser.dart
git commit -m "feat(ble): make profile picture characteristic writeable for sync requests"
```

---

### Task 3: Implement Push and Receive Logic in MessageHandler

**Files:**
- Modify: `lib/message_handler.dart`

- [ ] **Step 1: Add typeProfilePic and pushProfilePicture method**

```dart
// lib/message_handler.dart
static const int typeProfilePic = 0x03; // New type

static Future<void> pushProfilePicture({
  required int targetStableId,
  required String targetRemoteId,
  required Uint8List imageBytes,
}) async {
  final device = BluetoothDevice.fromId(targetRemoteId);
  try {
    _log.info('Connecting to $targetStableId to push profile picture...');
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
      final payload = Uint8List(1 + imageBytes.length);
      payload[0] = typeProfilePic;
      payload.setRange(1, payload.length, imageBytes);

      final encrypted = await _encryptMessage(payload, (await IsarService().db.foundDevices.where().stableIdEqualTo(targetStableId).findFirst())!.publicKey!);
      
      final chunks = ChunkedTransferManager.generateChunks(encrypted, Random().nextInt(256));
      for (final chunk in chunks) {
        await messageChar.write(chunk, withoutResponse: true);
        await Future.delayed(const Duration(milliseconds: 10));
      }
      _log.info('Profile picture pushed to $targetStableId');
    }
  } catch (e) {
    _log.severe('Failed to push profile picture: $e');
  } finally {
    await device.disconnect();
  }
}
```

- [ ] **Step 2: Update receiver logic to handle typeProfilePic**

```dart
// lib/message_handler.dart: initialize()
if (type == typeText) {
  // ...
} else if (type == typeImage) {
  // ...
} else if (type == typeProfilePic) {
  final isar = IsarService();
  final device = await isar.db.foundDevices.where().stableIdEqualTo(senderStableId).findFirst();
  if (device != null) {
    device.profilePicture = payload;
    device.lastPictureSync = DateTime.now();
    await isar.putFoundDevice(device);
    _log.info('Updated profile picture for $senderStableId');
  }
}
```

- [ ] **Step 3: Commit**

```bash
git add lib/message_handler.dart
git commit -m "feat(messaging): implement profile picture push and receive logic"
```

---

### Task 4: Update Background Service to Request Sync

**Files:**
- Modify: `lib/background_service.dart`

- [ ] **Step 1: Change read to write request in _fetchFullMetadata**

```dart
// lib/background_service.dart: _fetchFullMetadata
if (picChar != null &&
    (existing.profilePicture == null ||
        existing.profileHash != hashHex)) {
  log.info('Requesting profile picture sync from $stableId...');
  // Instead of reading, we write a "ping" (0x01)
  await picChar.write([0x01], withoutResponse: true);
}
```

- [ ] **Step 2: Remove redundant reading code**

Clean up the old `existing.profilePicture = await robustRead(picChar)` block.

- [ ] **Step 3: Commit**

```bash
git add lib/background_service.dart
git commit -m "feat(service): switch to request-based profile picture sync"
```
