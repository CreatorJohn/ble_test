# Design Spec: Request-Based Profile Picture Sync & Optimization

## Problem
The current implementation relies on a standard GATT `read` operation to fetch profile pictures. Since profile pictures are ~20KB (256x256 PNGs), a single GATT read is highly unreliable, frequently times out, or truncates data.

## Proposed Solution: Request & Push via Chunked Transfer
We will transition to an asynchronous "Request & Push" model, reusing our robust `ChunkedTransferManager`. We will also compress profile pictures from PNG to JPG to drastically reduce the payload size.

### 1. Image Format Optimization (`lib/profile_manager.dart`)
*   Update `_processImage` to encode the cropped 256x256 image as a **JPG** (quality: 70-80) instead of a PNG.
*   Update the internal storage filename from `profile_pic.png` to `profile_pic.jpg`.

### 2. Advertising Profile Sync Requests (`lib/ble_advertiser.dart`)
*   Modify `profilePicCharUuid` to include the `write` property and `writeable` permission.
*   In `setWriteRequestCallback`, if `profilePicCharUuid` receives a write request (e.g., `0x01`), trigger a background task:
    1.  Read local profile picture bytes.
    2.  Find the requester's `stableId` using the incoming connection's MAC (`deviceId`).
    3.  Call a new method `MessageHandler.pushProfilePicture(requesterStableId, deviceId, imageBytes)`.

### 3. Pushing the Picture (`lib/message_handler.dart`)
*   Define a new message type constant: `typeProfilePic = 0x03`.
*   Implement `pushProfilePicture()`:
    1.  Connect to the requester via `BluetoothDevice.fromId(deviceId)`.
    2.  Encrypt the image bytes prepended with `typeProfilePic`.
    3.  Generate chunks using `ChunkedTransferManager`.
    4.  Write chunks to the requester's `messageCharUuid`.
    5.  Disconnect.

### 4. Receiving and Saving (`lib/message_handler.dart`)
*   In `initialize()`, when a payload is completed and decrypted:
    *   If `type == typeProfilePic`, locate the `FoundDevice` via `senderStableId`.
    *   Update `profilePicture` with the payload and set `lastPictureSync = DateTime.now()`.
    *   Save to `IsarService`.

### 5. Requesting the Sync (`lib/background_service.dart`)
*   In `_fetchFullMetadata()`, instead of `await picChar.read()`, if the hash is outdated:
    *   Execute `await picChar.write([0x01], withoutResponse: true)`.
    *   Log: "Requested profile picture sync from $stableId".

## Success Criteria
1.  Profile pictures successfully transfer between devices without read timeouts.
2.  Storage and BLE bandwidth are optimized via JPG compression.
3.  The mesh network handles the asynchronous push natively through the encrypted chunked pipeline.
