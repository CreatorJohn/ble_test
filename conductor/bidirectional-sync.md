# Bidirectional Sync & Coordinated Disconnect

**Goal:** Improve mesh efficiency by allowing both devices to exchange all pending data (metadata, messages, ACKs) in a single connection session.

### 1. Protocol Constants (MessageHandler)
- `static const int typeIdentity = 0x06;` // [Type(1), ID(4), Hash(6), PubKey(32), Name(...)]
- `static const int typeSyncDone = 0x07;` // [Type(1)]
- `static const int typeRequestProfilePic = 0x08;` // [Type(1)]

### 2. Device A (Central) - The Initiator
- **Connect** to Device B.
- **Phase A: Update Knowledge of B**
  - Read B's Profile Hash.
  - If Pic is missing or Hash mismatched: Read Pic Characteristic (Header + Stream).
  - Read Name/PubKey if missing.
- **Phase B: Identity & Outbound Queue**
  - Enable notifications on `messageChar`.
  - Send `typeIdentity (0x06)` to B.
  - Fetch all unsent messages/ACKs for B and push them via `messageChar`.
- **Phase C: Wait for Inbound**
  - Create `Completer<void> syncDoneCompleter`.
  - Listen for `v[0] == typeRequestProfilePic (0x08)`: Stream our Pic to B.
  - Listen for `v[0] == typeSyncDone (0x07)`: Complete the completer.
- **Phase D: Disconnect**
  - `await syncDoneCompleter.future.timeout(const Duration(seconds: 20))`.
  - Disconnect in `finally` block.

### 3. Device B (Peripheral) - The Responder
- **Intercept Identity (0x06)**
  - Update/Create B's record of A (ID, Hash, PubKey, Name).
  - If A's Pic is missing or Hash mismatched: Notify `typeRequestProfilePic (0x08)`.
  - Wait for A to stream Pic (handled by existing `typeProfilePic` logic).
- **Push Inbound Queue**
  - Once Identity is processed (and Pic received if requested):
  - Fetch all unsent messages/ACKs for A and push them via Notifications.
  - Finally, Notify `typeSyncDone (0x07)`.

### Verification
- Check logs for "Identity sent", "Queue pushed", "SyncDone received".
- Ensure no data is lost when both sides have messages for each other.