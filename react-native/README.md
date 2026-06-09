# Bubbl React Native SDK

React Native wrapper for Bubbl SDK v3.

The JavaScript facade forwards calls to the native Android and iOS SDK cores. Native runtime behavior, durable ingest queues, geofence transitions, notification triggering, Firebase/APNs payload handling, and diagnostics are owned by the platform SDKs.

## Install

```bash
npm install @bubblsdk/react-native-sdk
```

## Boot

```ts
import { Bubbl } from '@bubblsdk/react-native-sdk';

await Bubbl.boot({ apiKey: '...' });
```

Enable SDK-owned location/background processing when the host app has collected
location permission:

```ts
await Bubbl.boot({
  apiKey: '...',
  enableLocationTracking: true,
});

await Bubbl.startLocationTracking();
```

The SDK owns the native background mechanics once enabled: Android uses the
bundled foreground location service and WorkManager restore/refresh path, and
iOS uses the bundled CoreLocation monitor. The host app still owns platform
declarations and runtime permission UX.

For iOS background geofence cold starts, forward launch options from your
`AppDelegate` before the React Native bridge or JavaScript UI is mounted:

```swift
import BubblReactNativeSdk

func application(
  _ application: UIApplication,
  didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
) -> Bool {
  BubblSdkLocationLaunchHandler.handleLaunchOptions(launchOptions as NSDictionary?)
  return true
}
```

For apps that render their own in-app notification modal while still letting
the native SDK trigger device notifications:

```ts
await Bubbl.boot({
  apiKey: '...',
  notificationRenderingMode: 'sdkDefault',
  enableDefaultNotificationModal: false,
});

// Or toggle it after boot.
await Bubbl.disableDefaultNotificationModal();
```

Apps with their own notification inbox/history can still ask the SDK to show
the bundled detail UI for a stored payload:

```ts
await Bubbl.openNotificationModal(payload);
```

This opens the default modal/detail UI without posting another device
notification.

## Android Notification Taps

Firebase auto-rendered notifications launch the app's `MainActivity` with the
notification payload as intent extras. Forward those launcher intents into the
SDK so notification taps open the app and route to the right modal.

Use `openDefaultModal(...)` when the SDK should show the bundled modal:

```kotlin
import android.content.Intent
import android.os.Bundle
import com.facebook.react.ReactActivity
import tech.bubbl.reactnative.BubblSdkNotificationIntents

class MainActivity : ReactActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        BubblSdkNotificationIntents.openDefaultModal(this, intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        BubblSdkNotificationIntents.openDefaultModal(this, intent)
    }
}
```

Use `openHostModal(...)` when the app renders its own modal. The SDK records
the tap, keeps the payload pending across cold start, and emits
`notificationTapped` once the React Native bridge subscribes:

```kotlin
BubblSdkNotificationIntents.openHostModal(this, intent)
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
- Host apps must declare push/location permissions. Android needs coarse/fine/background location, foreground-service location, and notification permissions. iOS needs location usage descriptions and `UIBackgroundModes` entries for `location` and `remote-notification`.
