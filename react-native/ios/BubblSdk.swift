import Foundation
import React
import BubblSDK
import UIKit

#if canImport(CoreLocation)
import CoreLocation
#endif

@objc(BubblSdk)
final class BubblSdk: RCTEventEmitter {
    private let sdk = BubblClient.shared
    private var eventTask: Task<Void, Never>?

    #if canImport(CoreLocation)
    @MainActor private lazy var locationMonitor = BubblLocationMonitor(sdk: sdk)
    #endif

    override static func requiresMainQueueSetup() -> Bool {
        false
    }

    override init() {
        super.init()
        Task { @MainActor in
            BubblNotificationCenterDelegate.installDefault()
        }
    }

    override func supportedEvents() -> [String]! {
        [Self.eventName]
    }

    override func startObserving() {
        eventTask?.cancel()
        eventTask = Task { [sdk] in
            let stream = await sdk.events
            for await event in stream {
                await MainActor.run {
                    self.sendEvent(withName: Self.eventName, body: event.reactMap())
                }
            }
        }
    }

    override func stopObserving() {
        eventTask?.cancel()
        eventTask = nil
    }

    @objc(boot:resolver:rejecter:)
    func boot(
        _ config: NSDictionary,
        resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        resolveAsync(resolve, reject) {
            try await self.sdk.boot(try config.swiftMap.bubblConfig()).reactMap()
        }
    }

    @objc(shutdown:rejecter:)
    func shutdown(
        _ resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        resolveAsync(resolve, reject) {
            await self.sdk.shutdown()
            return nil
        }
    }

    @objc(startLocationTracking:rejecter:)
    func startLocationTracking(
        _ resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        Task {
            #if canImport(CoreLocation)
            await MainActor.run { self.locationMonitor.start() }
            #endif
            resolve(NSNull())
        }
    }

    @objc(stopLocationTracking:rejecter:)
    func stopLocationTracking(
        _ resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        Task {
            #if canImport(CoreLocation)
            await MainActor.run { self.locationMonitor.stop() }
            #endif
            resolve(NSNull())
        }
    }

    @objc(refresh:rejecter:)
    func refresh(
        _ resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        resolveAsync(resolve, reject) {
            try await self.sdk.refresh()
            return nil
        }
    }

    @objc(refreshGeofence:longitude:resolver:rejecter:)
    func refreshGeofence(
        _ latitude: Double,
        longitude: Double,
        resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        resolveAsync(resolve, reject) {
            let location = BubblLocation(latitude: latitude, longitude: longitude)
            try await self.sdk.refreshGeofence(location)
            #if canImport(CoreLocation)
            await self.locationMonitor.refreshBackgroundRegions(near: location)
            #endif
            return nil
        }
    }

    @objc(handleLocationUpdate:longitude:resolver:rejecter:)
    func handleLocationUpdate(
        _ latitude: Double,
        longitude: Double,
        resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        resolveAsync(resolve, reject) {
            let location = BubblLocation(latitude: latitude, longitude: longitude)
            try await self.sdk.handleLocationUpdate(location)
            #if canImport(CoreLocation)
            await self.locationMonitor.refreshBackgroundRegions(near: location)
            #endif
            return nil
        }
    }

    @objc(refreshPush:rejecter:)
    func refreshPush(
        _ resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        resolveAsync(resolve, reject) {
            try await self.sdk.refreshPush()
            return nil
        }
    }

    @objc(getConfiguration:rejecter:)
    func getConfiguration(
        _ resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        resolveAsync(resolve, reject) {
            await self.sdk.getConfiguration()?.reactMap()
        }
    }

    @objc(getPrivacyText:rejecter:)
    func getPrivacyText(
        _ resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        resolveAsync(resolve, reject) {
            await self.sdk.getPrivacyText()
        }
    }

    @objc(updateSegments:resolver:rejecter:)
    func updateSegments(
        _ tags: NSArray,
        resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        resolveAsync(resolve, reject) {
            try await self.sdk.updateSegments(tags.compactMap { $0 as? String })
            return nil
        }
    }

    @objc(setCorrelationId:resolver:rejecter:)
    func setCorrelationId(
        _ value: NSString,
        resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        resolveAsync(resolve, reject) {
            try await self.sdk.setCorrelationId(value as String)
            return nil
        }
    }

    @objc(clearCorrelationId:rejecter:)
    func clearCorrelationId(
        _ resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        resolveAsync(resolve, reject) {
            try await self.sdk.clearCorrelationId()
            return nil
        }
    }

    @objc(setDefaultNotificationModalEnabled:resolver:rejecter:)
    func setDefaultNotificationModalEnabled(
        _ enabled: Bool,
        resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        resolveAsync(resolve, reject) {
            try await self.sdk.setDefaultNotificationModalEnabled(enabled)
            return nil
        }
    }

    @objc(setDefaultNotificationModalStyle:resolver:rejecter:)
    func setDefaultNotificationModalStyle(
        _ style: NSDictionary?,
        resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        resolveAsync(resolve, reject) {
            try await self.sdk.setDefaultNotificationModalStyle(try style?.swiftMap.notificationModalStyle())
            return nil
        }
    }

    @objc(registerPushToken:resolver:rejecter:)
    func registerPushToken(
        _ token: NSString,
        resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        resolveAsync(resolve, reject) {
            try await self.sdk.registerPushToken(token as String)
            return nil
        }
    }

    @objc(handleFirebasePayload:resolver:rejecter:)
    func handleFirebasePayload(
        _ payload: NSDictionary,
        resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        resolveAsync(resolve, reject) {
            try await self.sdk.handleFirebasePayload(payload.swiftMap.mapValues { String(describing: $0) })?.reactMap()
        }
    }

    @objc(showNotification:resolver:rejecter:)
    func showNotification(
        _ payload: NSDictionary,
        resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        resolveAsync(resolve, reject) {
            try await self.sdk.showNotification(try payload.swiftMap.notificationPayload()).reactMap()
        }
    }

    @objc(handleNotificationPayload:resolver:rejecter:)
    func handleNotificationPayload(
        _ payload: NSDictionary,
        resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        resolveAsync(resolve, reject) {
            try await self.sdk.handleNotificationPayload(try payload.swiftMap.notificationPayload()).reactMap()
        }
    }

    @objc(handleNotificationOpen:action:resolver:rejecter:)
    func handleNotificationOpen(
        _ payload: NSDictionary,
        action: NSString?,
        resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        resolveAsync(resolve, reject) {
            try await self.sdk.handleNotificationOpen(try payload.swiftMap.notificationPayload(), action: action as String?)
            return nil
        }
    }

    @objc(openNotificationModal:action:resolver:rejecter:)
    func openNotificationModal(
        _ payload: NSDictionary,
        action: NSString?,
        resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        resolveAsync(resolve, reject) {
            try await self.sdk.openNotificationModal(try payload.swiftMap.notificationPayload(), action: action as String?)
        }
    }

    @objc(handleNotificationCta:action:resolver:rejecter:)
    func handleNotificationCta(
        _ payload: NSDictionary,
        action: NSString?,
        resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        resolveAsync(resolve, reject) {
            try await self.sdk.handleNotificationCTA(try payload.swiftMap.notificationPayload(), action: action as String?)
            return nil
        }
    }

    @objc(handleNotificationMediaViewed:resolver:rejecter:)
    func handleNotificationMediaViewed(
        _ payload: NSDictionary,
        resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        resolveAsync(resolve, reject) {
            try await self.sdk.handleNotificationMediaViewed(try payload.swiftMap.notificationPayload())
            return nil
        }
    }

    @objc(handleNotificationSurveyRequested:resolver:rejecter:)
    func handleNotificationSurveyRequested(
        _ payload: NSDictionary,
        resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        resolveAsync(resolve, reject) {
            try await self.sdk.handleNotificationSurveyRequested(try payload.swiftMap.notificationPayload())
            return nil
        }
    }

    @objc(track:resolver:rejecter:)
    func track(
        _ event: NSDictionary,
        resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        resolveAsync(resolve, reject) {
            try await self.sdk.track(try event.swiftMap.trackEvent())
            return nil
        }
    }

    @objc(submitSurveyResponse:resolver:rejecter:)
    func submitSurveyResponse(
        _ response: NSDictionary,
        resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        resolveAsync(resolve, reject) {
            try await self.sdk.submitSurveyResponse(try response.swiftMap.surveyResponse())
            return nil
        }
    }

    @objc(flush:rejecter:)
    func flush(
        _ resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        resolveAsync(resolve, reject) {
            await self.sdk.flush().reactMap()
        }
    }

    @objc(diagnostics:rejecter:)
    func diagnostics(
        _ resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        resolveAsync(resolve, reject) {
            var diagnostics = await self.sdk.diagnostics()
            diagnostics.platform = "react-native"
            return diagnostics.reactMap()
        }
    }

    private func resolveAsync(
        _ resolve: @escaping RCTPromiseResolveBlock,
        _ reject: @escaping RCTPromiseRejectBlock,
        _ body: @escaping () async throws -> Any?
    ) {
        Task {
            do {
                resolve(try await body() ?? NSNull())
            } catch let error as BubblReactNativeError {
                reject(error.code, error.message, error)
            } catch {
                reject("bubbl_error", String(describing: error), error)
            }
        }
    }

    private static let eventName = "BubblSdkEvent"
}

@objc(BubblSdkLocationLaunchHandler)
public final class BubblSdkLocationLaunchHandler: NSObject {
    #if canImport(CoreLocation)
    @MainActor private static let locationMonitor = BubblLocationMonitor(sdk: .shared)
    #endif

    @objc(handleLaunchOptions:)
    public static func handleLaunchOptions(_ launchOptions: NSDictionary?) -> Bool {
        let launchedForLocation = launchOptions?[UIApplication.LaunchOptionsKey.location.rawValue] != nil
            || launchOptions?[UIApplication.LaunchOptionsKey.location] != nil

        guard launchedForLocation else {
            return false
        }

        #if canImport(CoreLocation)
        Task { @MainActor in
            await locationMonitor.resumeForBackgroundLocationLaunch()
        }
        #endif

        return true
    }
}

private struct BubblReactNativeError: Error {
    let code: String
    let message: String
}

private func reactValue(_ value: Any?) -> Any {
    value ?? NSNull()
}

private extension NSDictionary {
    var swiftMap: [String: Any] {
        var output: [String: Any] = [:]
        for (key, value) in self {
            guard let key = key as? String else { continue }
            output[key] = value
        }
        return output
    }
}

private extension Dictionary where Key == String, Value == Any {
    func requiredString(_ key: String) throws -> String {
        guard let value = self[key] as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw BubblReactNativeError(code: "invalid_argument", message: "\(key) is required.")
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
            defaultNotificationModalStyle: try map("defaultNotificationModalStyle")?.notificationModalStyle(),
            enableDefaultSurveyUi: bool("enableDefaultSurveyUi", default: true),
            logLevel: BubblLogLevel(rawValue: string("logLevel") ?? "warn") ?? .warn
        )
    }

    func notificationModalStyle() throws -> BubblNotificationModalStyle {
        BubblNotificationModalStyle(
            theme: BubblNotificationModalTheme(rawValue: string("theme") ?? "light") ?? .light,
            transparentBackdrop: bool("transparentBackdrop", default: true),
            backdropColor: string("backdropColor"),
            cardBackgroundColor: string("cardBackgroundColor"),
            cardBorderColor: string("cardBorderColor"),
            titleColor: string("titleColor"),
            bodyColor: string("bodyColor"),
            accentColor: string("accentColor"),
            iconBackgroundColor: string("iconBackgroundColor"),
            iconTextColor: string("iconTextColor"),
            primaryButtonBackgroundColor: string("primaryButtonBackgroundColor"),
            primaryButtonTextColor: string("primaryButtonTextColor"),
            secondaryButtonBackgroundColor: string("secondaryButtonBackgroundColor"),
            secondaryButtonTextColor: string("secondaryButtonTextColor"),
            textButtonColor: string("textButtonColor"),
            surveyBackgroundColor: string("surveyBackgroundColor"),
            inputBackgroundColor: string("inputBackgroundColor"),
            inputTextColor: string("inputTextColor"),
            inputBorderColor: string("inputBorderColor"),
            cornerRadius: optionalDouble("cornerRadius"),
            buttonCornerRadius: optionalDouble("buttonCornerRadius")
        )
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
            throw BubblReactNativeError(code: "invalid_argument", message: "media.url is invalid.")
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
    func reactMap() -> [String: Any] {
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
    func reactMap() -> [String: Any] {
        [
            "notificationsCount": notificationsCount,
            "daysCount": daysCount,
            "batteryCount": batteryCount,
            "privacyText": privacyText
        ]
    }
}

private extension BubblDiagnostics {
    func reactMap() -> [String: Any] {
        [
            "sdkVersion": sdkVersion,
            "platform": platform,
            "booted": booted,
            "pendingIngestCount": pendingIngestCount,
            "pushTokenSuffix": reactValue(pushTokenSuffix)
        ]
    }
}

private extension BubblFlushResult {
    func reactMap() -> [String: Any] {
        ["pendingCount": pendingCount]
    }
}

private extension BubblNotificationDisplayResult {
    func reactMap() -> [String: Any] {
        ["displayed": displayed, "reason": reactValue(reason)]
    }
}

private extension BubblLocation {
    func reactMap() -> [String: Any] {
        ["latitude": latitude, "longitude": longitude]
    }
}

private extension BubblGeofenceTransition {
    func reactMap() -> [String: Any] {
        [
            "type": type.rawValue,
            "campaignId": reactValue(campaignId),
            "locationId": reactValue(locationId),
            "location": location.reactMap()
        ]
    }
}

private extension BubblGeofenceVertex {
    func reactMap() -> [String: Any] {
        ["latitude": latitude, "longitude": longitude]
    }
}

private extension BubblGeofencePolygon {
    func reactMap() -> [String: Any] {
        [
            "campaignId": reactValue(campaignId),
            "campaignName": reactValue(campaignName),
            "locationId": reactValue(locationId),
            "vertices": vertices.map { $0.reactMap() }
        ]
    }
}

private extension BubblGeofenceCircle {
    func reactMap() -> [String: Any] {
        [
            "campaignId": reactValue(campaignId),
            "campaignName": reactValue(campaignName),
            "locationId": reactValue(locationId),
            "center": center.reactMap(),
            "radiusMeters": radiusMeters
        ]
    }
}

private extension BubblGeofenceSnapshot {
    func reactMap() -> [String: Any] {
        [
            "stats": [
                "campaignsTotal": stats.campaignsTotal,
                "polygonsTotal": stats.polygonsTotal
            ],
            "polygons": polygons.map { $0.reactMap() },
            "circles": circles.map { $0.reactMap() }
        ]
    }
}

private extension BubblNotificationPayload {
    func reactMap() -> [String: Any] {
        [
            "id": id,
            "title": title,
            "body": body,
            "source": source.rawValue,
            "locationId": reactValue(locationId),
            "curatedNotificationId": reactValue(curatedNotificationId),
            "correlationId": reactValue(correlationId),
            "media": reactValue(media?.reactMap()),
            "cta": reactValue(cta?.reactMap()),
            "survey": reactValue(survey?.reactMap()),
            "raw": raw
        ]
    }
}

private extension BubblNotificationMedia {
    func reactMap() -> [String: Any] {
        ["url": url.absoluteString, "type": reactValue(type), "altText": reactValue(altText)]
    }
}

private extension BubblNotificationCTA {
    func reactMap() -> [String: Any] {
        ["label": label, "url": reactValue(url?.absoluteString), "action": reactValue(action)]
    }
}

private extension BubblNotificationSurvey {
    func reactMap() -> [String: Any] {
        ["questions": questions.map { $0.reactMap() }]
    }
}

private extension BubblSurveyQuestion {
    func reactMap() -> [String: Any] {
        ["id": id, "title": title, "type": type, "choices": choices.map { $0.reactMap() }]
    }
}

private extension BubblSurveyChoice {
    func reactMap() -> [String: Any] {
        ["id": id, "label": label]
    }
}

private extension BubblEvent {
    func reactMap() -> [String: Any] {
        switch self {
        case .ready:
            return ["type": "ready"]
        case .diagnostic(var diagnostics):
            diagnostics.platform = "react-native"
            return ["type": "diagnostic", "diagnostics": diagnostics.reactMap()]
        case .notificationReceived(let payload):
            return ["type": "notificationReceived", "payload": payload.reactMap()]
        case .notificationDisplayed(let payload):
            return ["type": "notificationDisplayed", "payload": payload.reactMap()]
        case .notificationTapped(let payload, let action):
            return ["type": "notificationTapped", "payload": payload.reactMap(), "action": reactValue(action)]
        case .notificationCtaTapped(let payload, let action):
            return ["type": "notificationCtaTapped", "payload": payload.reactMap(), "action": reactValue(action)]
        case .notificationMediaViewed(let payload):
            return ["type": "notificationMediaViewed", "payload": payload.reactMap()]
        case .notificationSurveyRequested(let payload):
            return ["type": "notificationSurveyRequested", "payload": payload.reactMap()]
        case .locationUpdated(let location):
            return ["type": "locationUpdated", "location": location.reactMap()]
        case .geofenceSnapshot(let snapshot):
            return ["type": "geofenceSnapshot", "snapshot": snapshot.reactMap()]
        case .geofenceEntered(let transition):
            return ["type": "geofenceEntered", "transition": transition.reactMap()]
        case .geofenceExited(let transition):
            return ["type": "geofenceExited", "transition": transition.reactMap()]
        case .error(let code, let message):
            return ["type": "error", "code": code, "message": message]
        }
    }
}
