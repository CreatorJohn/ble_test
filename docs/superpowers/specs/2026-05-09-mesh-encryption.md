# Design Spec: Mesh End-to-End Encryption (E2EE)

## Problem
In a mesh network, messages may be relayed by intermediate "stranger" nodes. Without encryption, these nodes can read the content of any message they relay.

## Proposed Solution: Hybrid Cryptography
We will implement a Hybrid Encryption system using the `cryptography` package, combining asymmetric (X25519) and symmetric (ChaCha20-Poly1305) algorithms.

### 1. Key Management
*   **Identity Keys**: Every device generates a permanent **X25519 Key Pair** (32-byte Public, 32-byte Private) on first launch.
*   **Storage**: The Private Key is stored in a secure location (e.g., `flutter_secure_storage` or a protected Isar field). The Public Key is broadcasted via GATT.

### 2. Handshake (Exchange)
*   **New Characteristic**: A read-only "Public Key" characteristic (32 bytes) is added to the `BLEAdvertiser` service.
*   **Automatic Sync**: When a device is discovered, the background service connects and reads the Public Key, saving it in the `FoundDevice` record.

### 3. Messaging Flow
*   **Sender**:
    1.  Lookup the recipient's **Public Key** in the database.
    2.  Generate a temporary **Shared Secret** using `My Private Key + Their Public Key`.
    3.  Encrypt the message (and a unique 12-byte Nonce) using **ChaCha20-Poly1305**.
    4.  Send the `Nonce + Ciphertext` through the existing GATT chunking layer.
*   **Receiver**:
    1.  Identify the sender via their **Stable ID**.
    2.  Lookup the sender's **Public Key** in the database.
    3.  Generate the **same Shared Secret** using `My Private Key + Their Public Key`.
    4.  Decrypt the ciphertext using the Secret and the provided Nonce.

## Technical Components
*   **Algorithm**: X25519 (Key Exchange) + ChaCha20-Poly1305 (Encryption/Authentication).
*   **Overhead**: 12 bytes (Nonce) + 16 bytes (MAC tag) = 28 bytes per message.
*   **Performance**: <1ms for encryption; bottleneck remains the BLE airtime.

## Success Criteria
1.  Intermediate nodes can relay messages but cannot read the content.
2.  Messages are authenticated (receiver knows for sure who sent it and that it wasn't tampered with).
3.  Encryption survives app restarts and device reboots.
