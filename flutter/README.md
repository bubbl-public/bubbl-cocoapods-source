# Bubbl Flutter SDK

Flutter wrapper for Bubbl SDK v3.

The Dart facade forwards calls to the native Android and iOS SDK cores. Native runtime behavior, durable ingest queues, geofence transitions, notification triggering, Firebase/APNs payload handling, and diagnostics are owned by the platform SDKs.

## Install

```yaml
dependencies:
  bubbl_flutter_sdk: ^3.0.4
```

## Boot

```dart
await BubblSdk.instance.boot(
  const BubblConfig(apiKey: '...'),
);
```

For apps that render their own in-app notification modal while still letting
the native SDK trigger device notifications:

```dart
await BubblSdk.instance.boot(
  const BubblConfig(
    apiKey: '...',
    notificationRenderingMode: BubblNotificationRenderingMode.sdkDefault,
    enableDefaultNotificationModal: false,
  ),
);

// Or toggle it after boot.
await BubblSdk.instance.disableDefaultNotificationModal();
```

Apps with their own notification inbox/history can still ask the SDK to show
the bundled detail UI for a stored payload:

```dart
await BubblSdk.instance.openNotificationModal(payload);
```

This opens the default modal/detail UI without posting another device
notification.

## Notes

- Android depends on `tech.bubbl.sdk:bubbl-sdk` and requires `minSdkVersion 27` or higher.
- iOS depends on the `BubblSDK` CocoaPods/Swift package release and requires iOS 15 or higher.
- Host apps still need the usual platform permissions for push notifications and location tracking.
