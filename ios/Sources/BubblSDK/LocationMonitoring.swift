import Foundation

#if canImport(CoreLocation)
import CoreLocation

@MainActor
public final class BubblLocationMonitor: NSObject, @preconcurrency CLLocationManagerDelegate {
    private let sdk: BubblClient
    private let manager: CLLocationManager
    private var useSignificantChanges = true
    private var isTracking = false
    private var monitoredCandidates: [String: BubblGeofenceRegionCandidate] = [:]

    public init(
        sdk: BubblClient = .shared,
        manager: CLLocationManager = CLLocationManager()
    ) {
        self.sdk = sdk
        self.manager = manager
        super.init()
        self.manager.delegate = self
        self.manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        self.manager.distanceFilter = 50
    }

    public func requestWhenInUseAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    public func requestAlwaysAuthorization() {
        manager.requestAlwaysAuthorization()
    }

    public func start(useSignificantChanges: Bool = true, allowsBackgroundUpdates: Bool = true) {
        self.useSignificantChanges = useSignificantChanges
        self.isTracking = true

        #if os(iOS)
        manager.allowsBackgroundLocationUpdates = allowsBackgroundUpdates
        manager.pausesLocationUpdatesAutomatically = true
        #endif

        if useSignificantChanges {
            manager.startMonitoringSignificantLocationChanges()
        } else {
            manager.startUpdatingLocation()
        }

        Task {
            _ = try? await sdk.restoreForBackground()
            await refreshBackgroundRegions()
        }
    }

    public func stop() {
        isTracking = false
        if useSignificantChanges {
            manager.stopMonitoringSignificantLocationChanges()
        } else {
            manager.stopUpdatingLocation()
        }
        stopBackgroundRegionMonitoring()
    }

    public func refreshBackgroundRegions(
        near location: BubblLocation? = nil,
        limit: Int = 20
    ) async {
        guard let data = await sdk.cachedGeofenceRuntimeResponseForMonitoring() else {
            return
        }

        refreshBackgroundRegions(from: data, near: location, limit: limit)
    }

    public func refreshBackgroundRegions(
        from runtimeResponse: Data,
        near location: BubblLocation? = nil,
        limit: Int = 20
    ) {
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else {
            return
        }

        let referenceLocation = location ?? manager.location.map {
            BubblLocation(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)
        }
        let candidates = BubblGeofenceEngine.nearestRegionCandidates(
            runtimeResponse: runtimeResponse,
            near: referenceLocation,
            limit: limit
        )
        applyBackgroundRegions(candidates)
    }

    public func stopBackgroundRegionMonitoring() {
        for region in manager.monitoredRegions where region.identifier.hasPrefix(Self.regionIdentifierPrefix) {
            manager.stopMonitoring(for: region)
        }
        monitoredCandidates = [:]
    }

    public func resumeForBackgroundLocationLaunch(
        useSignificantChanges: Bool = true,
        allowsBackgroundUpdates: Bool = true
    ) async {
        guard (try? await sdk.restoreForBackground()) == true else {
            return
        }

        start(
            useSignificantChanges: useSignificantChanges,
            allowsBackgroundUpdates: allowsBackgroundUpdates
        )
        await refreshBackgroundRegions()

        if let location = manager.location {
            try? await handleRegionWake(
                location: BubblLocation(
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude
                )
            )
            return
        }

        manager.requestLocation()
    }

    public func handleRegionWake(location: BubblLocation) async throws {
        try await sdk.handleLocationUpdate(location)
        await refreshBackgroundRegions(near: location)
    }

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let bubblLocation = BubblLocation(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        )

        Task {
            do {
                try await handleRegionWake(location: bubblLocation)
            } catch {
                // Host apps can observe SDK errors from the event stream; CoreLocation callbacks should not throw.
            }
        }
    }

    public func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        handleRegionTransition(region)
    }

    public func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        handleRegionTransition(region)
    }

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Host apps can observe SDK errors from the event stream; CoreLocation callbacks should not throw.
    }

    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard isTracking else { return }

        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            Task {
                await refreshBackgroundRegions()
            }
        default:
            break
        }
    }

    private func applyBackgroundRegions(_ candidates: [BubblGeofenceRegionCandidate]) {
        let selected = Dictionary(uniqueKeysWithValues: candidates.map { ($0.identifier, $0) })
        let selectedIdentifiers = Set(selected.keys)

        for region in manager.monitoredRegions where region.identifier.hasPrefix(Self.regionIdentifierPrefix) {
            if !selectedIdentifiers.contains(region.identifier) {
                manager.stopMonitoring(for: region)
            }
        }

        let existingIdentifiers = Set(
            manager.monitoredRegions
                .filter { $0.identifier.hasPrefix(Self.regionIdentifierPrefix) }
                .map(\.identifier)
        )

        for candidate in candidates where !existingIdentifiers.contains(candidate.identifier) {
            guard let region = circularRegion(for: candidate) else { continue }
            manager.startMonitoring(for: region)
        }

        monitoredCandidates = selected
    }

    private func circularRegion(for candidate: BubblGeofenceRegionCandidate) -> CLCircularRegion? {
        let coordinate = CLLocationCoordinate2D(
            latitude: candidate.center.latitude,
            longitude: candidate.center.longitude
        )
        guard CLLocationCoordinate2DIsValid(coordinate) else {
            return nil
        }

        let maximumDistance = manager.maximumRegionMonitoringDistance
        let cappedRadius = maximumDistance > 0
            ? min(candidate.radiusMeters, maximumDistance)
            : candidate.radiusMeters
        let radius = max(1, cappedRadius)
        let region = CLCircularRegion(
            center: coordinate,
            radius: radius,
            identifier: candidate.identifier
        )
        region.notifyOnEntry = true
        region.notifyOnExit = true
        return region
    }

    private func handleRegionTransition(_ region: CLRegion) {
        guard region.identifier.hasPrefix(Self.regionIdentifierPrefix) else {
            return
        }

        if let bubblLocation = wakeLocation(for: region) {
            Task {
                try? await handleRegionWake(location: bubblLocation)
            }
            return
        }

        manager.requestLocation()
    }

    private func wakeLocation(for region: CLRegion) -> BubblLocation? {
        if let location = manager.location,
           abs(location.timestamp.timeIntervalSinceNow) <= Self.maximumLocationAgeSeconds {
            return BubblLocation(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude
            )
        }

        return monitoredCandidates[region.identifier]?.center
    }

    private static let regionIdentifierPrefix = "tech.bubbl.sdk.geofence."
    private static let maximumLocationAgeSeconds: TimeInterval = 120
}
#endif
