# iOS SDK Codemagic release

Codemagic runs the iOS SDK-only release workflow for these tags:

- `ios-X.Y.Z`
- `cm-ios-sdk-X.Y.Z`

The tag version must match `package.json`.

The workflow runs:

- SDK contract and wrapper validation
- production readiness checks
- Swift package tests
- XCFramework build
- CocoaPods spec lint
- CocoaPods trunk publish when `BUBBL_PUBLIC_REGISTRY_RELEASE=true` and `BUBBL_COCOAPODS_TRUNK_RELEASE=true`

For CocoaPods publish, the generated podspec source tag is the exact Codemagic tag, so `ios-X.Y.Z` and `cm-ios-sdk-X.Y.Z` can be used without also creating a bare `X.Y.Z` tag.
