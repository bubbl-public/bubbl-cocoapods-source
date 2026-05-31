package tech.bubbl.sdk

import android.Manifest
import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Build
import android.os.IBinder
import android.os.Looper
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject
import java.time.Duration
import java.time.Instant

internal data class BubblGeofenceEvaluation(
    val transitions: List<BubblGeofenceTransition>,
    val notifications: List<BubblGeofenceNotificationDispatch>,
    val nextState: BubblGeofenceState
)

internal data class BubblGeofenceNotificationDispatch(
    val transition: BubblGeofenceTransition,
    val payload: BubblNotificationPayload
)

internal object BubblGeofenceTriggerMetadata {
    const val triggerKey = "bubblGeofenceTriggerKey"
    const val ctaSuspend = "bubblGeofenceCtaSuspend"
}

internal data class BubblGeofenceState(
    val regions: Map<String, BubblGeofenceRegionState> = emptyMap(),
    val triggers: Map<String, BubblGeofenceTriggerState> = emptyMap(),
    val ctaSuspensions: Set<String> = emptySet(),
    val lastLocation: BubblLocation? = null
) {
    fun toJson(): JSONObject {
        val regionJson = JSONObject()
        regions.forEach { (key, value) -> regionJson.put(key, value.toJson()) }

        val triggerJson = JSONObject()
        triggers.forEach { (key, value) -> triggerJson.put(key, value.toJson()) }

        return JSONObject()
            .put("regions", regionJson)
            .put("triggers", triggerJson)
            .put("ctaSuspensions", JSONArray(ctaSuspensions.toList()))
            .put(
                "lastLocation",
                lastLocation?.let {
                    JSONObject()
                        .put("latitude", it.latitude)
                        .put("longitude", it.longitude)
                } ?: JSONObject.NULL
            )
    }

    companion object {
        fun fromJson(json: JSONObject): BubblGeofenceState {
            val regions = json.optJSONObject("regions")?.toMapValues { BubblGeofenceRegionState.fromJson(it) }.orEmpty()
            val triggers = json.optJSONObject("triggers")?.toMapValues { BubblGeofenceTriggerState.fromJson(it) }.orEmpty()
            val ctaSuspensions = json.optJSONArray("ctaSuspensions")?.toStringSet().orEmpty()
            val lastLocation = json.optJSONObject("lastLocation")?.let {
                BubblLocation(
                    latitude = it.optDouble("latitude"),
                    longitude = it.optDouble("longitude")
                )
            }

            return BubblGeofenceState(
                regions = regions,
                triggers = triggers,
                ctaSuspensions = ctaSuspensions,
                lastLocation = lastLocation
            )
        }
    }
}

internal data class BubblGeofenceRegionState(
    val inside: Boolean,
    val updatedAt: String
) {
    fun toJson(): JSONObject = JSONObject()
        .put("inside", inside)
        .put("updatedAt", updatedAt)

    companion object {
        fun fromJson(json: JSONObject): BubblGeofenceRegionState =
            BubblGeofenceRegionState(
                inside = json.optBoolean("inside", false),
                updatedAt = json.optString("updatedAt")
            )
    }
}

internal data class BubblGeofenceTriggerState(
    val count: Int,
    val lastTriggeredAt: String?
) {
    fun toJson(): JSONObject = JSONObject()
        .put("count", count)
        .put("lastTriggeredAt", lastTriggeredAt ?: JSONObject.NULL)

    companion object {
        fun fromJson(json: JSONObject): BubblGeofenceTriggerState =
            BubblGeofenceTriggerState(
                count = json.optInt("count", 0),
                lastTriggeredAt = json.optNullableString("lastTriggeredAt")
            )
    }
}

internal object BubblGeofenceEngine {
    fun evaluate(
        runtimeResponse: String,
        location: BubblLocation,
        state: BubblGeofenceState,
        now: Instant = Instant.now()
    ): BubblGeofenceEvaluation {
        val campaigns = runCatching { parseCampaigns(JSONObject(runtimeResponse)) }.getOrDefault(emptyList())
        val regions = state.regions.toMutableMap()
        val triggers = state.triggers.toMutableMap()
        val transitions = mutableListOf<BubblGeofenceTransition>()
        val notifications = mutableListOf<BubblGeofenceNotificationDispatch>()
        val nowString = now.toString()

        for (campaign in campaigns) {
            val inside = contains(location, campaign.polygon)
            val previous = state.regions[campaign.regionKey]
            val transitionType = when {
                inside && previous?.inside != true -> BubblGeofenceTransitionType.Enter
                !inside && previous?.inside == true -> BubblGeofenceTransitionType.Exit
                else -> null
            }

            regions[campaign.regionKey] = BubblGeofenceRegionState(
                inside = inside,
                updatedAt = nowString
            )

            if (transitionType == null) continue

            val transition = BubblGeofenceTransition(
                type = transitionType,
                campaignId = campaign.campaignId,
                locationId = campaign.locationId,
                location = location
            )
            transitions += transition

            for (candidate in campaign.notifications.filter { it.activation == transitionType }) {
                val triggerKey = listOf(campaign.regionKey, candidate.payload.id, transitionType.name).joinToString(":")
                val previousTrigger = triggers[triggerKey]
                if (!candidate.canTrigger(previousTrigger, state.ctaSuspensions.contains(triggerKey), now)) continue

                notifications += BubblGeofenceNotificationDispatch(
                    transition = transition,
                    payload = candidate.payload.withGeofenceTriggerMetadata(triggerKey, candidate.ctaSuspend)
                )
                triggers[triggerKey] = BubblGeofenceTriggerState(
                    count = (previousTrigger?.count ?: 0) + 1,
                    lastTriggeredAt = nowString
                )
            }
        }

        return BubblGeofenceEvaluation(
            transitions = transitions,
            notifications = notifications,
            nextState = BubblGeofenceState(
                regions = regions,
                triggers = triggers,
                ctaSuspensions = state.ctaSuspensions,
                lastLocation = location
            )
        )
    }

    private fun parseCampaigns(json: JSONObject): List<RuntimeGeofenceCampaign> {
        val campaigns = json.optJSONArray("geoCampaign") ?: return emptyList()
        val defaults = policyDefaults(json)

        return buildList {
            for (campaignIndex in 0 until campaigns.length()) {
                val campaign = campaigns.optJSONObject(campaignIndex) ?: continue
                if (!campaign.optRuntimeBoolean("active", default = true)) continue

                val campaignId = campaign.firstString("campaignId", "id")
                val campaignPolicy = campaign.optJSONObjectOrString("deliveryPolicy")
                val baseActivation = campaignPolicy?.firstString("activation", "trigger", "event", "eventType")
                    ?: campaign.firstString("activation", "trigger", "event", "eventType")
                val baseCooldown = campaignPolicy?.firstInt("coolingPeriodSeconds", "cooldownSeconds", "cooldown")
                    ?: campaign.firstInt("coolingPeriodSeconds", "cooldownSeconds", "cooldown")
                val baseMaximumTriggers = campaignPolicy?.firstInt("maximumTriggers", "maxTriggers")
                    ?: campaign.firstInt("maximumTriggers", "maxTriggers")
                val baseCtaSuspend = campaignPolicy?.firstBoolean("ctaSuspend", "cta_suspend")
                    ?: campaign.firstBoolean("ctaSuspend", "cta_suspend")
                val notifications = notificationCandidates(
                    campaign = campaign,
                    campaignActivation = baseActivation,
                    campaignCooldownSeconds = baseCooldown,
                    campaignMaximumTriggers = baseMaximumTriggers,
                    campaignCtaSuspend = baseCtaSuspend,
                    defaults = defaults
                )
                if (notifications.isEmpty()) continue

                for (locationShape in locationShapes(campaign)) {
                    add(
                        RuntimeGeofenceCampaign(
                            regionKey = listOfNotNull(campaignId, locationShape.locationId).ifEmpty {
                                listOf("campaign-$campaignIndex", "location-${size}")
                            }.joinToString(":"),
                            campaignId = campaignId,
                            locationId = locationShape.locationId,
                            polygon = locationShape.polygon,
                            notifications = notifications
                        )
                    )
                }
            }
        }
    }

    private fun notificationCandidates(
        campaign: JSONObject,
        campaignActivation: String?,
        campaignCooldownSeconds: Int?,
        campaignMaximumTriggers: Int?,
        campaignCtaSuspend: Boolean?,
        defaults: RuntimeGeofencePolicyDefaults
    ): List<RuntimeGeofenceNotification> {
        val notifications = campaign.optJSONArray("notificationsArray") ?: return emptyList()

        return buildList {
            for (index in 0 until notifications.length()) {
                val notification = notifications.optJSONObject(index) ?: continue
                if (!notification.optRuntimeBoolean("published", default = true)) continue
                val policy = notification.optJSONObjectOrString("deliveryPolicy")

                val payload = BubblRuntimeNotificationExtractor.notificationPayload(
                    campaign = campaign,
                    notification = notification,
                    source = BubblNotificationSource.Geofence
                ) ?: continue

                add(
                    RuntimeGeofenceNotification(
                        payload = payload,
                        activation = activationFrom(
                            policy?.firstString("activation", "trigger", "event", "eventType")
                                ?: notification.firstString("activation", "trigger", "event", "eventType")
                                ?: campaignActivation
                        ),
                        cooldownSeconds = policy?.firstInt("coolingPeriodSeconds", "cooldownSeconds", "cooldown")
                            ?: notification.firstInt("coolingPeriodSeconds", "cooldownSeconds", "cooldown")
                            ?: campaignCooldownSeconds
                            ?: defaults.coolingPeriodSeconds,
                        maximumTriggers = policy?.firstInt("maximumTriggers", "maxTriggers")
                            ?: notification.firstInt("maximumTriggers", "maxTriggers")
                            ?: campaignMaximumTriggers
                            ?: defaults.maximumTriggers,
                        ctaSuspend = policy?.firstBoolean("ctaSuspend", "cta_suspend")
                            ?: notification.firstBoolean("ctaSuspend", "cta_suspend")
                            ?: campaignCtaSuspend
                            ?: defaults.ctaSuspend
                    )
                )
            }
        }
    }

    private fun policyDefaults(json: JSONObject): RuntimeGeofencePolicyDefaults {
        val defaults = RuntimeGeofencePolicyDefaults()
        val frequencyDefaults = json.optJSONObject("configuration")
            ?.optJSONObjectOrString("frequencyDefaults")
            ?: return defaults

        return RuntimeGeofencePolicyDefaults(
            coolingPeriodSeconds = frequencyDefaults.firstInt("coolingPeriodSeconds", "cooldownSeconds", "cooldown")
                ?: defaults.coolingPeriodSeconds,
            maximumTriggers = frequencyDefaults.firstInt("maximumTriggers", "maxTriggers")
                ?: defaults.maximumTriggers,
            ctaSuspend = frequencyDefaults.firstBoolean("ctaSuspend", "cta_suspend")
                ?: defaults.ctaSuspend
        )
    }

    private fun locationShapes(campaign: JSONObject): List<RuntimeGeofenceLocationShape> {
        val locationsArray = campaign.opt("locationsArray")

        return when (locationsArray) {
            is JSONObject -> listOfNotNull(locationShape(locationsArray))
            is JSONArray -> buildList {
                for (index in 0 until locationsArray.length()) {
                    val location = locationsArray.optJSONObject(index) ?: continue
                    locationShape(location)?.let(::add)
                }
            }
            else -> emptyList()
        }
    }

    private fun locationShape(json: JSONObject): RuntimeGeofenceLocationShape? {
        val polygon = polygonFrom(
            json.optJSONArray("geofence")
                ?: json.optJSONArray("polygon")
                ?: json.optJSONArray("coordinates")
        )
        if (polygon.size < 3) return null

        return RuntimeGeofenceLocationShape(
            locationId = json.firstString("locationId", "location_id", "id"),
            polygon = polygon
        )
    }

    private fun polygonFrom(points: JSONArray?): List<GeoPoint> {
        if (points == null) return emptyList()

        return buildList {
            for (index in 0 until points.length()) {
                when (val point = points.opt(index)) {
                    is JSONObject -> {
                        val latitude = point.firstDouble("latitude", "lat")
                        val longitude = point.firstDouble("longitude", "lng", "lon")
                        if (latitude != null && longitude != null) {
                            add(GeoPoint(latitude = latitude, longitude = longitude))
                        }
                    }
                    is JSONArray -> {
                        val longitude = point.optDoubleOrNull(0)
                        val latitude = point.optDoubleOrNull(1)
                        if (latitude != null && longitude != null) {
                            add(GeoPoint(latitude = latitude, longitude = longitude))
                        }
                    }
                }
            }
        }
    }

    private fun contains(location: BubblLocation, polygon: List<GeoPoint>): Boolean {
        var inside = false
        var previousIndex = polygon.lastIndex
        val x = location.longitude
        val y = location.latitude

        for (index in polygon.indices) {
            val current = polygon[index]
            val previous = polygon[previousIndex]
            val intersects = ((current.latitude > y) != (previous.latitude > y)) &&
                (x < (previous.longitude - current.longitude) * (y - current.latitude) /
                    ((previous.latitude - current.latitude).takeIf { it != 0.0 } ?: Double.MIN_VALUE) + current.longitude)
            if (intersects) inside = !inside
            previousIndex = index
        }

        return inside
    }

    private fun activationFrom(value: String?): BubblGeofenceTransitionType =
        when (value?.trim()?.uppercase()) {
            "ON_EXIT", "EXIT", "GEOFENCE_EXIT" -> BubblGeofenceTransitionType.Exit
            else -> BubblGeofenceTransitionType.Enter
        }

    private data class RuntimeGeofenceCampaign(
        val regionKey: String,
        val campaignId: String?,
        val locationId: String?,
        val polygon: List<GeoPoint>,
        val notifications: List<RuntimeGeofenceNotification>
    )

    private data class RuntimeGeofenceLocationShape(
        val locationId: String?,
        val polygon: List<GeoPoint>
    )

    private data class RuntimeGeofenceNotification(
        val payload: BubblNotificationPayload,
        val activation: BubblGeofenceTransitionType,
        val cooldownSeconds: Int,
        val maximumTriggers: Int?,
        val ctaSuspend: Boolean
    ) {
        fun canTrigger(previous: BubblGeofenceTriggerState?, ctaSuspended: Boolean, now: Instant): Boolean {
            if (ctaSuspend && ctaSuspended) {
                return false
            }

            if (maximumTriggers != null && maximumTriggers > 0 && (previous?.count ?: 0) >= maximumTriggers) {
                return false
            }

            val lastTriggeredAt = previous?.lastTriggeredAt?.let { runCatching { Instant.parse(it) }.getOrNull() }
            if (lastTriggeredAt != null && cooldownSeconds > 0) {
                return Duration.between(lastTriggeredAt, now).seconds >= cooldownSeconds
            }

            return true
        }
    }

    private data class RuntimeGeofencePolicyDefaults(
        val coolingPeriodSeconds: Int = 259_200,
        val maximumTriggers: Int? = 5,
        val ctaSuspend: Boolean = false
    )

    private data class GeoPoint(val latitude: Double, val longitude: Double)
}

internal object BubblGeofenceSnapshotParser {
    fun fromRuntimeResponse(runtimeResponse: String): BubblGeofenceSnapshot {
        val json = runCatching { JSONObject(runtimeResponse) }.getOrNull()
            ?: return emptySnapshot()
        val campaigns = json.optJSONArray("geoCampaign")
            ?: return emptySnapshot()

        var activeCampaignCount = 0
        val polygons = mutableListOf<BubblGeofencePolygon>()

        for (campaignIndex in 0 until campaigns.length()) {
            val campaign = campaigns.optJSONObject(campaignIndex) ?: continue
            if (!campaign.optRuntimeBoolean("active", default = true)) continue
            if (!hasEligibleNotification(campaign)) continue

            val campaignId = campaign.firstString("campaignId", "campaign_id", "id")
            val campaignName = campaign.firstString("campaignName", "campaign_name", "name", "title")
            val campaignPolygons = locationPolygons(campaign, campaignId, campaignName)
            if (campaignPolygons.isEmpty()) continue

            activeCampaignCount += 1
            polygons += campaignPolygons
        }

        return BubblGeofenceSnapshot(
            stats = BubblGeofenceSnapshotStats(
                campaignsTotal = activeCampaignCount,
                polygonsTotal = polygons.size
            ),
            polygons = polygons,
            circles = polygons.mapNotNull(::deriveCircle)
        )
    }

    private fun emptySnapshot(): BubblGeofenceSnapshot =
        BubblGeofenceSnapshot(
            stats = BubblGeofenceSnapshotStats(campaignsTotal = 0, polygonsTotal = 0),
            polygons = emptyList(),
            circles = emptyList()
        )

    private fun hasEligibleNotification(campaign: JSONObject): Boolean {
        val notifications = campaign.optJSONArray("notificationsArray") ?: return false

        for (index in 0 until notifications.length()) {
            val notification = notifications.optJSONObject(index) ?: continue
            if (!notification.optRuntimeBoolean("published", default = true)) continue

            val payload = BubblRuntimeNotificationExtractor.notificationPayload(
                campaign = campaign,
                notification = notification,
                source = BubblNotificationSource.Geofence
            )
            if (payload != null) {
                return true
            }
        }

        return false
    }

    private fun locationPolygons(
        campaign: JSONObject,
        campaignId: String?,
        campaignName: String?
    ): List<BubblGeofencePolygon> {
        val locationsArray = campaign.opt("locationsArray")

        return when (locationsArray) {
            is JSONObject -> listOfNotNull(locationPolygon(locationsArray, campaignId, campaignName))
            is JSONArray -> buildList {
                for (index in 0 until locationsArray.length()) {
                    val location = locationsArray.optJSONObject(index) ?: continue
                    locationPolygon(location, campaignId, campaignName)?.let(::add)
                }
            }
            else -> emptyList()
        }
    }

    private fun locationPolygon(
        location: JSONObject,
        campaignId: String?,
        campaignName: String?
    ): BubblGeofencePolygon? {
        val vertices = verticesFrom(
            location.optJSONArray("geofence")
                ?: location.optJSONArray("polygon")
                ?: location.optJSONArray("coordinates")
        )
        if (vertices.size < 3) return null

        return BubblGeofencePolygon(
            campaignId = campaignId,
            campaignName = campaignName,
            locationId = location.firstString("locationId", "location_id", "id"),
            vertices = vertices
        )
    }

    private fun verticesFrom(points: JSONArray?): List<BubblGeofenceVertex> {
        if (points == null) return emptyList()

        return buildList {
            for (index in 0 until points.length()) {
                when (val point = points.opt(index)) {
                    is JSONObject -> {
                        val latitude = point.firstDouble("latitude", "lat")
                        val longitude = point.firstDouble("longitude", "lng", "lon")
                        if (latitude != null && longitude != null) {
                            add(BubblGeofenceVertex(latitude = latitude, longitude = longitude))
                        }
                    }
                    is JSONArray -> {
                        val longitude = point.optDoubleOrNull(0)
                        val latitude = point.optDoubleOrNull(1)
                        if (latitude != null && longitude != null) {
                            add(BubblGeofenceVertex(latitude = latitude, longitude = longitude))
                        }
                    }
                }
            }
        }
    }

    private fun deriveCircle(polygon: BubblGeofencePolygon): BubblGeofenceCircle? {
        val vertices = polygon.vertices
        if (vertices.isEmpty()) return null

        val centerLatitude = vertices.sumOf { it.latitude } / vertices.size
        val centerLongitude = vertices.sumOf { it.longitude } / vertices.size
        var radiusMeters = 0.0

        for (vertex in vertices) {
            radiusMeters = maxOf(
                radiusMeters,
                distanceMeters(
                    centerLatitude,
                    centerLongitude,
                    vertex.latitude,
                    vertex.longitude
                )
            )
        }

        return BubblGeofenceCircle(
            campaignId = polygon.campaignId,
            campaignName = polygon.campaignName,
            locationId = polygon.locationId,
            center = BubblGeofenceVertex(
                centerLatitude,
                centerLongitude,
            ),
            radiusMeters = radiusMeters
        )
    }

    private fun distanceMeters(
        fromLatitude: Double,
        fromLongitude: Double,
        toLatitude: Double,
        toLongitude: Double
    ): Double {
        val earthRadiusMeters = 6_371_000.0
        val deltaLatitude = Math.toRadians(toLatitude - fromLatitude)
        val deltaLongitude = Math.toRadians(toLongitude - fromLongitude)
        val fromLatitudeRadians = Math.toRadians(fromLatitude)
        val toLatitudeRadians = Math.toRadians(toLatitude)
        val a = kotlin.math.sin(deltaLatitude / 2) * kotlin.math.sin(deltaLatitude / 2) +
            kotlin.math.cos(fromLatitudeRadians) * kotlin.math.cos(toLatitudeRadians) *
            kotlin.math.sin(deltaLongitude / 2) * kotlin.math.sin(deltaLongitude / 2)
        val c = 2 * kotlin.math.atan2(kotlin.math.sqrt(a), kotlin.math.sqrt(1 - a))

        return earthRadiusMeters * c
    }
}

internal object BubblAndroidLocationProvider {
    fun lastKnownLocation(context: Context): BubblLocation? {
        if (!hasLocationPermission(context)) return null

        val manager = context.getSystemService(Context.LOCATION_SERVICE) as? LocationManager ?: return null
        return manager.getProviders(true)
            .mapNotNull { provider -> runCatching { manager.getLastKnownLocation(provider) }.getOrNull() }
            .maxByOrNull { it.time }
            ?.let { BubblLocation(latitude = it.latitude, longitude = it.longitude) }
    }

    fun hasLocationPermission(context: Context): Boolean =
        ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED ||
            ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED
}

internal data class BubblLocationTrackingSettings(
    val minTimeMillis: Long,
    val minDistanceMeters: Float
)

public class BubblLocationUpdatesService : Service() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var locationManager: LocationManager? = null
    private var registeredProviders: List<String> = emptyList()

    private val listener = object : LocationListener {
        override fun onLocationChanged(location: Location) {
            val bubblLocation = BubblLocation(
                latitude = location.latitude,
                longitude = location.longitude
            )
            scope.launch {
                runCatching { BubblSdk.handleLocationUpdate(bubblLocation) }
                    .onFailure { BubblSdk.emitError("location_update_failed", it.message.orEmpty()) }
            }
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (!BubblAndroidLocationProvider.hasLocationPermission(applicationContext)) {
            BubblSdk.emitError("location_permission_missing", "Location permission is required to start Bubbl location tracking.")
            stopSelf()
            return START_NOT_STICKY
        }

        startAsForegroundService()
        scope.launch {
            val restored = if (BubblSdk.hasRuntimeState()) {
                true
            } else {
                BubblSdk.install(applicationContext)
                BubblSdk.restoreForBackground()
            }
            if (!restored || !BubblSdk.locationTrackingEnabled()) {
                stopSelf()
                return@launch
            }

            if (intent?.action == ACTION_TEST_LOCATION_UPDATE) {
                handleTestLocation(intent)
                if (intent.getBooleanExtra(EXTRA_STOP_AFTER_TEST_LOCATION, true)) {
                    stopSelf()
                }
                return@launch
            }

            runCatching { startLocationUpdates(BubblSdk.locationTrackingSettings()) }
                .onFailure {
                    BubblSdk.emitError("location_tracking_failed", it.message.orEmpty())
                    stopSelf()
                }
        }

        return START_STICKY
    }

    override fun onDestroy() {
        stopLocationUpdates()
        scope.cancel()
        super.onDestroy()
    }

    private fun startAsForegroundService() {
        createNotificationChannel()
        val notification = foregroundNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    @SuppressLint("MissingPermission")
    private fun startLocationUpdates(settings: BubblLocationTrackingSettings) {
        val manager = getSystemService(Context.LOCATION_SERVICE) as? LocationManager
            ?: error("LocationManager is not available.")
        locationManager = manager
        val providers = listOf(
            LocationManager.GPS_PROVIDER,
            LocationManager.NETWORK_PROVIDER,
            LocationManager.PASSIVE_PROVIDER
        ).filter { provider -> runCatching { manager.isProviderEnabled(provider) }.getOrDefault(false) }

        if (providers.isEmpty()) {
            error("No enabled location providers are available.")
        }

        registeredProviders = providers
        providers.forEach { provider ->
            manager.requestLocationUpdates(
                provider,
                settings.minTimeMillis,
                settings.minDistanceMeters,
                listener,
                Looper.getMainLooper()
            )
        }
    }

    private fun stopLocationUpdates() {
        locationManager?.let { manager ->
            runCatching { manager.removeUpdates(listener) }
        }
        registeredProviders = emptyList()
        locationManager = null
    }

    private suspend fun handleTestLocation(intent: Intent) {
        val latitude = intent.getDoubleExtra(EXTRA_TEST_LATITUDE, Double.NaN)
        val longitude = intent.getDoubleExtra(EXTRA_TEST_LONGITUDE, Double.NaN)
        if (latitude.isNaN() || longitude.isNaN()) {
            BubblSdk.emitError("location_test_payload_invalid", "Test location intent was missing latitude or longitude.")
            return
        }

        BubblSdk.handleLocationUpdate(
            BubblLocation(
                latitude = latitude,
                longitude = longitude
            )
        )
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Bubbl location",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "Keeps Bubbl geofence campaigns up to date."
        }
        manager.createNotificationChannel(channel)
    }

    private fun foregroundNotification(): Notification =
        NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_menu_mylocation)
            .setContentTitle("Bubbl location active")
            .setContentText("Checking nearby Bubbl campaigns.")
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()

    public companion object {
        internal const val ACTION_TEST_LOCATION_UPDATE = "tech.bubbl.sdk.action.TEST_LOCATION_UPDATE"
        internal const val EXTRA_TEST_LATITUDE = "tech.bubbl.sdk.extra.TEST_LATITUDE"
        internal const val EXTRA_TEST_LONGITUDE = "tech.bubbl.sdk.extra.TEST_LONGITUDE"
        internal const val EXTRA_STOP_AFTER_TEST_LOCATION = "tech.bubbl.sdk.extra.STOP_AFTER_TEST_LOCATION"

        private const val CHANNEL_ID = "bubbl_location"
        private const val NOTIFICATION_ID = 7301

        public fun start(context: Context) {
            val appContext = context.applicationContext
            val intent = Intent(appContext, BubblLocationUpdatesService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                appContext.startForegroundService(intent)
            } else {
                appContext.startService(intent)
            }
        }

        public fun stop(context: Context) {
            context.applicationContext.stopService(
                Intent(context.applicationContext, BubblLocationUpdatesService::class.java)
            )
        }
    }
}

private fun <T> JSONObject.toMapValues(transform: (JSONObject) -> T): Map<String, T> {
    val result = mutableMapOf<String, T>()
    keys().forEach { key ->
        val value = optJSONObject(key) ?: return@forEach
        result[key] = transform(value)
    }
    return result
}

private fun JSONObject.optRuntimeBoolean(name: String, default: Boolean): Boolean {
    if (!has(name) || isNull(name)) return default

    return when (val value = opt(name)) {
        is Boolean -> value
        is Number -> value.toInt() != 0
        is String -> value.equals("true", ignoreCase = true) || value == "1" || value.equals("yes", ignoreCase = true)
        else -> default
    }
}

private fun JSONObject.optJSONObjectOrString(name: String): JSONObject? {
    val value = opt(name)
    return when (value) {
        is JSONObject -> value
        is String -> runCatching { JSONObject(value) }.getOrNull()
        else -> null
    }
}

private fun JSONObject.firstString(vararg keys: String): String? =
    keys.firstNotNullOfOrNull { key -> optNullableString(key)?.takeIf { it.isNotBlank() } }

private fun JSONObject.firstInt(vararg keys: String): Int? =
    keys.firstNotNullOfOrNull { key ->
        when (val value = opt(key)) {
            is Number -> value.toInt()
            is String -> value.toIntOrNull()
            else -> null
        }
    }

private fun JSONObject.firstBoolean(vararg keys: String): Boolean? =
    keys.firstNotNullOfOrNull { key ->
        if (!has(key) || isNull(key)) {
            null
        } else {
            when (val value = opt(key)) {
                is Boolean -> value
                is Number -> value.toInt() != 0
                is String -> when {
                    value.equals("true", ignoreCase = true) || value == "1" || value.equals("yes", ignoreCase = true) -> true
                    value.equals("false", ignoreCase = true) || value == "0" || value.equals("no", ignoreCase = true) -> false
                    else -> null
                }
                else -> null
            }
        }
    }

private fun JSONObject.firstDouble(vararg keys: String): Double? =
    keys.firstNotNullOfOrNull { key ->
        when (val value = opt(key)) {
            is Number -> value.toDouble()
            is String -> value.toDoubleOrNull()
            else -> null
        }
    }

private fun JSONArray.optDoubleOrNull(index: Int): Double? =
    when (val value = opt(index)) {
        is Number -> value.toDouble()
        is String -> value.toDoubleOrNull()
        else -> null
    }

private fun JSONArray.toStringSet(): Set<String> =
    buildSet {
        for (index in 0 until length()) {
            optString(index).takeIf { it.isNotBlank() }?.let(::add)
        }
    }

private fun BubblNotificationPayload.withGeofenceTriggerMetadata(
    triggerKey: String,
    ctaSuspend: Boolean
): BubblNotificationPayload =
    copy(
        raw = raw + mapOf(
            BubblGeofenceTriggerMetadata.triggerKey to triggerKey,
            BubblGeofenceTriggerMetadata.ctaSuspend to ctaSuspend.toString()
        )
    )
