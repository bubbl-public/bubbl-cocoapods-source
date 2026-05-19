# Codemagic CocoaPods Release

This repo contains two Codemagic workflows:

- `cocoapods-check`: validates the iOS SDK and lints the CocoaPods specs.
- `cocoapods-release`: runs the same checks, then publishes to CocoaPods trunk on a tag build when release gates are enabled.

## Codemagic Variable Group

Create a Codemagic environment variable group named `cocoapods-release`.

Required for trunk publishing:

```text
COCOAPODS_TRUNK_TOKEN=...
BUBBL_PUBLIC_REGISTRY_RELEASE=true
BUBBL_COCOAPODS_TRUNK_RELEASE=true
```

Public trunk source URL:

```text
BUBBL_COCOAPODS_SOURCE_URL=https://devops.bubbl.tech/bubbl-public/bubbl-cocoapods-source.git
```

This is also the default in `scripts/cocoapods-publish.sh`. Codemagic uses this
value to generate publish-ready podspecs under `build/cocoapods/` before
linting and pushing. The checked-in podspecs remain unchanged.

Optional:

```text
BUBBL_COCOAPODS_ALIAS_RELEASE=false
BUBBL_COCOAPODS_REQUIRE_PUBLIC_SOURCE=true
```

Keep `BUBBL_COCOAPODS_ALIAS_RELEASE=false` until the legacy `Bubbl-Sdk` pod ownership is available to the same trunk account.
With the public source URL set, the check workflow only lints `Bubbl-Sdk` when
that flag is true, because the alias depends on the matching `BubblSDK` version
already being available from trunk.

## Current Blockers

The checked-in `ios/BubblSDK.podspec` still points at the private GitLab repo:

```text
https://devops.bubbl.tech/bubbl/renewed-sdk.git
```

That URL is not anonymously readable, so public CocoaPods trunk consumers will not be able to resolve the pod from trunk yet. Before publishing publicly, either:

- use the public source mirror at `https://devops.bubbl.tech/bubbl-public/bubbl-cocoapods-source.git`, or
- use a private specs workflow instead of public trunk.

The public source mirror must have a matching `v<version>` tag, for example
`v3.0.1`. The generated publish podspec uses that source tag while keeping
`s.version` as `3.0.1`.

## GitLab Trigger

GitLab tag pipelines trigger the Codemagic `cocoapods-release` workflow through
the Codemagic Builds API. Add these protected, masked GitLab CI variables to
`bubbl/renewed-sdk`:

```text
CODEMAGIC_API_TOKEN=...
CODEMAGIC_APP_ID=...
```

`CODEMAGIC_WORKFLOW_ID` defaults to `cocoapods-release` in `.gitlab-ci.yml`.
The bridge job only runs for `v`-prefixed SemVer tags. A pushed GitLab tag such
as `v3.0.1` starts the matching CocoaPods release build on Codemagic. Codemagic
strips the leading `v`, verifies `package.json` is `3.0.1`, and publishes
`BubblSDK 3.0.1`.
