# Bubbl SDK v3 Release Configuration

The `renewed-sdk` GitHub repository is private. It is the source of truth for
the v3 monorepo, CI, and release artifacts.

By default, a version tag only runs validation, package dry-runs, and artifact
creation. Publishing into public registries is deliberately opt-in so a private
source repo cannot accidentally expose package contents.

## Package Identities

| Platform | Distribution | Package identity | v3 source |
| --- | --- | --- | --- |
| Android | Maven Central, opt-in | `tech.bubbl.sdk:bubbl-sdk` | `android/` |
| iOS | Private Swift Package / private CocoaPods specs | `BubblSDK` | `ios/` |
| iOS legacy alias | Private CocoaPods specs | `Bubbl-Sdk` | `ios/Bubbl-Sdk.podspec` |
| Flutter | pub.dev, opt-in | `bubbl_flutter_sdk` | `flutter/` |
| React Native | npm, opt-in | `@bubblsdk/react-native-sdk` | `react-native/` |

Already-published versions are immutable in registries. The release flow reuses
package identities but always publishes a new SemVer version.

Important: public registry packages expose their packaged artifacts. For
Flutter and React Native that means the published package includes source files.
Keep `BUBBL_PUBLIC_REGISTRY_RELEASE` unset unless that exposure is intended.

## Release Tag

Use a version tag that exactly matches the root package version:

```bash
git tag v3.0.4
git push origin v3.0.4
```

Tag pushes run the full release workflow. The default publish target is `all`,
so a public registry release publishes Android, Flutter, and React Native when
`BUBBL_PUBLIC_REGISTRY_RELEASE=true`. CocoaPods trunk remains separately gated.

## GitHub Workflow

`.github/workflows/sdk-release.yml` always:

- runs the release gate;
- tests Android and publishes the Android artifact to Maven local;
- tests iOS, builds `Bubbl.xcframework`, and uploads it as a workflow artifact;
- lints `BubblSDK` and the `Bubbl-Sdk` compatibility podspecs locally;
- analyzes/tests/dry-runs the Flutter package;
- packs and dry-runs the React Native npm package.

Manual workflow dispatch is also a dry-run.

Real public publishing only runs on tag pushes when the repository variable
`BUBBL_PUBLIC_REGISTRY_RELEASE` is set to `true`.

## Public Registry Opt-In

Set these GitHub repository variables only for an intentional public registry
release:

| Variable | Meaning |
| --- | --- |
| `BUBBL_PUBLIC_REGISTRY_RELEASE=true` | Enables Maven Central, pub.dev, and npm publish jobs on tag pushes. |
| `BUBBL_COCOAPODS_TRUNK_RELEASE=true` | Enables CocoaPods trunk publish when the podspec source URL points at a publicly readable repo and tag. |
| `BUBBL_COCOAPODS_SOURCE_URL` | Public git URL used inside the generated podspecs. Use the public CocoaPods source mirror, not the private monorepo. |
| `BUBBL_COCOAPODS_ALIAS_RELEASE=true` | Also publishes the legacy `Bubbl-Sdk` alias after ownership is confirmed. Keep false until then. |

The CocoaPods trunk job is separately guarded because trunk is for public specs.
The workflow may live in the private monorepo, but the generated podspecs must
reference a public source URL and tag.

## Required GitHub Secrets

Use the same registry accounts and package ownership as the legacy SDK repos
when public registry release is enabled.

| Secret | Used by | Notes |
| --- | --- | --- |
| `MAVEN_CENTRAL_USERNAME` | Android | Existing Central Portal token username. |
| `MAVEN_CENTRAL_PASSWORD` | Android | Existing Central Portal token password. |
| `MAVEN_CENTRAL_SIGNING_KEY` | Android | ASCII-armored GPG private key. |
| `MAVEN_CENTRAL_SIGNING_KEY_B64` | Android | Optional base64 alternative to `MAVEN_CENTRAL_SIGNING_KEY`. |
| `MAVEN_CENTRAL_SIGNING_PASSWORD` | Android | GPG key passphrase. |
| `COCOAPODS_TRUNK_TOKEN` | CocoaPods | Only needed if trunk publishing is intentionally enabled. |
| `NPM_TOKEN` | React Native | Optional if npm trusted publishing is configured; otherwise required. |

## One-Time Registry Settings

- Maven Central: no new namespace verification if the existing account can
  publish `tech.bubbl.sdk`.
- CocoaPods: trunk publishing uses generated podspecs whose source points at
  the public CocoaPods source mirror. Private source distribution can still use
  the private GitHub repo directly via Swift Package Manager or a private
  CocoaPods specs repo.
- pub.dev: if public Flutter publishing is intended, enable automated
  publishing for the existing `bubbl_flutter_sdk` package from
  `bubbl-platform/renewed-sdk`, with tag pattern `{{version}}` and package
  directory `flutter`.
- npm: configure trusted publishing for `@bubblsdk/react-native-sdk`, or add
  `NPM_TOKEN` to the GitHub repository secrets. npm provenance is not generated
  from private GitHub repositories.

## Validation

```bash
npm run release:check
npm run readiness:strict
```

The release workflow also runs the contract, wrapper, React Native, Android,
iOS, Flutter, package dry-run, and registry configuration checks before any
publish step.
