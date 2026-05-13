# MTU Optimization and Reliable Transfer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement dynamic MTU negotiation and adaptive chunk sizing for 100% reliable BLE transfers.

**Architecture:** Use `requestMtu(517)` and `bleDevice.mtu` stream to determine optimal packet size. Switch to `withoutResponse: false` (Write with Response) to ensure sequential delivery without buffer overflows.

**Tech Stack:** 
- `flutter_blue_plus` (MTU, Writes)
- `ChunkedTransferManager` (Adaptive generateChunks)

---

### Task 1: Optimization in Discovery Screen (Chat Messages)

**Files:**
- Modify: `lib/screens/discovery.dart`

- [ ] **Step 1: Update _performSendMessage with MTU negotiation**

```dart
// lib/screens/discovery.dart
// Inside _performSendMessage, after bleDevice.connect()

      await bleDevice.connect(
        timeout: const Duration(seconds: 15),
        autoConnect: false,
        license: License.free,
      );

      // --- MTU Negotiation Start ---
      if (Platform.isAndroid) {
        try {
          await bleDevice.requestMtu(517);
        } catch (e) {
          print('MTU Request failed: $e');
        }
      }
      
      final mtu = await bleDevice.mtu.first.timeout(const Duration(seconds: 3), onTimeout: () => 23);
      final maxChunkSize = (mtu - 10).clamp(20, 500);
      print('Negotiated MTU: $mtu, Chunk size: $maxChunkSize');
      // --- MTU Negotiation End ---
```

- [ ] **Step 2: Update chunk generation and reliable write loop**

```dart
// lib/screens/discovery.dart
// Inside _performSendMessage, replace chunk loop

          final chunks = ChunkedTransferManager.generateChunks(
            encryptedPayload,
            messageId,
            maxChunkSize: maxChunkSize, // Pass calculated size
          );

          int sent = 0;
          for (final chunk in chunks) {
            await messageChar.write(chunk, withoutResponse: false); // Changed to false
            sent++;
            // Removed Future.delayed(10ms)
          }
```

- [ ] **Step 3: Commit**

```bash
git add lib/screens/discovery.dart
git commit -m "feat(messaging): implement adaptive chunk sizing and reliable writes in Discovery"
```

---

### Task 2: Optimization in MessageHandler (Profile Picture Push)

**Files:**
- Modify: `lib/message_handler.dart`

- [ ] **Step 1: Update pushProfilePicture with MTU negotiation**

```dart
// lib/message_handler.dart
// Inside pushProfilePicture, after device.connect()

    await device.connect(timeout: const Duration(seconds: 15), autoConnect: false, license: License.free);
    
    // --- MTU Negotiation Start ---
    if (Platform.isAndroid) {
      try {
        await device.requestMtu(517);
      } catch (e) {
        _log.warning('MTU Request failed: $e');
      }
    }
    
    final mtu = await device.mtu.first.timeout(const Duration(seconds: 3), onTimeout: () => 23);
    final maxChunkSize = (mtu - 10).clamp(20, 500);
    // --- MTU Negotiation End ---
```

- [ ] **Step 2: Update chunk generation and reliable write loop**

```dart
// lib/message_handler.dart
// Inside pushProfilePicture, replace chunk loop

      final chunks = ChunkedTransferManager.generateChunks(
        encrypted, 
        Random().nextInt(256),
        maxChunkSize: maxChunkSize, // Pass calculated size
      );
      
      for (final chunk in chunks) {
        await messageChar.write(chunk, withoutResponse: false); // Changed to false
      }
```

- [ ] **Step 3: Commit**

```bash
git add lib/message_handler.dart
git commit -m "feat(profile): implement adaptive chunk sizing and reliable writes for profile pic sync"
```

---

### Task 3: Final Verification

**Files:**
- [ ] **Step 1: Final analysis check**

Run: `dart analyze`
Expected: No errors.

- [ ] **Step 2: Final commit**

```bash
git commit -m "chore: complete MTU optimization and reliability hardening"
```
