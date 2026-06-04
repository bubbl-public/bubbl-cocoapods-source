# Notification Delivery Smoke Notes

This note captures the June 2026 smoke investigation for device-level Bubbl
notification banners. The in-app event tray is useful for SDK diagnostics, but
it is not proof that iOS or Android displayed a system notification banner.

## Expected Behavior

- Foreground geofence notification: the SDK evaluates an eligible geofence
  transition and asks the OS to display a device notification.
- Background geofence notification: the SDK background location path wakes,
  evaluates the transition, and asks the OS to display a device notification.
- Remote push notification: Firebase/APNs or Firebase/Android delivers a push
  to the device and the OS displays a banner when app/user notification settings
  allow it.
- Restart persistence: the SDK restores its config, token, cached runtime data,
  geofence state, and pending ingest queue after app restart.

Retrigger/cooldown policy is intentionally outside this smoke scope.

## SDK-Owned Fixes

### Android

The Android SDK now creates the campaign notification channel during SDK
installation/boot, not only at the moment the SDK renders a local notification.
This matters because background FCM notification messages can be auto-rendered
by Google Play services without invoking `FirebaseMessagingService` first.

The SDK's bundled Android manifest also declares
`com.google.firebase.messaging.default_notification_channel_id` as
`bubbl_notifications`, so host apps get the high-importance campaign channel by
default.

The SDK also creates the legacy `bubbl_push` channel. This keeps older or
server-side payloads that still specify `android.notification.channel_id =
bubbl_push` displayable while the renewed backend moves to
`bubbl_notifications`.

Campaign notifications now request heads-up friendly presentation:

- `NotificationManager.IMPORTANCE_HIGH` channel
- `NotificationCompat.PRIORITY_HIGH`
- `NotificationCompat.CATEGORY_MESSAGE`
- `NotificationCompat.DEFAULT_ALL`

Android still requires the host app/user to allow notifications, including
`POST_NOTIFICATIONS` on Android 13+.

### iOS

The iOS SDK already schedules SDK-rendered device notifications through
`UNUserNotificationCenter.add(...)` and installs a foreground notification
delegate that returns banner/list/sound/badge presentation options on iOS 14+.

The simulator APNs smoke proved the app can display a real OS banner when a
push-like notification reaches the app:

```sh
xcrun simctl push <simulator_udid> tech.bubbl.react /tmp/bubbl-sim-push.apns
```

Live Firebase accepted a send to the registered simulator FCM token, but the
simulator did not display a visible banner from that live FCM send. Treat that
as inconclusive for production delivery; use a physical iPhone/TestFlight build
for final remote push acceptance.

## Host-App Requirements

No SDK can add platform capabilities to a host app after build time. Host apps
must include:

### iOS

- Push Notifications capability with `aps-environment` entitlement.
- Background Modes for `remote-notification` when background remote handling is
  needed.
- Background Modes for `location` when geofence/location wake behavior is
  needed.
- Notification permission request before expecting banners.
- APNs/FCM setup for the exact bundle ID and signing environment.
- A retained `UNUserNotificationCenterDelegate`, or the SDK-provided
  `BubblNotificationCenterDelegate.installDefault()`.

### Android

- `POST_NOTIFICATIONS` permission on Android 13+.
- Coarse/fine/background location permissions for geofence/background checks.
- Foreground service permissions for long-running location updates.
- Firebase configuration for the exact application ID.
- If overriding Firebase notification channel metadata, use a high-importance
  channel for campaign notifications.

## Smoke Evidence To Capture

- Screenshot/video of an actual OS notification banner, not just SDK event tray
  rows.
- SDK diagnostics showing booted state, push token suffix, campaign count, and
  pending queue count.
- Backend/Firebase response for direct test push.
- App restart followed by diagnostics showing restored SDK state.
- Android logcat or iOS device console showing SDK notification display result
  when available.
