# Bubbl SDK v3 Notifications

Notifications are a core priority of the SDK. The default popup/modal experience is also part of the shipped SDK experience, not a later nice-to-have.

The v3 distinction is:

- **Core runtime responsibility:** receive/parse notification-capable runtime and Firebase payloads, decide whether a device notification should be triggered, trigger the native device notification, dedupe/frequency-gate it, and emit typed events.
- **Default UI responsibility:** provide bundled popup/modal, media detail, CTA, and survey experiences that work with minimal host-app code.
- **Customization responsibility:** expose configuration, callbacks, event streams, and renderer hooks so host apps can brand, override, or fully replace pieces without re-implementing networking, Firebase parsing, dedupe, or analytics.

The SDK should make the common path easy while keeping host apps in control when they need custom behavior.

Apps that want their own in-app notification modal should keep
`notificationRenderingMode` as `sdkDefault` and set
`enableDefaultNotificationModal` to `false`, or call the wrapper helper
`disableDefaultNotificationModal()` after boot. That keeps Firebase/runtime/
geofence device notifications, dedupe, and analytics in the SDK while stopping
the bundled detail/modal UI from drawing on top of the host app's custom UI.

Apps with an in-app notification inbox/history can call
`openNotificationModal(payload)` to open the SDK's bundled detail UI for an
already stored notification. This does not trigger a second device notification;
it presents the default detail/survey UI and routes the open through the same
analytics path as an external notification-tray tap.

## Current Native Slice

Implemented in this repository now:

- Shared native notification models for payload, media, CTA, survey questions, display result, source, and rendering mode.
- Typed events for notification received, displayed, and tapped.
- Runtime campaign dispatch:
  - `/api/check-push` `pushCampaign[].notificationsArray[]` entries are parsed into notification payloads and dispatched through the same native pipeline as Firebase.
  - `/api/check-geofence` `geoCampaign[]` entries are parsed into geofence polygons, enter/exit activation rules, notification payloads, cooldowns, and maximum trigger gates.
  - Geofence-sourced notifications are dispatched through the same native pipeline only after the native transition engine detects an eligible enter/exit.
  - Runtime parsing is tolerant of legacy field variants such as `headline`, `body`, `curatedNotificationId`, `locationId`, `ctaLabel`, `ctaUrl`, `mediaUrl`, `media[]`, `cta[]`, and `questions`.
  - Dashboard notification analytics only treat `curated_notification_id`, `curatedNotificationId`, `curated_notification`, `curatedNotification`, `n_id`, and `nId` as canonical curated notification IDs. Generic provider fields such as `notification_id` and `notificationId` are retained for local notification identity/dedupe but are never sent to Dashboard as curated IDs.
  - While v3 exposes typed interaction names internally, legacy `/api/activities` posts use Dashboard's historical activity strings: `notification_sent`, `notification_delivered`, `cta_engagment`, `media_viewed`, and `dismissed`; plain opens and automatic survey-render events stay local until the v1 ingest path can store them explicitly.
- Native geofence transition engine:
  - Persists last location, inside/outside state, notification trigger counts, and last trigger timestamps in the existing runtime cache.
  - Emits typed location update, geofence entered, and geofence exited events.
  - Queues location/geofence activity and geofence notification batches to the renewed Ingest service paths.
  - Suppresses repeat notifications while the device remains inside a region and enforces per-notification cooldown and maximum trigger values, scoped to the campaign when campaign identity is available.
- Android Firebase bridge:
  - Bundled `BubblFirebaseMessagingService`.
  - `onMessageReceived` forwards Firebase data/notification payloads into the SDK.
  - `onNewToken` forwards FCM tokens through `syncFcmToken(token)` / `registerPushToken(token)`.
  - Native notification channel and `NotificationCompat` system notification rendering.
  - The Android SDK creates the high-importance `bubbl_notifications` channel during install/boot so background FCM auto-rendered notifications can use the same heads-up capable channel before the SDK service is invoked.
  - Big-picture image notifications for image media payloads, with text fallback when media cannot be downloaded.
  - CTA notification actions route through the bundled tap activity and queue CTA analytics.
  - Notification taps route through bundled `BubblNotificationActivity`.
  - `openNotificationModal(context, payload)` opens the bundled detail/survey UI from an in-app inbox/history row without posting a new system notification.
  - Firebase auto-rendered notification taps that launch the host app can be forwarded from `MainActivity`. Native apps can choose `BubblNotificationTapPresentation.DefaultModal` for the bundled modal or `HostModal` for a custom modal; React Native apps can call `BubblSdkNotificationIntents.openDefaultModal(this, intent)` or `openHostModal(this, intent)`.
  - Custom-modal notification taps are kept pending across cold start and replayed as `notificationTapped` when the React Native bridge subscribes, so tray taps can open host-rendered UI even when the app was not already running.
  - Bundled Android detail/survey UI can show title/body, media, CTA, and simple survey questions.
  - Default Android detail UI is system-bar/display-cutout aware, keeps content vertically centered when it fits, scrolls when needed, and includes a close button.
  - Apps can disable the bundled Android detail UI with `enableDefaultNotificationModal = false` / `disableDefaultNotificationModal()` while still allowing the SDK to trigger the device notification. Notification taps are tracked and then the host app is brought forward instead of drawing the bundled detail activity.
  - `POST_NOTIFICATIONS` manifest permission.
  - Short-window duplicate suppression by notification ID.
  - Received/displayed/opened/CTA/media/survey-requested analytics queued to `/api/activities`.
  - Notification analytics are not enqueued to Dashboard unless a Dashboard-canonical curated notification ID is present, avoiding legacy Dashboard 404s from Firebase/provider IDs.
  - Notification receipt/display telemetry is opportunistically flushed so Dashboard receives it without waiting for a later manual flush.
- iOS notification bridge:
  - `handleRemoteNotification(_:)` for APNs-style payloads.
  - `handleFirebasePayload(_:)` for FCM data payloads.
  - `updateAPNsToken(_:)` and `updateFCMToken(_:)` token forwarding.
  - `BubblNotificationCenterDelegate` handles notification responses/taps.
  - Default `UNUserNotificationCenter` presenter, injectable for apps/tests/custom renderers.
  - Remote media payloads become `UNNotificationAttachment` files when supported, with notification display continuing if attachment download fails.
  - CTA actions are registered as notification categories and route through the existing response analytics path.
  - Default UIKit `BubblNotificationViewController` for notification detail, media, CTA, and simple surveys.
  - `openNotificationModal(payload)` opens the bundled detail/survey UI from an in-app inbox/history row without posting a new system notification.
  - Default iOS detail UI is safe-area aware for Dynamic Island/notches/home indicator, keeps content vertically centered when it fits, scrolls when needed, and includes a close button.
  - Received/displayed/opened/CTA/media/survey-requested analytics queued to `/api/activities`.
  - Notification analytics are not enqueued to Dashboard unless a Dashboard-canonical curated notification ID is present, avoiding legacy Dashboard 404s from APNs/Firebase/provider IDs.
  - Notification receipt/display telemetry is opportunistically flushed so Dashboard receives it without waiting for a later manual flush.
- Location integration:
  - Android periodic WorkManager refresh uses the device's last known location when `enableLocationTracking` is enabled and location permission is granted.
  - Android includes `BubblLocationUpdatesService`, an opted-in foreground location service started by `enableLocationTracking` when permission is already granted or manually through `startLocationTracking()`.
  - iOS includes `BubblLocationMonitor`, a CoreLocation helper that can request authorization, use significant-change or standard location updates, and forward fixes to `handleLocationUpdate(_:)`.
  - Apps that own their own region/location stack can forward wakes through `BubblLocationMonitor.handleRegionWake(location:)`.
  - iOS `BubblLocationMonitor` can update background `CLCircularRegion` monitoring from cached Transmission geofence data, selecting the nearest 20 campaign regions to respect the platform region cap.
- Host apps on any native/wrapper surface can manually forward location fixes through `handleLocationUpdate(location)`.
- Flutter and React Native wrapper calls, including `openNotificationModal(...)`, forward to the same native Android/iOS notification, location, geofence, and ingest engines instead of reimplementing runtime behavior in wrapper code.
- Android connected canaries cover the foreground service route into geofence refresh/transition telemetry.
  - iOS simulator canary covers the monitor region-wake route into geofence refresh/transition telemetry.

Still to build:

- True live-movement canaries using Android provider-delivered fixes and iOS simulated/physical CoreLocation region callbacks.
- Full durable cross-source frequency gates.
- Production-polished theming/customization for bundled modal, media, CTA, and survey UI.
- Permission helper APIs and foreground presentation policy helpers.

## Goals

- Device notifications work out of the box once push/location permissions and platform setup are complete.
- Banner acceptance tests must verify an OS-level notification banner/notification-center entry, not only a host-app tray event.
- Firebase integration is bundled into the platform SDK/runtime so most apps do not need to write Firebase glue code.
- Default notification and survey UI ships with the SDK and works out of the box.
- Host apps can customize or replace default UI when needed.
- Notification delivery, open, CTA, media, survey, geofence entry, and geofence exit events are tracked through the durable ingest queue.
- Duplicate notifications are suppressed across Firebase payloads, geofence-triggered notifications, app lifecycle transitions, and background workers.

## Integration Modes

### 1. Batteries-Included Native Runtime

Recommended for most apps.

The host app boots the SDK, grants permissions, and installs the native runtime. The SDK handles:

- Firebase/APNs token registration.
- Firebase data payload parsing.
- Runtime campaign notification parsing.
- Geofence enter/exit notification triggers.
- Native device notification rendering.
- Notification tap parsing.
- Default popup/modal rendering.
- Default media, CTA, and survey UI.
- Delivered/opened/CTA/media analytics.
- Typed SDK events for app UI.

### 2. Host Firebase Service Adapter

For apps that already own their Firebase messaging service.

The host app forwards Firebase payloads and refreshed tokens into the SDK:

- Android host service calls the SDK Firebase adapter from `onMessageReceived` and `onNewToken`.
- iOS app forwards APNs/FCM tokens and notification payloads through SDK helpers.
- SDK still handles parsing, dedupe, native notification triggering, and events unless the host opts out of rendering.

### 3. Fully Custom Rendering

For apps that want total UI/control.

The SDK parses and validates payloads, runs dedupe/frequency logic, emits typed events, and records analytics. The host app can render notifications or in-app UI itself.

This mode must still allow the host app to ask the SDK to report delivery/open/CTA/media/survey events so analytics stay consistent.

## Runtime Responsibilities

The notification runtime must support:

- Push notifications from Firebase/APNs.
- Geofence-triggered notifications from `/api/check-geofence`.
- Push campaign notifications from `/api/check-push` or runtime campaign payloads.
- Headline, body, location ID, curated notification ID, campaign ID.
- Media metadata: image, video, audio, message, survey.
- CTA metadata: label and URL.
- Survey questions and completion message.
- Local/native device notification rendering.
- Tap/open payload extraction.
- Foreground and background delivery behavior.
- Dedupe and cooldowns.
- Analytics reporting through queued ingest.

## Default UI

Default modals and survey screens are part of the SDK v3 release scope. They should be included in the native packages and enabled by default when notification handling is enabled.

The default UI should:

- Subscribe to typed notification events from the native runtime.
- Render notification details, media, CTA, and surveys.
- Keep text and controls inside platform safe areas, away from status bars, Dynamic Island/notches, display cutouts, and home indicators.
- Provide a visible close action.
- Submit survey responses through the core SDK.
- Allow host apps to replace copy, colors, layout, media presentation, CTA handling, and survey completion behavior.
- Avoid embedding their own networking, dedupe, or Firebase logic.

Customization should be additive and straightforward:

- Theme hooks for colors, typography, spacing, button style, and icons.
- Content hooks for title/body transformation, empty media states, CTA labels, and survey completion message.
- Behavior hooks for CTA handling, modal dismissal, survey submission result, media view reporting, and notification tap routing.
- Full custom renderer/event-only mode for advanced apps.

## Platform Expectations

### Android

The v3 Android runtime should provide:

- Bundled Firebase Messaging service/adapter with simple manifest/setup guidance.
- Token sync into `registerPushToken(token)`.
- `POST_NOTIFICATIONS` permission helper.
- Device notification channel setup.
- Native notification builder with image support and CTA actions.
- Default modal/activity/fragment UI for notification details, media, CTA, and surveys.
- Foreground/background duplicate suppression.
- Geofence enter/exit notification dispatch from native workers/services.
- Host-app event stream for notification received, delivered, tapped, dismissed, CTA tapped, media viewed, and survey requested.

### iOS

The v3 iOS runtime should provide:

- APNs and FCM token forwarding helpers.
- `UNUserNotificationCenterDelegate` bridge or composable delegate adapter.
- Push permission helper.
- Local notification scheduling for geofence/runtime-triggered notifications.
- Firebase/APNs payload parser, including nested payload shapes.
- Foreground presentation policy.
- Notification response/tap parser.
- Default SwiftUI/UIKit modal UI for notification details, media, CTA, and surveys.
- Host-app `AsyncStream` events, with optional Combine adapter.

## Configuration Direction

Current config has `enablePushHandling`. It should mean:

- `true`: SDK may parse payloads, trigger device notifications, show default popup/modal UI, emit notification events, and report notification analytics.
- `false`: SDK will not render or schedule device notifications automatically, but explicit calls like `registerPushToken`, `track`, and `submitSurveyResponse` still work.

Future runtime/UI config should separate:

- `enablePushHandling`
- `enableGeofenceNotifications`
- `enableFirebaseBridge`
- `notificationRenderingMode`: `sdkDefault`, `eventOnly`, `hostRendered`
- `enableDefaultNotificationModal`
- `enableDefaultSurveyUi`

Use `hostRendered` only when the host app wants to take over notification
rendering entirely. Use `sdkDefault` plus `enableDefaultNotificationModal =
false` when the SDK should still trigger native device notifications but the app
will render its own in-app modal from SDK events.

## Internal Modularity

The developer-facing SDK should be batteries-included. Internally, implementation should still keep transport, Firebase bridge, notification runtime, and UI layers separate so we can test them independently and let advanced apps customize behavior.

The release package should make the default integration simple first, then expose escape hatches.
