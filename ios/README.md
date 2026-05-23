# Bubbl iOS SDK v3

The Swift package product is `BubblSDK`. The main public client type is `BubblClient` to avoid a Swift module/type name collision during library-evolution and XCFramework builds.

```swift
import BubblSDK

let sdk = BubblClient.shared

try await sdk.boot(
    BubblConfig(apiKey: "...")
)
```

Apps with custom notification UI can keep SDK device notification handling on
and disable only bundled modal/detail presentation with
`enableDefaultNotificationModal: false` at boot or
`try await sdk.setDefaultNotificationModalEnabled(false)` after boot.

Apps with an in-app notification inbox/history can present the bundled detail
UI for a stored payload with `try await sdk.openNotificationModal(payload)`.
That opens the default modal without posting another device notification.

Default environment endpoints follow the renewed split hosts: `.development`
and `.staging` use `staging.*`, and `.production` uses
`https://transmission.bubbl.tech` for Transmission plus
`https://ingest.bubbl.tech` for ingest. Public
`defaultDistanceMeters` remains meters; the Swift transport converts it to the
current Transmission v2 wire distance unit before calling `/api/check-geofence`.

Release packaging:

- Swift Package is the primary integration path.
- `BubblSDK.podspec` provides transitional CocoaPods compatibility for private specs repos.
- `../scripts/build-ios-xcframework.sh` builds `ios/build/Bubbl.xcframework` from the Swift package.
