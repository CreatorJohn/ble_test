# BLE Mesh Protocol Specification (v1.0)

This document defines the byte-level protocol used by the BLE Mesh test app for communication, relaying, and synchronization.

## MTU & Chunking
All messages larger than the negotiated MTU (minus 10 bytes overhead) are fragmented using the `ChunkedTransferManager`.

**Chunk Header (4 bytes):**
- `[0]` : Magic Byte (0xBB)
- `[1]` : Message ID (8-bit)
- `[2]` : Chunk Index (8-bit)
- `[3]` : Total Chunks (8-bit)
- `[4...]` : Data

---

## Packet Types

### 0x01: Text Message (Encrypted)
Used for direct peer-to-peer text communication.
- `[0]` : Type (0x01)
- `[1...]` : UTF-8 encoded string

### 0x02: Image (Encrypted)
Used for sending photos.
- `[0]` : Type (0x02)
- `[1...]` : Raw image bytes (PNG/JPG)

### 0x03: Profile Picture (Unencrypted)
Used for the initial profile picture exchange.
- `[0]` : Type (0x03)
- `[1...]` : Raw image bytes

### 0x04: Relay Wrapper (Unencrypted Header)
The primary transport mechanism for multi-hop messages.
- `[0]` : Type (0x04)
- `[1-4]` : **Target ID** (32-bit Big Endian) - Destination node
- `[5-8]` : **Origin ID** (32-bit Big Endian) - Original sender node
- `[9]` : **Message ID** (8-bit) - Sequence number for deduplication
- `[10]` : **TTL** (8-bit) - Time-To-Live (Max 10 hops)
- `[11...]` : **Encrypted Payload** (Chacha20-Poly1305)

### 0x05: Delivery ACK (Unencrypted)
Sent back along the reverse path to confirm delivery.
- `[0]` : Type (0x05)
- `[1-4]` : **Target ID** (32-bit Big Endian) - Next hop in reverse path
- `[5-8]` : **Origin ID** (32-bit Big Endian) - Person who sent the original message
- `[9]` : **Message ID** (8-bit) - Matches original message ID

### 0x06: Identity Message (Unencrypted)
Sent by Central to Peripheral immediately upon connection.
- `[0]` : Type (0x06)
- `[1-4]` : **Stable ID** (32-bit Big Endian)
- `[5-10]` : **Profile Hash** (6 bytes) - First 6 bytes of image SHA-256
- `[11-42]` : **Public Key** (32 bytes) - X25519 public key
- `[43...]` : **Display Name** (UTF-8)

### 0x07: SyncDone (Unencrypted)
Signaled by Peripheral to Central to indicate queue is empty.
- `[0]` : Type (0x07)

### 0x08: RequestProfilePic (Unencrypted)
Requested by Peripheral if the incoming Identity Hash is mismatched.
- `[0]` : Type (0x08)

---

## 7-Step Sync Handshake
1. **Connect**: Device A connects to Device B.
2. **Metadata Pull**: Device A reads B's GATT characteristics (Hash, Name, PubKey, Pic).
3. **Identity Push**: Device A writes `0x06 (Identity)` to Device B.
4. **Outbound Push**: Device A writes its `RelayTasks` for Device B.
5. **Conditional Pic**: If B needs A's Pic, B notifies `0x08 (Request)`. A streams `0x03 (Pic)`.
6. **Inbound Piggyback**: Device B notifies its `RelayTasks` for Device A.
7. **SyncDone**: Device B notifies `0x07 (Done)`. Device A disconnects.
