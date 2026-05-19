# Bubbl iOS Canary

This canary app depends on the local `../../ios` Swift Package and proves the v3 iOS SDK inside a simulator app runtime.

The canary flow covers:

- `boot(config)` queues renewed Ingest service telemetry.
- `track(event)` and push-token registration enqueue durable ingest.
- `getConfiguration()` uses URLSession, writes runtime cache, and falls back to cache when runtime goes offline.
- Failed ingest flush leaves the SQLite queue intact.
- A second SDK instance restores the SQLite queue and Keychain-backed state.
- A successful retry clears the ingest queue and reports diagnostics.
- `BubblLocationMonitor.handleRegionWake(location:)` routes a region wake through `/api/check-geofence` and queues geofence telemetry.

Run it with:

```sh
./run-canary.sh
```
