# Hardening & Maintenance Plan

**Goal:** Implement database cleanup routines, ensure inbound message ACKs are robust, and gracefully handle Bluetooth "off" states to make the app production-ready.

### 1. Database Pruning
- **Location:** `lib/data/isar_service.dart` and `lib/background_service.dart`
- **Implementation:**
  - Add `Future<void> pruneDatabase()` to `IsarService`.
  - Calculate `oneMonthAgo = DateTime.now().subtract(const Duration(days: 30))`.
  - Fetch devices where `lastSeen < oneMonthAgo`.
  - For those specific devices, find all `Message`s where `timestamp < oneMonthAgo` and the device is either sender or receiver.
  - Delete those specific messages.
  - Call `pruneDatabase()` once during `BackgroundService` initialization.

### 2. Mesh "Inbound" Message Acknowledgement
- **Location:** `lib/message_handler.dart`
- **Implementation:**
  - The logic for `_pushAck` already exists inside `MessageHandler.initialize()` when receiving `typeRelay` and `targetId == myId`.
  - To fulfill the requirement and ensure it doesn't fail silently or get skipped, I will review the `_pushAck` call. I will add error handling and ensure the ACK is pushed reliably to the `directSenderId`.
  - I will verify if `await` is appropriate to guarantee the ACK goes out before the main payload is processed, or if it should run concurrently.

### 3. Handle Bluetooth "Off" State Gracefully
- **Location:** `lib/background_service.dart`, `lib/providers/system_health.dart`, `lib/components/system_health_card.dart`
- **Implementation:**
  - **Background Service:** Update `startSafeScan()`. Instead of waiting 15 seconds for Bluetooth to turn on (which causes errors/blocking), immediately check `FlutterBluePlus.adapterStateNow`. If it's not `on`, simply `return` early. The periodic timer will try again later.
  - **Provider:** Add `isBluetoothOn` boolean to `SystemHealthState`. In `SystemHealth.checkHealth()`, retrieve `FlutterBluePlus.adapterStateNow == BluetoothAdapterState.on`.
  - **UI:** In `SystemHealthCard`, if `!isBluetoothOn`, display a high-priority warning: "Bluetooth is OFF". Add an action button. On Android, we can call `FlutterBluePlus.turnOn()`.

### Verification
- Run `dart analyze` to ensure no syntax errors.
- Confirm `IsarService.pruneDatabase()` has correct Isar query logic.
- Confirm UI handles Bluetooth off state.