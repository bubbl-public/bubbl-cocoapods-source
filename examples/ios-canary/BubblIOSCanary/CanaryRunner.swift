import BubblSDK
import Foundation

struct CanaryReport: Equatable {
    let summary: String
    let steps: [CanaryStep]
}

struct CanaryRunner {
    func run() async throws -> CanaryReport {
        CanaryURLProtocol.reset()

        let storageDirectory = try freshStorageDirectory()
        let transport = URLSessionBubblHTTPTransport(session: canaryURLSession())
        let firstSDK = BubblClient(storageDirectory: storageDirectory, transport: transport)
        let config = BubblConfig(
            apiKey: "canary-api-key",
            runtimeBaseUrl: URL(string: "https://canary-runtime.bubbl.local")!,
            ingestBaseUrl: URL(string: "https://canary-ingest.bubbl.local")!,
            segments: ["canary", "ios"],
            enablePushHandling: false,
            enableLocationTracking: false,
            logLevel: .debug
        )

        var steps: [CanaryStep] = []

        let boot = try await firstSDK.boot(config)
        try expect(boot.ready, "Boot returned ready")
        var diagnostics = await firstSDK.diagnostics()
        try expect(diagnostics.pendingIngestCount == 1, "Boot queued one ingest request")
        steps.append(
            CanaryStep(
                title: "Boot queued device ingest",
                detail: "Pending ingest count after boot: \(diagnostics.pendingIngestCount).",
                accessibilityIdentifier: "canary-step-boot"
            )
        )

        try await firstSDK.setCorrelationId("canary-correlation")
        try await firstSDK.registerPushToken("canary-push-token")
        try await firstSDK.track(
            BubblTrackEvent(
                type: "activity",
                activity: "canary_tap",
                locationId: "42",
                curatedNotificationId: "84",
                latitude: 51.5072,
                longitude: -0.1276
            )
        )
        diagnostics = await firstSDK.diagnostics()
        try expect(diagnostics.pendingIngestCount == 3, "Push token and track requests were queued")
        steps.append(
            CanaryStep(
                title: "Track and token queued",
                detail: "Pending ingest count after push token registration and track: \(diagnostics.pendingIngestCount).",
                accessibilityIdentifier: "canary-step-track"
            )
        )

        CanaryURLProtocol.setRuntimeAvailable(true)
        let liveConfiguration = try await unwrap(firstSDK.getConfiguration(), "Expected live runtime configuration")
        try expect(liveConfiguration.privacyText == "Canary privacy text", "Live config privacy text matched")
        CanaryURLProtocol.setRuntimeAvailable(false)
        let cachedConfiguration = try await unwrap(firstSDK.getConfiguration(), "Expected cached runtime configuration")
        try expect(cachedConfiguration == liveConfiguration, "Cached config fallback matched live response")
        steps.append(
            CanaryStep(
                title: "Runtime cache fallback",
                detail: "Config fetched through URLSession, then returned from cache while runtime was offline.",
                accessibilityIdentifier: "canary-step-cache-fallback"
            )
        )

        CanaryURLProtocol.setRuntimeAvailable(true)
        let monitor = await MainActor.run { BubblLocationMonitor(sdk: firstSDK) }
        try await monitor.handleRegionWake(
            location: BubblLocation(latitude: 51.50158, longitude: -0.141)
        )
        diagnostics = await firstSDK.diagnostics()
        try expect(diagnostics.pendingIngestCount == 6, "Region wake should queue location, geofence, and notification telemetry")
        steps.append(
            CanaryStep(
                title: "Region wake routed geofence",
                detail: "BubblLocationMonitor routed a region wake through /api/check-geofence and queued telemetry.",
                accessibilityIdentifier: "canary-step-region-wake"
            )
        )

        CanaryURLProtocol.setIngestStatusCode(500)
        let failedFlush = await firstSDK.flush()
        try expect(failedFlush.pendingCount == 6, "Failed flush kept all ingest requests queued")
        steps.append(
            CanaryStep(
                title: "Failed flush retained queue",
                detail: "Pending ingest count after HTTP 500 flush: \(failedFlush.pendingCount).",
                accessibilityIdentifier: "canary-step-failed-flush"
            )
        )

        await firstSDK.shutdown()

        let secondSDK = BubblClient(storageDirectory: storageDirectory, transport: transport)
        _ = try await secondSDK.boot(config)
        diagnostics = await secondSDK.diagnostics()
        try expect(diagnostics.pendingIngestCount == 7, "Second SDK restored SQLite queue and added boot ingest")
        steps.append(
            CanaryStep(
                title: "SQLite queue restored",
                detail: "Second SDK instance saw \(diagnostics.pendingIngestCount) queued requests before retry.",
                accessibilityIdentifier: "canary-step-sqlite-restore"
            )
        )

        CanaryURLProtocol.setIngestStatusCode(200)
        let successfulRetry = await secondSDK.flush()
        try expect(successfulRetry.pendingCount == 0, "Successful retry cleared ingest queue")
        steps.append(
            CanaryStep(
                title: "Retry cleared queue",
                detail: "Pending ingest count after retry: \(successfulRetry.pendingCount).",
                accessibilityIdentifier: "canary-step-retry-cleared"
            )
        )

        let requests = CanaryURLProtocol.requestRecords()
        try assertTransportShape(requests)
        steps.append(
            CanaryStep(
                title: "Transport map verified",
                detail: "Observed /api/device-data, /api/device-registerd/create, /api/activities, and /api/get-config.",
                accessibilityIdentifier: "canary-step-transport-map"
            )
        )

        try assertKeychainStateRestored(in: requests)
        steps.append(
            CanaryStep(
                title: "Keychain state restored",
                detail: "Second SDK boot reused install ID, correlation ID, and push token from secure state.",
                accessibilityIdentifier: "canary-step-keychain-restore"
            )
        )

        diagnostics = await secondSDK.diagnostics()
        steps.append(
            CanaryStep(
                title: "Diagnostics visible",
                detail: "booted=\(diagnostics.booted), pendingIngestCount=\(diagnostics.pendingIngestCount), sdkVersion=\(diagnostics.sdkVersion).",
                accessibilityIdentifier: "canary-step-diagnostics"
            )
        )

        return CanaryReport(
            summary: "iOS canary exercised URLSession transport, Keychain state, SQLite ingest durability, retry, and runtime cache fallback.",
            steps: steps
        )
    }

    private func canaryURLSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CanaryURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func freshStorageDirectory() throws -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let directory = base
            .appendingPathComponent("BubblIOSCanary", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func assertTransportShape(_ requests: [CanaryRequestRecord]) throws {
        let paths = Set(requests.map(\.path))
        try expect(paths.contains("/api/get-config"), "Runtime config path was not requested")
        try expect(paths.contains("/api/check-geofence"), "Runtime geofence path was not requested")
        try expect(paths.contains("/api/device-data"), "Device-data ingest path was not requested")
        try expect(paths.contains("/api/device-registerd/create"), "Device registration ingest path was not requested")
        try expect(paths.contains("/api/activities"), "Activity ingest path was not requested")
        try expect(paths.contains("/api/geofence-data"), "Geofence ingest path was not requested")

        let ingestRequests = requests.filter { $0.host == "canary-ingest.bubbl.local" }
        try expect(!ingestRequests.isEmpty, "No ingest requests were captured")
        for request in ingestRequests {
            try expect(request.headers["ApiKey"] == "canary-api-key", "Ingest request was missing ApiKey")
            try expect(request.headers["X-Bubbl-SDK-Version"] == "3.1.5", "Ingest request was missing SDK version")
            try expect(request.headers["X-Bubbl-SDK-Platform"] == "ios", "Ingest request was missing SDK platform")
            try expect(request.headers["X-Bubbl-Install-ID"]?.isEmpty == false, "Ingest request was missing install ID")
        }
    }

    private func assertKeychainStateRestored(in requests: [CanaryRequestRecord]) throws {
        let deviceDataRequests = requests.filter { $0.path == "/api/device-data" }
        try expect(deviceDataRequests.count >= 2, "Expected at least two device-data requests")

        let firstInstallId = try installId(from: deviceDataRequests[0])
        let restoredInstallId = try installId(from: deviceDataRequests[deviceDataRequests.count - 1])
        try expect(firstInstallId == restoredInstallId, "Install ID did not persist across SDK instances")

        let restoredDevice = try deviceRegistered(from: deviceDataRequests[deviceDataRequests.count - 1])
        try expect(restoredDevice["correlation_id"] as? String == "canary-correlation", "Correlation ID did not restore")
        try expect(restoredDevice["device_token"] as? String == "canary-push-token", "Push token did not restore")
    }

    private func installId(from request: CanaryRequestRecord) throws -> String {
        let device = try deviceRegistered(from: request)
        return try unwrap(device["device_id"] as? String, "Expected device_id in device_registered payload")
    }

    private func deviceRegistered(from request: CanaryRequestRecord) throws -> [String: Any] {
        let body = try unwrap(request.body, "Expected body for \(request.path)")
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        let payload = try unwrap(json, "Expected JSON object for \(request.path)")
        return try unwrap(payload["device_registered"] as? [String: Any], "Expected device_registered payload")
    }
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else {
        throw CanaryFailure(message)
    }
}

private func unwrap<T>(_ value: T?, _ message: String) throws -> T {
    guard let value else {
        throw CanaryFailure(message)
    }
    return value
}

struct CanaryFailure: Error, CustomStringConvertible, Equatable {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}
