package tech.bubbl.sdk

import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.time.Instant
import java.util.UUID

internal interface BubblStore {
    suspend fun loadState(): BubblStoredState
    suspend fun saveState(state: BubblStoredState)
    suspend fun loadConfig(): BubblConfig?
    suspend fun saveConfig(config: BubblConfig)
    suspend fun append(request: BubblQueuedRequest)
    suspend fun loadQueue(): List<BubblQueuedRequest>
    suspend fun saveQueue(queue: List<BubblQueuedRequest>)
    suspend fun saveRuntimeCache(name: String, body: String)
    suspend fun loadRuntimeCache(name: String): String?
    suspend fun pendingCount(): Int
}

internal data class BubblStoredState(
    val installId: String,
    val correlationId: String?,
    val segments: List<String>,
    val pushToken: String?
) {
    fun toJson(): JSONObject = JSONObject()
        .put("installId", installId)
        .put("correlationId", correlationId ?: JSONObject.NULL)
        .put("segments", JSONArray(segments))
        .put("pushToken", pushToken ?: JSONObject.NULL)

    companion object {
        fun fresh(): BubblStoredState = BubblStoredState(
            installId = UUID.randomUUID().toString(),
            correlationId = null,
            segments = emptyList(),
            pushToken = null
        )

        fun fromJson(json: JSONObject): BubblStoredState = BubblStoredState(
            installId = json.getString("installId"),
            correlationId = json.optNullableString("correlationId"),
            segments = json.optJSONArray("segments")?.toStringList().orEmpty(),
            pushToken = json.optNullableString("pushToken")
        )
    }
}

internal data class BubblQueuedRequest(
    val id: String = UUID.randomUUID().toString(),
    val path: String,
    val body: String,
    val idempotencyKey: String = UUID.randomUUID().toString(),
    val attempts: Int = 0,
    val createdAt: String = Instant.now().toString()
) {
    fun withAttempt(): BubblQueuedRequest = copy(attempts = attempts + 1)

    fun toJson(): JSONObject = JSONObject()
        .put("id", id)
        .put("path", path)
        .put("body", body)
        .put("idempotencyKey", idempotencyKey)
        .put("attempts", attempts)
        .put("createdAt", createdAt)

    companion object {
        fun fromJson(json: JSONObject): BubblQueuedRequest = BubblQueuedRequest(
            id = json.getString("id"),
            path = json.getString("path"),
            body = json.getString("body"),
            idempotencyKey = json.getString("idempotencyKey"),
            attempts = json.optInt("attempts", 0),
            createdAt = json.optString("createdAt", Instant.now().toString())
        )
    }
}

internal class FileBubblStore(private val directory: File) : BubblStore {
    override suspend fun loadState(): BubblStoredState {
        ensureDirectory()
        if (!stateFile.exists()) {
            return BubblStoredState.fresh().also { saveState(it) }
        }

        return BubblStoredState.fromJson(JSONObject(stateFile.readText()))
    }

    override suspend fun saveState(state: BubblStoredState) {
        ensureDirectory()
        stateFile.writeText(state.toJson().toString())
    }

    override suspend fun loadConfig(): BubblConfig? {
        ensureDirectory()
        if (!configFile.exists()) return null

        return bubblConfigFromJson(JSONObject(configFile.readText()))
    }

    override suspend fun saveConfig(config: BubblConfig) {
        ensureDirectory()
        configFile.writeText(config.toJson().toString())
    }

    override suspend fun append(request: BubblQueuedRequest) {
        val queue = loadQueue().toMutableList()
        queue += request
        saveQueue(queue)
    }

    override suspend fun loadQueue(): List<BubblQueuedRequest> {
        ensureDirectory()
        if (!queueFile.exists()) return emptyList()

        val json = JSONArray(queueFile.readText())
        return List(json.length()) { index -> BubblQueuedRequest.fromJson(json.getJSONObject(index)) }
    }

    override suspend fun saveQueue(queue: List<BubblQueuedRequest>) {
        ensureDirectory()
        val json = JSONArray()
        queue.forEach { json.put(it.toJson()) }
        queueFile.writeText(json.toString())
    }

    override suspend fun saveRuntimeCache(name: String, body: String) {
        ensureDirectory()
        File(directory, "runtime-$name.json").writeText(body)
    }

    override suspend fun loadRuntimeCache(name: String): String? {
        ensureDirectory()
        val file = File(directory, "runtime-$name.json")
        return file.takeIf { it.exists() }?.readText()
    }

    override suspend fun pendingCount(): Int = loadQueue().size

    private fun ensureDirectory() {
        directory.mkdirs()
    }

    private val stateFile: File
        get() = File(directory, "state.json")

    private val configFile: File
        get() = File(directory, "config.json")

    private val queueFile: File
        get() = File(directory, "ingest-queue.json")
}

internal fun BubblConfig.toJson(): JSONObject = JSONObject()
    .put("apiKey", apiKey)
    .put("environment", environment.name)
    .put("runtimeBaseUrl", runtimeBaseUrl ?: JSONObject.NULL)
    .put("ingestBaseUrl", ingestBaseUrl ?: JSONObject.NULL)
    .put("segments", JSONArray(segments))
    .put("correlationId", correlationId ?: JSONObject.NULL)
    .put("defaultDistanceMeters", defaultDistanceMeters)
    .put("refreshIntervalSeconds", refreshIntervalSeconds)
    .put("enablePushHandling", enablePushHandling)
    .put("enableLocationTracking", enableLocationTracking)
    .put("notificationRenderingMode", notificationRenderingMode.name)
    .put("enableDefaultNotificationModal", enableDefaultNotificationModal)
    .put("enableDefaultSurveyUi", enableDefaultSurveyUi)
    .put("logLevel", logLevel.name)

internal fun bubblConfigFromJson(json: JSONObject): BubblConfig = BubblConfig(
    apiKey = json.getString("apiKey"),
    environment = enumValueOf(json.optString("environment", BubblEnvironment.Staging.name)),
    runtimeBaseUrl = json.optNullableString("runtimeBaseUrl"),
    ingestBaseUrl = json.optNullableString("ingestBaseUrl"),
    segments = json.optJSONArray("segments")?.toStringList().orEmpty(),
    correlationId = json.optNullableString("correlationId"),
    defaultDistanceMeters = json.optInt("defaultDistanceMeters", 10),
    refreshIntervalSeconds = json.optInt("refreshIntervalSeconds", 300),
    enablePushHandling = json.optBoolean("enablePushHandling", true),
    enableLocationTracking = json.optBoolean("enableLocationTracking", false),
    notificationRenderingMode = enumValueOf(
        json.optString("notificationRenderingMode", BubblNotificationRenderingMode.SdkDefault.name)
    ),
    enableDefaultNotificationModal = json.optBoolean("enableDefaultNotificationModal", true),
    enableDefaultSurveyUi = json.optBoolean("enableDefaultSurveyUi", true),
    logLevel = enumValueOf(json.optString("logLevel", BubblLogLevel.Warn.name))
)

internal fun JSONObject.optNullableString(name: String): String? =
    if (!has(name) || isNull(name)) null else optString(name)

internal fun JSONArray.toStringList(): List<String> =
    List(length()) { index -> getString(index) }
