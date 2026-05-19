# Bubbl SDK v3 Legacy Runtime Parity

This document tracks the Android and iOS runtime behavior that must exist before SDK v3 can replace the current native SDKs.

The v3 SDK transport core remains internally modular, but the shipped SDK must be **batteries-included for notifications**. Native device notification triggering, Firebase/APNs push handling, default popup/modal UI, geofence-triggered notifications, local device notification rendering, and notification analytics are core release requirements. Host apps should get a simple default integration first, with customization hooks when they need them.

See [docs/NOTIFICATIONS.md](docs/NOTIFICATIONS.md) for the notification strategy.

## Current v3 Foundation

Implemented in the native cores:

- Stable facade: `boot`, `shutdown`, `refresh`, `refreshGeofence`, `refreshPush`, `getConfiguration`, `getPrivacyText`, `updateSegments`, `setCorrelationId`, `clearCorrelationId`, `registerPushToken`, `track`, `submitSurveyResponse`, `flush`, `diagnostics`, `events`.
- Runtime reads: Transmission `/api/check-geofence`, `/api/check-push`, `/api/get-config`.
- Renewed Ingest service writes through SDK-compatible paths.
- Default endpoint resolution uses the renewed split hosts:
  - `development` and `nightly`: `nightly.transmission.bubbl.tech` + `nightly.ingest.bubbl.tech`.
  - `staging`: `staging.transmission.bubbl.tech` + `staging.ingest.bubbl.tech`.
  - `production`: `transmission.bubbl.tech` + `ingest.bubbl.tech`.
- Public geofence distance remains meters, with native SDKs converting to the current Transmission v2 wire distance unit before calling `/api/check-geofence`.
- Durable ingest queue:
  - Android: Room.
  - iOS: SQLite.
- Secure/state storage:
  - Android: DataStore.
  - iOS: Keychain for secure state, file cache for runtime responses.
- Cache fallback for runtime responses.
- Diagnostic and idempotency headers.
- Android WorkManager flush/refresh canaries.
- iOS simulator canary for URLSession, Keychain, SQLite queue restore, retry, runtime cache fallback, and diagnostics.
- Typed notification payloads/events on Android and iOS.
- Runtime push/geofence campaign notification extraction from Transmission responses, dispatched through the same notification engine as Firebase payloads.
- Native geofence transition engine on Android and iOS:
  - Parses Transmission `geoCampaign` polygons and `notificationsArray` activation rules.
  - Detects enter/exit with point-in-polygon checks.
  - Persists last location, region state, trigger counts, and last trigger timestamps.
  - Enforces geofence notification cooldown and maximum trigger gates.
  - Emits typed location/geofence events and queues geofence/location/notification telemetry.
- Android WorkManager background refresh now checks last-known location when location tracking is enabled.
- Android includes an opted-in foreground `BubblLocationUpdatesService` with start/stop facade methods and foreground service location manifest wiring.
- iOS includes a `BubblLocationMonitor` CoreLocation helper for significant-change or standard location update forwarding.
- iOS background region selection chooses the nearest 20 Transmission geofence polygons and applies them as `CLCircularRegion` monitors.
- Android connected canary verifies a foreground-service location wake routes through `/api/check-geofence`, typed geofence enter events, and durable telemetry.
- iOS simulator canary verifies `BubblLocationMonitor` region wakes route through `/api/check-geofence` and durable telemetry.
- Android bundled Firebase Messaging service, FCM token sync, Firebase payload parsing, native system notification rendering, notification tap Activity, basic detail/survey UI, short-window duplicate suppression, and delivered/opened/CTA/media/survey-requested analytics.
- iOS APNs/FCM token forwarding helpers, APNs/Firebase payload parsing, notification response delegate, injectable default `UNUserNotificationCenter` presentation, basic UIKit detail/survey view controller, and delivered/opened/CTA/media/survey-requested analytics.

Not yet implemented in v3:

- Full lifecycle switching between foreground and background monitors.
- True live-movement canaries using Android provider-delivered fixes and iOS simulated/physical CoreLocation callbacks.
- Host app geofence callbacks and streams beyond typed SDK events.
- Production-polished bundled notification/survey default UI modules and customization hooks.
- Full durable notification dedupe/frequency gates across Firebase, runtime, geofence, lifecycle, and background workers.
- Map polygon/circle snapshot streams.
- Permission helper APIs.

## Android Legacy Behavior To Preserve

Current Android SDK behavior found in `sdk/bubbl-android-sdk`:

- `BubblSdk.init(application, config)` registers runtime context, device, location receiver, geofence engine, WorkManager refresh, and entry/exit worker.
- `startLocationTracking(context)` starts `LocationUpdatesService` as a foreground location service.
- `LocationUpdatesService` emits location broadcasts, uses high accuracy fused location updates, and routes fixes into geofence handling.
- `EntryExitWorker` runs periodic background point-in-polygon checks using passive fused location and emits `ON_ENTER` / `ON_EXIT` notifications.
- `GeofenceRefreshWorker` periodically refreshes campaigns from Transmission using last known location.
- `GeofenceEngine` detects entered/exited campaigns from cached polygons.
- Geofence responses are cached and published through `geofenceFlow`.
- Public helpers expose `hasCampaigns`, `getCampaignCount`, `forceRefreshCampaigns`, and `clearCachedCampaigns`.
- Firebase support:
  - Fetches initial `FirebaseMessaging.getInstance().token`.
  - `syncFcmToken(context, token)` re-registers refreshed tokens.
  - `MyFirebaseMessagingService` parses Firebase data payloads, nested payloads, media, CTA, survey questions, and message IDs.
- Notification handling:
  - `NotificationRouter.push(...)` renders system notifications.
  - Image notifications upgrade to big picture style.
  - CTA actions are supported.
  - A local broadcast passes notification JSON to the host app for modal/UI handling.
  - Local and campaign-level dedupe suppress duplicate notifications.
  - Delivered, CTA, media, geofence, location, and survey events are reported.
- Required app capabilities/dependencies include location permissions, background location, foreground service location, post notifications, Firebase Messaging, Play Services Location/Maps, and WorkManager.

## iOS Legacy Behavior To Preserve

Current iOS SDK behavior found in `sdk/bubbl-ios-source`:

- `BubblPlugin.start(apiKey:env:segmentations:delegate:)` configures services, registers device, starts geofence polling, and wires app state monitoring.
- Permission helpers:
  - `requestLocationWhenInUse()`
  - `requestLocationAlways()`
  - `requestPushPermission()`
  - authorization status publishers/properties.
- Token hooks:
  - `updateAPNsToken(_:)`
  - `updateFCMToken(_:)`
- Geofence service:
  - Polls `/check-geofence`.
  - Caches raw geofence response.
  - Publishes campaign polygons for host map overlays.
  - Uses 5 minute foreground polling and 30 minute background polling.
  - Refreshes after significant background location movement.
- Foreground geofence monitor:
  - Uses point-in-polygon checks.
  - Publishes/forwards entry and exit events.
  - Sends `ON_ENTER` / `ON_EXIT` local notifications.
  - Reports geofence and location activity.
- Background region monitor:
  - Uses `CLCircularRegion` monitoring.
  - Respects iOS 20 monitored region limit by selecting nearest campaigns.
  - Pauses in foreground and resumes in background.
  - Tracks inside regions, dwell/exit timing, and cooldowns.
  - Uses temporary location updates to improve exit detection.
  - Sends background local notifications and reports activity.
- Notification manager:
  - Can be set as `UNUserNotificationCenter.delegate`.
  - Parses Firebase/APNs payload shapes, including nested `notification_data`.
  - Publishes `BubblNotificationDetails` to the host app.
  - Extracts media, CTA, location, notification ID, survey questions, and completion messages.
  - Reports notification delivered, CTA engagement, and media viewed.
- Public helpers expose configuration/privacy text, refetch geofence, notification stats, survey response submission, and survey event tracking.

## Required v3 Runtime Additions

Before alpha replacement, v3 needs these native runtime modules. Notification delivery and default popup/modal UI are first-class.

1. **Notification Runtime**
   - Trigger native device notifications from runtime campaigns, geofence transitions, and Firebase/APNs payloads.
   - Show default notification popup/modal UI when users open or receive supported notification payloads.
   - Support headline/body, image, video/audio metadata, CTA, survey payloads, completion message, location ID, and curated notification ID.
   - Add dedupe/frequency gates equivalent to or stricter than legacy.
   - Report notification delivered/opened/CTA/media events through durable ingest queue.
   - Emit typed SDK events so host apps can customize or replace UI.

2. **Firebase Push Bridge**
   - Android: bundled Firebase Messaging service/adapter that can be used directly or called from the host app's own service.
   - iOS: APNs/FCM token forwarding helpers and notification payload parser.
   - `registerPushToken(token)` remains the platform-neutral core method.
   - Firebase setup should be simple and documented; advanced apps can still forward tokens/messages manually.

3. **Location Runtime**
   - Android foreground service for opted-in continuous location tracking.
   - Android passive/background WorkManager entry/exit checks.
   - iOS foreground point-in-polygon monitor.
   - iOS background `CLCircularRegion` monitor with 20-region cap strategy.
   - App lifecycle switching between foreground and background monitors.
   - Permission helpers and status events.

4. **Geofence Runtime**
   - Parse full geofence runtime fixture into typed campaigns, locations, polygons, notifications, media, CTA, and surveys.
   - Persist last known location and cached campaigns.
   - Detect enter/exit transitions.
   - Emit typed SDK events for geofence enter/exit and location update.
   - Report geofence and location activity through durable ingest queue.
   - Publish map overlay/snapshot data for host apps.

5. **Default UI And Customization**
   - Bundled notification modal/details UI.
   - Bundled survey UI and response submission helpers.
   - Bundled media and CTA handling.
   - Theme, copy, behavior, and renderer hooks for host customization.
   - Full custom/event-only mode for advanced apps.
   - UI should subscribe to native runtime events instead of embedding networking, Firebase parsing, or dedupe logic.

## Compatibility Rule

If old SDK behavior is app-visible, v3 needs either:

- The same native behavior by default when enabled by config, or
- A clearly named customization/override path with tests.

Flutter and React Native wrappers must not re-implement geofence, Firebase, notification, or dedupe logic. They should bridge typed calls/events to the native Android/iOS runtime modules.
