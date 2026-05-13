# Design Spec: Dynamic MTU Negotiation and Reliable Transfers

## Problem
The current messaging and profile picture push mechanisms rely on `writeWithoutResponse: true` with a hardcoded `maxChunkSize` of 200 bytes and an arbitrary 10ms delay between chunks. This can easily overwhelm the OS Bluetooth buffer, leading to silent packet loss and failed reassembly, especially on devices with smaller MTUs or aggressive throttling.

## Proposed Solution
Transition from a fast but unreliable "fire and forget" model to a highly reliable, adaptive model using Maximum Transmission Unit (MTU) negotiation and Acknowledgment (ACK) based writes (`writeWithoutResponse: false`).

### 1. MTU Negotiation (`lib/screens/discovery.dart` & `lib/message_handler.dart`)
Whenever we connect to a device to push data (either a chat message in `discovery.dart` or a profile picture in `message_handler.dart`):
*   After calling `connect()`, if the platform is Android, execute `await bleDevice.requestMtu(517);`. (iOS negotiates automatically).
*   Wait for the negotiated MTU: `final mtu = await bleDevice.mtu.first;`.

### 2. Adaptive Chunk Sizing
*   The effective payload size per chunk is `MTU - 3 (ATT Header) - 4 (Our Custom Header)`. To be safe, we will use a chunk size of `mtu - 10`.
*   Pass this calculated size to `ChunkedTransferManager.generateChunks(..., maxChunkSize: maxChunkSize)`.
*   If `mtu - 10` is less than 20, fallback to a safe minimum of 20 bytes.

### 3. Reliable Writes
*   Change the chunk writing loop to use `withoutResponse: false`:
    `await messageChar.write(chunk, withoutResponse: false);`
*   Remove the `Future.delayed(10ms)`. Waiting for the `write` future to complete acts as a hardware-level ACK, ensuring the peer's buffer is ready for the next chunk.

## Success Criteria
1.  0% packet loss during transmission, ensuring successful chunk reassembly on the receiving end.
2.  High-end devices negotiate a 512-byte payload and transfer data rapidly in fewer chunks.
3.  Lower-end devices gracefully fall back to smaller chunks without crashing or dropping data.
