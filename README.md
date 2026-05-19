# Bubbl SDK v3

This repository is the source of truth for the Bubbl SDK v3 contract and implementation family.

The SDK public API is clean and platform-neutral. Runtime reads go to the Transmission service, telemetry writes go to the Ingest service, and platform/account operations belong on the Platform API.

The renewed Ingest transport intentionally keeps the existing SDK path shapes:

- `POST /api/device-registerd/create`
- `POST /api/device-data`
- `POST /api/geofence-data`
- `POST /api/activities`
- `POST /api/segments`
- `POST /api/survey-response`

Transmission runtime reads remain on the existing SDK runtime paths:

- `POST /api/check-geofence`
- `GET /api/check-push`
- `GET /api/get-config`

Environment defaults follow the renewed service split:

| Environment | Platform API | Transmission | Ingest |
| --- | --- | --- | --- |
| `development` | `https://nightly.api.bubbl.tech` | `https://nightly.transmission.bubbl.tech` | `https://nightly.ingest.bubbl.tech` |
| `nightly` | `https://nightly.api.bubbl.tech` | `https://nightly.transmission.bubbl.tech` | `https://nightly.ingest.bubbl.tech` |
| `staging` | `https://staging.api.bubbl.tech` | `https://staging.transmission.bubbl.tech` | `https://staging.ingest.bubbl.tech` |
| `production` | `https://api.bubbl.tech` | `https://transmission.bubbl.tech` | `https://ingest.bubbl.tech` |

The public SDK distance setting is meters. The current Transmission v2
`/api/check-geofence` wire parameter is still interpreted as miles, so the
native clients convert meters to miles at the compatibility boundary.

## Layout

```text
contracts/      OpenAPI, schemas, fixtures, and transport map
android/        Kotlin Android SDK v3 source
ios/            Swift Package SDK v3 source
flutter/        Flutter plugin wrapper
react-native/   React Native package wrapper
examples/       Canary app placeholders
scripts/        Repository validation scripts
docs/           Runtime strategy notes
```

## Current Status

This is the beta candidate foundation:

- Contract schemas and golden fixtures are present.
- Transport mapping records that Ingest uses SDK-compatible paths, Transmission runtime uses the renewed split hosts, Platform API hosts are listed for app/account clients, and public meter distances are converted for the current Transmission v2 wire unit.
- Android implements runtime networking, DataStore-backed state/cache, Room-backed durable ingest, geofence transition state, WorkManager background flush/refresh with last-known-location geofence refresh, and an opted-in foreground location service.
- iOS implements runtime networking, Keychain-backed secure state, SQLite-backed durable ingest, file-backed runtime cache fallback, geofence transition state, a CoreLocation monitor helper, and background circular-region selection capped to the nearest 20 geofences.
- The iOS Swift package product remains `BubblSDK`; the public client type is `BubblClient` so release builds can generate stable Swift interfaces and XCFramework artifacts without a module/type name collision.
- Android now includes the notification foundation: typed notification payloads/events, bundled Firebase Messaging service, FCM token sync, native system notification triggering, big-picture image notifications, CTA actions, tap routing through a bundled default Activity, basic detail/survey UI, short-window duplicate suppression, and notification telemetry through the durable ingest queue.
- iOS now includes the notification foundation: typed APNs/FCM payload parsing, APNs/FCM token forwarding helpers, notification response delegate, injectable default `UNUserNotificationCenter` presentation, remote media attachments, CTA categories, basic UIKit detail/survey UI, and notification telemetry through the durable ingest queue.
- Runtime `pushCampaign` payloads from Transmission are parsed and dispatched through the same native notification engine as Firebase payloads. Runtime `geoCampaign` payloads are parsed into geofence polygons/notifications, gated by native enter/exit transition detection, and then dispatched through that same notification engine.
- `examples/ios-canary` proves the local iOS Swift Package inside a simulator app runtime.
- [docs/NOTIFICATIONS.md](docs/NOTIFICATIONS.md) defines notifications as a core runtime priority: the shipped SDK should bundle Firebase integration, trigger native device notifications, and provide default popup/survey UI with customization hooks.
- [LEGACY_PARITY.md](LEGACY_PARITY.md) tracks the old SDK geofence, background, Firebase, notification, and host-callback behavior still needed before v3 can replace current native SDKs.
- [RELEASE.md](RELEASE.md) defines the private-source monorepo release setup. Tag builds always validate and create artifacts; public registry publishing is an explicit opt-in.
- Flutter now bridges the Dart facade to native Android/iOS SDK cores through platform channels. React Native now bridges the JS facade to native Android/iOS SDK cores through autolinked native modules, with the TurboModule spec kept in place for codegen.
- `npm run test:contracts` validates the contract pack without external dependencies.
