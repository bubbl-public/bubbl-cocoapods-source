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
| `development` | `https://staging.api.bubbl.tech` | `https://staging.transmission.bubbl.tech` | `https://staging.ingest.bubbl.tech` |
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

## Local Setup

Required tooling:

- Node.js 22+
- JDK 17+
- Android SDK and Gradle wrapper support
- Xcode with Swift Package Manager and CocoaPods 1.16+
- Flutter stable

Install JavaScript dependencies from the repo root:

```bash
npm install
```

The repo is version-locked as a monorepo. The root `package.json`,
`android/gradle.properties`, `ios/*.podspec`, `flutter/pubspec.yaml`, and
`react-native/package.json` must all agree on the same SemVer version.

## Validate Everything

Fast cross-platform validation:

```bash
npm run test:contracts
npm run test:wrappers
npm run test:rn
npm run release:check
npm run readiness
```

Full local validation, where native tooling is available:

```bash
npm run test:local
```

Strict readiness is intentionally tougher and is useful before a public release:

```bash
npm run readiness:strict
```

## Android

Source: `android/`

Package: `tech.bubbl.sdk:bubbl-sdk`

Build, test, and publish to local Maven:

```bash
chmod +x android/gradlew
android/gradlew -p android testDebugUnitTest publishToMavenLocal --no-daemon --stacktrace
```

Public release to Maven Central is handled by GitHub Actions. Push a semantic
version tag:

```bash
git tag 3.0.5
git push origin 3.0.5
```

## iOS

Source: `ios/`

Packages:

- Swift Package product: `BubblSDK`
- CocoaPods trunk pod: `BubblSDK`
- Legacy alias podspec: `Bubbl-Sdk`

Run Swift tests:

```bash
swift test --package-path ios --scratch-path /tmp/bubbl-renewed-sdk-ios-build
```

Lint CocoaPods locally against the checked-in private source:

```bash
sh scripts/cocoapods-lint.sh
```

For public CocoaPods trunk publishing, the source mirror
`bubbl-public/bubbl-cocoapods-source` must have a matching `v<version>` tag.
GitHub Actions runs the macOS release workflow:

```bash
git tag 3.0.5
git push origin 3.0.5
```

The release workflow validates the tag against `package.json`, builds the
XCFramework, lints the podspecs, rewrites the generated podspec to use the
public source mirror tag, and pushes `BubblSDK` to CocoaPods trunk when
`BUBBL_COCOAPODS_TRUNK_RELEASE=true`.

## Flutter

Source: `flutter/`

Package: `bubbl_flutter_sdk`

Analyze, test, and dry-run locally:

```bash
cd flutter
flutter pub get
flutter analyze
flutter test
flutter pub publish --dry-run
```

Public release to pub.dev is handled by GitHub Actions:

```bash
git tag 3.0.5
git push origin 3.0.5
```

## React Native

Source: `react-native/`

Package: `@bubblsdk/react-native-sdk`

Validate wrapper surface and package contents:

```bash
npm run test:rn
cd react-native
npm pack --dry-run
npm publish --dry-run --access public
```

Public release to npm is handled by GitHub Actions:

```bash
git tag 3.0.5
git push origin 3.0.5
```

## Release Tags

Push a semantic version tag that exactly matches `package.json`:

```bash
git tag 3.0.5
git push origin 3.0.5
```

The GitHub release workflow always runs validation and package checks. Public
publishing runs only when the corresponding GitHub repository variables and
secrets are configured:

- `BUBBL_PUBLIC_REGISTRY_RELEASE=true` enables Maven Central, pub.dev, and npm.
- `BUBBL_COCOAPODS_TRUNK_RELEASE=true` enables CocoaPods trunk.
- `BUBBL_COCOAPODS_ALIAS_RELEASE=false` keeps the legacy `Bubbl-Sdk` alias off until ownership is confirmed.

Public registries are immutable. Do not rerun a lane tag for a version that has
already published successfully; bump the monorepo version instead.

## GitHub Actions Secrets

GitHub repository variables and secrets required for public releases:

| Variable | Used by |
| --- | --- |
| `BUBBL_PUBLIC_REGISTRY_RELEASE=true` | Enables publish lanes |
| `BUBBL_COCOAPODS_TRUNK_RELEASE=true` | CocoaPods trunk gate |
| `BUBBL_COCOAPODS_SOURCE_URL` | Public CocoaPods source mirror |
| `BUBBL_COCOAPODS_ALIAS_RELEASE=false` | Legacy alias gate |
| `MAVEN_CENTRAL_USERNAME` | Android |
| `MAVEN_CENTRAL_PASSWORD` | Android |
| `MAVEN_CENTRAL_SIGNING_KEY_B64` or `MAVEN_CENTRAL_SIGNING_KEY` | Android |
| `MAVEN_CENTRAL_SIGNING_PASSWORD` | Android |
| `COCOAPODS_TRUNK_TOKEN` | CocoaPods |
| `PUB_DEV_GOOGLE_SERVICE_ACCOUNT_KEY_B64` or `PUB_DEV_CREDENTIALS_B64` | Flutter |
| `NPM_TOKEN` | React Native |

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
