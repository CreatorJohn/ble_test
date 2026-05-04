# Background Service Implementation Plan

## Objective
Implement missing platform-specific configurations for the `flutter_background_service` package to ensure it functions correctly on both iOS and Android.

## Key Files & Context
*   `ios/Runner/Info.plist`: Needs background modes and task identifiers for iOS background execution.
*   `android/app/src/main/res/drawable/ic_bg_service_small.xml`: New file required for the Android foreground service notification icon.

## Implementation Steps

1.  **Configure iOS Background Modes (`ios/Runner/Info.plist`)**
    *   Add the `UIBackgroundModes` key with an array containing `fetch`, `processing`, and `bluetooth-central` (required for BLE scanning in the background).
    *   Add the `BGTaskSchedulerPermittedIdentifiers` key with an array containing `dev.flutter.background.refresh`.

2.  **Add Android Notification Icon (`android/app/src/main/res/drawable/ic_bg_service_small.xml`)**
    *   Create a basic placeholder vector drawable named `ic_bg_service_small.xml` in the `drawable` directory. This will prevent crashes on newer Android versions that mandate a valid small icon for foreground service notifications.

## Verification & Testing
*   Verify that `Info.plist` is valid XML after the additions.
*   Verify that the `ic_bg_service_small.xml` file exists in the correct directory.
*   (Manual) Run the application on an iOS simulator/device and start the service from the discovery screen to verify no immediate crashes occur related to missing background modes.
*   (Manual) Run the application on an Android device and start the service to verify the foreground notification appears with the icon and doesn't crash.