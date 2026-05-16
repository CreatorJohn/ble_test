# Mesh Packet Refactoring Plan

**Goal:** Refactor the raw byte manipulation and procedural parsing in `MessageHandler` into a clean, object-oriented class hierarchy. This will improve code readability, testability, and future maintainability.

### 1. New File: `lib/data/mesh_packet.dart`
Create a base `MeshPacket` class and subclasses for every protocol type defined in `PROTOCOL.md`. We use the name "Packet" to avoid conflict with the existing Isar `Message` entity.

#### Base Class
```dart
abstract class MeshPacket {
  int get type;
  Uint8List toBytes();

  // Factory constructor to parse raw bytes into the correct subclass
  static MeshPacket parse(Uint8List data) { ... }
}
```

#### Subclasses
- **`TextPacket` (0x01)**: Holds `String text`.
- **`ImagePacket` (0x02)**: Holds `Uint8List imageData`.
- **`ProfilePicPacket` (0x03)**: Holds `Uint8List imageData`.
- **`RelayPacket` (0x04)**: Holds `targetId`, `originId`, `msgId`, `ttl`, `encryptedPayload`.
- **`AckPacket` (0x05)**: Holds `targetId`, `originId`, `msgId`.
- **`IdentityPacket` (0x06)**: Holds `stableId`, `profileHash`, `publicKey`, `name`.
- **`SyncDonePacket` (0x07)**: Empty payload.
- **`RequestProfilePicPacket` (0x08)**: Empty payload.

*Each subclass will implement `toBytes()` and a `fromBytes(Uint8List)` factory/constructor.*

### 2. Update `lib/message_handler.dart`
- Replace the constants (`typeText`, `typeAck`, etc.) with references to `MeshPacket` types.
- In `initialize()`, replace the large `if/else` block that parses bytes manually with:
  ```dart
  final packet = MeshPacket.parse(fullData);
  if (packet is RelayPacket) {
      ...
  } else if (packet is IdentityPacket) {
      ...
  }
  // etc.
  ```
- Update `_pushAck`, `getRelayWrappedPayload`, and `streamOurProfilePic` to construct the relevant `MeshPacket` subclass and call `.toBytes()` instead of using `ByteData.view` manually.

### 3. Benefits
- **Type Safety**: Parsing errors are caught early in the factory method.
- **Single Source of Truth**: The byte structure of each packet type is isolated within its own class, matching `PROTOCOL.md` exactly.
- **Clean `MessageHandler`**: The handler can focus purely on business logic (routing, database updates) instead of byte manipulation.

### Verification
- Ensure `dart analyze` passes with 0 errors.
- Ensure the app logic remains 100% functionally identical.