# Bubbl SDK v3 Canary Apps

Canary apps live here and prove each SDK package inside a real application runtime.

Available apps:

- `ios-canary`: SwiftUI app wired to the local `../ios` Swift Package with UI tests for URLSession transport, Keychain state, SQLite queue durability, retry, cache fallback, and diagnostics.
- `flutter-wrapper`: Flutter host app wired to the local `../flutter` plugin with Android/iOS builds proving the wrapper can be consumed by a real app.

Planned apps:

- `android-native`
- `react-native`

Each canary should prove boot, config, geofence refresh, push token forwarding, events, segments, survey response, offline flush, tenant switch, and diagnostics against staging.
