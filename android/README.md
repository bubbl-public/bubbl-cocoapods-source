# Bubbl Android SDK v3

Android v3 is a native Kotlin SDK. The native layer owns runtime reads, local cache, durable ingest queue, push token forwarding, notification triggering, and diagnostics.

Initial transport target:

- Runtime: Transmission `/api/check-geofence`, `/api/check-push`, `/api/get-config`
- Ingest: renewed Dashboard legacy-mirrored paths documented in `../contracts/transport-map.json`
- Environment defaults mirror the legacy Android/iOS SDKs. `Development` and `Nightly` use nightly endpoints, `Staging` uses staging endpoints, and `Production` uses `https://production.api.bubbl.tech` for Transmission plus `https://platform.bubbl.tech` for ingest.
- `defaultDistanceMeters` stays public in meters; the Android transport converts it to the current Transmission v2 wire distance unit before calling `/api/check-geofence`.

The alpha runtime has real transport and Android persistence wiring behind the stable public facade:

- `boot(config)` persists install state and queues `/api/device-data`.
- `refreshGeofence(location)`, `refreshPush()`, and `getConfiguration()` call Transmission and cache successful responses.
- `track(event)`, `updateSegments(tags)`, `registerPushToken(token)`, and `submitSurveyResponse(response)` append durable Dashboard ingest writes.
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
- Notification taps route through `BubblNotificationActivity`, which provides a default detail/survey UI.
- Delivered/opened/CTA/media/survey-requested notification events are queued to `/api/activities`.
- Geofence entry/exit and location update events are queued to the renewed Dashboard legacy-mirrored ingest paths.

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
