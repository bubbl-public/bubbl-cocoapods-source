package tech.bubbl.sdk

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.net.HttpURLConnection
import java.net.URL

data class BubblHttpRequest(
    val method: String,
    val url: String,
    val headers: Map<String, String> = emptyMap(),
    val body: String? = null
)

data class BubblHttpResponse(
    val statusCode: Int,
    val body: String,
    val headers: Map<String, List<String>> = emptyMap()
)

fun interface BubblHttpTransport {
    suspend fun send(request: BubblHttpRequest): BubblHttpResponse
}

class UrlConnectionBubblHttpTransport : BubblHttpTransport {
    override suspend fun send(request: BubblHttpRequest): BubblHttpResponse = withContext(Dispatchers.IO) {
        val connection = URL(request.url).openConnection() as HttpURLConnection
        connection.requestMethod = request.method
        connection.connectTimeout = 30_000
        connection.readTimeout = 30_000
        connection.doInput = true

        request.headers.forEach { (name, value) ->
            connection.setRequestProperty(name, value)
        }

        request.body?.let { body ->
            connection.doOutput = true
            connection.outputStream.use { stream ->
                stream.write(body.toByteArray(Charsets.UTF_8))
            }
        }

        val status = connection.responseCode
        val responseBody = runCatching {
            val stream = if (status in 200..299) connection.inputStream else connection.errorStream
            stream?.bufferedReader(Charsets.UTF_8)?.use { it.readText() }.orEmpty()
        }.getOrDefault("")

        BubblHttpResponse(
            statusCode = status,
            body = responseBody,
            headers = connection.headerFields
                .orEmpty()
                .filterKeys { it != null }
                .mapKeys { it.key.orEmpty() }
                .mapValues { it.value.orEmpty() }
        )
    }
}

internal object BubblTransportMap {
    const val sdkVersion = "3.1.3"
    const val platform = "android"

    const val runtimeAuthHeader = "x-api-key"
    const val ingestAuthHeader = "ApiKey"
    const val dashboardAuthHeader = "ApiKey"

    const val refreshGeofencePath = "/api/check-geofence"
    const val refreshPushPath = "/api/check-push"
    const val getConfigurationPath = "/api/get-config"

    const val registerDevicePath = "/api/device-registerd/create"
    const val bootBatchPath = "/api/device-data"
    const val trackEventPath = "/api/activities"
    const val updateSegmentsPath = "/api/segments"
    const val submitSurveyResponsePath = "/api/survey-response"
    const val trackGeofenceBatchPath = "/api/geofence-data"

    fun transmissionBaseUrl(config: BubblConfig): String =
        config.transmissionBaseUrl ?: config.runtimeBaseUrl ?: when (config.environment) {
            BubblEnvironment.Development,
            BubblEnvironment.Staging -> "https://staging.transmission.bubbl.tech"
            BubblEnvironment.Production -> "https://transmission.bubbl.tech"
        }

    fun runtimeBaseUrl(config: BubblConfig): String = transmissionBaseUrl(config)

    fun ingestBaseUrl(config: BubblConfig): String =
        config.ingestBaseUrl ?: when (config.environment) {
            BubblEnvironment.Development,
            BubblEnvironment.Staging -> "https://staging.ingest.bubbl.tech"
            BubblEnvironment.Production -> "https://ingest.bubbl.tech"
        }

    fun transmissionDistanceMiles(publicDistanceMeters: Int): Double =
        publicDistanceMeters.coerceAtLeast(1) / 1609.344
}
