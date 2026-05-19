# Bubbl SDK v3 Production Readiness

This is the release gate for moving v3 from beta candidate to a production SDK family.

## Current Verdict

**Beta-ready, not GA-ready yet.** Android, iOS, Flutter, and React Native now have native runtime wiring and strict local readiness can pass at `3.0.1`. The repo still needs staging/device canaries, CI proof against published artifacts, and final notification/location production polish before `3.0.1`.

The transport map is still correct for the current platform split:

- Transmission runtime: `POST /api/check-geofence`, `GET /api/check-push`, `GET /api/get-config`.
- Renewed Ingest service: `POST /api/device-registerd/create`, `POST /api/device-data`, `POST /api/geofence-data`, `POST /api/activities`, `POST /api/segments`, `POST /api/survey-response`.
- Default environment endpoints now use the renewed split hosts: `nightly.api|transmission|ingest.bubbl.tech`, `staging.api|transmission|ingest.bubbl.tech`, and production `api|transmission|ingest.bubbl.tech`.
- Public SDK distance remains meters; native clients convert to the current Transmission v2 `distance` wire unit at send time.

## Gates

### Beta Gate

Satisfied for `3.0.1`:

- Android and iOS native SDKs pass unit tests and local canaries.
- Flutter calls through to native Android/iOS cores, and React Native calls through to native Android/iOS cores instead of returning scaffold responses.
- Production readiness report exists in CI.
- Contracts, fixtures, native tests, and wrapper surface checks run from root scripts.
- Notification triggering remains enabled by default when configured, with host override paths documented.
- Location/geofence runtime has permission status helpers and lifecycle guidance.

### RC Gate

Must be true before `3.0.1-rc.1`:

- Staging canary apps prove backend ingest, Transmission runtime, Firebase/APNs token flow, notification delivery/open analytics, geofence enter/exit, offline queue retry, and diagnostics.
- Android Maven Central dry-run passes from the monorepo release workflow with signed artifacts and POM metadata.
- iOS SPM tag flow, XCFramework build, and CocoaPods compatibility specs pass in CI.
- Flutter `pub publish --dry-run` passes.
- React Native npm package build/typecheck passes.
- Migration guide covers old native SDK behavior and v3 replacement behavior.

### GA Gate

Must be true before `3.0.1`:

- At least one real Android and one real iOS host app integrate without SDK source patches.
- No strict production readiness blockers remain.
- Known limitations are documented as explicit post-GA follow-ups.
- Rollback plan exists for package releases and backend route compatibility.

## P0 Blockers

| Area | Status | Required work |
| --- | --- | --- |
| Flutter | Beta-ready | Android/iOS platform-channel bridge, host-app canaries, wrapper tests, and `pub publish --dry-run` pass. Still needs deeper event/serialization parity and staging-device proof before RC. |
| React Native | Beta-ready | Autolinked Android/iOS native modules call the native SDK cores, the TurboModule spec is present, wrapper validation covers both native sides, and npm package dry-run validation is available. Still needs generated TurboModule host canaries and staging-device proof before RC. |
| Android release | Configured | Maven Central Portal publishing now reuses `tech.bubbl.sdk:bubbl-sdk`. Still needs migrated secrets and a tag publish dry-run/proof from GitHub. |
| iOS release | Configured | SPM, `BubblSDK`, legacy `Bubbl-Sdk`, and XCFramework artifact flow are wired. Private repo distribution should use SPM or a private CocoaPods specs repo; public trunk is intentionally gated off for the private monorepo. |
| CI | Configured | CI and release workflows now run strict readiness plus registry configuration checks. Still needs the new monorepo to be pushed to GitHub with secrets/environments configured. |
| Notifications | Partially ready | Android rich image notifications, iOS media attachments, CTA action routing, default UI, and notification telemetry exist. Still needs durable cross-source frequency gates, permission helpers, and polished customization hooks. |
| Location | Needs hardening | Add foreground/background lifecycle switching, permission helpers, live movement canary evidence, and map overlay snapshots. |
| Backend staging | Needs proof | Run SDK canaries against renewed Ingest and Transmission services with real staging credentials and Firebase/APNs config. |

## P1 Production Work

- Add a version-bump script so Android, iOS, Flutter, React Native, contracts, fixtures, and canary metadata update together.
- Add typed failure events and stable error envelopes across native and wrapper SDKs.
- Add integration docs per platform with copy-paste setup.
- Add migration docs from old Android/iOS SDK methods to v3 methods.
- Add diagnostics redaction rules and queue retention policy docs.
- Add device matrix notes for Android API levels and iOS versions.

## Validation Commands

Local non-device checks:

```bash
npm run test:contracts
npm run test:wrappers
npm run test:android
npm run test:ios
npm run test:flutter
npm run test:rn
npm run readiness
```

Strict release gate:

```bash
npm run readiness:strict
```

Device/canary checks:

```bash
../sdk/bubbl-android-sdk/gradlew -p android connectedDebugAndroidTest
npm run test:ios-canary
flutter create --platforms=android --template=app /tmp/bubbl_flutter_canary
flutter create --platforms=ios --template=app /tmp/bubbl_flutter_ios_canary
cd react-native && npm pack --dry-run
```

## Release Order

1. Backend staging route/contract proof.
2. Android beta package.
3. iOS beta package.
4. Flutter beta wrapper.
5. React Native beta wrapper.
6. Canary host apps.
7. RC publish dry-runs.
8. `3.0.1` GA.
