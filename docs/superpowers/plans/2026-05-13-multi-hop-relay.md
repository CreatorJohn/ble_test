# Multi-Hop Relaying Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement a true BLE mesh network using a "Directed Flood" approach with Geographic Routing and Angular Dispersion.

**Architecture:** A new `typeRelay` (0x04) message wrapper encapsulates encrypted payloads with routing metadata (Target ID, MsgId, TTL). `MessageHandler` manages deduplication via a timed cache and uses geographic coordinates to select the optimal 3 neighbors for forwarding.

**Tech Stack:** Dart, Flutter Blue Plus, Isar, Cryptography.

---

### Task 1: Constants and Cache Infrastructure

**Files:**
- Modify: `lib/message_handler.dart`

- [ ] **Step 1: Add typeRelay constant**
```dart
static const int typeRelay = 0x04;
```

- [ ] **Step 2: Initialize seen message cache and cleanup timer**
```dart
static final Map<int, DateTime> _seenRelayMessageIds = {};
static Timer? _cacheCleanupTimer;

static void _startCacheCleanupTimer() {
  _cacheCleanupTimer?.cancel();
  _cacheCleanupTimer = Timer.periodic(const Duration(seconds: 60), (timer) {
    final now = DateTime.now();
    // Cache Lifetime = (TTL 10 * 100s) + 20s = 1020s
    _seenRelayMessageIds.removeWhere((id, timestamp) => 
      now.difference(timestamp) > const Duration(seconds: 1020));
  });
}
```

- [ ] **Step 3: Call cleanup timer in initialize()**
Add `_startCacheCleanupTimer();` inside the `initialize()` method.

- [ ] **Step 4: Commit**
```bash
git add lib/message_handler.dart
git commit -m "feat(mesh): add relay constants and cache infrastructure"
```

---

### Task 2: Geographic Routing Utilities

**Files:**
- Create: `lib/utils/geo_utils.dart`

- [ ] **Step 1: Implement Haversine and Bearing math**
```dart
import 'dart:math';

class GeoUtils {
  static double calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const p = 0.017453292519943295;
    final a = 0.5 - cos((lat2 - lat1) * p) / 2 +
        cos(lat1 * p) * cos(lat2 * p) * (1 - cos((lon2 - lon1) * p)) / 2;
    return 12742 * asin(sqrt(a)); // 2 * R; R = 6371 km
  }

  static double calculateBearing(double lat1, double lon1, double lat2, double lon2) {
    final dLon = (lon2 - lon1) * (pi / 180);
    final y = sin(dLon) * cos(lat2 * (pi / 180));
    final x = cos(lat1 * (pi / 180)) * sin(lat2 * (pi / 180)) -
        sin(lat1 * (pi / 180)) * cos(lat2 * (pi / 180)) * cos(dLon);
    final brng = atan2(y, x) * (180 / pi);
    return (brng + 360) % 360;
  }
}
```

- [ ] **Step 2: Commit**
```bash
git add lib/utils/geo_utils.dart
git commit -m "feat(mesh): add geographic math utilities"
```

---

### Task 3: Relay Receiving Logic

**Files:**
- Modify: `lib/message_handler.dart`

- [ ] **Step 1: Update initialize listener to handle typeRelay**
```dart
// Inside ChunkedTransferManager listener
if (type == typeRelay) {
  if (payload.length < 6) return; // Header: Target(4), MsgId(1), TTL(1)
  final buffer = ByteData.view(payload.buffer);
  final targetId = buffer.getUint32(1, Endian.big);
  final msgId = payload[5];
  int ttl = payload[6];

  if (_seenRelayMessageIds.containsKey(msgId)) return;
  _seenRelayMessageIds[msgId] = DateTime.now();

  final myId = await ProfileManager.getStableDeviceId();
  if (targetId == myId) {
    // Decrypt the inner payload starting at offset 7
    final innerPayload = payload.sublist(7);
    final decrypted = await _decryptMessage(senderStableId, innerPayload);
    // ... standard processing logic (text/image) ...
  } else if (ttl > 1) {
    payload[6] = ttl - 1;
    _forwardRelayPayload(payload, targetId, senderStableId);
  }
  return;
}
```

- [ ] **Step 2: Commit**
```bash
git add lib/message_handler.dart
git commit -m "feat(mesh): implement relay receiving and deduplication"
```

---

### Task 4: Geographic Forwarding Logic

**Files:**
- Modify: `lib/message_handler.dart`
- Modify: `lib/data/isar_service.dart` (Add findActiveNeighbors)

- [ ] **Step 1: Add neighbor discovery to IsarService**
```dart
Future<List<FoundDevice>> findActiveNeighbors(int excludeId) async {
  final sixtySecondsAgo = DateTime.now().subtract(const Duration(seconds: 60));
  return await db.foundDevices
      .where()
      .lastSeenGreaterThan(sixtySecondsAgo)
      .filter()
      .not().stableIdEqualTo(excludeId)
      .findAll();
}
```

- [ ] **Step 2: Implement _forwardRelayPayload in MessageHandler**
```dart
static Future<void> _forwardRelayPayload(Uint8List payload, int targetId, int excludeId) async {
  final isar = IsarService();
  final neighbors = await isar.findActiveNeighbors(excludeId);
  if (neighbors.isEmpty) return;

  final targetDevice = await isar.db.foundDevices.where().stableIdEqualTo(targetId).findFirst();
  final List<FoundDevice> selected;

  if (targetDevice != null && targetDevice.latitude != null) {
    // Scenario A: Directed Beam
    neighbors.sort((a, b) => GeoUtils.calculateDistance(a.latitude!, a.longitude!, targetDevice.latitude!, targetDevice.longitude!)
        .compareTo(GeoUtils.calculateDistance(b.latitude!, b.longitude!, targetDevice.latitude!, targetDevice.longitude!)));
    selected = neighbors.take(3).toList();
  } else {
    // Scenario B: Starburst
    // ... complex selection logic using 120 deg offsets ...
    selected = neighbors.take(3).toList(); // Fallback to first 3 for now
  }

  for (final neighbor in selected) {
    _pushToNeighbor(neighbor, payload);
  }
}
```

- [ ] **Step 3: Commit**
```bash
git add lib/message_handler.dart lib/data/isar_service.dart
git commit -m "feat(mesh): implement geographic forwarding logic"
```

---

### Task 5: Origin Sender Updates

**Files:**
- Modify: `lib/message_handler.dart`

- [ ] **Step 1: Wrap outgoing messages in Relay Header**
Update `getEncryptedPayload` or similar to prepend the 7-byte relay header before transmission.

- [ ] **Step 2: Commit**
```bash
git add lib/message_handler.dart
git commit -m "feat(mesh): wrap outgoing messages in relay headers"
```

---

### Task 6: Final Verification

- [ ] **Step 1: Analysis check**
Run: `dart analyze`
Expected: No errors.

- [ ] **Step 2: Push to Github**
Only when user confirms.
