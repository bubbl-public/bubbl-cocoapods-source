import Foundation
import UserNotifications

public final actor BubblClient {
    public static let shared = BubblClient()

    private let streamContinuation: AsyncStream<BubblEvent>.Continuation
    public let events: AsyncStream<BubblEvent>
    private let transport: any BubblHTTPTransport
    private let store: BubblPersistentStore
    private let notificationPresenter: any BubblNotificationPresenting
    private var config: BubblConfig?
    private var state: BubblStoredState?
    private var booted = false
    private var cachedConfiguration: BubblConfiguration?

    public init(
        storageDirectory: URL? = nil,
        transport: any BubblHTTPTransport = URLSessionBubblHTTPTransport(),
        notificationPresenter: any BubblNotificationPresenting = SystemBubblNotificationPresenter()
    ) {
        var continuation: AsyncStream<BubblEvent>.Continuation!
        self.events = AsyncStream { continuation = $0 }
        self.streamContinuation = continuation
        self.transport = transport
        self.store = BubblPersistentStore(directory: storageDirectory)
        self.notificationPresenter = notificationPresenter
    }

    public func boot(_ config: BubblConfig) async throws -> BubblBootResult {
        guard !config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw BubblError.invalidConfig("apiKey is required")
        }

        var storedState = try loadState()
        storedState.correlationId = config.correlationId ?? storedState.correlationId
        storedState.segments = config.segments
        try saveState(storedState)
        try saveConfig(config)

        self.config = config
        self.state = storedState
        self.booted = true
        self.cachedConfiguration = try cachedConfigurationFromDisk()

        try enqueue(
            path: BubblTransportMap.bootBatchPath,
            payload: deviceDataPayload(config: config, state: storedState, activity: "plugin_opened")
        )

        let result = BubblBootResult(
            ready: true,
            fromCache: cachedConfiguration != nil,
            deviceRegistered: false,
            requiresPermission: config.requiredPermissions,
            warnings: []
        )
        streamContinuation.yield(.ready)
        return result
    }

    public func shutdown() async {
        booted = false
        config = nil
    }

    public func refresh() async throws {
        _ = await getConfiguration()
        try await refreshPush()
    }

    public func refreshGeofence(_ location: BubblLocation) async throws {
        try await recordLocationUpdate(location)
        let activeConfig = try requireConfig()
        let activeState = try requireState()
        let payload: [String: Any] = [
            "latitude": String(location.latitude),
            "longitude": String(location.longitude),
            "distance": BubblTransportMap.transmissionDistanceMiles(publicDistanceMeters: activeConfig.defaultDistanceMeters),
            "segmentationTags": activeState.segments.joined(separator: ",")
        ]

        let data = try await sendRuntime(
            method: "POST",
            path: BubblTransportMap.refreshGeofencePath,
            body: jsonData(payload),
            cacheName: "geofence"
        )
        cachedConfiguration = try configuration(from: data)
        try await processGeofenceRuntime(data, location: location)
    }

    public func handleLocationUpdate(_ location: BubblLocation) async throws {
        try restoreRuntimeStateIfNeeded()
        try await refreshGeofence(location)
    }

    public func refreshPush() async throws {
        let data = try await sendRuntime(
            method: "GET",
            path: BubblTransportMap.refreshPushPath,
            body: nil,
            cacheName: "push"
        )
        cachedConfiguration = try configuration(from: data)
        await dispatchRuntimeNotifications(from: data)
    }

    public func getConfiguration() async -> BubblConfiguration? {
        do {
            let data = try await sendRuntime(
                method: "GET",
                path: BubblTransportMap.getConfigurationPath,
                body: nil,
                cacheName: "config"
            )
            let configuration = try configuration(from: data)
            cachedConfiguration = configuration
            return configuration
        } catch {
            streamContinuation.yield(.error(code: "runtime_configuration_failed", message: String(describing: error)))
            return cachedConfiguration ?? (try? cachedConfigurationFromDisk())
        }
    }

    public func getPrivacyText() async -> String { await getConfiguration()?.privacyText ?? "" }

    public func updateSegments(_ tags: [String]) async throws {
        let activeState = try requireState()
        var nextState = activeState
        nextState.segments = tags
        try saveState(nextState)

        try enqueue(path: BubblTransportMap.updateSegmentsPath, payload: [
            "device_registered_id": nextState.installId,
            "segmentation": tags
        ])
    }

    public func setCorrelationId(_ value: String) async throws {
        var activeState = try requireState()
        activeState.correlationId = value
        try saveState(activeState)
    }

    public func clearCorrelationId() async throws {
        var activeState = try requireState()
        activeState.correlationId = nil
        try saveState(activeState)
    }

    public func setDefaultNotificationModalEnabled(_ enabled: Bool) async throws {
        var nextConfig = try requireConfig()
        nextConfig.enableDefaultNotificationModal = enabled
        config = nextConfig
        try saveConfig(nextConfig)
    }

    public func setDefaultNotificationModalStyle(_ style: BubblNotificationModalStyle?) async throws {
        var nextConfig = try requireConfig()
        nextConfig.defaultNotificationModalStyle = style
        config = nextConfig
        try saveConfig(nextConfig)
    }

    public func defaultNotificationModalStyle() async -> BubblNotificationModalStyle {
        config?.defaultNotificationModalStyle ?? .default
    }

    public func registerPushToken(_ token: String) async throws {
        try restoreRuntimeStateIfNeeded()
        let activeConfig = try requireConfig()
        var activeState = try requireState()
        activeState.pushToken = token
        try saveState(activeState)

        try enqueue(path: BubblTransportMap.registerDevicePath, payload: deviceRegistrationPayload(config: activeConfig, state: activeState))
    }

    public func updateAPNsToken(_ token: Data) async throws {
        try await registerPushToken(token.map { String(format: "%02.2hhx", $0) }.joined())
        _ = await flush()
    }

    public func updateFCMToken(_ token: String) async throws {
        try await registerPushToken(token)
        _ = await flush()
    }

    public func handleRemoteNotification(_ userInfo: [AnyHashable: Any]) async throws -> BubblNotificationPayload? {
        try restoreRuntimeStateIfNeeded()
        guard let payload = BubblNotificationPayloadParser.fromRemoteNotification(userInfo, source: .apns) else {
            streamContinuation.yield(.error(code: "notification_payload_invalid", message: "Remote notification did not contain notification content."))
            return nil
        }

        _ = try await handleNotificationPayload(payload)
        return payload
    }

    public func handleFirebasePayload(_ payload: [String: String]) async throws -> BubblNotificationPayload? {
        try restoreRuntimeStateIfNeeded()
        guard let notification = BubblNotificationPayloadParser.fromFirebasePayload(payload) else {
            streamContinuation.yield(.error(code: "notification_payload_invalid", message: "Firebase payload did not contain notification content."))
            return nil
        }

        _ = try await handleNotificationPayload(notification)
        return notification
    }

    public func showNotification(_ payload: BubblNotificationPayload) async throws -> BubblNotificationDisplayResult {
        try await recordNotificationReceived(payload)
        do {
            let result = try await renderDefaultNotification(payload)
            await flushNotificationTelemetry()
            return result
        } catch {
            await flushNotificationTelemetry()
            throw error
        }
    }

    public func handleNotificationPayload(_ payload: BubblNotificationPayload) async throws -> BubblNotificationDisplayResult {
        let activeConfig = try requireConfig()
        try await recordNotificationReceived(payload)

        do {
            let result: BubblNotificationDisplayResult
            guard activeConfig.enablePushHandling else {
                result = BubblNotificationDisplayResult(displayed: false, reason: "push_handling_disabled")
                await flushNotificationTelemetry()
                return result
            }

            switch activeConfig.notificationRenderingMode {
            case .sdkDefault:
                result = try await renderDefaultNotification(payload)
            case .hostRendered:
                result = BubblNotificationDisplayResult(displayed: false, reason: "host_rendered")
            case .eventOnly:
                result = BubblNotificationDisplayResult(displayed: false, reason: "event_only")
            }

            await flushNotificationTelemetry()
            return result
        } catch {
            await flushNotificationTelemetry()
            throw error
        }
    }

    public func handleNotificationResponse(
        userInfo: [AnyHashable: Any],
        actionIdentifier: String? = nil
    ) async throws -> BubblNotificationPayload? {
        try restoreRuntimeStateIfNeeded()
        guard let payload = BubblNotificationPayloadParser.fromRemoteNotification(userInfo, source: .apns) else {
            streamContinuation.yield(.error(code: "notification_payload_invalid", message: "Notification response did not contain Bubbl notification content."))
            return nil
        }

        if actionIdentifier == UNNotificationDismissActionIdentifier {
            try await track(notificationInteractionEvent(payload, activity: "notification_dismissed"))
            return payload
        }

        let action = normalizedNotificationAction(actionIdentifier)
        try await handleNotificationOpen(payload, action: action)

        if let actionIdentifier,
           actionIdentifier != UNNotificationDefaultActionIdentifier,
           payload.cta != nil {
            try await handleNotificationCTA(payload, action: action)
        }

        return payload
    }

    public func handleNotificationResponse(_ response: UNNotificationResponse) async throws -> BubblNotificationPayload? {
        try await handleNotificationResponse(
            userInfo: response.notification.request.content.userInfo,
            actionIdentifier: response.actionIdentifier
        )
    }

    public func handleNotificationOpen(_ payload: BubblNotificationPayload, action: String? = nil) async throws {
        _ = try requireConfig()
        streamContinuation.yield(.notificationTapped(payload, action: action))
        try await track(notificationInteractionEvent(payload, activity: "notification_opened"))
    }

    public func openNotificationModal(_ payload: BubblNotificationPayload, action: String? = nil) async throws -> Bool {
        _ = try requireConfig()

        #if os(iOS)
        let presented = await BubblNotificationModalPresenter.present(payload, sdk: self)
        guard presented else {
            streamContinuation.yield(.error(code: "notification_modal_open_failed", message: "No foreground view controller was available."))
            return false
        }

        try await handleNotificationOpen(payload, action: action)
        return true
        #else
        streamContinuation.yield(.error(code: "notification_modal_open_failed", message: "Default notification modal is only available on iOS."))
        return false
        #endif
    }

    public func handleNotificationCTA(_ payload: BubblNotificationPayload, action: String? = nil) async throws {
        _ = try requireConfig()
        streamContinuation.yield(.notificationCtaTapped(payload, action: action ?? payload.cta?.action))
        try await track(notificationInteractionEvent(payload, activity: "notification_cta_tapped"))
        try? markGeofenceCTASuspended(payload)
    }

    public func handleNotificationMediaViewed(_ payload: BubblNotificationPayload) async throws {
        _ = try requireConfig()
        streamContinuation.yield(.notificationMediaViewed(payload))
        try await track(notificationInteractionEvent(payload, activity: "notification_media_viewed"))
    }

    public func handleNotificationSurveyRequested(_ payload: BubblNotificationPayload) async throws {
        _ = try requireConfig()
        streamContinuation.yield(.notificationSurveyRequested(payload))
        try await track(notificationInteractionEvent(payload, activity: "notification_survey_requested"))
    }

    public func track(_ event: BubblTrackEvent) async throws {
        let activeState = try requireState()
        guard let dashboardActivity = dashboardActivityName(event.activity) else {
            return
        }
        var payload: [String: Any] = [
            "device_registered_id": activeState.installId,
            "type": event.type,
            "activity": dashboardActivity,
            "time": isoNow()
        ]

        if let locationId = intString(event.locationId) {
            payload["location_id"] = locationId
        }
        if event.type == "notification" {
            guard let value = event.curatedNotificationId, let curatedNotificationId = Int(value) else {
                streamContinuation.yield(
                    .error(
                        code: "notification_missing_curated_id",
                        message: "Notification analytics require a Dashboard curated notification id."
                    )
                )
                return
            }
            payload["curated_notification_id"] = curatedNotificationId
        } else if let value = event.curatedNotificationId, let curatedNotificationId = Int(value) {
            payload["curated_notification_id"] = curatedNotificationId
        }
        if let latitude = event.latitude {
            payload["latitude"] = latitude
        }
        if let longitude = event.longitude {
            payload["longitude"] = longitude
        }

        try enqueue(path: BubblTransportMap.trackEventPath, payload: payload)
    }

    public func submitSurveyResponse(_ response: BubblSurveyResponse) async throws {
        let activeState = try requireState()
        var payload: [String: Any] = [
            "device_registered_id": activeState.installId,
            "activity": "survey_submit",
            "curated_notification_id": intString(response.curatedNotificationId) ?? response.curatedNotificationId,
            "responses": response.answers.map(surveyAnswerPayload),
            "time": isoNow()
        ]

        if let locationId = intString(response.locationId) {
            payload["location_id"] = locationId
        }

        try enqueue(path: BubblTransportMap.submitSurveyResponsePath, payload: payload)
    }

    public func flush() async -> BubblFlushResult {
        guard config != nil, state != nil else {
            return BubblFlushResult(pendingCount: (try? store.pendingCount()) ?? 0)
        }

        do {
            let queue = try store.loadQueue()
            var remaining: [BubblQueuedRequest] = []

            for var entry in queue {
                do {
                    try await sendIngest(entry)
                } catch {
                    entry.attempts += 1
                    remaining.append(entry)
                    streamContinuation.yield(.error(code: "ingest_flush_failed", message: String(describing: error)))
                }
            }

            try store.saveQueue(remaining)
            let result = BubblFlushResult(pendingCount: remaining.count)
            streamContinuation.yield(
                .diagnostic(
                    BubblDiagnostics(
                        booted: booted,
                        pendingIngestCount: remaining.count,
                        pushTokenSuffix: pushTokenSuffix(state?.pushToken)
                    )
                )
            )
            return result
        } catch {
            streamContinuation.yield(.error(code: "ingest_queue_failed", message: String(describing: error)))
            return BubblFlushResult(pendingCount: (try? store.pendingCount()) ?? 0)
        }
    }

    public func diagnostics() async -> BubblDiagnostics {
        let storedPushToken = state?.pushToken ?? (try? store.loadState())?.pushToken
        return BubblDiagnostics(
            booted: booted,
            pendingIngestCount: (try? store.pendingCount()) ?? 0,
            pushTokenSuffix: pushTokenSuffix(storedPushToken)
        )
    }

    @discardableResult
    public func restoreForBackground() throws -> Bool {
        if config != nil && state != nil {
            return true
        }

        guard let restoredConfig = try loadConfig() else {
            return false
        }

        config = restoredConfig
        state = try loadState()
        cachedConfiguration = try cachedConfigurationFromDisk()
        return true
    }

    private func pushTokenSuffix(_ token: String?) -> String? {
        guard let token = token?.trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty else {
            return nil
        }

        return String(token.suffix(7))
    }

    private func renderDefaultNotification(_ payload: BubblNotificationPayload) async throws -> BubblNotificationDisplayResult {
        let activeConfig = try requireConfig()
        guard activeConfig.enablePushHandling else {
            return BubblNotificationDisplayResult(displayed: false, reason: "push_handling_disabled")
        }

        let result = try await notificationPresenter.present(payload)
        if result.displayed {
            streamContinuation.yield(.notificationDisplayed(payload))
            try await track(notificationDeliveredEvent(payload))
        } else if result.reason != "duplicate_notification" {
            streamContinuation.yield(.error(code: "notification_display_failed", message: result.reason ?? "Notification display failed."))
        }

        return result
    }

    private func dispatchRuntimeNotifications(from data: Data) async {
        let payloads = BubblNotificationPayloadParser.fromRuntimeResponse(data)
        for payload in payloads {
            do {
                _ = try await handleNotificationPayload(payload)
            } catch {
                streamContinuation.yield(.error(code: "runtime_notification_failed", message: String(describing: error)))
            }
        }
    }

    private func recordLocationUpdate(_ location: BubblLocation) async throws {
        _ = try requireState()
        streamContinuation.yield(.locationUpdated(location))
        try await track(
            BubblTrackEvent(
                type: "location",
                activity: "location_update",
                latitude: location.latitude,
                longitude: location.longitude
            )
        )
    }

    private func recordNotificationReceived(_ payload: BubblNotificationPayload) async throws {
        streamContinuation.yield(.notificationReceived(payload))
        try await track(notificationSentEvent(payload))
    }

    private func flushNotificationTelemetry() async {
        _ = await flush()
    }

    private func processGeofenceRuntime(_ data: Data, location: BubblLocation) async throws {
        streamContinuation.yield(.geofenceSnapshot(BubblGeofenceEngine.snapshot(runtimeResponse: data)))

        let state = try loadGeofenceState()
        let evaluation = BubblGeofenceEngine.evaluate(
            runtimeResponse: data,
            location: location,
            state: state
        )
        try saveGeofenceState(evaluation.nextState)

        for transition in evaluation.transitions {
            switch transition.type {
            case .enter:
                streamContinuation.yield(.geofenceEntered(transition))
            case .exit:
                streamContinuation.yield(.geofenceExited(transition))
            }
            try await track(transitionEvent(transition))
        }

        for dispatch in evaluation.notifications {
            try enqueueGeofenceNotificationBatch(dispatch)
            do {
                _ = try await handleNotificationPayload(dispatch.payload)
            } catch {
                streamContinuation.yield(.error(code: "geofence_notification_failed", message: String(describing: error)))
            }
        }
    }

    private func enqueue(path: String, payload: [String: Any]) throws {
        let body = try jsonData(payload)
        try store.append(BubblQueuedRequest(path: path, body: body))
    }

    private func sendRuntime(method: String, path: String, body: Data?, cacheName: String) async throws -> Data {
        let activeConfig = try requireConfig()
        let activeState = try requireState()
        let request = BubblHTTPRequest(
            method: method,
            url: endpointURL(base: BubblTransportMap.transmissionBaseURL(activeConfig), path: path),
            headers: headers(authHeader: BubblTransportMap.runtimeAuthHeader, config: activeConfig, state: activeState),
            body: body
        )

        do {
            let response = try await transport.send(request)
            guard (200..<300).contains(response.statusCode) else {
                throw BubblError.invalidResponse("Runtime returned HTTP \(response.statusCode).")
            }
            try store.saveRuntimeCache(response.data, named: cacheName)
            return response.data
        } catch {
            if let cached = try? store.loadRuntimeCache(named: cacheName) {
                return cached
            }
            throw error
        }
    }

    private func sendIngest(_ entry: BubblQueuedRequest) async throws {
        let activeConfig = try requireConfig()
        let activeState = try requireState()
        var requestHeaders = headers(authHeader: BubblTransportMap.ingestAuthHeader, config: activeConfig, state: activeState)
        requestHeaders["Idempotency-Key"] = entry.idempotencyKey

        let request = BubblHTTPRequest(
            method: "POST",
            url: endpointURL(base: BubblTransportMap.ingestBaseURL(activeConfig), path: entry.path),
            headers: requestHeaders,
            body: entry.body
        )
        let response = try await transport.send(request)

        guard (200..<300).contains(response.statusCode) else {
            throw BubblError.invalidResponse("Ingest returned HTTP \(response.statusCode).")
        }
    }

    private func headers(authHeader: String, config: BubblConfig, state: BubblStoredState) -> [String: String] {
        [
            authHeader: config.apiKey,
            "Content-Type": "application/json",
            "Accept": "application/json",
            "X-Bubbl-SDK-Version": BubblTransportMap.sdkVersion,
            "X-Bubbl-SDK-Platform": BubblTransportMap.platform,
            "X-Bubbl-Request-ID": UUID().uuidString,
            "X-Bubbl-Install-ID": state.installId
        ]
    }

    private func requireConfig() throws -> BubblConfig {
        guard let config else {
            throw BubblError.notBooted
        }

        return config
    }

    private func requireState() throws -> BubblStoredState {
        guard let state else {
            throw BubblError.notBooted
        }

        return state
    }

    private func loadState() throws -> BubblStoredState {
        do {
            return try store.loadState()
        } catch {
            throw BubblError.storage(String(describing: error))
        }
    }

    private func saveState(_ nextState: BubblStoredState) throws {
        do {
            try store.saveState(nextState)
            state = nextState
        } catch {
            throw BubblError.storage(String(describing: error))
        }
    }

    private func loadConfig() throws -> BubblConfig? {
        do {
            return try store.loadConfig()
        } catch {
            throw BubblError.storage(String(describing: error))
        }
    }

    private func saveConfig(_ nextConfig: BubblConfig) throws {
        do {
            try store.saveConfig(nextConfig)
        } catch {
            throw BubblError.storage(String(describing: error))
        }
    }

    private func restoreRuntimeStateIfNeeded() throws {
        if config != nil && state != nil {
            return
        }

        guard try restoreForBackground() else {
            throw BubblError.notBooted
        }
    }

    private func cachedConfigurationFromDisk() throws -> BubblConfiguration? {
        for name in ["config", "geofence", "push"] {
            if let data = try store.loadRuntimeCache(named: name),
               let configuration = try? configuration(from: data) {
                return configuration
            }
        }

        return nil
    }

    func cachedGeofenceRuntimeResponseForMonitoring() -> Data? {
        try? store.loadRuntimeCache(named: "geofence")
    }

    private func loadGeofenceState() throws -> BubblGeofenceState {
        guard let data = try store.loadRuntimeCache(named: "geofence-state") else {
            return BubblGeofenceState()
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(BubblGeofenceState.self, from: data)) ?? BubblGeofenceState()
    }

    private func saveGeofenceState(_ state: BubblGeofenceState) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try store.saveRuntimeCache(try encoder.encode(state), named: "geofence-state")
    }

    private func markGeofenceCTASuspended(_ payload: BubblNotificationPayload) throws {
        guard let triggerKey = payload.raw[BubblGeofenceTriggerMetadata.triggerKey],
              !triggerKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              payload.raw[BubblGeofenceTriggerMetadata.ctaSuspend]?.isRuntimeTrue == true else {
            return
        }

        var state = try loadGeofenceState()
        guard !state.ctaSuspensions.contains(triggerKey) else { return }
        state.ctaSuspensions.insert(triggerKey)
        try saveGeofenceState(state)
    }

    private func configuration(from data: Data) throws -> BubblConfiguration {
        let envelope = try JSONDecoder().decode(RuntimeConfigurationEnvelope.self, from: data)
        return envelope.configuration
    }

    private func deviceRegistrationPayload(config: BubblConfig, state: BubblStoredState) -> [String: Any] {
        [
            "app_name": Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                ?? Bundle.main.bundleIdentifier
                ?? "Bubbl iOS App",
            "api_key": config.apiKey,
            "sdk_version": BubblTransportMap.sdkVersion,
            "platform": BubblTransportMap.platform,
            "os_version": ProcessInfo.processInfo.operatingSystemVersionString,
            "device_model": "Apple device",
            "device_name": "Apple device",
            "manufacturer": "Apple",
            "country": Locale.current.regionCode ?? "",
            "language": Locale.current.languageCode ?? "en",
            "device_id": state.installId,
            "segmentations": state.segments,
            "correlation_id": state.correlationId as Any,
            "bubbl_id": state.installId,
            "device_token": state.pushToken as Any
        ]
    }

    private func deviceDataPayload(config: BubblConfig, state: BubblStoredState, activity: String) -> [String: Any] {
        [
            "device_registered": deviceRegistrationPayload(config: config, state: state),
            "plugin_activity": [
                "device_registered_id": state.installId,
                "time": isoNow(),
                "activity": activity
            ],
            "raw_data": [
                "event": "boot",
                "request": [
                    "source": "sdk-v3",
                    "environment": config.environment.rawValue
                ]
            ]
        ]
    }

    private func surveyAnswerPayload(_ answer: BubblSurveyAnswer) -> [String: Any] {
        [
            "question_id": intString(answer.questionId) ?? answer.questionId,
            "type": answer.type,
            "value": answer.value as Any,
            "choice": answer.choiceIds.map { ["choice_id": intString($0) ?? $0] }
        ]
    }

    private func notificationDeliveredEvent(_ payload: BubblNotificationPayload) -> BubblTrackEvent {
        BubblTrackEvent(
            type: "notification",
            activity: "notification_delivered",
            locationId: payload.locationId,
            curatedNotificationId: payload.curatedNotificationId
        )
    }

    private func notificationSentEvent(_ payload: BubblNotificationPayload) -> BubblTrackEvent {
        BubblTrackEvent(
            type: "notification",
            activity: "notification_sent",
            locationId: payload.locationId,
            curatedNotificationId: payload.curatedNotificationId
        )
    }

    private func notificationInteractionEvent(_ payload: BubblNotificationPayload, activity: String) -> BubblTrackEvent {
        BubblTrackEvent(
            type: "notification",
            activity: activity,
            locationId: payload.locationId,
            curatedNotificationId: payload.curatedNotificationId
        )
    }

    private func transitionEvent(_ transition: BubblGeofenceTransition) -> BubblTrackEvent {
        BubblTrackEvent(
            type: "geofence",
            activity: transition.type == .enter ? "geofence_entry" : "geofence_exit",
            locationId: transition.locationId,
            latitude: transition.location.latitude,
            longitude: transition.location.longitude
        )
    }

    private func enqueueGeofenceNotificationBatch(_ dispatch: BubblGeofenceNotificationDispatch) throws {
        let activeState = try requireState()
        let transition = dispatch.transition
        let payload = dispatch.payload

        guard let notificationId = payload.curatedNotificationId.flatMap(Int.init),
              let locationId = Int(transition.locationId ?? payload.locationId ?? "") else {
            return
        }

        let time = isoNow()
        try enqueue(path: BubblTransportMap.trackGeofenceBatchPath, payload: [
            "geo": [
                "location_id": locationId,
                "device_registered_id": activeState.installId,
                "time": time,
                "activity": transition.type == .enter ? "geofence_entry" : "geofence_exit",
                "latitude": transition.location.latitude,
                "longitude": transition.location.longitude
            ],
            "location": [
                "device_registered_id": activeState.installId,
                "time": time,
                "activity": "location_update",
                "latitude": transition.location.latitude,
                "longitude": transition.location.longitude
            ],
            "notification": [
                "device_registered_id": activeState.installId,
                "time": time,
                "activity": "notification_sent",
                "curated_notification_id": notificationId,
                "allow": true
            ]
        ])
    }
}

private struct RuntimeConfigurationEnvelope: Decodable {
    let configuration: BubblConfiguration
}

private func jsonData(_ value: [String: Any]) throws -> Data {
    let normalized = normalizeJSON(value)

    guard JSONSerialization.isValidJSONObject(normalized) else {
        throw BubblError.invalidConfig("Payload could not be encoded as JSON.")
    }

    return try JSONSerialization.data(withJSONObject: normalized, options: [.sortedKeys])
}

private func normalizeJSON(_ value: Any) -> Any {
    let mirror = Mirror(reflecting: value)
    if mirror.displayStyle == .optional {
        guard let child = mirror.children.first else {
            return NSNull()
        }
        return normalizeJSON(child.value)
    }

    if let dictionary = value as? [String: Any] {
        return dictionary.reduce(into: [String: Any]()) { result, item in
            result[item.key] = normalizeJSON(item.value)
        }
    }

    if let array = value as? [Any] {
        return array.map(normalizeJSON)
    }

    return value
}

private func intString(_ value: String?) -> Any? {
    guard let value else { return nil }
    return Int(value) ?? value
}

private func dashboardActivityName(_ activity: String) -> String? {
    switch activity {
    case "notification_cta_tapped",
         "cta_engagement":
        return "cta_engagment"
    case "notification_media_viewed":
        return "media_viewed"
    case "notification_dismissed":
        return "dismissed"
    case "notification_opened":
        return "notification_opened"
    case "notification_survey_requested":
        return nil
    default:
        return activity
    }
}

private func endpointURL(base: URL, path: String) -> URL {
    let trimmedBase = base.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    return URL(string: trimmedBase + path)!
}

private func isoNow() -> String {
    ISO8601DateFormatter().string(from: Date())
}

private func normalizedNotificationAction(_ actionIdentifier: String?) -> String? {
    guard let actionIdentifier,
          actionIdentifier != UNNotificationDefaultActionIdentifier,
          actionIdentifier != UNNotificationDismissActionIdentifier else {
        return nil
    }

    return actionIdentifier
}

private extension String {
    var isRuntimeTrue: Bool {
        self == "1"
            || caseInsensitiveCompare("true") == .orderedSame
            || caseInsensitiveCompare("yes") == .orderedSame
    }
}
