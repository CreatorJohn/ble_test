# Mesh End-to-End Encryption (E2EE) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement End-to-End Encryption for all mesh messages using X25519 for key exchange and ChaCha20-Poly1305 for data encryption.

**Architecture:** 
1. **Key Management**: `ProfileManager` will generate and persist a permanent X25519 key pair. The private key will be stored securely.
2. **Key Exchange**: A new `publicKeyCharUuid` characteristic will be added to the BLE service. The background service will automatically fetch and store public keys for all discovered devices in the `FoundDevice` model.
3. **Encryption Layer**: `MessageHandler` will be refactored to perform a Diffie-Hellman key exchange to derive a shared secret. All message payloads will be encrypted (with a unique nonce) before being passed to the `ChunkedTransferManager`.

**Tech Stack:** `cryptography` package, `isar`, `shared_preferences`.

---

### Task 1: Dependencies and Key Generation

**Files:**
- Modify: `pubspec.yaml`
- Modify: `lib/profile_manager.dart`
- Modify: `lib/data/found_device.dart`

- [ ] **Step 1: Add cryptography package**
Run: `flutter pub add cryptography`

- [ ] **Step 2: Update FoundDevice model for Public Keys**
Add `publicKey` field to `FoundDevice`.

```dart
// lib/data/found_device.dart
@Collection()
class FoundDevice {
  // ... existing fields
  List<int>? publicKey; // 32-byte X25519 public key
}
```

- [ ] **Step 3: Implement Secure Key Generation in ProfileManager**
Generate and persist the X25519 key pair.

```dart
// lib/profile_manager.dart
import 'package:cryptography/cryptography.dart';

static const String _privateKeyKey = 'secure_private_key_v1';
static const String _publicKeyKey = 'public_key_v1';

static Future<SimpleKeyPair> getKeyPair() async {
  final algorithm = X25519();
  final prefs = await SharedPreferences.getInstance();
  final privBase64 = prefs.getString(_privateKeyKey);
  
  if (privBase64 == null) {
    final keyPair = await algorithm.newKeyPair();
    final privBytes = await keyPair.extractPrivateKeyBytes();
    final pubKey = await keyPair.extractPublicKey();
    
    await prefs.setString(_privateKeyKey, base64Encode(privBytes));
    await prefs.setString(_publicKeyKey, base64Encode(pubKey.bytes));
    return keyPair;
  }
  
  return SimpleKeyPairData(
    base64Decode(privBase64),
    publicKey: SimplePublicKey(base64Decode(prefs.getString(_publicKeyKey)!), type: KeyPairType.x25519),
    type: KeyPairType.x25519,
  );
}
```

- [ ] **Step 4: Commit**
Commit changes with message "feat: implement X25519 identity key generation and storage".

---

### Task 2: GATT Key Exchange

**Files:**
- Modify: `lib/ble_advertiser.dart`
- Modify: `lib/background_service.dart`

- [ ] **Step 1: Add Public Key characteristic to BLEAdvertiser**
Add `publicKeyCharUuid` and expose the local public key.

- [ ] **Step 2: Update background service to fetch Public Keys**
In `_fetchFullMetadata`, add logic to read the `publicKeyCharUuid` and save it to the `FoundDevice` record.

- [ ] **Step 3: Commit**
Commit changes with message "feat: expose and sync X25519 public keys via GATT".

---

### Task 3: Encryption Logic in MessageHandler

**Files:**
- Modify: `lib/message_handler.dart`

- [ ] **Step 1: Implement Hybrid Encryption Flow**
Refactor `handleOutgoingMessage` to encrypt data and `handleIncomingMessage` (via `onPayloadComplete`) to decrypt.

```dart
// lib/message_handler.dart logic snippet
static final cipher = Chacha20.poly1305Aead();

static Future<Uint8List> encrypt(Uint8List cleartext, Uint8List theirPubKey) async {
  final myKeyPair = await ProfileManager.getKeyPair();
  final sharedSecret = await X25519().sharedSecretKey(
    keyPair: myKeyPair,
    remotePublicKey: SimplePublicKey(theirPubKey, type: KeyPairType.x25519),
  );
  final secretKeyBytes = await sharedSecret.extractBytes();
  
  final secretKey = SecretKey(secretKeyBytes);
  final secretBox = await cipher.encrypt(cleartext, secretKey: secretKey);
  
  // Format: [12-byte Nonce] + [Ciphertext]
  final result = Uint8List(12 + secretBox.cipherText.length + 16);
  result.setRange(0, 12, secretBox.nonce);
  result.setRange(12, 12 + secretBox.cipherText.length, secretBox.cipherText);
  result.setRange(12 + secretBox.cipherText.length, result.length, secretBox.mac.bytes);
  return result;
}
```

- [ ] **Step 2: Commit**
Commit changes with message "feat: implement end-to-end encryption for mesh messages".
