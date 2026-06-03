# Bubbl Flutter Wrapper Smoke App

This is a tiny Flutter host app that consumes the local SDK wrapper:

```yaml
bubbl_flutter_sdk:
  path: ../../flutter
```

It proves the app-level integration path, not a live staging runtime. The screen
includes buttons for the core wrapper calls: boot, diagnostics, track,
notification handling, flush, and SDK event listening.

## Local Builds

From the repository root, publish the local Android core to Maven local first,
because the Flutter Android plugin depends on
`tech.bubbl.sdk:bubbl-sdk:3.1.3`:

```sh
../sdk/bubbl-android-sdk/gradlew -p android publishToMavenLocal
```

Then build the app from this directory:

```sh
cd examples/flutter-wrapper
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
flutter build ios --simulator --no-codesign
```

Or run the repository canary:

```sh
npm run test:flutter-wrapper
```

The iOS Podfile pins `BubblSDK` to the local `../../../ios` pod so the wrapper
build does not need a published CocoaPods release.
