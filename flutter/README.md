# Bubbl Flutter SDK

Flutter wrapper for Bubbl SDK v3.

The Dart facade forwards calls to the native Android and iOS SDK cores. Native runtime behavior, durable ingest queues, geofence transitions, notification triggering, Firebase/APNs payload handling, and diagnostics are owned by the platform SDKs.

## Install

```yaml
dependencies:
  bubbl_flutter_sdk: ^3.0.0-beta.1
```

## Boot

```dart
await BubblSdk.instance.boot(
  const BubblConfig(apiKey: '...'),
);
```

## Notes

- Android depends on `tech.bubbl.sdk:bubbl-sdk` and requires `minSdkVersion 27` or higher.
- iOS depends on the `BubblSDK` CocoaPods/Swift package release and requires iOS 15 or higher.
- Host apps still need the usual platform permissions for push notifications and location tracking.
