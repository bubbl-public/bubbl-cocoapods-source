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

Required before public trunk publish:

```text
BUBBL_COCOAPODS_SOURCE_URL=https://public-readable-source-url.git
```

Codemagic uses this value to generate publish-ready podspecs under
`build/cocoapods/` before linting and pushing. The checked-in podspecs remain
unchanged.

Optional:

```text
BUBBL_COCOAPODS_ALIAS_RELEASE=false
BUBBL_COCOAPODS_REQUIRE_PUBLIC_SOURCE=true
```

Keep `BUBBL_COCOAPODS_ALIAS_RELEASE=false` until the legacy `Bubbl-Sdk` pod ownership is available to the same trunk account.

## Current Blockers

`ios/BubblSDK.podspec` currently points at:

```text
https://devops.bubbl.tech/bubbl/renewed-sdk.git
```

That URL is not anonymously readable, so public CocoaPods trunk consumers will not be able to resolve the pod from trunk yet. Before publishing publicly, either:

- mirror the release source/tag to a public readable repo/archive and update the podspec source, or
- use a private specs workflow instead of public trunk.

The local `BubblSDK` podspec lint already passes for `3.0.0`.
