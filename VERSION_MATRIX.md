# Bubbl SDK Version Matrix

| Release | Android | iOS | Flutter | React Native | Runtime Contract | Dashboard Ingest |
| --- | --- | --- | --- | --- | --- | --- |
| `4.0.0` | `4.0.0` | `4.0.0` | `4.0.0` | `4.0.0` | `sdk-runtime-legacy-v1` | `legacy-mirrored-v1` |
| `3.1.6` | `3.1.6` | `3.1.6` | `3.1.6` | `3.1.6` | `sdk-runtime-legacy-v1` | `legacy-mirrored-v1` |
| `3.1.5` | `3.1.5` | `3.1.5` | `3.1.5` | `3.1.5` | `sdk-runtime-legacy-v1` | `legacy-mirrored-v1` |
| `3.1.4` | `3.1.4` | `3.1.4` | `3.1.4` | `3.1.4` | `sdk-runtime-legacy-v1` | `legacy-mirrored-v1` |
| `3.1.2` | `3.1.2` | `3.1.2` | `3.1.2` | `3.1.2` | `sdk-runtime-legacy-v1` | `legacy-mirrored-v1` |
| `3.0.6` | `3.0.6` | `3.0.6` | `3.0.6` | `3.0.6` | `sdk-runtime-legacy-v1` | `legacy-mirrored-v1` |
| `3.0.5` | `3.0.5` | `3.0.5` | `3.0.5` | `3.0.5` | `sdk-runtime-legacy-v1` | `legacy-mirrored-v1` |

## Package Identities

| Platform | Registry package |
| --- | --- |
| Android | `tech.bubbl.sdk:bubbl-sdk` |
| iOS | `BubblSDK` plus legacy CocoaPods alias `Bubbl-Sdk` |
| Flutter | `bubbl_flutter_sdk` |
| React Native | `@bubblsdk/react-native-sdk` |

## Rules

- Native SDKs release before wrapper SDKs.
- Wrapper SDKs pin to known native SDK versions.
- v3 reuses the existing public package identities; published versions are never overwritten.
- Flutter uses native Android/iOS SDK cores through platform channels.
- React Native uses native Android/iOS SDK cores through autolinked native modules plus the TurboModule spec.
- Patch releases must not change required wire fields.
- Minor releases may add optional fields.
- Major releases may remove legacy adapters.
