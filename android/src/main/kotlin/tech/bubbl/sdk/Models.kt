package tech.bubbl.sdk

data class BubblConfig(
    val apiKey: String,
    val environment: BubblEnvironment = BubblEnvironment.Staging,
    val runtimeBaseUrl: String? = null,
    val transmissionBaseUrl: String? = null,
    val ingestBaseUrl: String? = null,
    val segments: List<String> = emptyList(),
    val correlationId: String? = null,
    val defaultDistanceMeters: Int = 10,
    val refreshIntervalSeconds: Int = 300,
    val enablePushHandling: Boolean = true,
    val enableLocationTracking: Boolean = false,
    val notificationRenderingMode: BubblNotificationRenderingMode = BubblNotificationRenderingMode.SdkDefault,
    val enableDefaultNotificationModal: Boolean = true,
    val enableDefaultSurveyUi: Boolean = true,
    val logLevel: BubblLogLevel = BubblLogLevel.Warn
)

enum class BubblEnvironment { Development, Nightly, Staging, Production }
enum class BubblLogLevel { Off, Error, Warn, Info, Debug }
enum class BubblNotificationRenderingMode { SdkDefault, HostRendered, EventOnly }
enum class BubblNotificationTapPresentation { Auto, DefaultModal, HostModal }
enum class BubblNotificationSource { Firebase, Apns, Runtime, Geofence, Manual }

data class BubblBootResult(
    val ready: Boolean,
    val fromCache: Boolean,
    val deviceRegistered: Boolean,
    val requiresPermission: List<String>,
    val warnings: List<String>
)

data class BubblLocation(val latitude: Double, val longitude: Double)

enum class BubblGeofenceTransitionType { Enter, Exit }

data class BubblGeofenceTransition(
    val type: BubblGeofenceTransitionType,
    val campaignId: String? = null,
    val locationId: String? = null,
    val location: BubblLocation
)

data class BubblGeofenceVertex(
    val latitude: Double,
    val longitude: Double
)

data class BubblGeofencePolygon(
    val campaignId: String? = null,
    val campaignName: String? = null,
    val locationId: String? = null,
    val vertices: List<BubblGeofenceVertex>
)

data class BubblGeofenceCircle(
    val campaignId: String? = null,
    val campaignName: String? = null,
    val locationId: String? = null,
    val center: BubblGeofenceVertex,
    val radiusMeters: Double
)

data class BubblGeofenceSnapshotStats(
    val campaignsTotal: Int,
    val polygonsTotal: Int
)

data class BubblGeofenceSnapshot(
    val stats: BubblGeofenceSnapshotStats,
    val polygons: List<BubblGeofencePolygon>,
    val circles: List<BubblGeofenceCircle> = emptyList()
)

data class BubblConfiguration(
    val notificationsCount: Int,
    val daysCount: Int,
    val batteryCount: Int,
    val privacyText: String
)

data class BubblTrackEvent(
    val type: String,
    val activity: String,
    val locationId: String? = null,
    val curatedNotificationId: String? = null,
    val latitude: Double? = null,
    val longitude: Double? = null
)

data class BubblSurveyResponse(
    val curatedNotificationId: String,
    val locationId: String? = null,
    val answers: List<BubblSurveyAnswer>
)

data class BubblSurveyAnswer(
    val questionId: String,
    val type: String,
    val value: String? = null,
    val choiceIds: List<String> = emptyList()
)

data class BubblNotificationPayload(
    val id: String,
    val title: String,
    val body: String,
    val source: BubblNotificationSource = BubblNotificationSource.Manual,
    val locationId: String? = null,
    val curatedNotificationId: String? = null,
    val correlationId: String? = null,
    val media: BubblNotificationMedia? = null,
    val cta: BubblNotificationCta? = null,
    val survey: BubblNotificationSurvey? = null,
    val raw: Map<String, String> = emptyMap()
)

data class BubblNotificationMedia(
    val url: String,
    val type: String? = null,
    val altText: String? = null
)

data class BubblNotificationCta(
    val label: String,
    val url: String? = null,
    val action: String? = null
)

data class BubblNotificationSurvey(
    val questions: List<BubblSurveyQuestion> = emptyList()
)

data class BubblSurveyQuestion(
    val id: String,
    val title: String,
    val type: String,
    val choices: List<BubblSurveyChoice> = emptyList()
)

data class BubblSurveyChoice(
    val id: String,
    val label: String
)

data class BubblNotificationDisplayResult(
    val displayed: Boolean,
    val reason: String? = null
)

data class BubblNotificationTap(
    val payload: BubblNotificationPayload,
    val action: String? = null
)

data class BubblFlushResult(val pendingCount: Int)

data class BubblDiagnostics(
    val sdkVersion: String = "3.0.1",
    val platform: String = "android",
    val booted: Boolean = false,
    val pendingIngestCount: Int = 0,
    val pushTokenSuffix: String? = null
)

sealed interface BubblEvent {
    data object Ready : BubblEvent
    data class Diagnostic(val diagnostics: BubblDiagnostics) : BubblEvent
    data class NotificationReceived(val payload: BubblNotificationPayload) : BubblEvent
    data class NotificationDisplayed(val payload: BubblNotificationPayload) : BubblEvent
    data class NotificationTapped(val payload: BubblNotificationPayload, val action: String? = null) : BubblEvent
    data class NotificationCtaTapped(val payload: BubblNotificationPayload, val action: String? = null) : BubblEvent
    data class NotificationMediaViewed(val payload: BubblNotificationPayload) : BubblEvent
    data class NotificationSurveyRequested(val payload: BubblNotificationPayload) : BubblEvent
    data class LocationUpdated(val location: BubblLocation) : BubblEvent
    data class GeofenceSnapshot(val snapshot: BubblGeofenceSnapshot) : BubblEvent
    data class GeofenceEntered(val transition: BubblGeofenceTransition) : BubblEvent
    data class GeofenceExited(val transition: BubblGeofenceTransition) : BubblEvent
    data class Error(val code: String, val message: String) : BubblEvent
}
