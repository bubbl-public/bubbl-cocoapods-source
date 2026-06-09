# Changelog

## 4.0.0

- Primes iOS native background region monitoring when location tracking starts and after geofence/location refresh calls, so background geofence notifications can fire without relying on foreground Dart UI execution.
- Handles iOS `UIApplication.LaunchOptionsKey.location` launches by restoring persisted SDK state and resuming native geofence monitoring before the Flutter UI mounts.
- Registers the Flutter iOS plugin as an application delegate, requests APNs registration when push handling is enabled, and forwards APNs token/remote-notification callbacks into the native SDK.
- Aligns the Flutter wrapper with the native SDK 4.0.0 release.

## 3.1.7

- Aligns the Flutter wrapper with the native SDK 3.1.7 release.
- Android and iOS default notification modals now embed YouTube media in-app instead of handing off externally.

## 3.1.6

- Aligns the Flutter wrapper with the native SDK 3.1.6 release.
- Android geofence retrigger gates now suppress the same notification across a campaign while allowing distinct notifications to fire independently.
- Android method-channel void results are normalized to avoid `kotlin.Unit` codec errors from SDK controls such as geofence refresh.

## 3.1.5

- Aligns the Flutter wrapper with the native SDK 3.1.5 release.
- iOS notification tap handling now completes the `UNUserNotificationCenterDelegate` response on the main actor to avoid UIKit state-restoration crashes when opening a notification from the tray.

## 3.1.4

- Aligns the Flutter wrapper with the native SDK 3.1.4 release.
- Android SDK notifications now create both the canonical `bubbl_notifications` channel and legacy `bubbl_push` channel during install/boot so background FCM auto-rendering can use a heads-up capable channel.
- Android local campaign notifications now render with high priority, message category, and default alert behavior for more reliable device banners.

## 3.1.2

- Persists iOS SDK boot configuration so background notification and location wakes can restore runtime state before React Native or Flutter host code has booted again.
- Aligns the Flutter wrapper with the native SDK 3.1.2 release.

## 3.1.1

- Restyles the native SDK default notification modal on Android and iOS with a light card layout, clearer actions, and polished survey controls.
- Adds regression coverage so survey options/choices continue to survive notification payload parsing.
- Aligns the Flutter wrapper with the native SDK 3.1.1 release.

## 3.0.6

- Adds Flutter geofence snapshot event models and native bridge handling so host apps can render active campaign polygons consistently across Android and iOS.
- Expands native geofence parsing to accept imported runtime aliases such as `locations`, `location`, `notifications`, and `curatedNotifications`.
- Aligns the Flutter wrapper with the native SDK 3.0.6 release.

## 3.0.5

- Android SDK notifications now create the shared `bubbl_notifications` channel at high importance, replacing an older lower-importance channel when possible so eligible notifications can appear as heads-up banners.
- Android SDK registration now emits a clear `firebase_config_missing` error when Firebase is not configured in the host app, instead of silently failing to register an FCM token.
- iOS installs a retained default `UNUserNotificationCenterDelegate` from the Flutter wrapper so foreground notifications use banner/list presentation and taps are forwarded to the SDK.
- Filters paused and inactive runtime campaigns before they can surface through geofence or notification handling.
- Aligns the Flutter wrapper with the native SDK 3.0.5 release.

## 3.0.2

- Updated package metadata to use the GitHub `bubbl-platform/renewed-sdk` source.
- Removed the nightly environment from the public SDK surface.

## 3.0.1

- Added the initial Flutter v3 facade and model surface.
- Added native Android and iOS platform-channel bridge scaffolding to the Bubbl SDK v3 cores.
- Added baseline wrapper tests and publish metadata.
