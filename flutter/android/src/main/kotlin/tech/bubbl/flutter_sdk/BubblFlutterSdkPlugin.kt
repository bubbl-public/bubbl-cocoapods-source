package tech.bubbl.flutter_sdk

import android.content.Context
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import tech.bubbl.sdk.BubblBootResult
import tech.bubbl.sdk.BubblConfig
import tech.bubbl.sdk.BubblConfiguration
import tech.bubbl.sdk.BubblDiagnostics
import tech.bubbl.sdk.BubblEnvironment
import tech.bubbl.sdk.BubblEvent
import tech.bubbl.sdk.BubblFlushResult
import tech.bubbl.sdk.BubblGeofenceCircle
import tech.bubbl.sdk.BubblGeofencePolygon
import tech.bubbl.sdk.BubblGeofenceSnapshot
import tech.bubbl.sdk.BubblGeofenceTransition
import tech.bubbl.sdk.BubblGeofenceTransitionType
import tech.bubbl.sdk.BubblGeofenceVertex
import tech.bubbl.sdk.BubblLocation
import tech.bubbl.sdk.BubblLogLevel
import tech.bubbl.sdk.BubblNotificationCta
import tech.bubbl.sdk.BubblNotificationDisplayResult
import tech.bubbl.sdk.BubblNotificationMedia
import tech.bubbl.sdk.BubblNotificationPayload
import tech.bubbl.sdk.BubblNotificationRenderingMode
import tech.bubbl.sdk.BubblNotificationSource
import tech.bubbl.sdk.BubblNotificationSurvey
import tech.bubbl.sdk.BubblSdk
import tech.bubbl.sdk.BubblSurveyAnswer
import tech.bubbl.sdk.BubblSurveyChoice
import tech.bubbl.sdk.BubblSurveyQuestion
import tech.bubbl.sdk.BubblSurveyResponse
import tech.bubbl.sdk.BubblTrackEvent

class BubblFlutterSdkPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private lateinit var context: Context
    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private var scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var eventJob: Job? = null
    private var eventSink: EventChannel.EventSink? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        BubblSdk.install(context)

        methodChannel = MethodChannel(binding.binaryMessenger, "tech.bubbl.sdk/flutter/methods")
        methodChannel.setMethodCallHandler(this)

        eventChannel = EventChannel(binding.binaryMessenger, "tech.bubbl.sdk/flutter/events")
        eventChannel.setStreamHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        eventJob?.cancel()
        eventSink = null
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        scope.cancel()
        scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        eventSink = events
        eventJob?.cancel()
        eventJob = scope.launch {
            BubblSdk.events.collectLatest { event ->
                events.success(event.toMap())
            }
        }
    }

    override fun onCancel(arguments: Any?) {
        eventJob?.cancel()
        eventJob = null
        eventSink = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        scope.launch {
            try {
                val value = withContext(Dispatchers.IO) { handle(call) }
                result.success(value.toFlutterResult())
            } catch (error: IllegalArgumentException) {
                result.error("invalid_argument", error.message, null)
            } catch (error: Throwable) {
                result.error("bubbl_error", error.message ?: error.toString(), null)
            }
        }
    }

    private suspend fun handle(call: MethodCall): Any? {
        return when (call.method) {
            "boot" -> BubblSdk.boot(call.argumentsMap().toConfig()).toMap()
            "shutdown" -> BubblSdk.shutdown()
            "startLocationTracking" -> BubblSdk.startLocationTracking(context)
            "stopLocationTracking" -> BubblSdk.stopLocationTracking(context)
            "refresh" -> BubblSdk.refresh()
            "refreshGeofence" -> BubblSdk.refreshGeofence(call.argumentsMap().toLocation())
            "handleLocationUpdate" -> BubblSdk.handleLocationUpdate(call.argumentsMap().toLocation())
            "refreshPush" -> BubblSdk.refreshPush()
            "getConfiguration" -> BubblSdk.getConfiguration()?.toMap()
            "getPrivacyText" -> BubblSdk.getPrivacyText()
            "updateSegments" -> BubblSdk.updateSegments(call.argumentsMap().stringList("tags"))
            "setCorrelationId" -> BubblSdk.setCorrelationId(call.argumentsMap().requiredString("value"))
            "clearCorrelationId" -> BubblSdk.clearCorrelationId()
            "setDefaultNotificationModalEnabled" ->
                BubblSdk.setDefaultNotificationModalEnabled(call.argumentsMap().bool("enabled", true))
            "registerPushToken" -> BubblSdk.registerPushToken(call.argumentsMap().requiredString("token"))
            "handleFirebasePayload" -> {
                val payload = call.argumentsMap()["payload"] as? Map<*, *> ?: emptyMap<String, String>()
                BubblSdk.handleFirebasePayload(payload.mapKeys { it.key.toString() }.mapValues { it.value.toString() })?.toMap()
            }
            "showNotification" -> BubblSdk.showNotification(call.argumentsMap().toNotificationPayload()).toMap()
            "handleNotificationPayload" -> BubblSdk.handleNotificationPayload(call.argumentsMap().toNotificationPayload()).toMap()
            "handleNotificationOpen" -> {
                val args = call.argumentsMap()
                BubblSdk.handleNotificationOpen(args.payloadArgument(), args["action"] as? String)
            }
            "openNotificationModal" -> {
                val args = call.argumentsMap()
                BubblSdk.openNotificationModal(context, args.payloadArgument(), args["action"] as? String)
            }
            "handleNotificationCta" -> {
                val args = call.argumentsMap()
                BubblSdk.handleNotificationCta(args.payloadArgument(), args["action"] as? String)
            }
            "handleNotificationMediaViewed" -> BubblSdk.handleNotificationMediaViewed(call.argumentsMap().toNotificationPayload())
            "handleNotificationSurveyRequested" -> BubblSdk.handleNotificationSurveyRequested(call.argumentsMap().toNotificationPayload())
            "track" -> BubblSdk.track(call.argumentsMap().toTrackEvent())
            "submitSurveyResponse" -> BubblSdk.submitSurveyResponse(call.argumentsMap().toSurveyResponse())
            "flush" -> BubblSdk.flush().toMap()
            "diagnostics" -> BubblSdk.diagnostics().copy(platform = "flutter").toMap()
            else -> throw IllegalArgumentException("Unknown Bubbl Flutter method: ${call.method}")
        }
    }

    private fun Any?.toFlutterResult(): Any? =
        if (this == Unit) null else this

    @Suppress("UNCHECKED_CAST")
    private fun MethodCall.argumentsMap(): Map<String, Any?> =
        arguments as? Map<String, Any?> ?: emptyMap()

    @Suppress("UNCHECKED_CAST")
    private fun Map<String, Any?>.payloadArgument(): BubblNotificationPayload =
        (this["payload"] as? Map<String, Any?> ?: this).toNotificationPayload()

    private fun Map<String, Any?>.toConfig(): BubblConfig =
        BubblConfig(
            apiKey = requiredString("apiKey"),
            environment = enumValue(string("environment"), BubblEnvironment.Staging) {
                BubblEnvironment.valueOf(it.replaceFirstChar(Char::uppercaseChar))
            },
            runtimeBaseUrl = string("runtimeBaseUrl"),
            transmissionBaseUrl = string("transmissionBaseUrl"),
            ingestBaseUrl = string("ingestBaseUrl"),
            segments = stringList("segments"),
            correlationId = string("correlationId"),
            defaultDistanceMeters = int("defaultDistanceMeters", 10),
            refreshIntervalSeconds = int("refreshIntervalSeconds", 300),
            enablePushHandling = bool("enablePushHandling", true),
            enableLocationTracking = bool("enableLocationTracking", false),
            notificationRenderingMode = enumValue(string("notificationRenderingMode"), BubblNotificationRenderingMode.SdkDefault) {
                when (it) {
                    "hostRendered" -> BubblNotificationRenderingMode.HostRendered
                    "eventOnly" -> BubblNotificationRenderingMode.EventOnly
                    else -> BubblNotificationRenderingMode.SdkDefault
                }
            },
            enableDefaultNotificationModal = bool("enableDefaultNotificationModal", true),
            enableDefaultSurveyUi = bool("enableDefaultSurveyUi", true),
            logLevel = enumValue(string("logLevel"), BubblLogLevel.Warn) {
                BubblLogLevel.valueOf(it.replaceFirstChar(Char::uppercaseChar))
            }
        )

    private fun Map<String, Any?>.toLocation(): BubblLocation =
        BubblLocation(double("latitude"), double("longitude"))

    private fun Map<String, Any?>.toTrackEvent(): BubblTrackEvent =
        BubblTrackEvent(
            type = requiredString("type"),
            activity = requiredString("activity"),
            locationId = string("locationId"),
            curatedNotificationId = string("curatedNotificationId"),
            latitude = nullableDouble("latitude"),
            longitude = nullableDouble("longitude")
        )

    private fun Map<String, Any?>.toSurveyResponse(): BubblSurveyResponse =
        BubblSurveyResponse(
            curatedNotificationId = requiredString("curatedNotificationId"),
            locationId = string("locationId"),
            answers = mapList("answers").map { it.toSurveyAnswer() }
        )

    private fun Map<String, Any?>.toSurveyAnswer(): BubblSurveyAnswer =
        BubblSurveyAnswer(
            questionId = requiredString("questionId"),
            type = requiredString("type"),
            value = string("value"),
            choiceIds = stringList("choiceIds")
        )

    private fun Map<String, Any?>.toNotificationPayload(): BubblNotificationPayload =
        BubblNotificationPayload(
            id = requiredString("id"),
            title = requiredString("title"),
            body = requiredString("body"),
            source = enumValue(string("source"), BubblNotificationSource.Manual) {
                when (it) {
                    "firebase" -> BubblNotificationSource.Firebase
                    "apns" -> BubblNotificationSource.Apns
                    "runtime" -> BubblNotificationSource.Runtime
                    "geofence" -> BubblNotificationSource.Geofence
                    else -> BubblNotificationSource.Manual
                }
            },
            locationId = string("locationId"),
            curatedNotificationId = string("curatedNotificationId"),
            correlationId = string("correlationId"),
            media = map("media")?.toNotificationMedia(),
            cta = map("cta")?.toNotificationCta(),
            survey = map("survey")?.toNotificationSurvey(),
            raw = map("raw")?.mapValues { it.value.toString() }.orEmpty()
        )

    private fun Map<String, Any?>.toNotificationMedia(): BubblNotificationMedia =
        BubblNotificationMedia(url = requiredString("url"), type = string("type"), altText = string("altText"))

    private fun Map<String, Any?>.toNotificationCta(): BubblNotificationCta =
        BubblNotificationCta(label = requiredString("label"), url = string("url"), action = string("action"))

    private fun Map<String, Any?>.toNotificationSurvey(): BubblNotificationSurvey =
        BubblNotificationSurvey(questions = mapList("questions").map { it.toSurveyQuestion() })

    private fun Map<String, Any?>.toSurveyQuestion(): BubblSurveyQuestion =
        BubblSurveyQuestion(
            id = requiredString("id"),
            title = requiredString("title"),
            type = requiredString("type"),
            choices = mapList("choices").map { it.toSurveyChoice() }
        )

    private fun Map<String, Any?>.toSurveyChoice(): BubblSurveyChoice =
        BubblSurveyChoice(id = requiredString("id"), label = requiredString("label"))

    private fun BubblBootResult.toMap(): Map<String, Any?> = mapOf(
        "ready" to ready,
        "fromCache" to fromCache,
        "deviceRegistered" to deviceRegistered,
        "requiresPermission" to requiresPermission,
        "warnings" to warnings
    )

    private fun BubblConfiguration.toMap(): Map<String, Any?> = mapOf(
        "notificationsCount" to notificationsCount,
        "daysCount" to daysCount,
        "batteryCount" to batteryCount,
        "privacyText" to privacyText
    )

    private fun BubblDiagnostics.toMap(): Map<String, Any?> = mapOf(
        "sdkVersion" to sdkVersion,
        "platform" to platform,
        "booted" to booted,
        "pendingIngestCount" to pendingIngestCount,
        "pushTokenSuffix" to pushTokenSuffix
    )

    private fun BubblFlushResult.toMap(): Map<String, Any?> = mapOf("pendingCount" to pendingCount)

    private fun BubblNotificationDisplayResult.toMap(): Map<String, Any?> =
        mapOf("displayed" to displayed, "reason" to reason)

    private fun BubblLocation.toMap(): Map<String, Any?> = mapOf("latitude" to latitude, "longitude" to longitude)

    private fun BubblGeofenceTransition.toMap(): Map<String, Any?> = mapOf(
        "type" to when (type) {
            BubblGeofenceTransitionType.Enter -> "enter"
            BubblGeofenceTransitionType.Exit -> "exit"
        },
        "campaignId" to campaignId,
        "locationId" to locationId,
        "location" to location.toMap()
    )

    private fun BubblGeofenceVertex.toMap(): Map<String, Any?> = mapOf("latitude" to latitude, "longitude" to longitude)

    private fun BubblGeofencePolygon.toMap(): Map<String, Any?> = mapOf(
        "campaignId" to campaignId,
        "campaignName" to campaignName,
        "locationId" to locationId,
        "vertices" to vertices.map { it.toMap() }
    )

    private fun BubblGeofenceCircle.toMap(): Map<String, Any?> = mapOf(
        "campaignId" to campaignId,
        "campaignName" to campaignName,
        "locationId" to locationId,
        "center" to center.toMap(),
        "radiusMeters" to radiusMeters
    )

    private fun BubblGeofenceSnapshot.toMap(): Map<String, Any?> = mapOf(
        "stats" to mapOf(
            "campaignsTotal" to stats.campaignsTotal,
            "polygonsTotal" to stats.polygonsTotal
        ),
        "polygons" to polygons.map { it.toMap() },
        "circles" to circles.map { it.toMap() }
    )

    private fun BubblNotificationPayload.toMap(): Map<String, Any?> = mapOf(
        "id" to id,
        "title" to title,
        "body" to body,
        "source" to when (source) {
            BubblNotificationSource.Firebase -> "firebase"
            BubblNotificationSource.Apns -> "apns"
            BubblNotificationSource.Runtime -> "runtime"
            BubblNotificationSource.Geofence -> "geofence"
            BubblNotificationSource.Manual -> "manual"
        },
        "locationId" to locationId,
        "curatedNotificationId" to curatedNotificationId,
        "correlationId" to correlationId,
        "media" to media?.toMap(),
        "cta" to cta?.toMap(),
        "survey" to survey?.toMap(),
        "raw" to raw
    )

    private fun BubblNotificationMedia.toMap(): Map<String, Any?> =
        mapOf("url" to url, "type" to type, "altText" to altText)

    private fun BubblNotificationCta.toMap(): Map<String, Any?> =
        mapOf("label" to label, "url" to url, "action" to action)

    private fun BubblNotificationSurvey.toMap(): Map<String, Any?> =
        mapOf("questions" to questions.map { it.toMap() })

    private fun BubblSurveyQuestion.toMap(): Map<String, Any?> =
        mapOf("id" to id, "title" to title, "type" to type, "choices" to choices.map { it.toMap() })

    private fun BubblSurveyChoice.toMap(): Map<String, Any?> =
        mapOf("id" to id, "label" to label)

    private fun BubblEvent.toMap(): Map<String, Any?> = when (this) {
        BubblEvent.Ready -> mapOf("type" to "ready")
        is BubblEvent.Diagnostic -> mapOf("type" to "diagnostic", "diagnostics" to diagnostics.copy(platform = "flutter").toMap())
        is BubblEvent.NotificationReceived -> mapOf("type" to "notificationReceived", "payload" to payload.toMap())
        is BubblEvent.NotificationDisplayed -> mapOf("type" to "notificationDisplayed", "payload" to payload.toMap())
        is BubblEvent.NotificationTapped -> mapOf("type" to "notificationTapped", "payload" to payload.toMap(), "action" to action)
        is BubblEvent.NotificationCtaTapped -> mapOf("type" to "notificationCtaTapped", "payload" to payload.toMap(), "action" to action)
        is BubblEvent.NotificationMediaViewed -> mapOf("type" to "notificationMediaViewed", "payload" to payload.toMap())
        is BubblEvent.NotificationSurveyRequested -> mapOf("type" to "notificationSurveyRequested", "payload" to payload.toMap())
        is BubblEvent.LocationUpdated -> mapOf("type" to "locationUpdated", "location" to location.toMap())
        is BubblEvent.GeofenceSnapshot -> mapOf("type" to "geofenceSnapshot", "snapshot" to snapshot.toMap())
        is BubblEvent.GeofenceEntered -> mapOf("type" to "geofenceEntered", "transition" to transition.toMap())
        is BubblEvent.GeofenceExited -> mapOf("type" to "geofenceExited", "transition" to transition.toMap())
        is BubblEvent.Error -> mapOf("type" to "error", "code" to code, "message" to message)
    }

    private fun Map<String, Any?>.requiredString(key: String): String =
        string(key)?.takeIf { it.isNotBlank() } ?: throw IllegalArgumentException("$key is required")

    private fun Map<String, Any?>.string(key: String): String? = this[key] as? String
    private fun Map<String, Any?>.bool(key: String, default: Boolean): Boolean = this[key] as? Boolean ?: default
    private fun Map<String, Any?>.int(key: String, default: Int): Int = (this[key] as? Number)?.toInt() ?: default
    private fun Map<String, Any?>.double(key: String): Double = (this[key] as? Number)?.toDouble() ?: 0.0
    private fun Map<String, Any?>.nullableDouble(key: String): Double? = (this[key] as? Number)?.toDouble()
    private fun Map<String, Any?>.stringList(key: String): List<String> =
        (this[key] as? List<*>)?.map { it.toString() } ?: emptyList()

    @Suppress("UNCHECKED_CAST")
    private fun Map<String, Any?>.map(key: String): Map<String, Any?>? =
        this[key] as? Map<String, Any?>

    @Suppress("UNCHECKED_CAST")
    private fun Map<String, Any?>.mapList(key: String): List<Map<String, Any?>> =
        (this[key] as? List<*>)?.mapNotNull { it as? Map<String, Any?> } ?: emptyList()

    private fun <T> enumValue(value: String?, default: T, block: (String) -> T): T =
        value?.let { runCatching { block(it) }.getOrNull() } ?: default
}
