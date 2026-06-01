# Changelog

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
