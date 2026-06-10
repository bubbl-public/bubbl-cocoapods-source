import Foundation

public struct BubblConfig: Sendable, Codable, Equatable {
    public var apiKey: String
    public var environment: BubblEnvironment
    public var runtimeBaseUrl: URL?
    public var transmissionBaseUrl: URL?
    public var ingestBaseUrl: URL?
    public var segments: [String]
    public var correlationId: String?
    public var defaultDistanceMeters: Int
    public var refreshIntervalSeconds: Int
    public var enablePushHandling: Bool
    public var enableLocationTracking: Bool
    public var notificationRenderingMode: BubblNotificationRenderingMode
    public var enableDefaultNotificationModal: Bool
    public var defaultNotificationModalStyle: BubblNotificationModalStyle?
    public var enableDefaultSurveyUi: Bool
    public var logLevel: BubblLogLevel

    public init(
        apiKey: String,
        environment: BubblEnvironment = .staging,
        runtimeBaseUrl: URL? = nil,
        transmissionBaseUrl: URL? = nil,
        ingestBaseUrl: URL? = nil,
        segments: [String] = [],
        correlationId: String? = nil,
        defaultDistanceMeters: Int = 10,
        refreshIntervalSeconds: Int = 300,
        enablePushHandling: Bool = true,
        enableLocationTracking: Bool = false,
        notificationRenderingMode: BubblNotificationRenderingMode = .sdkDefault,
        enableDefaultNotificationModal: Bool = true,
        defaultNotificationModalStyle: BubblNotificationModalStyle? = nil,
        enableDefaultSurveyUi: Bool = true,
        logLevel: BubblLogLevel = .warn
    ) {
        self.apiKey = apiKey
        self.environment = environment
        self.runtimeBaseUrl = runtimeBaseUrl
        self.transmissionBaseUrl = transmissionBaseUrl
        self.ingestBaseUrl = ingestBaseUrl
        self.segments = segments
        self.correlationId = correlationId
        self.defaultDistanceMeters = defaultDistanceMeters
        self.refreshIntervalSeconds = refreshIntervalSeconds
        self.enablePushHandling = enablePushHandling
        self.enableLocationTracking = enableLocationTracking
        self.notificationRenderingMode = notificationRenderingMode
        self.enableDefaultNotificationModal = enableDefaultNotificationModal
        self.defaultNotificationModalStyle = defaultNotificationModalStyle
        self.enableDefaultSurveyUi = enableDefaultSurveyUi
        self.logLevel = logLevel
    }

    var requiredPermissions: [String] {
        var permissions: [String] = []
        if enableLocationTracking { permissions.append("location") }
        if enablePushHandling { permissions.append("push") }
        return permissions
    }
}

public enum BubblEnvironment: String, Sendable, Codable {
    case development
    case staging
    case production
}

public enum BubblLogLevel: String, Sendable, Codable {
    case off
    case error
    case warn
    case info
    case debug
}

public enum BubblNotificationRenderingMode: String, Sendable, Codable {
    case sdkDefault
    case hostRendered
    case eventOnly
}

public enum BubblNotificationSource: String, Sendable, Codable {
    case firebase
    case apns
    case runtime
    case geofence
    case manual
}

public enum BubblNotificationModalTheme: String, Sendable, Codable, Equatable {
    case light
    case dark
}

public struct BubblNotificationModalStyle: Sendable, Codable, Equatable {
    public var theme: BubblNotificationModalTheme
    public var transparentBackdrop: Bool
    public var backdropColor: String?
    public var cardBackgroundColor: String?
    public var cardBorderColor: String?
    public var titleColor: String?
    public var bodyColor: String?
    public var accentColor: String?
    public var iconBackgroundColor: String?
    public var iconTextColor: String?
    public var primaryButtonBackgroundColor: String?
    public var primaryButtonTextColor: String?
    public var secondaryButtonBackgroundColor: String?
    public var secondaryButtonTextColor: String?
    public var textButtonColor: String?
    public var surveyBackgroundColor: String?
    public var inputBackgroundColor: String?
    public var inputTextColor: String?
    public var inputBorderColor: String?
    public var cornerRadius: Double?
    public var buttonCornerRadius: Double?

    public init(
        theme: BubblNotificationModalTheme = .light,
        transparentBackdrop: Bool = true,
        backdropColor: String? = nil,
        cardBackgroundColor: String? = nil,
        cardBorderColor: String? = nil,
        titleColor: String? = nil,
        bodyColor: String? = nil,
        accentColor: String? = nil,
        iconBackgroundColor: String? = nil,
        iconTextColor: String? = nil,
        primaryButtonBackgroundColor: String? = nil,
        primaryButtonTextColor: String? = nil,
        secondaryButtonBackgroundColor: String? = nil,
        secondaryButtonTextColor: String? = nil,
        textButtonColor: String? = nil,
        surveyBackgroundColor: String? = nil,
        inputBackgroundColor: String? = nil,
        inputTextColor: String? = nil,
        inputBorderColor: String? = nil,
        cornerRadius: Double? = nil,
        buttonCornerRadius: Double? = nil
    ) {
        self.theme = theme
        self.transparentBackdrop = transparentBackdrop
        self.backdropColor = backdropColor
        self.cardBackgroundColor = cardBackgroundColor
        self.cardBorderColor = cardBorderColor
        self.titleColor = titleColor
        self.bodyColor = bodyColor
        self.accentColor = accentColor
        self.iconBackgroundColor = iconBackgroundColor
        self.iconTextColor = iconTextColor
        self.primaryButtonBackgroundColor = primaryButtonBackgroundColor
        self.primaryButtonTextColor = primaryButtonTextColor
        self.secondaryButtonBackgroundColor = secondaryButtonBackgroundColor
        self.secondaryButtonTextColor = secondaryButtonTextColor
        self.textButtonColor = textButtonColor
        self.surveyBackgroundColor = surveyBackgroundColor
        self.inputBackgroundColor = inputBackgroundColor
        self.inputTextColor = inputTextColor
        self.inputBorderColor = inputBorderColor
        self.cornerRadius = cornerRadius
        self.buttonCornerRadius = buttonCornerRadius
    }

    public static let `default` = BubblNotificationModalStyle()
}

public struct BubblBootResult: Sendable, Codable, Equatable {
    public let ready: Bool
    public let fromCache: Bool
    public let deviceRegistered: Bool
    public let requiresPermission: [String]
    public let warnings: [String]

    public init(
        ready: Bool,
        fromCache: Bool,
        deviceRegistered: Bool,
        requiresPermission: [String],
        warnings: [String]
    ) {
        self.ready = ready
        self.fromCache = fromCache
        self.deviceRegistered = deviceRegistered
        self.requiresPermission = requiresPermission
        self.warnings = warnings
    }
}

public struct BubblLocation: Sendable, Codable, Equatable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

public enum BubblGeofenceTransitionType: String, Sendable, Codable {
    case enter
    case exit
}

public struct BubblGeofenceTransition: Sendable, Codable, Equatable {
    public let type: BubblGeofenceTransitionType
    public let campaignId: String?
    public let locationId: String?
    public let location: BubblLocation

    public init(
        type: BubblGeofenceTransitionType,
        campaignId: String? = nil,
        locationId: String? = nil,
        location: BubblLocation
    ) {
        self.type = type
        self.campaignId = campaignId
        self.locationId = locationId
        self.location = location
    }
}

public struct BubblGeofenceVertex: Sendable, Codable, Equatable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

public struct BubblGeofencePolygon: Sendable, Codable, Equatable {
    public let campaignId: String?
    public let campaignName: String?
    public let locationId: String?
    public let vertices: [BubblGeofenceVertex]

    public init(
        campaignId: String? = nil,
        campaignName: String? = nil,
        locationId: String? = nil,
        vertices: [BubblGeofenceVertex]
    ) {
        self.campaignId = campaignId
        self.campaignName = campaignName
        self.locationId = locationId
        self.vertices = vertices
    }
}

public struct BubblGeofenceCircle: Sendable, Codable, Equatable {
    public let campaignId: String?
    public let campaignName: String?
    public let locationId: String?
    public let center: BubblGeofenceVertex
    public let radiusMeters: Double

    public init(
        campaignId: String? = nil,
        campaignName: String? = nil,
        locationId: String? = nil,
        center: BubblGeofenceVertex,
        radiusMeters: Double
    ) {
        self.campaignId = campaignId
        self.campaignName = campaignName
        self.locationId = locationId
        self.center = center
        self.radiusMeters = radiusMeters
    }
}

public struct BubblGeofenceSnapshotStats: Sendable, Codable, Equatable {
    public let campaignsTotal: Int
    public let polygonsTotal: Int

    public init(campaignsTotal: Int, polygonsTotal: Int) {
        self.campaignsTotal = campaignsTotal
        self.polygonsTotal = polygonsTotal
    }
}

public struct BubblGeofenceSnapshot: Sendable, Codable, Equatable {
    public let stats: BubblGeofenceSnapshotStats
    public let polygons: [BubblGeofencePolygon]
    public let circles: [BubblGeofenceCircle]

    public init(
        stats: BubblGeofenceSnapshotStats,
        polygons: [BubblGeofencePolygon],
        circles: [BubblGeofenceCircle] = []
    ) {
        self.stats = stats
        self.polygons = polygons
        self.circles = circles
    }
}

public struct BubblConfiguration: Sendable, Codable, Equatable {
    public let notificationsCount: Int
    public let daysCount: Int
    public let batteryCount: Int
    public let privacyText: String

    public init(notificationsCount: Int, daysCount: Int, batteryCount: Int, privacyText: String) {
        self.notificationsCount = notificationsCount
        self.daysCount = daysCount
        self.batteryCount = batteryCount
        self.privacyText = privacyText
    }
}

public struct BubblTrackEvent: Sendable, Codable, Equatable {
    public let type: String
    public let activity: String
    public let locationId: String?
    public let curatedNotificationId: String?
    public let latitude: Double?
    public let longitude: Double?

    public init(
        type: String,
        activity: String,
        locationId: String? = nil,
        curatedNotificationId: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil
    ) {
        self.type = type
        self.activity = activity
        self.locationId = locationId
        self.curatedNotificationId = curatedNotificationId
        self.latitude = latitude
        self.longitude = longitude
    }
}

public struct BubblSurveyResponse: Sendable, Codable, Equatable {
    public let curatedNotificationId: String
    public let locationId: String?
    public let answers: [BubblSurveyAnswer]

    public init(curatedNotificationId: String, locationId: String? = nil, answers: [BubblSurveyAnswer]) {
        self.curatedNotificationId = curatedNotificationId
        self.locationId = locationId
        self.answers = answers
    }
}

public struct BubblSurveyAnswer: Sendable, Codable, Equatable {
    public let questionId: String
    public let type: String
    public let value: String?
    public let choiceIds: [String]

    public init(questionId: String, type: String, value: String? = nil, choiceIds: [String] = []) {
        self.questionId = questionId
        self.type = type
        self.value = value
        self.choiceIds = choiceIds
    }
}

public struct BubblNotificationPayload: Sendable, Codable, Equatable {
    public let id: String
    public let title: String
    public let body: String
    public let source: BubblNotificationSource
    public let locationId: String?
    public let curatedNotificationId: String?
    public let correlationId: String?
    public let media: BubblNotificationMedia?
    public let cta: BubblNotificationCTA?
    public let survey: BubblNotificationSurvey?
    public let raw: [String: String]

    public init(
        id: String,
        title: String,
        body: String,
        source: BubblNotificationSource = .manual,
        locationId: String? = nil,
        curatedNotificationId: String? = nil,
        correlationId: String? = nil,
        media: BubblNotificationMedia? = nil,
        cta: BubblNotificationCTA? = nil,
        survey: BubblNotificationSurvey? = nil,
        raw: [String: String] = [:]
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.source = source
        self.locationId = locationId
        self.curatedNotificationId = curatedNotificationId
        self.correlationId = correlationId
        self.media = media
        self.cta = cta
        self.survey = survey
        self.raw = raw
    }
}

public struct BubblNotificationMedia: Sendable, Codable, Equatable {
    public let url: URL
    public let type: String?
    public let altText: String?

    public init(url: URL, type: String? = nil, altText: String? = nil) {
        self.url = url
        self.type = type
        self.altText = altText
    }
}

public struct BubblNotificationCTA: Sendable, Codable, Equatable {
    public let label: String
    public let url: URL?
    public let action: String?

    public init(label: String, url: URL? = nil, action: String? = nil) {
        self.label = label
        self.url = url
        self.action = action
    }
}

public struct BubblNotificationSurvey: Sendable, Codable, Equatable {
    public let questions: [BubblSurveyQuestion]

    public init(questions: [BubblSurveyQuestion] = []) {
        self.questions = questions
    }
}

public struct BubblSurveyQuestion: Sendable, Codable, Equatable {
    public let id: String
    public let title: String
    public let type: String
    public let choices: [BubblSurveyChoice]

    public init(id: String, title: String, type: String, choices: [BubblSurveyChoice] = []) {
        self.id = id
        self.title = title
        self.type = type
        self.choices = choices
    }
}

public struct BubblSurveyChoice: Sendable, Codable, Equatable {
    public let id: String
    public let label: String

    public init(id: String, label: String) {
        self.id = id
        self.label = label
    }
}

public struct BubblNotificationDisplayResult: Sendable, Codable, Equatable {
    public let displayed: Bool
    public let reason: String?

    public init(displayed: Bool, reason: String? = nil) {
        self.displayed = displayed
        self.reason = reason
    }
}

public struct BubblFlushResult: Sendable, Codable, Equatable {
    public let pendingCount: Int

    public init(pendingCount: Int) {
        self.pendingCount = pendingCount
    }
}

public struct BubblDiagnostics: Sendable, Codable, Equatable {
    public var sdkVersion = "4.0.1"
    public var platform = "ios"
    public var booted = false
    public var pendingIngestCount = 0
    public var pushTokenSuffix: String?

    public init(
        sdkVersion: String = "4.0.1",
        platform: String = "ios",
        booted: Bool = false,
        pendingIngestCount: Int = 0,
        pushTokenSuffix: String? = nil
    ) {
        self.sdkVersion = sdkVersion
        self.platform = platform
        self.booted = booted
        self.pendingIngestCount = pendingIngestCount
        self.pushTokenSuffix = pushTokenSuffix
    }
}

public enum BubblEvent: Sendable, Equatable {
    case ready
    case diagnostic(BubblDiagnostics)
    case notificationReceived(BubblNotificationPayload)
    case notificationDisplayed(BubblNotificationPayload)
    case notificationTapped(BubblNotificationPayload, action: String?)
    case notificationCtaTapped(BubblNotificationPayload, action: String?)
    case notificationMediaViewed(BubblNotificationPayload)
    case notificationSurveyRequested(BubblNotificationPayload)
    case locationUpdated(BubblLocation)
    case geofenceSnapshot(BubblGeofenceSnapshot)
    case geofenceEntered(BubblGeofenceTransition)
    case geofenceExited(BubblGeofenceTransition)
    case error(code: String, message: String)
}

public enum BubblError: Error, Sendable, Equatable {
    case invalidConfig(String)
    case notBooted
    case invalidResponse(String)
    case transport(String)
    case storage(String)
}
