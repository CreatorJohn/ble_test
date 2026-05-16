# Remove Non-Advertising Support

**Goal:** Strip out the identity linking and placeholder logic that allowed non-advertising devices (like Chromebooks) to participate in the mesh. The app will now only communicate with nodes actively discovered via BLE scanning.

### 1. MessageHandler Updates
- **Location:** `lib/message_handler.dart`
- **Actions:**
  - Remove the `_linkIdentity` function completely.
  - In `initialize()`, remove the block handling `ttl == 10 || ttl == 5` that calls `_linkIdentity`.
  - In `initialize()`, under the direct message handling, remove the `_linkIdentity` call.

### 2. BLEAdvertiser Updates
- **Location:** `lib/ble_advertiser.dart`
- **Actions:**
  - In `setWriteRequestCallback`, when handling an incoming message from a device not found in Isar by `remoteId`:
    - Remove the logic that generates a temporary `stableId` and saves a placeholder `FoundDevice` named `"Connecting Device..."`.
    - Instead, log a warning and return a failed `WriteRequestResult(status: 1)` or just ignore it.

### 3. BackgroundService Updates
- **Location:** `lib/background_service.dart`
- **Actions:**
  - In `startSafeScan()`, remove `.or().nameEqualTo("Connecting Device...")` from the Isar query that finds devices needing sync.
  - In `_fetchFullMetadata()`, remove the check for `dev.name == "Connecting Device..."` when deciding whether to read the name characteristic.

### Verification
- Run `dart analyze` to ensure no orphaned variables or syntax errors.