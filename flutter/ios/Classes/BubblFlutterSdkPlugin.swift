import Flutter
import Foundation
import BubblSDK
import UIKit

#if canImport(CoreLocation)
import CoreLocation
#endif

public final class BubblFlutterSdkPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
    private let sdk = BubblClient.shared
    private var eventSink: FlutterEventSink?
    private var eventTask: Task<Void, Never>?

    #if canImport(CoreLocation)
    @MainActor private lazy var locationMonitor = BubblLocationMonitor(sdk: sdk)
    #endif

    public static func register(with registrar: FlutterPluginRegistrar) {
        Task { @MainActor in
            BubblNotificationCenterDelegate.installDefault()
        }

        let instance = BubblFlutterSdkPlugin()
        let methodChannel = FlutterMethodChannel(
            name: "tech.bubbl.sdk/flutter/methods",
            binaryMessenger: registrar.messenger()
        )
        let eventChannel = FlutterEventChannel(
            name: "tech.bubbl.sdk/flutter/events",
            binaryMessenger: registrar.messenger()
        )

        registrar.addMethodCallDelegate(instance, channel: methodChannel)
        registrar.addApplicationDelegate(instance)
        eventChannel.setStreamHandler(instance)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        Task {
            do {
                let value = try await handleAsync(call)
                await MainActor.run { result(value) }
            } catch let error as BubblFlutterPluginError {
                await MainActor.run {
                    result(FlutterError(code: error.code, message: error.message, details: nil))
                }
            } catch {
                await MainActor.run {
                    result(FlutterError(code: "bubbl_error", message: String(describing: error), details: nil))
                }
            }
        }
    }

    public func onListen(
        withArguments arguments: Any?,
        eventSink events: @escaping FlutterEventSink
    ) -> FlutterError? {
        eventSink = events
        eventTask?.cancel()
        eventTask = Task { [sdk] in
            let stream = await sdk.events
            for await event in stream {
                await MainActor.run {
                    events(event.flutterMap())
                }
            }
        }
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventTask?.cancel()
        eventTask = nil
        eventSink = nil
        return nil
    }

    private func handleAsync(_ call: FlutterMethodCall) async throws -> Any? {
        switch call.method {
        case "boot":
            let config = try call.argumentsMap().bubblConfig()
            let bootResult = try await sdk.boot(config)
            if config.enablePushHandling {
                await MainActor.run {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
            return bootResult.flutterMap()
        case "shutdown":
            await sdk.shutdown()
            return nil
        case "startLocationTracking":
            #if canImport(CoreLocation)
            await MainActor.run { locationMonitor.start() }
            #endif
            return nil
        case "stopLocationTracking":
            #if canImport(CoreLocation)
            await MainActor.run { locationMonitor.stop() }
            #endif
            return nil
        case "refresh":
            try await sdk.refresh()
            return nil
        case "refreshGeofence":
            try await sdk.refreshGeofence(call.argumentsMap().bubblLocation())
            return nil
        case "handleLocationUpdate":
            try await sdk.handleLocationUpdate(call.argumentsMap().bubblLocation())
            return nil
        case "refreshPush":
            try await sdk.refreshPush()
            return nil
        case "getConfiguration":
            return await sdk.getConfiguration()?.flutterMap()
        case "getPrivacyText":
            return await sdk.getPrivacyText()
        case "updateSegments":
            try await sdk.updateSegments(call.argumentsMap().stringArray("tags"))
            return nil
        case "setCorrelationId":
            try await sdk.setCorrelationId(call.argumentsMap().requiredString("value"))
            return nil
        case "clearCorrelationId":
            try await sdk.clearCorrelationId()
            return nil
        case "setDefaultNotificationModalEnabled":
            try await sdk.setDefaultNotificationModalEnabled(call.argumentsMap().bool("enabled", default: true))
            return nil
        case "registerPushToken":
            try await sdk.registerPushToken(call.argumentsMap().requiredString("token"))
            return nil
        case "handleFirebasePayload":
            let payload = try call.argumentsMap().map("payload") ?? [:]
            return try await sdk.handleFirebasePayload(payload.mapValues { String(describing: $0) })?.flutterMap()
        case "showNotification":
            return try await sdk.showNotification(call.argumentsMap().notificationPayload()).flutterMap()
        case "handleNotificationPayload":
            return try await sdk.handleNotificationPayload(call.argumentsMap().notificationPayload()).flutterMap()
        case "handleNotificationOpen":
            let args = try call.argumentsMap()
            try await sdk.handleNotificationOpen(args.payloadArgument(), action: args.string("action"))
            return nil
        case "openNotificationModal":
            let args = try call.argumentsMap()
            return try await sdk.openNotificationModal(args.payloadArgument(), action: args.string("action"))
        case "handleNotificationCta":
            let args = try call.argumentsMap()
            try await sdk.handleNotificationCTA(args.payloadArgument(), action: args.string("action"))
            return nil
        case "handleNotificationMediaViewed":
            try await sdk.handleNotificationMediaViewed(call.argumentsMap().notificationPayload())
            return nil
        case "handleNotificationSurveyRequested":
            try await sdk.handleNotificationSurveyRequested(call.argumentsMap().notificationPayload())
            return nil
        case "track":
            try await sdk.track(call.argumentsMap().trackEvent())
            return nil
        case "submitSurveyResponse":
            try await sdk.submitSurveyResponse(call.argumentsMap().surveyResponse())
            return nil
        case "flush":
            return await sdk.flush().flutterMap()
        case "diagnostics":
            var diagnostics = await sdk.diagnostics()
            diagnostics.platform = "flutter"
            return diagnostics.flutterMap()
        default:
            throw BubblFlutterPluginError(code: "not_implemented", message: "Unknown Bubbl Flutter method: \(call.method)")
        }
    }

    public func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task {
            try? await sdk.updateAPNsToken(deviceToken)
        }
    }

    public func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        // Hosts can still observe APNs registration failures from their app delegate.
    }

    public func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) -> Bool {
        Task {
            let payload = try? await sdk.handleRemoteNotification(userInfo)
            completionHandler(payload == nil ? .noData : .newData)
        }
        return true
    }
}

private struct BubblFlutterPluginError: Error {
    let code: String
    let message: String
}

private extension FlutterMethodCall {
    func argumentsMap() throws -> [String: Any] {
        if let map = arguments as? [String: Any] {
            return map
        }
        if arguments == nil {
            return [:]
        }
        throw BubblFlutterPluginError(code: "invalid_argument", message: "Expected map arguments.")
    }
}

private extension Dictionary where Key == String, Value == Any {
    func requiredString(_ key: String) throws -> String {
        guard let value = self[key] as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw BubblFlutterPluginError(code: "invalid_argument", message: "\(key) is required.")
        }
        return value
    }

    func string(_ key: String) -> String? {
        self[key] as? String
    }

    func bool(_ key: String, default defaultValue: Bool) -> Bool {
        self[key] as? Bool ?? defaultValue
    }

    func int(_ key: String, default defaultValue: Int) -> Int {
        (self[key] as? NSNumber)?.intValue ?? defaultValue
    }

    func double(_ key: String) -> Double {
        (self[key] as? NSNumber)?.doubleValue ?? 0
    }

    func optionalDouble(_ key: String) -> Double? {
        (self[key] as? NSNumber)?.doubleValue
    }

    func stringArray(_ key: String) -> [String] {
        (self[key] as? [Any] ?? []).map { String(describing: $0) }
    }

    func map(_ key: String) -> [String: Any]? {
        self[key] as? [String: Any]
    }

    func mapArray(_ key: String) -> [[String: Any]] {
        self[key] as? [[String: Any]] ?? []
    }

    func bubblConfig() throws -> BubblConfig {
        BubblConfig(
            apiKey: try requiredString("apiKey"),
            environment: BubblEnvironment(rawValue: string("environment") ?? "staging") ?? .staging,
            runtimeBaseUrl: string("runtimeBaseUrl").flatMap(URL.init(string:)),
            transmissionBaseUrl: string("transmissionBaseUrl").flatMap(URL.init(string:)),
            ingestBaseUrl: string("ingestBaseUrl").flatMap(URL.init(string:)),
            segments: stringArray("segments"),
            correlationId: string("correlationId"),
            defaultDistanceMeters: int("defaultDistanceMeters", default: 10),
            refreshIntervalSeconds: int("refreshIntervalSeconds", default: 300),
            enablePushHandling: bool("enablePushHandling", default: true),
            enableLocationTracking: bool("enableLocationTracking", default: false),
            notificationRenderingMode: BubblNotificationRenderingMode(rawValue: string("notificationRenderingMode") ?? "sdkDefault") ?? .sdkDefault,
            enableDefaultNotificationModal: bool("enableDefaultNotificationModal", default: true),
            enableDefaultSurveyUi: bool("enableDefaultSurveyUi", default: true),
            logLevel: BubblLogLevel(rawValue: string("logLevel") ?? "warn") ?? .warn
        )
    }

    func bubblLocation() -> BubblLocation {
        BubblLocation(latitude: double("latitude"), longitude: double("longitude"))
    }

    func trackEvent() throws -> BubblTrackEvent {
        BubblTrackEvent(
            type: try requiredString("type"),
            activity: try requiredString("activity"),
            locationId: string("locationId"),
            curatedNotificationId: string("curatedNotificationId"),
            latitude: optionalDouble("latitude"),
            longitude: optionalDouble("longitude")
        )
    }

    func surveyResponse() throws -> BubblSurveyResponse {
        BubblSurveyResponse(
            curatedNotificationId: try requiredString("curatedNotificationId"),
            locationId: string("locationId"),
            answers: try mapArray("answers").map { try $0.surveyAnswer() }
        )
    }

    func surveyAnswer() throws -> BubblSurveyAnswer {
        BubblSurveyAnswer(
            questionId: try requiredString("questionId"),
            type: try requiredString("type"),
            value: string("value"),
            choiceIds: stringArray("choiceIds")
        )
    }

    func payloadArgument() throws -> BubblNotificationPayload {
        if let payload = map("payload") {
            return try payload.notificationPayload()
        }
        return try notificationPayload()
    }

    func notificationPayload() throws -> BubblNotificationPayload {
        BubblNotificationPayload(
            id: try requiredString("id"),
            title: try requiredString("title"),
            body: try requiredString("body"),
            source: BubblNotificationSource(rawValue: string("source") ?? "manual") ?? .manual,
            locationId: string("locationId"),
            curatedNotificationId: string("curatedNotificationId"),
            correlationId: string("correlationId"),
            media: try map("media")?.notificationMedia(),
            cta: try map("cta")?.notificationCTA(),
            survey: try map("survey")?.notificationSurvey(),
            raw: map("raw")?.mapValues { String(describing: $0) } ?? [:]
        )
    }

    func notificationMedia() throws -> BubblNotificationMedia {
        guard let url = URL(string: try requiredString("url")) else {
            throw BubblFlutterPluginError(code: "invalid_argument", message: "media.url is invalid.")
        }
        return BubblNotificationMedia(url: url, type: string("type"), altText: string("altText"))
    }

    func notificationCTA() throws -> BubblNotificationCTA {
        BubblNotificationCTA(
            label: try requiredString("label"),
            url: string("url").flatMap(URL.init(string:)),
            action: string("action")
        )
    }

    func notificationSurvey() throws -> BubblNotificationSurvey {
        BubblNotificationSurvey(questions: try mapArray("questions").map { try $0.surveyQuestion() })
    }

    func surveyQuestion() throws -> BubblSurveyQuestion {
        BubblSurveyQuestion(
            id: try requiredString("id"),
            title: try requiredString("title"),
            type: try requiredString("type"),
            choices: try mapArray("choices").map { try $0.surveyChoice() }
        )
    }

    func surveyChoice() throws -> BubblSurveyChoice {
        BubblSurveyChoice(id: try requiredString("id"), label: try requiredString("label"))
    }
}

private extension BubblBootResult {
    func flutterMap() -> [String: Any] {
        [
            "ready": ready,
            "fromCache": fromCache,
            "deviceRegistered": deviceRegistered,
            "requiresPermission": requiresPermission,
            "warnings": warnings
        ]
    }
}

private extension BubblConfiguration {
    func flutterMap() -> [String: Any] {
        [
            "notificationsCount": notificationsCount,
            "daysCount": daysCount,
            "batteryCount": batteryCount,
            "privacyText": privacyText
        ]
    }
}

private extension BubblDiagnostics {
    func flutterMap() -> [String: Any] {
        [
            "sdkVersion": sdkVersion,
            "platform": platform,
            "booted": booted,
            "pendingIngestCount": pendingIngestCount,
            "pushTokenSuffix": pushTokenSuffix
        ]
    }
}

private extension BubblFlushResult {
    func flutterMap() -> [String: Any] {
        ["pendingCount": pendingCount]
    }
}

private extension BubblNotificationDisplayResult {
    func flutterMap() -> [String: Any?] {
        ["displayed": displayed, "reason": reason]
    }
}

private extension BubblLocation {
    func flutterMap() -> [String: Any] {
        ["latitude": latitude, "longitude": longitude]
    }
}

private extension BubblGeofenceTransition {
    func flutterMap() -> [String: Any?] {
        [
            "type": type.rawValue,
            "campaignId": campaignId,
            "locationId": locationId,
            "location": location.flutterMap()
        ]
    }
}

private extension BubblGeofenceVertex {
    func flutterMap() -> [String: Any] {
        ["latitude": latitude, "longitude": longitude]
    }
}

private extension BubblGeofencePolygon {
    func flutterMap() -> [String: Any?] {
        [
            "campaignId": campaignId,
            "campaignName": campaignName,
            "locationId": locationId,
            "vertices": vertices.map { $0.flutterMap() }
        ]
    }
}

private extension BubblGeofenceCircle {
    func flutterMap() -> [String: Any?] {
        [
            "campaignId": campaignId,
            "campaignName": campaignName,
            "locationId": locationId,
            "center": center.flutterMap(),
            "radiusMeters": radiusMeters
        ]
    }
}

private extension BubblGeofenceSnapshot {
    func flutterMap() -> [String: Any] {
        [
            "stats": [
                "campaignsTotal": stats.campaignsTotal,
                "polygonsTotal": stats.polygonsTotal
            ],
            "polygons": polygons.map { $0.flutterMap() },
            "circles": circles.map { $0.flutterMap() }
        ]
    }
}

private extension BubblNotificationPayload {
    func flutterMap() -> [String: Any?] {
        [
            "id": id,
            "title": title,
            "body": body,
            "source": source.rawValue,
            "locationId": locationId,
            "curatedNotificationId": curatedNotificationId,
            "correlationId": correlationId,
            "media": media?.flutterMap(),
            "cta": cta?.flutterMap(),
            "survey": survey?.flutterMap(),
            "raw": raw
        ]
    }
}

private extension BubblNotificationMedia {
    func flutterMap() -> [String: Any?] {
        ["url": url.absoluteString, "type": type, "altText": altText]
    }
}

private extension BubblNotificationCTA {
    func flutterMap() -> [String: Any?] {
        ["label": label, "url": url?.absoluteString, "action": action]
    }
}

private extension BubblNotificationSurvey {
    func flutterMap() -> [String: Any] {
        ["questions": questions.map { $0.flutterMap() }]
    }
}

private extension BubblSurveyQuestion {
    func flutterMap() -> [String: Any] {
        ["id": id, "title": title, "type": type, "choices": choices.map { $0.flutterMap() }]
    }
}

private extension BubblSurveyChoice {
    func flutterMap() -> [String: Any] {
        ["id": id, "label": label]
    }
}

private extension BubblEvent {
    func flutterMap() -> [String: Any?] {
        switch self {
        case .ready:
            return ["type": "ready"]
        case .diagnostic(var diagnostics):
            diagnostics.platform = "flutter"
            return ["type": "diagnostic", "diagnostics": diagnostics.flutterMap()]
        case .notificationReceived(let payload):
            return ["type": "notificationReceived", "payload": payload.flutterMap()]
        case .notificationDisplayed(let payload):
            return ["type": "notificationDisplayed", "payload": payload.flutterMap()]
        case .notificationTapped(let payload, let action):
            return ["type": "notificationTapped", "payload": payload.flutterMap(), "action": action]
        case .notificationCtaTapped(let payload, let action):
            return ["type": "notificationCtaTapped", "payload": payload.flutterMap(), "action": action]
        case .notificationMediaViewed(let payload):
            return ["type": "notificationMediaViewed", "payload": payload.flutterMap()]
        case .notificationSurveyRequested(let payload):
            return ["type": "notificationSurveyRequested", "payload": payload.flutterMap()]
        case .locationUpdated(let location):
            return ["type": "locationUpdated", "location": location.flutterMap()]
        case .geofenceSnapshot(let snapshot):
            return ["type": "geofenceSnapshot", "snapshot": snapshot.flutterMap()]
        case .geofenceEntered(let transition):
            return ["type": "geofenceEntered", "transition": transition.flutterMap()]
        case .geofenceExited(let transition):
            return ["type": "geofenceExited", "transition": transition.flutterMap()]
        case .error(let code, let message):
            return ["type": "error", "code": code, "message": message]
        }
    }
}
