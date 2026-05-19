package tech.bubbl.reactnative

import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.ReactContextBaseJavaModule
import com.facebook.react.bridge.ReactMethod
import com.facebook.react.bridge.ReadableArray
import com.facebook.react.bridge.ReadableMap
import com.facebook.react.bridge.WritableArray
import com.facebook.react.bridge.WritableMap
import com.facebook.react.modules.core.DeviceEventManagerModule
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
import tech.bubbl.sdk.BubblLocation
import tech.bubbl.sdk.BubblLogLevel
import tech.bubbl.sdk.BubblNotificationCta
import tech.bubbl.sdk.BubblNotificationDisplayResult
import tech.bubbl.sdk.BubblNotificationMedia
import tech.bubbl.sdk.BubblNotificationPayload
import tech.bubbl.sdk.BubblNotificationRenderingMode
import tech.bubbl.sdk.BubblNotificationSource
import tech.bubbl.sdk.BubblNotificationSurvey
import tech.bubbl.sdk.BubblNotificationTap
import tech.bubbl.sdk.BubblSdk
import tech.bubbl.sdk.BubblSurveyAnswer
import tech.bubbl.sdk.BubblSurveyChoice
import tech.bubbl.sdk.BubblSurveyQuestion
import tech.bubbl.sdk.BubblSurveyResponse
import tech.bubbl.sdk.BubblTrackEvent

class BubblSdkModule(
    private val reactContext: ReactApplicationContext
) : ReactContextBaseJavaModule(reactContext) {
    private var scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var eventJob: Job? = null
    private var listenerCount = 0

    init {
        BubblSdk.install(reactContext)
    }

    override fun getName(): String = NAME

    override fun invalidate() {
        eventJob?.cancel()
        scope.cancel()
        scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
        super.invalidate()
    }

    @ReactMethod
    fun addListener(eventName: String) {
        listenerCount += 1
        if (eventName == EVENT_NAME && eventJob == null) {
            eventJob = scope.launch {
                BubblSdk.events.collectLatest { event ->
                    emitEvent(event.toWritableMap())
                }
            }
            BubblSdk.drainPendingNotificationTaps().forEach { tap ->
                emitEvent(tap.toWritableMap())
            }
        }
    }

    @ReactMethod
    fun removeListeners(count: Int) {
        listenerCount = (listenerCount - count).coerceAtLeast(0)
        if (listenerCount == 0) {
            eventJob?.cancel()
            eventJob = null
        }
    }

    @ReactMethod
    fun boot(config: ReadableMap, promise: Promise) = resolve(promise) {
        BubblSdk.boot(config.toConfig()).toWritableMap()
    }

    @ReactMethod
    fun shutdown(promise: Promise) = resolve(promise) {
        BubblSdk.shutdown()
        null
    }

    @ReactMethod
    fun startLocationTracking(promise: Promise) = resolve(promise) {
        BubblSdk.startLocationTracking(reactContext)
        null
    }

    @ReactMethod
    fun stopLocationTracking(promise: Promise) = resolve(promise) {
        BubblSdk.stopLocationTracking(reactContext)
        null
    }

    @ReactMethod
    fun refresh(promise: Promise) = resolve(promise) {
        BubblSdk.refresh()
        null
    }

    @ReactMethod
    fun refreshGeofence(latitude: Double, longitude: Double, promise: Promise) = resolve(promise) {
        BubblSdk.refreshGeofence(BubblLocation(latitude, longitude))
        null
    }

    @ReactMethod
    fun handleLocationUpdate(latitude: Double, longitude: Double, promise: Promise) = resolve(promise) {
        BubblSdk.handleLocationUpdate(BubblLocation(latitude, longitude))
        null
    }

    @ReactMethod
    fun refreshPush(promise: Promise) = resolve(promise) {
        BubblSdk.refreshPush()
        null
    }

    @ReactMethod
    fun getConfiguration(promise: Promise) = resolve(promise) {
        BubblSdk.getConfiguration()?.toWritableMap()
    }

    @ReactMethod
    fun getPrivacyText(promise: Promise) = resolve(promise) {
        BubblSdk.getPrivacyText()
    }

    @ReactMethod
    fun updateSegments(tags: ReadableArray, promise: Promise) = resolve(promise) {
        BubblSdk.updateSegments(tags.stringList())
        null
    }

    @ReactMethod
    fun setCorrelationId(value: String, promise: Promise) = resolve(promise) {
        BubblSdk.setCorrelationId(value)
        null
    }

    @ReactMethod
    fun clearCorrelationId(promise: Promise) = resolve(promise) {
        BubblSdk.clearCorrelationId()
        null
    }

    @ReactMethod
    fun setDefaultNotificationModalEnabled(enabled: Boolean, promise: Promise) = resolve(promise) {
        BubblSdk.setDefaultNotificationModalEnabled(enabled)
        null
    }

    @ReactMethod
    fun registerPushToken(token: String, promise: Promise) = resolve(promise) {
        BubblSdk.registerPushToken(token)
        null
    }

    @ReactMethod
    fun handleFirebasePayload(payload: ReadableMap, promise: Promise) = resolve(promise) {
        BubblSdk.handleFirebasePayload(payload.stringMap())?.toWritableMap()
    }

    @ReactMethod
    fun showNotification(payload: ReadableMap, promise: Promise) = resolve(promise) {
        BubblSdk.showNotification(payload.toNotificationPayload()).toWritableMap()
    }

    @ReactMethod
    fun handleNotificationPayload(payload: ReadableMap, promise: Promise) = resolve(promise) {
        BubblSdk.handleNotificationPayload(payload.toNotificationPayload()).toWritableMap()
    }

    @ReactMethod
    fun handleNotificationOpen(payload: ReadableMap, action: String?, promise: Promise) = resolve(promise) {
        BubblSdk.handleNotificationOpen(payload.toNotificationPayload(), action)
        null
    }

    @ReactMethod
    fun openNotificationModal(payload: ReadableMap, action: String?, promise: Promise) = resolve(promise) {
        BubblSdk.openNotificationModal(reactContext, payload.toNotificationPayload(), action)
    }

    @ReactMethod
    fun handleNotificationCta(payload: ReadableMap, action: String?, promise: Promise) = resolve(promise) {
        BubblSdk.handleNotificationCta(payload.toNotificationPayload(), action)
        null
    }

    @ReactMethod
    fun handleNotificationMediaViewed(payload: ReadableMap, promise: Promise) = resolve(promise) {
        BubblSdk.handleNotificationMediaViewed(payload.toNotificationPayload())
        null
    }

    @ReactMethod
    fun handleNotificationSurveyRequested(payload: ReadableMap, promise: Promise) = resolve(promise) {
        BubblSdk.handleNotificationSurveyRequested(payload.toNotificationPayload())
        null
    }

    @ReactMethod
    fun track(event: ReadableMap, promise: Promise) = resolve(promise) {
        BubblSdk.track(event.toTrackEvent())
        null
    }

    @ReactMethod
    fun submitSurveyResponse(response: ReadableMap, promise: Promise) = resolve(promise) {
        BubblSdk.submitSurveyResponse(response.toSurveyResponse())
        null
    }

    @ReactMethod
    fun flush(promise: Promise) = resolve(promise) {
        BubblSdk.flush().toWritableMap()
    }

    @ReactMethod
    fun diagnostics(promise: Promise) = resolve(promise) {
        BubblSdk.diagnostics().copy(platform = "react-native").toWritableMap()
    }

    private fun resolve(promise: Promise, block: suspend () -> Any?) {
        scope.launch {
            try {
                val value = withContext(Dispatchers.IO) { block() }
                promise.resolve(value)
            } catch (error: IllegalArgumentException) {
                promise.reject("invalid_argument", error.message, error)
            } catch (error: Throwable) {
                promise.reject("bubbl_error", error.message ?: error.toString(), error)
            }
        }
    }

    private fun emitEvent(body: WritableMap) {
        if (!reactContext.hasActiveReactInstance()) return

        reactContext
            .getJSModule(DeviceEventManagerModule.RCTDeviceEventEmitter::class.java)
            .emit(EVENT_NAME, body)
    }

    private fun ReadableMap.toConfig(): BubblConfig =
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

    private fun ReadableMap.toTrackEvent(): BubblTrackEvent =
        BubblTrackEvent(
            type = requiredString("type"),
            activity = requiredString("activity"),
            locationId = string("locationId"),
            curatedNotificationId = string("curatedNotificationId"),
            latitude = nullableDouble("latitude"),
            longitude = nullableDouble("longitude")
        )

    private fun ReadableMap.toSurveyResponse(): BubblSurveyResponse =
        BubblSurveyResponse(
            curatedNotificationId = requiredString("curatedNotificationId"),
            locationId = string("locationId"),
            answers = mapList("answers").map { it.toSurveyAnswer() }
        )

    private fun ReadableMap.toSurveyAnswer(): BubblSurveyAnswer =
        BubblSurveyAnswer(
            questionId = requiredString("questionId"),
            type = requiredString("type"),
            value = string("value"),
            choiceIds = stringList("choiceIds")
        )

    private fun ReadableMap.toNotificationPayload(): BubblNotificationPayload =
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
            raw = map("raw")?.stringMap().orEmpty()
        )

    private fun ReadableMap.toNotificationMedia(): BubblNotificationMedia =
        BubblNotificationMedia(url = requiredString("url"), type = string("type"), altText = string("altText"))

    private fun ReadableMap.toNotificationCta(): BubblNotificationCta =
        BubblNotificationCta(label = requiredString("label"), url = string("url"), action = string("action"))

    private fun ReadableMap.toNotificationSurvey(): BubblNotificationSurvey =
        BubblNotificationSurvey(questions = mapList("questions").map { it.toSurveyQuestion() })

    private fun ReadableMap.toSurveyQuestion(): BubblSurveyQuestion =
        BubblSurveyQuestion(
            id = requiredString("id"),
            title = requiredString("title"),
            type = requiredString("type"),
            choices = mapList("choices").map { it.toSurveyChoice() }
        )

    private fun ReadableMap.toSurveyChoice(): BubblSurveyChoice =
        BubblSurveyChoice(id = requiredString("id"), label = requiredString("label"))

    private fun BubblBootResult.toWritableMap(): WritableMap = Arguments.createMap().apply {
        putBoolean("ready", ready)
        putBoolean("fromCache", fromCache)
        putBoolean("deviceRegistered", deviceRegistered)
        putArray("requiresPermission", requiresPermission.toWritableStringArray())
        putArray("warnings", warnings.toWritableStringArray())
    }

    private fun BubblConfiguration.toWritableMap(): WritableMap = Arguments.createMap().apply {
        putInt("notificationsCount", notificationsCount)
        putInt("daysCount", daysCount)
        putInt("batteryCount", batteryCount)
        putString("privacyText", privacyText)
    }

    private fun BubblDiagnostics.toWritableMap(): WritableMap = Arguments.createMap().apply {
        putString("sdkVersion", sdkVersion)
        putString("platform", platform)
        putBoolean("booted", booted)
        putInt("pendingIngestCount", pendingIngestCount)
        putNullableString("pushTokenSuffix", pushTokenSuffix)
    }

    private fun BubblFlushResult.toWritableMap(): WritableMap = Arguments.createMap().apply {
        putInt("pendingCount", pendingCount)
    }

    private fun BubblNotificationDisplayResult.toWritableMap(): WritableMap = Arguments.createMap().apply {
        putBoolean("displayed", displayed)
        putNullableString("reason", reason)
    }

    private fun BubblLocation.toWritableMap(): WritableMap = Arguments.createMap().apply {
        putDouble("latitude", latitude)
        putDouble("longitude", longitude)
    }

    private fun BubblGeofenceTransition.toWritableMap(): WritableMap = Arguments.createMap().apply {
        putString(
            "type",
            when (type) {
                BubblGeofenceTransitionType.Enter -> "enter"
                BubblGeofenceTransitionType.Exit -> "exit"
            }
        )
        putNullableString("campaignId", campaignId)
        putNullableString("locationId", locationId)
        putMap("location", location.toWritableMap())
    }

    private fun BubblNotificationPayload.toWritableMap(): WritableMap = Arguments.createMap().apply {
        putString("id", id)
        putString("title", title)
        putString("body", body)
        putString(
            "source",
            when (source) {
                BubblNotificationSource.Firebase -> "firebase"
                BubblNotificationSource.Apns -> "apns"
                BubblNotificationSource.Runtime -> "runtime"
                BubblNotificationSource.Geofence -> "geofence"
                BubblNotificationSource.Manual -> "manual"
            }
        )
        putNullableString("locationId", locationId)
        putNullableString("curatedNotificationId", curatedNotificationId)
        putNullableString("correlationId", correlationId)
        putNullableMap("media", media?.toWritableMap())
        putNullableMap("cta", cta?.toWritableMap())
        putNullableMap("survey", survey?.toWritableMap())
        putMap("raw", raw.toWritableMap())
    }

    private fun BubblNotificationMedia.toWritableMap(): WritableMap = Arguments.createMap().apply {
        putString("url", url)
        putNullableString("type", type)
        putNullableString("altText", altText)
    }

    private fun BubblNotificationCta.toWritableMap(): WritableMap = Arguments.createMap().apply {
        putString("label", label)
        putNullableString("url", url)
        putNullableString("action", action)
    }

    private fun BubblNotificationSurvey.toWritableMap(): WritableMap = Arguments.createMap().apply {
        putArray("questions", questions.map { it.toWritableMap() }.toWritableMapArray())
    }

    private fun BubblSurveyQuestion.toWritableMap(): WritableMap = Arguments.createMap().apply {
        putString("id", id)
        putString("title", title)
        putString("type", type)
        putArray("choices", choices.map { it.toWritableMap() }.toWritableMapArray())
    }

    private fun BubblSurveyChoice.toWritableMap(): WritableMap = Arguments.createMap().apply {
        putString("id", id)
        putString("label", label)
    }

    private fun BubblEvent.toWritableMap(): WritableMap = when (this) {
        BubblEvent.Ready -> Arguments.createMap().apply { putString("type", "ready") }
        is BubblEvent.Diagnostic -> Arguments.createMap().apply {
            putString("type", "diagnostic")
            putMap("diagnostics", diagnostics.copy(platform = "react-native").toWritableMap())
        }
        is BubblEvent.NotificationReceived -> eventPayload("notificationReceived", payload)
        is BubblEvent.NotificationDisplayed -> eventPayload("notificationDisplayed", payload)
        is BubblEvent.NotificationTapped -> eventPayload("notificationTapped", payload, action)
        is BubblEvent.NotificationCtaTapped -> eventPayload("notificationCtaTapped", payload, action)
        is BubblEvent.NotificationMediaViewed -> eventPayload("notificationMediaViewed", payload)
        is BubblEvent.NotificationSurveyRequested -> eventPayload("notificationSurveyRequested", payload)
        is BubblEvent.LocationUpdated -> Arguments.createMap().apply {
            putString("type", "locationUpdated")
            putMap("location", location.toWritableMap())
        }
        is BubblEvent.GeofenceSnapshot -> Arguments.createMap().apply {
            putString("type", "geofenceSnapshot")
            putMap("snapshot", snapshot.toWritableMap())
        }
        is BubblEvent.GeofenceEntered -> Arguments.createMap().apply {
            putString("type", "geofenceEntered")
            putMap("transition", transition.toWritableMap())
        }
        is BubblEvent.GeofenceExited -> Arguments.createMap().apply {
            putString("type", "geofenceExited")
            putMap("transition", transition.toWritableMap())
        }
        is BubblEvent.Error -> Arguments.createMap().apply {
            putString("type", "error")
            putString("code", code)
            putString("message", message)
        }
    }

    private fun BubblNotificationTap.toWritableMap(): WritableMap =
        eventPayload("notificationTapped", payload, action)

    private fun eventPayload(
        type: String,
        payload: BubblNotificationPayload,
        action: String? = null
    ): WritableMap = Arguments.createMap().apply {
        putString("type", type)
        putMap("payload", payload.toWritableMap())
        if (action == null) {
            putNull("action")
        } else {
            putString("action", action)
        }
    }

    private fun BubblGeofenceSnapshot.toWritableMap(): WritableMap = Arguments.createMap().apply {
        val statsMap = Arguments.createMap().apply {
            putInt("campaignsTotal", stats.campaignsTotal)
            putInt("polygonsTotal", stats.polygonsTotal)
        }
        putMap("stats", statsMap)
        putArray("polygons", polygons.map { it.toWritableMap() }.toWritableMapArray())
        putArray("circles", circles.map { it.toWritableMap() }.toWritableMapArray())
    }

    private fun BubblGeofencePolygon.toWritableMap(): WritableMap = Arguments.createMap().apply {
        putNullableId("campaignId", campaignId)
        putNullableString("campaignName", campaignName)
        putNullableId("locationId", locationId)
        putArray(
            "vertices",
            vertices.map { vertex ->
                Arguments.createMap().apply {
                    putDouble("latitude", vertex.latitude)
                    putDouble("longitude", vertex.longitude)
                }
            }.toWritableMapArray()
        )
    }

    private fun BubblGeofenceCircle.toWritableMap(): WritableMap = Arguments.createMap().apply {
        putNullableId("campaignId", campaignId)
        putNullableString("campaignName", campaignName)
        putNullableId("locationId", locationId)
        putMap(
            "center",
            Arguments.createMap().apply {
                putDouble("latitude", center.latitude)
                putDouble("longitude", center.longitude)
            }
        )
        putDouble("radius", radiusMeters)
    }

    private fun ReadableMap.requiredString(key: String): String =
        string(key)?.takeIf { it.isNotBlank() } ?: throw IllegalArgumentException("$key is required")

    private fun ReadableMap.string(key: String): String? =
        if (hasKey(key) && !isNull(key)) getString(key) else null

    private fun ReadableMap.bool(key: String, default: Boolean): Boolean =
        if (hasKey(key) && !isNull(key)) getBoolean(key) else default

    private fun ReadableMap.int(key: String, default: Int): Int =
        if (hasKey(key) && !isNull(key)) getDouble(key).toInt() else default

    private fun ReadableMap.nullableDouble(key: String): Double? =
        if (hasKey(key) && !isNull(key)) getDouble(key) else null

    private fun ReadableMap.map(key: String): ReadableMap? =
        if (hasKey(key) && !isNull(key)) getMap(key) else null

    private fun ReadableMap.stringList(key: String): List<String> =
        if (hasKey(key) && !isNull(key)) getArray(key)?.stringList().orEmpty() else emptyList()

    private fun ReadableMap.mapList(key: String): List<ReadableMap> =
        if (hasKey(key) && !isNull(key)) getArray(key)?.mapList().orEmpty() else emptyList()

    private fun ReadableMap.stringMap(): Map<String, String> {
        val output = mutableMapOf<String, String>()
        val iterator = keySetIterator()
        while (iterator.hasNextKey()) {
            val key = iterator.nextKey()
            if (!isNull(key)) {
                output[key] = when (getType(key).name) {
                    "Boolean" -> getBoolean(key).toString()
                    "Number" -> getDouble(key).toString()
                    "String" -> getString(key).orEmpty()
                    else -> getDynamic(key).toString()
                }
            }
        }
        return output
    }

    private fun ReadableArray.stringList(): List<String> =
        (0 until size()).mapNotNull { index ->
            if (isNull(index)) null else getString(index)
        }

    private fun ReadableArray.mapList(): List<ReadableMap> =
        (0 until size()).mapNotNull { index ->
            if (isNull(index)) null else getMap(index)
        }

    private fun List<String>.toWritableStringArray(): WritableArray = Arguments.createArray().also { array ->
        forEach { array.pushString(it) }
    }

    private fun List<WritableMap>.toWritableMapArray(): WritableArray = Arguments.createArray().also { array ->
        forEach { array.pushMap(it) }
    }

    private fun Map<String, String>.toWritableMap(): WritableMap = Arguments.createMap().apply {
        forEach { (key, value) -> putString(key, value) }
    }

    private fun WritableMap.putNullableString(key: String, value: String?) {
        if (value == null) putNull(key) else putString(key, value)
    }

    private fun WritableMap.putNullableMap(key: String, value: WritableMap?) {
        if (value == null) putNull(key) else putMap(key, value)
    }

    private fun WritableMap.putNullableId(key: String, value: String?) {
        when {
            value == null -> putNull(key)
            value.toIntOrNull() != null -> putInt(key, value.toInt())
            else -> putString(key, value)
        }
    }

    private fun <T> enumValue(value: String?, default: T, block: (String) -> T): T =
        value?.let { runCatching { block(it) }.getOrNull() } ?: default

    companion object {
        const val NAME = "BubblSdk"
        private const val EVENT_NAME = "BubblSdkEvent"
    }
}
