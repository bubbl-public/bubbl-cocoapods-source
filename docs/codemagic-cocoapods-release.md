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
that flag is true, because the alias depends on `BubblSDK 3.0.0` already being
available from trunk.

## Current Blockers

The checked-in `ios/BubblSDK.podspec` still points at the private GitLab repo:

```text
https://devops.bubbl.tech/bubbl/renewed-sdk.git
```

That URL is not anonymously readable, so public CocoaPods trunk consumers will not be able to resolve the pod from trunk yet. Before publishing publicly, either:

- use the public source mirror at `https://devops.bubbl.tech/bubbl-public/bubbl-cocoapods-source.git`, or
- use a private specs workflow instead of public trunk.

The public source mirror has a `3.0.0` tag. The local `BubblSDK` and
`Bubbl-Sdk` podspec lints already pass for `3.0.0`.
