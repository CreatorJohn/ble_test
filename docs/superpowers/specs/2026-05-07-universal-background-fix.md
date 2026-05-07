# Design Spec: Universal Background Service Stability (Android 11-16)

## Problem
Background services are frequently killed by Android's Power Management, especially on aggressive skins like Xiaomi HyperOS. Additionally, Android 14+ requires explicit `foregroundServiceType` declarations.

## Proposed Changes

### 1. Platform Configuration (Android)
*   **Manifest:**
    *   Add `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`.
    *   Add `ACCESS_BACKGROUND_LOCATION`.
    *   Update `BackgroundService` declaration with `foregroundServiceType="location|specialUse"`.
*   **Dependencies:**
    *   `device_info_plus` (Hardware detection).
    *   `disable_battery_optimization` (Settings redirects).

### 2. State Management (`lib/providers/system_health.dart`)
*   Create a `SystemHealth` notifier that tracks:
    *   `isBatteryOptimized`
    *   `hasLocationAlways`
    *   `hasNotificationPermission` (Android 13+)
    *   `isXiaomi` (For specific Autostart tips)

### 3. UI Implementation (`lib/screens/discovery.dart`)
*   Implement `SystemHealthCard` component.
*   Conditional visibility: `if (!health.isOptimal)`.
*   Actionable buttons to resolve each identified issue.

### 4. Background Service (`lib/background_service.dart`)
*   Update `onStart` to handle Android 14 `location` type.
*   Add robust error logging to Isar for debugging isolate deaths.

## Success Criteria
1. Background scanning persists after screen off.
2. User is guided to fix configurations on any Android 11-16 device.
3. Xiaomi-specific settings (Autostart) are reachable from within the app.
