# Bubbl React Native SDK

React Native wrapper for Bubbl SDK v3.

The JavaScript facade forwards calls to the native Android and iOS SDK cores. Native runtime behavior, durable ingest queues, geofence transitions, notification triggering, Firebase/APNs payload handling, and diagnostics are owned by the platform SDKs.

## Install

```bash
npm install @bubbl-tech/react-native-sdk
```

## Boot

```ts
import { Bubbl } from '@bubbl-tech/react-native-sdk';

await Bubbl.boot({ apiKey: '...' });
```

## Events

```ts
const subscription = Bubbl.events.addListener((event) => {
  if (event.type === 'notificationReceived') {
    // Host apps can inspect or custom-render notification payloads here.
  }
});

subscription.remove();
```

## Notes

- Android depends on `tech.bubbl.sdk:bubbl-sdk` and requires `minSdkVersion 27` or higher.
- iOS depends on the `BubblSDK` CocoaPods/Swift package release and requires iOS 15 or higher.
- Host apps still need the usual platform permissions for push notifications and location tracking.
