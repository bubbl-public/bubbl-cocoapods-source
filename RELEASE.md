# Bubbl SDK v3 Release Configuration

The v3 monorepo publishes into the existing Bubbl package spaces. This avoids
new registry ownership verification and lets host apps upgrade by changing SDK
versions rather than package names.

## Public Package Identities

| Platform | Registry | Package identity | v3 source |
| --- | --- | --- | --- |
| Android | Maven Central | `tech.bubbl.sdk:bubbl-sdk` | `android/` |
| iOS | Swift Package / CocoaPods | `BubblSDK` | `ios/` |
| iOS legacy alias | CocoaPods | `Bubbl-Sdk` | `ios/Bubbl-Sdk.podspec` |
| Flutter | pub.dev | `bubbl_flutter_sdk` | `flutter/` |
| React Native | npm | `@bubbl-tech/react-native-sdk` | `react-native/` |

Already-published versions are immutable in the public registries. The release
flow reuses package identities but always publishes a new SemVer version.

## Release Tag

Use a tag that exactly matches the root package version:

```bash
git tag 3.0.0-beta.1
git push origin 3.0.0-beta.1
```

The exact-match tag keeps CocoaPods, Maven Central, pub.dev, npm, and the
monorepo version matrix aligned from one release event.

## GitHub Workflow

`.github/workflows/sdk-release.yml` runs the release gate and then:

- publishes Android to Maven Central through the Central Portal lane;
- tests iOS, builds `Bubbl.xcframework`, and uploads it as a workflow artifact;
- publishes `BubblSDK` and the `Bubbl-Sdk` compatibility alias to CocoaPods trunk;
- dry-runs Flutter publish, then publishes `bubbl_flutter_sdk` through pub.dev automated publishing;
- packs and publishes `@bubbl-tech/react-native-sdk` to npm.

Manual workflow dispatch is treated as a dry-run. Real publishing is tag-driven.

## Required GitHub Secrets

Use the same registry accounts and package ownership as the legacy SDK repos.

| Secret | Used by | Notes |
| --- | --- | --- |
| `MAVEN_CENTRAL_USERNAME` | Android | Existing Central Portal token username. |
| `MAVEN_CENTRAL_PASSWORD` | Android | Existing Central Portal token password. |
| `MAVEN_CENTRAL_SIGNING_KEY` | Android | ASCII-armored GPG private key. |
| `MAVEN_CENTRAL_SIGNING_KEY_B64` | Android | Optional base64 alternative to `MAVEN_CENTRAL_SIGNING_KEY`. |
| `MAVEN_CENTRAL_SIGNING_PASSWORD` | Android | GPG key passphrase. |
| `COCOAPODS_TRUNK_TOKEN` | CocoaPods | Existing Bubbl trunk owner token. |
| `NPM_TOKEN` | React Native | Optional if npm trusted publishing is configured; otherwise required. |

## One-Time Registry Settings

- Maven Central: no new namespace verification if the existing account can
  publish `tech.bubbl.sdk`.
- CocoaPods: no new pod claim if the existing trunk owner can publish
  `BubblSDK` and `Bubbl-Sdk`.
- pub.dev: enable automated publishing for the existing `bubbl_flutter_sdk`
  package from the new `bubbl-repo/renewed-sdk` repository, with tag pattern
  `{{version}}` and package directory `flutter`.
- npm: configure trusted publishing for `@bubbl-tech/react-native-sdk`, or add
  `NPM_TOKEN` to the GitHub repository secrets.

## Validation

```bash
npm run release:check
npm run readiness:strict
```

The release workflow also runs the contract, wrapper, React Native, Android,
iOS, Flutter, package dry-run, and registry configuration checks before any
publish step.
