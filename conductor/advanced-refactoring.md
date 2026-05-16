# Advanced Mesh Refactoring Plan (Polymorphism)

**Goal:** Replace complex conditional logic with polymorphic patterns (Strategy and Command) to make the mesh engine modular and extensible.

### 1. MeshRouter Strategy Pattern
Move neighbor selection logic out of `MessageHandler.pushQueuedDataToPeer`.

#### New File: `lib/data/mesh_router.dart`
- **`abstract class MeshRouter`**:
  - `List<int> selectNeighbors(RelayTask task, List<FoundDevice> availableNeighbors, int myId);`
- **`class DirectedBeamRouter`**: Implements GPS-based distance sorting.
- **`class StarburstRouter`**: Implements the fallback broadcast logic.

#### Update `MessageHandler`
- In `pushQueuedDataToPeer`, use a `MeshRouter` instance to decide which `peerStableId` should receive which `RelayTask`.

---

### 2. Packet Handler (Command Pattern)
Move business logic out of `MessageHandler.initialize`.

#### Update `lib/data/mesh_packet.dart`
- **`PacketContext`**: A new class to hold state needed for processing (Isar, LocalID, Logger, etc.).
- **`abstract class MeshPacket`**:
  - Add `Future<void> handle(PacketContext context);`
- **Subclasses**:
  - `RelayPacket.handle(...)`: Enqueues the next hop.
  - `AckPacket.handle(...)`: Updates message status and enqueues fan-back.
  - `IdentityPacket.handle(...)`: Updates/Creates device record.
  - ...and so on for all 8 types.

#### Update `MessageHandler.initialize()`
- The core loop becomes:
  ```dart
  final packet = MeshPacket.parse(fullData);
  await packet.handle(PacketContext(directSenderId, isar, ...));
  ```

---

### Verification
- `dart analyze` reports 0 errors.
- Confirm all 8 packet types still behave exactly as before.
