# Bubbl iOS SDK v3

The Swift package product is `BubblSDK`. The main public client type is `BubblClient` to avoid a Swift module/type name collision during library-evolution and XCFramework builds.

```swift
import BubblSDK

let sdk = BubblClient.shared

try await sdk.boot(
    BubblConfig(apiKey: "...")
)
```

Default environment endpoints mirror the legacy SDKs: `.development` and
`.nightly` use nightly, `.staging` uses staging, and `.production` uses
`https://production.api.bubbl.tech` for Transmission plus
`https://platform.bubbl.tech` for Dashboard ingest. Public
`defaultDistanceMeters` remains meters; the Swift transport converts it to the
current Transmission v2 wire distance unit before calling `/api/check-geofence`.

Release packaging:

- Swift Package is the primary integration path.
- `BubblSDK.podspec` provides transitional CocoaPods compatibility for private specs repos.
- `../scripts/build-ios-xcframework.sh` builds `ios/build/Bubbl.xcframework` from the Swift package.
