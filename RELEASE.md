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

Use a tag that exactly matches the root package version:

```bash
git tag 3.0.0
git push origin 3.0.0
```

The exact-match tag keeps the monorepo version matrix aligned from one release
event.

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
| `BUBBL_COCOAPODS_TRUNK_RELEASE=true` | Enables CocoaPods trunk publish only when the GitHub repository is public. This remains false for the private monorepo. |

The CocoaPods trunk job is separately guarded because trunk is for public specs.
For private iOS distribution, use the private Swift Package URL or push the
podspecs to a private specs repo with `pod repo push`.

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
| `COCOAPODS_TRUNK_TOKEN` | CocoaPods | Only needed if trunk publishing is intentionally enabled from a public repo. |
| `NPM_TOKEN` | React Native | Optional if npm trusted publishing is configured; otherwise required. |

## One-Time Registry Settings

- Maven Central: no new namespace verification if the existing account can
  publish `tech.bubbl.sdk`.
- CocoaPods: private source distribution should use the private GitHub repo
  directly via Swift Package Manager or a private CocoaPods specs repo. Do not
  enable trunk from the private monorepo.
- pub.dev: if public Flutter publishing is intended, enable automated
  publishing for the existing `bubbl_flutter_sdk` package from
  `bubbl-repo/renewed-sdk`, with tag pattern `{{version}}` and package
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

## Codemagic CocoaPods

`codemagic.yaml` contains `cocoapods-check` and `cocoapods-release` workflows.
Use the Codemagic variable group `cocoapods-release` for trunk credentials and
release gates. Details live in `docs/codemagic-cocoapods-release.md`.
