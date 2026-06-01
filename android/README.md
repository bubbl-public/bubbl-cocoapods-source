# Bubbl Android SDK v3

Android v3 is a native Kotlin SDK. The native layer owns runtime reads, local cache, durable ingest queue, push token forwarding, notification triggering, and diagnostics.

Initial transport target:

- Runtime: Transmission `/api/check-geofence`, `/api/check-push`, `/api/get-config`
- Ingest: renewed Ingest SDK-compatible paths documented in `../contracts/transport-map.json`
- Environment defaults follow the renewed split hosts. `Development` and `Staging` use `staging.*`, and `Production` uses `https://transmission.bubbl.tech` for Transmission plus `https://ingest.bubbl.tech` for ingest.
- `defaultDistanceMeters` stays public in meters; the Android transport converts it to the current Transmission v2 wire distance unit before calling `/api/check-geofence`.

The alpha runtime has real transport and Android persistence wiring behind the stable public facade:

- `boot(config)` persists install state and queues `/api/device-data`.
- `refreshGeofence(location)`, `refreshPush()`, and `getConfiguration()` call Transmission and cache successful responses.
- `track(event)`, `updateSegments(tags)`, `registerPushToken(token)`, and `submitSurveyResponse(response)` append durable Ingest service writes.
- `flush()` drains the persisted ingest queue and leaves failed writes queued with incremented attempts.
- DataStore stores install state, active config, runtime cache, segments, correlation ID, and push token.
- Room stores the durable ingest queue.
- WorkManager schedules constrained one-shot flushes and a periodic refresh/flush worker.
- `BubblFirebaseMessagingService` handles Firebase payloads/tokens when the app uses the bundled bridge.
- `handleFirebasePayload(...)`, `syncFcmToken(token)`, and `showNotification(payload)` are available for apps that already own Firebase integration.
- `refreshPush()` parses Transmission `pushCampaign` notification payloads and dispatches them through the same notification engine.
- `refreshGeofence(location)` parses Transmission `geoCampaign` polygons/notifications, detects enter/exit transitions, enforces cooldown/maximum trigger gates, and dispatches eligible geofence notifications through the same notification engine.
- `handleLocationUpdate(location)` lets host apps or wrappers forward foreground location fixes into the same geofence refresh/transition path.
- `startLocationTracking()` / `stopLocationTracking()` control `BubblLocationUpdatesService`, the opted-in foreground service that continuously forwards location fixes while `enableLocationTracking` is true.
- When `enableLocationTracking` is enabled, the periodic WorkManager refresh tries the device's last known location for background-safe geofence refreshes.
- Native device notifications are rendered by default when `enablePushHandling = true` and `notificationRenderingMode = SdkDefault`.
- Native device notifications use a high-importance `bubbl_notifications` channel on Android O+ so eligible campaign notifications can appear as heads-up banners when system/user notification settings allow it.
- Notification taps route through `BubblNotificationActivity`, which provides a default detail/survey UI.
- Firebase auto-rendered notification taps can be forwarded from the launcher activity with `BubblSdk.openNotificationIntent(activity, intent)`.
- In-app notification inbox/history rows can open the bundled detail/survey UI with `BubblSdk.openNotificationModal(context, payload)` without posting another device notification.
- Apps with custom in-app notification UI can keep native device notifications enabled and disable only the bundled detail UI with `enableDefaultNotificationModal = false` or `BubblSdk.setDefaultNotificationModalEnabled(false)`.
- Delivered/opened/CTA/media/survey-requested notification events are queued to `/api/activities`.
- Geofence entry/exit and location update events are queued to the renewed Ingest service paths.

Install with an Android `Context` in app code:

```kotlin
BubblSdk.install(context)
BubblSdk.boot(BubblConfig(apiKey = "..."))
```

Apps with their own Firebase service can forward into the SDK:

```kotlin
private val bubblScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

override fun onMessageReceived(message: RemoteMessage) {
    bubblScope.launch {
        BubblSdk.handleFirebasePayload(
            payload = message.data,
            messageId = message.messageId,
            notificationTitle = message.notification?.title,
            notificationBody = message.notification?.body
        )
    }
}

override fun onNewToken(token: String) {
    bubblScope.launch {
        BubblSdk.syncFcmToken(token)
    }
}
```

If Firebase launches your app directly from a system notification tap, forward
the launcher intent before drawing your own UI. Use `DefaultModal` when the SDK
should show the bundled modal:

```kotlin
override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    BubblSdk.openNotificationIntent(
        this,
        intent,
        BubblNotificationTapPresentation.DefaultModal
    )
}

override fun onNewIntent(intent: Intent) {
    super.onNewIntent(intent)
    setIntent(intent)
    BubblSdk.openNotificationIntent(
        this,
        intent,
        BubblNotificationTapPresentation.DefaultModal
    )
}
```

Use `HostModal` when the app renders its own modal. The SDK keeps the tap
payload pending across cold start so the host can drain or receive the
`NotificationTapped` event once its listener is attached:

```kotlin
BubblSdk.openNotificationIntent(
    this,
    intent,
    BubblNotificationTapPresentation.HostModal
)
```

Apps that want the bundled foreground location loop can start it after location permission is granted:

```kotlin
BubblSdk.boot(BubblConfig(apiKey = "...", enableLocationTracking = true))
BubblSdk.startLocationTracking()
```

The file-backed install path remains for JVM tests and local harnesses:

```kotlin
BubblSdk.install(storageDirectory = File(context.filesDir, "bubbl-sdk"))
BubblSdk.boot(BubblConfig(apiKey = "..."))
```

## Verification

JVM tests cover transport serialization, cache fallback, and background restore:

```bash
../sdk/bubbl-android-sdk/gradlew -p android testDebugUnitTest
```

Instrumentation canaries cover the real Android persistence/scheduler stack:

- DataStore state/config/runtime cache
- Room durable ingest queue
- WorkManager flush and periodic refresh scheduling
- Foreground location service route into `/api/check-geofence`, typed geofence enter events, and durable telemetry

Build the canary APK:

```bash
../sdk/bubbl-android-sdk/gradlew -p android assembleDebugAndroidTest
```

Run on a connected emulator/device:

```bash
../sdk/bubbl-android-sdk/gradlew -p android connectedDebugAndroidTest
```
