# Multi-Hop Relaying (Mesh Network) Design Specification

## 1. Overview
This feature implements true multi-hop relaying for the BLE messaging application. It allows messages to travel beyond the immediate BLE range of the sender by utilizing intermediate devices as relay nodes. The system uses a "Directed Flood" approach, prioritizing Geographic Routing and Angular Dispersion, combined with Time-To-Live (TTL) and Message ID caching to prevent infinite routing loops and network congestion.

## 2. Packet Structure: The Relay Wrapper
A new message type is introduced to distinguish relay-wrapped payloads from direct payloads.

*   `static const int typeRelay = 0x04;`

The `typeRelay` header is applied at the **Application Layer** *before* the payload is passed to the `ChunkedTransferManager`. This ensures the routing data stays perfectly synchronized with the payload regardless of how many BLE chunks it is split into over the air.

**Relay Payload Structure:**
```
[Byte 0: 0x04 (typeRelay)]
[Bytes 1-4: TargetStableId (Uint32, Big Endian)]
[Byte 5: MessageId (Uint8, 1-255)]
[Byte 6: TTL (Uint8)]
[Bytes 7+: Encrypted Payload (e.g., typeText or typeImage)]
```
*Note: Because the 7-byte header is unencrypted, any intermediate node can read the routing data without needing the target's private key.*

## 3. Loop Prevention: TTL + Cache
To prevent messages from bouncing infinitely between nodes, two mechanisms work together:

1.  **Time-To-Live (TTL):** Every time a node relays a message, it decrements the TTL by 1. If TTL hits 0, the message is dropped.
2.  **Message ID Cache:** Devices remember the `MessageId` of every relay payload they process. If a duplicate arrives via a different path, it is instantly dropped.

### Cache Cleanup Math
To prevent memory leaks while ensuring safety, the cache is periodically cleaned. The lifetime of a cache entry is strictly tied to the maximum possible network traversal time.
*   `Cycle Time` = `scanDuration (20s) + waitDuration (80s) = 100s`
*   `Formula:` Cache Lifetime = (Initial TTL * 100) + 20 seconds (buffer).
A periodic timer in `MessageHandler` sweeps `_seenRelayMessageIds` and removes entries older than this calculated lifetime.

## 4. Receiving & Forwarding Logic (`MessageHandler`)
When `ChunkedTransferManager` fully reassembles a payload starting with `0x04`:

1.  Parse `TargetStableId`, `MessageId`, and `TTL`.
2.  Check `_seenRelayMessageIds`. If `MessageId` exists, **DROP**.
3.  Add `MessageId` to `_seenRelayMessageIds` with `DateTime.now()`.
4.  **Is Target == myStableId?**
    *   **YES:** We are the destination. Strip the 7-byte header and pass the `Encrypted Payload` back into `_decryptMessage`. Do not forward.
    *   **NO:** We are a relay.
        *   Decrement TTL.
        *   If `TTL == 0`, **DROP**.
        *   If `TTL > 0`, call `forwardRelayPayload(modified_payload, targetStableId, senderStableId)`.

## 5. Transmission Strategy: Geographic Routing
When `forwardRelayPayload` is invoked, the device uses a "Push" model but restricts connections to a maximum of **3 neighbors** to prevent bottlenecks. The selection of these 3 neighbors depends on the availability of the target's location data.

**Scenario A: Target Location Known (Directed Beam Routing)**
If the local `IsarService` has a valid `latitude/longitude` for `TargetStableId`:
1.  Calculate the geographic distance from each active neighbor (seen in the last 60s) to the *target's* location using the Haversine formula.
2.  Filter out the `senderStableId` to prevent immediate bounce-backs.
3.  Select the top 3 neighbors with the *shortest* distance to the target.
4.  Connect and push the payload to those 3 neighbors.

**Scenario B: Target Location Unknown (Starburst Routing)**
If the target's location is unknown, the goal is to maximize outward coverage using **Angular Dispersion**:
1.  Filter active neighbors (excluding `senderStableId`).
2.  Calculate the distance and compass bearing from *our* location to each neighbor.
3.  **Node 1:** Select the neighbor furthest away. (Let's call its bearing X°).
4.  **Node 2:** Select the furthest neighbor whose bearing is closest to X° + 120°.
5.  **Node 3:** Select the furthest neighbor whose bearing is closest to X° - 120°.
6.  Connect and push the payload to these 3 neighbors, guaranteeing the message travels in multiple, non-overlapping directions.

## 6. Origin Sender Modifications
When a user sends a message from the UI:
1.  Generate the encrypted payload.
2.  Generate a random `MessageId` (1-255).
3.  Set `Initial TTL` (e.g., 10).
4.  Prepend the `typeRelay` header to create the full `RelayPayload`.
5.  Pass this payload into the Geographic Routing logic (Scenario A or B) to push to the first set of hops.
