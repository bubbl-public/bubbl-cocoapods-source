# Changelog

## 3.0.5

- Android SDK notifications now create the shared `bubbl_notifications` channel at high importance, replacing an older lower-importance channel when possible so eligible notifications can appear as heads-up banners.
- Android SDK registration now emits a clear `firebase_config_missing` error when Firebase is not configured in the host app, instead of silently failing to register an FCM token.
- iOS installs a retained default `UNUserNotificationCenterDelegate` from the React Native wrapper so foreground notifications use banner/list presentation and taps are forwarded to the SDK.
- Filters paused and inactive runtime campaigns before they can surface through geofence or notification handling.
- Aligns the React Native wrapper with the native SDK 3.0.5 release.

## 3.0.2

- Updated package metadata to use the GitHub `bubbl-platform/renewed-sdk` source.
- Removed the nightly environment from the public SDK surface.

## 3.0.1

- Adds the React Native facade for Bubbl SDK v3.
- Bridges the facade to the native Android and iOS SDK cores.
- Exposes native SDK events through `Bubbl.events`.
