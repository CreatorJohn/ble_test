# Delivery ACKs (Breadcrumb Reverse Path Forwarding) Design Specification

## 1. Overview
To provide WhatsApp-like delivery receipts in the offline BLE mesh network, we are introducing a "Delivery ACK" mechanism. Because flooding the network with ACKs would consume too much bandwidth, we use a stateless Reverse Path Forwarding (Breadcrumb) approach. When a message travels forward through relay nodes, those nodes remember who handed them the message. When the destination receives the message, an ACK travels back exactly along that known path.

## 2. Packet Structure: The ACK Packet
A new message type `typeAck = 0x05` is introduced. ACKs are small, unencrypted control packets written directly to a neighbor's GATT server.

**ACK Payload Structure (10 bytes):**
```
[Byte 0: 0x05 (typeAck)]
[Bytes 1-4: TargetStableId (Uint32, Big Endian) - The upstream node we are returning the ACK to]
[Bytes 5-8: OriginStableId (Uint32, Big Endian) - The original creator of the message]
[Byte 9: MessageId (Uint8, 1-255)]
```

## 3. The Routing Table (Breadcrumbs)
Relay nodes must maintain an in-memory map to route ACKs upstream.

*   **State Location:** `MessageHandler._pendingAcks`
*   **Cache Key:** `(OriginStableId << 8) | MessageId` (Unique per message across the network).
*   **Value:** `PendingAck` object containing:
    *   `upstreamNodeId`: The `directSenderId` that handed us the `typeRelay` message.
    *   `timestamp`: When the entry was created.
*   **Cleanup:** A periodic timer sweeps the table and removes entries older than 50 minutes (to safely cover maximum TTL delays).

## 4. Routing Logic

### Phase 1: Dropping Breadcrumbs (Forward Path)
When `MessageHandler` processes an incoming `typeRelay` (0x04) message and determines it must forward it (Target != Me):
1.  Before calling `_forwardRelayPayload`, it records the breadcrumb: `_pendingAcks[cacheKey] = PendingAck(directSenderId, DateTime.now())`.

### Phase 2: Generating the ACK (Terminal Node)
When a node receives a `typeRelay` message where `Target == myId`:
1.  It decrypts and saves the payload.
2.  It immediately constructs a 10-byte `typeAck` packet.
    *   `TargetStableId` = The `directSenderId` (the neighbor who handed it the packet).
    *   `OriginStableId` = Parsed from the relay header.
    *   `MessageId` = Parsed from the relay header.
3.  It connects to `directSenderId` and writes the ACK packet to its `messageCharUuid` (`withoutResponse: false`).

### Phase 3: Relaying the ACK (Reverse Path)
When a node's GATT server (`ble_advertiser.dart` or `ChunkedTransferManager`) receives a write starting with `0x05`:
1.  Parse `TargetStableId`, `OriginStableId`, and `MessageId`.
2.  **Is Target == Me?** If no, drop it. (ACKs are point-to-point, not flooded).
3.  **Is Origin == Me?** If yes, we are the original sender!
    *   Find the message in the database using `MessageId` (and our stable ID).
    *   Update `isDelivered = true`.
4.  **Otherwise (We are a Relay):**
    *   Look up `cacheKey` in `_pendingAcks`.
    *   If found:
        *   Construct a new ACK packet where `TargetStableId` = `PendingAck.upstreamNodeId`.
        *   Connect and write the ACK to `upstreamNodeId`.
        *   **Delete** the entry from `_pendingAcks`. (First ACK wins; subsequent ACKs from other branches for this message are ignored).
    *   If not found: Drop it. (We already processed an ACK for this, or it timed out).

## 5. Database & UI Updates
*   **Schema (`Message`):**
    *   Add `bool isDelivered = false;`
    *   Add `int? messageId;` (Populated when sending, so the origin knows which message to update).
*   **UI (`DiscoveryScreen` / Chat View):**
    *   When displaying sent messages, show a single checkmark (✓) if `!isDelivered`, and a double checkmark (✓✓) if `isDelivered == true`.
