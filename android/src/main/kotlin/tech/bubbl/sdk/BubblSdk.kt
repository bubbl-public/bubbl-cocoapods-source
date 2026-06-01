package tech.bubbl.sdk

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import com.google.firebase.messaging.FirebaseMessaging
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.time.Instant
import java.util.Locale
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

object BubblSdk {
    private const val logTag = "BubblSdk"
    private val eventBus = MutableSharedFlow<BubblEvent>(extraBufferCapacity = 64)
    private val backgroundScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var transport: BubblHttpTransport = UrlConnectionBubblHttpTransport()
    private var store: BubblStore = FileBubblStore(defaultStorageDirectory())
    private var appContext: Context? = null
    private var config: BubblConfig? = null
    private var state: BubblStoredState? = null
    private var booted: Boolean = false
    private var cachedConfiguration: BubblConfiguration? = null
    private val pendingNotificationTapLock = Any()
    private val pendingNotificationTaps = mutableListOf<BubblNotificationTap>()

    val events: SharedFlow<BubblEvent> = eventBus

    fun install(
        storageDirectory: File,
        transport: BubblHttpTransport = UrlConnectionBubblHttpTransport()
    ) {
        this.store = FileBubblStore(storageDirectory)
        this.transport = transport
        this.appContext = null
    }

    fun install(
        context: Context,
        transport: BubblHttpTransport = UrlConnectionBubblHttpTransport()
    ) {
        this.appContext = context.applicationContext
        this.store = AndroidBubblStore(context.applicationContext)
        this.transport = transport
    }

    suspend fun boot(config: BubblConfig): BubblBootResult {
        require(config.apiKey.isNotBlank()) { "apiKey is required" }

        val previousState = store.loadState()
        val storedState = previousState.copy(
            correlationId = config.correlationId ?: previousState.correlationId,
            segments = config.segments
        )
        store.saveState(storedState)
        store.saveConfig(config)

        this.config = config
        this.state = storedState
        this.booted = true
        this.cachedConfiguration = cachedConfigurationFromDisk()

        enqueue(
            path = BubblTransportMap.bootBatchPath,
            payload = deviceDataPayload(config, storedState, activity = "plugin_opened")
        )

        eventBus.tryEmit(BubblEvent.Ready)
        appContext?.let {
            BubblWorkScheduler.schedulePeriodicWork(it, config)
            if (config.enablePushHandling) {
                syncCurrentFcmTokenAsync(it)
            }
            if (config.enableLocationTracking && BubblAndroidLocationProvider.hasLocationPermission(it)) {
                startLocationTracking(it)
            }
        }

        return BubblBootResult(
            ready = true,
            fromCache = cachedConfiguration != null,
            deviceRegistered = false,
            requiresPermission = buildList {
                if (config.enableLocationTracking) add("location")
                if (config.enablePushHandling) add("push")
            },
            warnings = emptyList()
        )
    }

    suspend fun shutdown() {
        appContext?.let { BubblLocationUpdatesService.stop(it) }
        booted = false
        config = null
    }

    fun startLocationTracking() {
        val context = appContext ?: error("BubblSdk.install(context) must be called before startLocationTracking().")
        startLocationTracking(context)
    }

    fun startLocationTracking(context: Context) {
        appContext = context.applicationContext
        if (!BubblAndroidLocationProvider.hasLocationPermission(context.applicationContext)) {
            eventBus.tryEmit(
                BubblEvent.Error(
                    "location_permission_missing",
                    "Location permission is required to start Bubbl location tracking."
                )
            )
            return
        }

        runCatching { BubblLocationUpdatesService.start(context.applicationContext) }
            .onFailure { eventBus.tryEmit(BubblEvent.Error("location_tracking_start_failed", it.message.orEmpty())) }
    }

    fun stopLocationTracking() {
        val context = appContext ?: error("BubblSdk.install(context) must be called before stopLocationTracking().")
        stopLocationTracking(context)
    }

    fun stopLocationTracking(context: Context) {
        runCatching { BubblLocationUpdatesService.stop(context.applicationContext) }
            .onFailure { eventBus.tryEmit(BubblEvent.Error("location_tracking_stop_failed", it.message.orEmpty())) }
    }

    suspend fun refresh() {
        getConfiguration()
        refreshPush()
    }

    suspend fun refreshGeofence(location: BubblLocation) {
        recordLocationUpdate(location)
        val activeConfig = requireConfig()
        val activeState = requireState()
        val body = JSONObject()
            .put("latitude", location.latitude.toString())
            .put("longitude", location.longitude.toString())
            .put("distance", BubblTransportMap.transmissionDistanceMiles(activeConfig.defaultDistanceMeters))
            .put("segmentationTags", activeState.segments.joinToString(","))

        val response = sendRuntime(
            method = "POST",
            path = BubblTransportMap.refreshGeofencePath,
            body = body.toString(),
            cacheName = "geofence"
        )
        cachedConfiguration = configurationFrom(response)
        processGeofenceRuntime(response, location)
    }

    suspend fun handleLocationUpdate(location: BubblLocation) {
        refreshGeofence(location)
    }

    suspend fun refreshPush() {
        val response = sendRuntime(
            method = "GET",
            path = BubblTransportMap.refreshPushPath,
            body = null,
            cacheName = "push"
        )
        cachedConfiguration = configurationFrom(response)
        dispatchRuntimeNotifications(response)
    }

    suspend fun getConfiguration(): BubblConfiguration? = try {
        val response = sendRuntime(
            method = "GET",
            path = BubblTransportMap.getConfigurationPath,
            body = null,
            cacheName = "config"
        )
        configurationFrom(response).also { cachedConfiguration = it }
    } catch (error: Throwable) {
        eventBus.tryEmit(BubblEvent.Error("runtime_configuration_failed", error.message.orEmpty()))
        cachedConfiguration ?: cachedConfigurationFromDisk()
    }

    suspend fun getPrivacyText(): String = getConfiguration()?.privacyText.orEmpty()

    suspend fun updateSegments(tags: List<String>) {
        val nextState = requireState().copy(segments = tags)
        saveState(nextState)

        enqueue(
            path = BubblTransportMap.updateSegmentsPath,
            payload = JSONObject()
                .put("device_registered_id", nextState.installId)
                .put("segmentation", JSONArray(tags))
        )
    }

    suspend fun setCorrelationId(value: String) {
        saveState(requireState().copy(correlationId = value))
    }

    suspend fun clearCorrelationId() {
        saveState(requireState().copy(correlationId = null))
    }

    suspend fun setDefaultNotificationModalEnabled(enabled: Boolean) {
        val nextConfig = requireConfig().copy(enableDefaultNotificationModal = enabled)
        config = nextConfig
        store.saveConfig(nextConfig)
    }

    suspend fun registerPushToken(token: String) {
        val activeConfig = requireConfig()
        val nextState = requireState().copy(pushToken = token)
        saveState(nextState)

        enqueue(
            path = BubblTransportMap.registerDevicePath,
            payload = deviceRegistrationPayload(activeConfig, nextState)
        )
    }

    suspend fun syncFcmToken(token: String) {
        registerPushToken(token)
    }

    internal fun syncCurrentFcmTokenAsync(context: Context) {
        backgroundScope.launch {
            runCatching { syncCurrentFcmToken(context.applicationContext) }
                .onFailure { error ->
                    Log.w(logTag, "REG-TOKEN-02 token sync failed", error)
                    eventBus.tryEmit(BubblEvent.Error("fcm_token_sync_failed", error.message.orEmpty()))
                }
        }
    }

    internal suspend fun syncCurrentFcmToken(context: Context): Boolean {
        if (config?.enablePushHandling != true) {
            return false
        }

        appContext = context.applicationContext
        if (!hasFirebaseAppConfig(context.applicationContext)) {
            val message = "Firebase is not configured for this app. Add google-services.json and apply the Google Services Gradle plugin so the SDK can obtain an FCM token."
            Log.w(logTag, "REG-TOKEN-00 $message")
            eventBus.tryEmit(BubblEvent.Error("firebase_config_missing", message))
            return false
        }

        Log.d(logTag, "REG-TOKEN-01 requesting current FCM token")

        val token = currentFcmToken()
        if (token.isBlank()) {
            Log.w(logTag, "REG-TOKEN-01 FCM returned a blank token")
            eventBus.tryEmit(BubblEvent.Error("fcm_token_blank", "Firebase returned a blank FCM token."))
            return false
        }

        Log.i(logTag, "New FCM token received (${token.length} chars)")
        registerPushToken(token)

        val result = flush()
        return if (result.pendingCount == 0) {
            Log.i(logTag, "REG-TOKEN-02 token synced successfully")
            true
        } else {
            Log.w(logTag, "REG-TOKEN-02 token queued but ${result.pendingCount} ingest request(s) remain pending")
            false
        }
    }

    suspend fun handleFirebasePayload(
        payload: Map<String, String>,
        messageId: String? = null,
        notificationTitle: String? = null,
        notificationBody: String? = null
    ): BubblNotificationPayload? {
        val notification = BubblNotificationPayloadParser.fromFirebasePayload(
            payload = payload,
            messageId = messageId,
            notificationTitle = notificationTitle,
            notificationBody = notificationBody
        )

        if (notification == null) {
            eventBus.tryEmit(BubblEvent.Error("notification_payload_invalid", "Firebase payload did not contain notification content."))
            return null
        }

        handleNotificationPayload(notification)
        return notification
    }

    fun openNotificationIntent(activity: Activity, intent: Intent?): Boolean =
        openNotificationIntent(activity, intent, BubblNotificationTapPresentation.Auto)

    fun openNotificationIntent(
        activity: Activity,
        intent: Intent?,
        presentation: BubblNotificationTapPresentation
    ): Boolean {
        val launchIntent = intent ?: return false
        if (launchIntent.getBooleanExtra(BubblNotificationPayloadCodec.extraHandledByHost, false)) {
            return false
        }

        val payload = BubblNotificationPayloadCodec.fromIntent(launchIntent)
            ?: BubblNotificationPayloadParser.fromFirebaseIntent(launchIntent)
            ?: return false
        val action = launchIntent.getStringExtra(BubblNotificationPayloadCodec.extraAction)
            ?: BubblNotificationPayloadCodec.actionDefault
        val tap = BubblNotificationTap(payload, action)

        return when (presentation) {
            BubblNotificationTapPresentation.HostModal -> openHostNotificationIntent(activity, tap)
            BubblNotificationTapPresentation.DefaultModal -> openDefaultNotificationIntent(
                activity = activity,
                tap = tap,
                forceDefaultModal = true
            )
            BubblNotificationTapPresentation.Auto -> openDefaultNotificationIntent(
                activity = activity,
                tap = tap,
                forceDefaultModal = false
            )
        }
    }

    private fun openDefaultNotificationIntent(
        activity: Activity,
        tap: BubblNotificationTap,
        forceDefaultModal: Boolean
    ): Boolean {
        return startDefaultNotificationActivity(
            context = activity,
            tap = tap,
            forceDefaultModal = forceDefaultModal,
            includeNewTaskFlag = false,
            errorCode = "notification_intent_open_failed"
        )
    }

    private fun openHostNotificationIntent(activity: Activity, tap: BubblNotificationTap): Boolean {
        installIfNeeded(activity.applicationContext)
        val queuedForLater = queuePendingNotificationTapIfNoSubscribers(tap)

        backgroundScope.launch {
            runCatching {
                if (restoreForBackground()) {
                    recordNotificationOpen(
                        payload = tap.payload,
                        action = tap.action,
                        emitEvent = !queuedForLater,
                        queueIfNoSubscribers = false
                    )
                    flush()
                } else if (!queuedForLater) {
                    eventBus.tryEmit(BubblEvent.NotificationTapped(tap.payload, tap.action))
                }
                Unit
            }.onFailure { error ->
                eventBus.tryEmit(BubblEvent.Error("notification_intent_open_failed", error.message.orEmpty()))
            }
        }

        return true
    }

    private fun installIfNeeded(context: Context) {
        if (appContext == null) {
            install(context)
        } else {
            appContext = context.applicationContext
        }
    }

    fun drainPendingNotificationTaps(): List<BubblNotificationTap> =
        synchronized(pendingNotificationTapLock) {
            pendingNotificationTaps.toList().also { pendingNotificationTaps.clear() }
        }

    suspend fun openNotificationModal(
        context: Context,
        payload: BubblNotificationPayload,
        action: String? = null
    ): Boolean {
        installIfNeeded(context.applicationContext)
        requireConfig()

        return withContext(Dispatchers.Main.immediate) {
            startDefaultNotificationActivity(
                context = context,
                tap = BubblNotificationTap(payload, action ?: BubblNotificationPayloadCodec.actionDefault),
                forceDefaultModal = true,
                includeNewTaskFlag = context !is Activity,
                errorCode = "notification_modal_open_failed"
            )
        }
    }

    private fun startDefaultNotificationActivity(
        context: Context,
        tap: BubblNotificationTap,
        forceDefaultModal: Boolean,
        includeNewTaskFlag: Boolean,
        errorCode: String
    ): Boolean {
        val modalIntent = Intent(context, BubblNotificationActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
            .putExtra(BubblNotificationPayloadCodec.extraForceDefaultModal, forceDefaultModal)
        if (includeNewTaskFlag) {
            modalIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        BubblNotificationPayloadCodec.addToIntent(modalIntent, tap.payload, tap.action)

        return runCatching {
            context.startActivity(modalIntent)
            true
        }.getOrElse { error ->
            eventBus.tryEmit(BubblEvent.Error(errorCode, error.message.orEmpty()))
            false
        }
    }

    suspend fun showNotification(payload: BubblNotificationPayload): BubblNotificationDisplayResult {
        recordNotificationReceived(payload)
        return try {
            renderDefaultNotification(payload)
        } finally {
            flushNotificationTelemetry()
        }
    }

    suspend fun handleNotificationPayload(payload: BubblNotificationPayload): BubblNotificationDisplayResult {
        val activeConfig = requireConfig()
        recordNotificationReceived(payload)

        return try {
            if (!activeConfig.enablePushHandling) {
                BubblNotificationDisplayResult(displayed = false, reason = "push_handling_disabled")
            } else {
                when (activeConfig.notificationRenderingMode) {
                    BubblNotificationRenderingMode.SdkDefault -> renderDefaultNotification(payload)
                    BubblNotificationRenderingMode.HostRendered ->
                        BubblNotificationDisplayResult(displayed = false, reason = "host_rendered")
                    BubblNotificationRenderingMode.EventOnly ->
                        BubblNotificationDisplayResult(displayed = false, reason = "event_only")
                }
            }
        } finally {
            flushNotificationTelemetry()
        }
    }

    suspend fun handleNotificationOpen(payload: BubblNotificationPayload, action: String? = null) {
        recordNotificationOpen(
            payload = payload,
            action = action,
            emitEvent = true,
            queueIfNoSubscribers = true
        )
    }

    private suspend fun recordNotificationOpen(
        payload: BubblNotificationPayload,
        action: String?,
        emitEvent: Boolean,
        queueIfNoSubscribers: Boolean
    ) {
        requireConfig()
        if (queueIfNoSubscribers) {
            queuePendingNotificationTapIfNoSubscribers(BubblNotificationTap(payload, action))
        }
        if (emitEvent) {
            eventBus.tryEmit(BubblEvent.NotificationTapped(payload, action))
        }
        track(notificationInteractionEvent(payload, "notification_opened"))
    }

    private fun queuePendingNotificationTapIfNoSubscribers(tap: BubblNotificationTap): Boolean {
        if (eventBus.subscriptionCount.value > 0) {
            return false
        }

        synchronized(pendingNotificationTapLock) {
            val alreadyQueued = pendingNotificationTaps.any { pending ->
                pending.payload.id == tap.payload.id && pending.action == tap.action
            }
            if (!alreadyQueued) {
                pendingNotificationTaps += tap
            }
        }

        return true
    }

    suspend fun handleNotificationCta(payload: BubblNotificationPayload, action: String? = null) {
        requireConfig()
        eventBus.tryEmit(BubblEvent.NotificationCtaTapped(payload, action ?: payload.cta?.action))
        track(notificationInteractionEvent(payload, "notification_cta_tapped"))
        markGeofenceCtaSuspended(payload)
    }

    suspend fun handleNotificationMediaViewed(payload: BubblNotificationPayload) {
        requireConfig()
        eventBus.tryEmit(BubblEvent.NotificationMediaViewed(payload))
        track(notificationInteractionEvent(payload, "notification_media_viewed"))
    }

    suspend fun handleNotificationSurveyRequested(payload: BubblNotificationPayload) {
        requireConfig()
        eventBus.tryEmit(BubblEvent.NotificationSurveyRequested(payload))
        track(notificationInteractionEvent(payload, "notification_survey_requested"))
    }

    private suspend fun renderDefaultNotification(payload: BubblNotificationPayload): BubblNotificationDisplayResult {
        val activeConfig = requireConfig()
        if (!activeConfig.enablePushHandling) {
            return BubblNotificationDisplayResult(displayed = false, reason = "push_handling_disabled")
        }

        val context = appContext
        val result = if (context == null) {
            BubblNotificationDisplayResult(displayed = false, reason = "android_context_not_installed")
        } else {
            BubblAndroidNotificationRuntime.show(context, payload)
        }

        if (result.displayed) {
            eventBus.tryEmit(BubblEvent.NotificationDisplayed(payload))
            track(notificationDeliveredEvent(payload))
        } else if (result.reason !in setOf("duplicate_notification")) {
            eventBus.tryEmit(BubblEvent.Error("notification_display_failed", result.reason.orEmpty()))
        }

        return result
    }

    private suspend fun dispatchRuntimeNotifications(body: String) {
        val payloads = BubblRuntimeNotificationExtractor.fromRuntimeResponse(body)
        payloads.forEach { payload ->
            runCatching { handleNotificationPayload(payload) }
                .onFailure { error ->
                    eventBus.tryEmit(BubblEvent.Error("runtime_notification_failed", error.message.orEmpty()))
                }
        }
    }

    private suspend fun recordLocationUpdate(location: BubblLocation) {
        requireState()
        eventBus.tryEmit(BubblEvent.LocationUpdated(location))
        track(
            BubblTrackEvent(
                type = "location",
                activity = "location_update",
                latitude = location.latitude,
                longitude = location.longitude
            )
        )
    }

    private suspend fun recordNotificationReceived(payload: BubblNotificationPayload) {
        eventBus.tryEmit(BubblEvent.NotificationReceived(payload))
        track(notificationSentEvent(payload))
    }

    private suspend fun flushNotificationTelemetry() {
        runCatching { flush() }
            .onFailure { error ->
                eventBus.tryEmit(BubblEvent.Error("notification_telemetry_flush_failed", error.message.orEmpty()))
            }
    }

    private suspend fun processGeofenceRuntime(body: String, location: BubblLocation) {
        eventBus.tryEmit(
            BubblEvent.GeofenceSnapshot(
                BubblGeofenceSnapshotParser.fromRuntimeResponse(body)
            )
        )

        val state = loadGeofenceState()
        val evaluation = BubblGeofenceEngine.evaluate(
            runtimeResponse = body,
            location = location,
            state = state
        )
        saveGeofenceState(evaluation.nextState)

        for (transition in evaluation.transitions) {
            eventBus.tryEmit(
                when (transition.type) {
                    BubblGeofenceTransitionType.Enter -> BubblEvent.GeofenceEntered(transition)
                    BubblGeofenceTransitionType.Exit -> BubblEvent.GeofenceExited(transition)
                }
            )
            track(transitionEvent(transition))
        }

        for (dispatch in evaluation.notifications) {
            enqueueGeofenceNotificationBatch(dispatch)
            runCatching { handleNotificationPayload(dispatch.payload) }
                .onFailure { error ->
                    eventBus.tryEmit(BubblEvent.Error("geofence_notification_failed", error.message.orEmpty()))
                }
        }
    }

    suspend fun track(event: BubblTrackEvent) {
        val activeState = requireState()
        val dashboardActivity = dashboardActivityName(event.activity) ?: return
        val payload = JSONObject()
            .put("device_registered_id", activeState.installId)
            .put("type", event.type)
            .put("activity", dashboardActivity)
            .put("time", isoNow())

        event.locationId?.toIntOrNull()?.let { payload.put("location_id", it) }
        val curatedNotificationId = event.curatedNotificationId?.toIntOrNull()
        if (event.type == "notification") {
            if (curatedNotificationId == null) {
                eventBus.tryEmit(
                    BubblEvent.Error(
                        "notification_missing_curated_id",
                        "Notification analytics require a Dashboard curated notification id."
                    )
                )
                return
            }
            payload.put("curated_notification_id", curatedNotificationId)
        } else if (curatedNotificationId != null) {
            payload.put("curated_notification_id", curatedNotificationId)
        }
        event.latitude?.let { payload.put("latitude", it) }
        event.longitude?.let { payload.put("longitude", it) }

        enqueue(path = BubblTransportMap.trackEventPath, payload = payload)
    }

    suspend fun submitSurveyResponse(response: BubblSurveyResponse) {
        val activeState = requireState()
        val payload = JSONObject()
            .put("device_registered_id", activeState.installId)
            .put("activity", "survey_submit")
            .put("curated_notification_id", response.curatedNotificationId.toIntOrNull() ?: response.curatedNotificationId)
            .put("responses", JSONArray(response.answers.map(::surveyAnswerPayload)))
            .put("time", isoNow())

        response.locationId?.toIntOrNull()?.let { payload.put("location_id", it) }

        enqueue(path = BubblTransportMap.submitSurveyResponsePath, payload = payload)
    }

    suspend fun flush(): BubblFlushResult {
        val queue = runCatching { store.loadQueue() }.getOrElse {
            eventBus.tryEmit(BubblEvent.Error("ingest_queue_failed", it.message.orEmpty()))
            return BubblFlushResult(pendingCount = store.pendingCount())
        }
        val remaining = mutableListOf<BubblQueuedRequest>()

        queue.forEach { entry ->
            runCatching { sendIngest(entry) }
                .onFailure { error ->
                    remaining += entry.withAttempt()
                    eventBus.tryEmit(BubblEvent.Error("ingest_flush_failed", error.message.orEmpty()))
                }
        }

        store.saveQueue(remaining)
        eventBus.tryEmit(
            BubblEvent.Diagnostic(
                BubblDiagnostics(
                    booted = booted,
                    pendingIngestCount = remaining.size,
                    pushTokenSuffix = pushTokenSuffix(state?.pushToken)
                )
            )
        )

        return BubblFlushResult(pendingCount = remaining.size)
    }

    suspend fun diagnostics(): BubblDiagnostics {
        val currentState = state ?: runCatching { store.loadState() }.getOrNull()
        return BubblDiagnostics(
            booted = booted,
            pendingIngestCount = store.pendingCount(),
            pushTokenSuffix = pushTokenSuffix(currentState?.pushToken)
        )
    }

    private fun pushTokenSuffix(token: String?): String? =
        token
            ?.trim()
            ?.takeIf { it.isNotEmpty() }
            ?.takeLast(7)

    private suspend fun enqueue(path: String, payload: JSONObject) {
        store.append(BubblQueuedRequest(path = path, body = payload.toString()))
        appContext?.let { BubblWorkScheduler.scheduleFlush(it) }
    }

    private suspend fun sendRuntime(method: String, path: String, body: String?, cacheName: String): String {
        val activeConfig = requireConfig()
        val activeState = requireState()
        val request = BubblHttpRequest(
            method = method,
            url = endpointUrl(BubblTransportMap.transmissionBaseUrl(activeConfig), path),
            headers = headers(BubblTransportMap.runtimeAuthHeader, activeConfig, activeState),
            body = body
        )

        return try {
            val response = transport.send(request)
            check(response.statusCode in 200..299) { "Runtime returned HTTP ${response.statusCode}" }
            store.saveRuntimeCache(cacheName, response.body)
            response.body
        } catch (error: Throwable) {
            store.loadRuntimeCache(cacheName) ?: throw error
        }
    }

    private suspend fun sendIngest(entry: BubblQueuedRequest) {
        val activeConfig = requireConfig()
        val activeState = requireState()
        val requestHeaders = headers(BubblTransportMap.ingestAuthHeader, activeConfig, activeState) +
            mapOf("Idempotency-Key" to entry.idempotencyKey)
        val response = transport.send(
            BubblHttpRequest(
                method = "POST",
                url = endpointUrl(BubblTransportMap.ingestBaseUrl(activeConfig), entry.path),
                headers = requestHeaders,
                body = entry.body
            )
        )

        check(response.statusCode in 200..299) { "Ingest returned HTTP ${response.statusCode}" }
    }

    private fun requireConfig(): BubblConfig = config ?: error("BubblSdk.boot(config) must be called first")
    private fun requireState(): BubblStoredState = state ?: error("BubblSdk.boot(config) must be called first")

    private suspend fun saveState(nextState: BubblStoredState) {
        store.saveState(nextState)
        state = nextState
    }

    internal suspend fun restoreForBackground(): Boolean {
        val restoredConfig = store.loadConfig() ?: return false
        val restoredState = store.loadState()
        config = restoredConfig
        state = restoredState
        cachedConfiguration = cachedConfigurationFromDisk()
        return true
    }

    internal fun hasRuntimeState(): Boolean =
        config != null && state != null

    internal fun defaultNotificationModalEnabled(): Boolean =
        config?.enableDefaultNotificationModal ?: true

    internal suspend fun refreshGeofenceFromLastKnownLocation(context: Context): Boolean {
        val activeConfig = config ?: return false
        if (!activeConfig.enableLocationTracking) return false

        val location = BubblAndroidLocationProvider.lastKnownLocation(context) ?: return false
        refreshGeofence(location)
        return true
    }

    internal fun locationTrackingEnabled(): Boolean =
        config?.enableLocationTracking == true

    internal fun locationTrackingSettings(): BubblLocationTrackingSettings {
        val activeConfig = config
        return BubblLocationTrackingSettings(
            minTimeMillis = ((activeConfig?.refreshIntervalSeconds ?: 60).coerceAtLeast(30) * 1_000L),
            minDistanceMeters = (activeConfig?.defaultDistanceMeters ?: 50).coerceAtLeast(10).toFloat()
        )
    }

    internal fun emitError(code: String, message: String) {
        eventBus.tryEmit(BubblEvent.Error(code, message))
    }

    private suspend fun cachedConfigurationFromDisk(): BubblConfiguration? {
        for (name in listOf("config", "geofence", "push")) {
            val cached = store.loadRuntimeCache(name) ?: continue
            val configuration = runCatching { configurationFrom(cached) }.getOrNull()
            if (configuration != null) {
                return configuration
            }
        }

        return null
    }

    private suspend fun currentFcmToken(): String =
        suspendCancellableCoroutine { continuation ->
            val task = FirebaseMessaging.getInstance().token
            task.addOnSuccessListener { token ->
                if (continuation.isActive) {
                    continuation.resume(token.orEmpty())
                }
            }
            task.addOnFailureListener { error ->
                if (continuation.isActive) {
                    continuation.resumeWithException(error)
                }
            }
            task.addOnCanceledListener {
                if (continuation.isActive) {
                    continuation.resumeWithException(IllegalStateException("Firebase token request was cancelled."))
                }
            }
        }

    private fun hasFirebaseAppConfig(context: Context): Boolean {
        val resourceId = context.resources.getIdentifier("google_app_id", "string", context.packageName)
        if (resourceId == 0) {
            return false
        }

        return runCatching { context.getString(resourceId).isNotBlank() }.getOrDefault(false)
    }

    private suspend fun loadGeofenceState(): BubblGeofenceState =
        store.loadRuntimeCache("geofence-state")
            ?.let { runCatching { BubblGeofenceState.fromJson(JSONObject(it)) }.getOrNull() }
            ?: BubblGeofenceState()

    private suspend fun saveGeofenceState(state: BubblGeofenceState) {
        store.saveRuntimeCache("geofence-state", state.toJson().toString())
    }

    private suspend fun markGeofenceCtaSuspended(payload: BubblNotificationPayload) {
        val triggerKey = payload.raw[BubblGeofenceTriggerMetadata.triggerKey]
            ?.takeIf { it.isNotBlank() }
            ?: return
        val shouldSuspend = payload.raw[BubblGeofenceTriggerMetadata.ctaSuspend]
            ?.let { value ->
                value.equals("true", ignoreCase = true) ||
                    value == "1" ||
                    value.equals("yes", ignoreCase = true)
            }
            ?: false

        if (!shouldSuspend) return

        val state = loadGeofenceState()
        if (triggerKey in state.ctaSuspensions) return

        saveGeofenceState(
            state.copy(ctaSuspensions = state.ctaSuspensions + triggerKey)
        )
    }

    private fun configurationFrom(body: String): BubblConfiguration {
        val configuration = JSONObject(body).getJSONObject("configuration")
        return BubblConfiguration(
            notificationsCount = configuration.optInt("notificationsCount"),
            daysCount = configuration.optInt("daysCount"),
            batteryCount = configuration.optInt("batteryCount"),
            privacyText = configuration.optString("privacyText")
        )
    }

    private fun headers(authHeader: String, config: BubblConfig, state: BubblStoredState): Map<String, String> =
        mapOf(
            authHeader to config.apiKey,
            "Content-Type" to "application/json",
            "Accept" to "application/json",
            "X-Bubbl-SDK-Version" to BubblTransportMap.sdkVersion,
            "X-Bubbl-SDK-Platform" to BubblTransportMap.platform,
            "X-Bubbl-Request-ID" to java.util.UUID.randomUUID().toString(),
            "X-Bubbl-Install-ID" to state.installId
        )

    private fun deviceRegistrationPayload(config: BubblConfig, state: BubblStoredState): JSONObject =
        JSONObject()
            .put("app_name", "Bubbl Android App")
            .put("api_key", config.apiKey)
            .put("sdk_version", BubblTransportMap.sdkVersion)
            .put("platform", BubblTransportMap.platform)
            .put("os_version", Build.VERSION.RELEASE ?: "")
            .put("device_model", Build.MODEL ?: "Android device")
            .put("device_name", Build.DEVICE ?: "Android device")
            .put("manufacturer", Build.MANUFACTURER ?: "Android")
            .put("country", Locale.getDefault().country.orEmpty())
            .put("language", Locale.getDefault().language.orEmpty())
            .put("device_id", state.installId)
            .put("segmentations", JSONArray(state.segments))
            .put("correlation_id", state.correlationId ?: JSONObject.NULL)
            .put("bubbl_id", state.installId)
            .put("device_token", state.pushToken ?: JSONObject.NULL)

    private fun deviceDataPayload(config: BubblConfig, state: BubblStoredState, activity: String): JSONObject =
        JSONObject()
            .put("device_registered", deviceRegistrationPayload(config, state))
            .put(
                "plugin_activity",
                JSONObject()
                    .put("device_registered_id", state.installId)
                    .put("time", isoNow())
                    .put("activity", activity)
            )
            .put(
                "raw_data",
                JSONObject()
                    .put("event", "boot")
                    .put(
                        "request",
                        JSONObject()
                            .put("source", "sdk-v3")
                            .put("environment", config.environment.name.lowercase())
                    )
            )

    private fun surveyAnswerPayload(answer: BubblSurveyAnswer): JSONObject =
        JSONObject()
            .put("question_id", answer.questionId.toIntOrNull() ?: answer.questionId)
            .put("type", answer.type)
            .put("value", answer.value ?: JSONObject.NULL)
            .put(
                "choice",
                JSONArray(answer.choiceIds.map { choiceId ->
                    JSONObject().put("choice_id", choiceId.toIntOrNull() ?: choiceId)
                })
            )

    private fun notificationDeliveredEvent(payload: BubblNotificationPayload): BubblTrackEvent =
        BubblTrackEvent(
            type = "notification",
            activity = "notification_delivered",
            locationId = payload.locationId,
            curatedNotificationId = payload.curatedNotificationId
        )

    private fun notificationSentEvent(payload: BubblNotificationPayload): BubblTrackEvent =
        BubblTrackEvent(
            type = "notification",
            activity = "notification_sent",
            locationId = payload.locationId,
            curatedNotificationId = payload.curatedNotificationId
        )

    private fun notificationInteractionEvent(payload: BubblNotificationPayload, activity: String): BubblTrackEvent =
        BubblTrackEvent(
            type = "notification",
            activity = activity,
            locationId = payload.locationId,
            curatedNotificationId = payload.curatedNotificationId
        )

    private fun transitionEvent(transition: BubblGeofenceTransition): BubblTrackEvent =
        BubblTrackEvent(
            type = "geofence",
            activity = when (transition.type) {
                BubblGeofenceTransitionType.Enter -> "geofence_entry"
                BubblGeofenceTransitionType.Exit -> "geofence_exit"
            },
            locationId = transition.locationId,
            latitude = transition.location.latitude,
            longitude = transition.location.longitude
        )

    private fun dashboardActivityName(activity: String): String? =
        when (activity) {
            "notification_cta_tapped",
            "cta_engagement" -> "cta_engagment"
            "notification_media_viewed" -> "media_viewed"
            "notification_dismissed" -> "dismissed"
            "notification_opened",
            "notification_survey_requested" -> null
            else -> activity
        }

    private suspend fun enqueueGeofenceNotificationBatch(dispatch: BubblGeofenceNotificationDispatch) {
        val activeState = requireState()
        val transition = dispatch.transition
        val payload = dispatch.payload
        val notificationId = payload.curatedNotificationId?.toIntOrNull() ?: return
        val locationId = transition.locationId?.toIntOrNull() ?: payload.locationId?.toIntOrNull() ?: return
        val time = isoNow()

        enqueue(
            path = BubblTransportMap.trackGeofenceBatchPath,
            payload = JSONObject()
                .put(
                    "geo",
                    JSONObject()
                        .put("location_id", locationId)
                        .put("device_registered_id", activeState.installId)
                        .put("time", time)
                        .put(
                            "activity",
                            when (transition.type) {
                                BubblGeofenceTransitionType.Enter -> "geofence_entry"
                                BubblGeofenceTransitionType.Exit -> "geofence_exit"
                            }
                        )
                        .put("latitude", transition.location.latitude)
                        .put("longitude", transition.location.longitude)
                )
                .put(
                    "location",
                    JSONObject()
                        .put("device_registered_id", activeState.installId)
                        .put("time", time)
                        .put("activity", "location_update")
                        .put("latitude", transition.location.latitude)
                        .put("longitude", transition.location.longitude)
                )
                .put(
                    "notification",
                    JSONObject()
                        .put("device_registered_id", activeState.installId)
                        .put("time", time)
                        .put("activity", "notification_sent")
                        .put("curated_notification_id", notificationId)
                        .put("allow", true)
                )
        )
    }

    private fun endpointUrl(baseUrl: String, path: String): String =
        baseUrl.trimEnd('/') + path

    private fun isoNow(): String = Instant.now().toString()

    private fun defaultStorageDirectory(): File =
        File(System.getProperty("java.io.tmpdir") ?: ".", "tech.bubbl.sdk")
}
