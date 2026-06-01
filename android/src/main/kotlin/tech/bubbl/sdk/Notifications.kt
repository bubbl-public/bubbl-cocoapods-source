package tech.bubbl.sdk

import android.Manifest
import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.graphics.Typeface
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.RadioButton
import android.widget.RadioGroup
import android.widget.ScrollView
import android.widget.TextView
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.util.Locale
import kotlin.math.absoluteValue

public open class BubblFirebaseMessagingService : FirebaseMessagingService() {
    private companion object {
        private const val logTag = "BubblSdk"
    }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    override fun onMessageReceived(message: RemoteMessage) {
        super.onMessageReceived(message)
        BubblSdk.install(applicationContext)

        scope.launch {
            if (!BubblSdk.restoreForBackground()) {
                BubblSdk.emitError("notification_not_booted", "Received Firebase notification before BubblSdk.boot(config).")
                return@launch
            }

            BubblSdk.handleFirebasePayload(
                payload = message.data,
                messageId = message.messageId,
                notificationTitle = message.notification?.title,
                notificationBody = message.notification?.body
            )
            BubblSdk.flush()
        }
    }

    override fun onNewToken(token: String) {
        super.onNewToken(token)
        Log.i(logTag, "New FCM token received from FirebaseMessagingService (${token.length} chars)")
        BubblSdk.install(applicationContext)

        scope.launch {
            if (BubblSdk.restoreForBackground()) {
                Log.d(logTag, "REG-TOKEN-02 syncing rotated FCM token")
                BubblSdk.syncFcmToken(token)
                val result = BubblSdk.flush()
                if (result.pendingCount == 0) {
                    Log.i(logTag, "REG-TOKEN-02 token synced successfully")
                } else {
                    Log.w(logTag, "REG-TOKEN-02 token queued but ${result.pendingCount} ingest request(s) remain pending")
                }
            } else {
                Log.w(logTag, "REG-TOKEN-02 token received before BubblSdk boot state was available")
            }
        }
    }

    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }
}

public class BubblNotificationActivity : Activity() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var payload: BubblNotificationPayload? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val notificationPayload = BubblNotificationPayloadCodec.fromIntent(intent)
        if (notificationPayload == null) {
            finish()
            return
        }

        payload = notificationPayload
        BubblSdk.install(applicationContext)

        val tapAction = intent.getStringExtra(BubblNotificationPayloadCodec.extraAction)
            ?: BubblNotificationPayloadCodec.actionDefault
        val forceDefaultModal = intent.getBooleanExtra(BubblNotificationPayloadCodec.extraForceDefaultModal, false)

        scope.launch {
            if (BubblSdk.restoreForBackground()) {
                BubblSdk.handleNotificationOpen(notificationPayload, tapAction)
                if (BubblNotificationPayloadCodec.isCtaAction(tapAction) && notificationPayload.cta != null) {
                    BubblSdk.handleNotificationCta(notificationPayload, tapAction)
                    notificationPayload.cta.url?.let(::openUrl)
                }
                BubblSdk.flush()

                if (!forceDefaultModal && !BubblSdk.defaultNotificationModalEnabled()) {
                    launchHostApp(notificationPayload, tapAction)
                    finish()
                    return@launch
                }
            } else {
                BubblSdk.emitError("notification_not_booted", "Opened notification before BubblSdk.boot(config).")
            }

            setContentView(defaultContentView(notificationPayload))
        }
    }

    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }

    private fun defaultContentView(payload: BubblNotificationPayload): View {
        val density = resources.displayMetrics.density
        fun dp(value: Int): Int = (value * density).toInt()

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
            setPadding(0, dp(8), 0, dp(8))
        }

        val header = LinearLayout(this).apply {
            gravity = Gravity.END or Gravity.CENTER_VERTICAL
            minimumHeight = dp(52)
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            )
            setPadding(dp(16), 0, dp(16), 0)
        }

        header.addView(Button(this).apply {
            text = "Close"
            minHeight = dp(44)
            minWidth = dp(72)
            setOnClickListener { finish() }
        })

        root.addView(header)

        val container = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(24), dp(16), dp(24), dp(32))
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
        }

        container.addView(TextView(this).apply {
            text = payload.title
            textSize = 24f
            typeface = Typeface.DEFAULT_BOLD
        })

        if (payload.body.isNotBlank()) {
            container.addView(TextView(this).apply {
                text = payload.body
                textSize = 16f
                setPadding(0, dp(12), 0, dp(16))
            })
        }

        payload.media?.let { media ->
            container.addView(Button(this).apply {
                text = media.altText ?: "View media"
                setOnClickListener {
                    scope.launch {
                        BubblSdk.handleNotificationMediaViewed(payload)
                        BubblSdk.flush()
                    }
                    openUrl(media.url)
                }
            })
        }

        payload.cta?.let { cta ->
            container.addView(Button(this).apply {
                text = cta.label
                setOnClickListener {
                    scope.launch {
                        BubblSdk.handleNotificationCta(payload, cta.action)
                        BubblSdk.flush()
                    }
                    cta.url?.let(::openUrl)
                }
            })
        }

        payload.survey?.takeIf { it.questions.isNotEmpty() }?.let { survey ->
            scope.launch {
                BubblSdk.handleNotificationSurveyRequested(payload)
                BubblSdk.flush()
            }
            container.addView(TextView(this).apply {
                text = "Survey"
                textSize = 20f
                typeface = Typeface.DEFAULT_BOLD
                setPadding(0, dp(20), 0, dp(8))
            })

            val answers = mutableMapOf<String, () -> BubblSurveyAnswer>()

            survey.questions.forEach { question ->
                container.addView(TextView(this).apply {
                    text = question.title
                    textSize = 16f
                    typeface = Typeface.DEFAULT_BOLD
                    setPadding(0, dp(12), 0, dp(6))
                })

                if (question.choices.isNotEmpty()) {
                    val group = RadioGroup(this).apply {
                        orientation = RadioGroup.VERTICAL
                    }
                    question.choices.forEach { choice ->
                        group.addView(RadioButton(this).apply {
                            id = View.generateViewId()
                            text = choice.label
                            tag = choice.id
                        })
                    }
                    container.addView(group)
                    answers[question.id] = {
                        val selected = group.findViewById<RadioButton>(group.checkedRadioButtonId)
                        BubblSurveyAnswer(
                            questionId = question.id,
                            type = question.type,
                            choiceIds = listOfNotNull(selected?.tag as? String)
                        )
                    }
                } else {
                    val input = EditText(this).apply {
                        hint = "Your answer"
                        minLines = 2
                    }
                    container.addView(input)
                    answers[question.id] = {
                        BubblSurveyAnswer(
                            questionId = question.id,
                            type = question.type,
                            value = input.text?.toString()
                        )
                    }
                }
            }

            container.addView(Button(this).apply {
                text = "Submit"
                setOnClickListener {
                    isEnabled = false
                    scope.launch {
                        val curatedNotificationId = payload.curatedNotificationId
                        if (curatedNotificationId == null) {
                            BubblSdk.emitError(
                                "notification_missing_curated_id",
                                "Survey response requires a curated notification id."
                            )
                            isEnabled = true
                            return@launch
                        }
                        BubblSdk.submitSurveyResponse(
                            BubblSurveyResponse(
                                curatedNotificationId = curatedNotificationId,
                                locationId = payload.locationId,
                                answers = answers.values.map { answer -> answer() }
                            )
                        )
                        BubblSdk.flush()
                    }
                    text = "Submitted"
                }
            })
        }

        val scrollView = ScrollView(this).apply {
            isFillViewport = true
            clipToPadding = false
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                0,
                1f
            )
            addView(container)
        }

        root.addView(scrollView)

        ViewCompat.setOnApplyWindowInsetsListener(root) { view, insets ->
            val safeInsets = insets.getInsets(
                WindowInsetsCompat.Type.systemBars() or WindowInsetsCompat.Type.displayCutout()
            )
            view.setPadding(
                safeInsets.left,
                safeInsets.top + dp(8),
                safeInsets.right,
                safeInsets.bottom + dp(8)
            )
            insets
        }
        ViewCompat.requestApplyInsets(root)

        return root
    }

    private fun openUrl(url: String) {
        runCatching {
            startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
        }
    }

    private fun launchHostApp(payload: BubblNotificationPayload, action: String?) {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName) ?: return
        launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        launchIntent.putExtra("bubbl_notification_id", payload.id)
        launchIntent.putExtra("bubbl_curated_notification_id", payload.curatedNotificationId)
        launchIntent.putExtra("bubbl_location_id", payload.locationId)
        launchIntent.putExtra(BubblNotificationPayloadCodec.extraHandledByHost, true)
        payload.cta?.url?.let { launchIntent.putExtra("bubbl_cta_url", it) }
        payload.cta?.action?.let { launchIntent.putExtra("bubbl_cta_action", it) }
        BubblNotificationPayloadCodec.addToIntent(launchIntent, payload, action)
        runCatching { startActivity(launchIntent) }
    }
}

internal object BubblNotificationPayloadParser {
    fun fromFirebaseIntent(intent: Intent): BubblNotificationPayload? {
        val extras = intent.extras ?: return null
        val payload = mutableMapOf<String, String>()
        extras.keySet().forEach { key ->
            @Suppress("DEPRECATION")
            val value = extras.get(key)
            if (value != null) {
                payload[key] = value.toString()
            }
        }

        return fromFirebasePayload(
            payload = payload,
            messageId = payload["google.message_id"] ?: payload["gcm.message_id"] ?: payload["message_id"],
            notificationTitle = payload["gcm.n.title"] ?: payload["gcm.notification.title"],
            notificationBody = payload["gcm.n.body"] ?: payload["gcm.notification.body"]
        )
    }

    fun fromFirebasePayload(
        payload: Map<String, String>,
        messageId: String? = null,
        notificationTitle: String? = null,
        notificationBody: String? = null
    ): BubblNotificationPayload? {
        val data = flattenNestedPayload(payload)
        return fromPayload(
            payload = data,
            source = BubblNotificationSource.Firebase,
            messageId = messageId,
            notificationTitle = notificationTitle,
            notificationBody = notificationBody
        )
    }

    fun fromRuntimePayload(
        payload: Map<String, String>,
        source: BubblNotificationSource
    ): BubblNotificationPayload? =
        fromPayload(payload = payload, source = source)

    private fun fromPayload(
        payload: Map<String, String>,
        source: BubblNotificationSource,
        messageId: String? = null,
        notificationTitle: String? = null,
        notificationBody: String? = null
    ): BubblNotificationPayload? {
        val data = payload
        val parsedTitle = firstPresent(
            data,
            "title",
            "headline",
            "notification_title",
            "notificationTitle",
            "gcm.n.title",
            "gcm.notification.title"
        )
            ?: notificationTitle
        val parsedBody = firstPresent(
            data,
            "body",
            "message",
            "notification_body",
            "notificationBody",
            "description",
            "gcm.n.body",
            "gcm.notification.body"
        )
            ?: notificationBody

        if (parsedTitle.isNullOrBlank() && parsedBody.isNullOrBlank()) {
            return null
        }

        val title = parsedTitle?.takeIf { it.isNotBlank() } ?: "Bubbl"
        val body = parsedBody.orEmpty()

        val curatedNotificationId = firstPresent(
            data,
            "curated_notification_id",
            "curatedNotificationId",
            "curated_notification",
            "curatedNotification",
            "n_id",
            "nId"
        )
        val locationId = firstPresent(data, "location_id", "locationId", "locationID")
        val id = firstPresent(
            data,
            "id",
            "message_id",
            "messageId",
            "push_id",
            "pushId",
            "notification_id",
            "notificationId",
            "gcm.message_id",
            "google.message_id"
        )
            ?: curatedNotificationId
            ?: messageId
            ?: stableId(title, body, curatedNotificationId, locationId)

        return BubblNotificationPayload(
            id = id,
            title = title,
            body = body,
            source = source,
            locationId = locationId,
            curatedNotificationId = curatedNotificationId,
            correlationId = firstPresent(data, "correlation_id", "correlationId"),
            media = mediaFrom(data),
            cta = ctaFrom(data),
            survey = surveyFrom(data),
            raw = data
        )
    }

    private fun flattenNestedPayload(payload: Map<String, String>): Map<String, String> {
        val data = payload.toMutableMap()
        for (key in listOf("notification_data", "notificationData", "bubbl_notification", "bubblNotification", "payload", "data")) {
            val nested = payload[key]?.trim().orEmpty()
            if (!nested.startsWith("{")) continue

            runCatching { JSONObject(nested) }
                .getOrNull()
                ?.let { json ->
                    json.keys().forEach { nestedKey ->
                        if (!data.containsKey(nestedKey)) {
                            data[nestedKey] = json.opt(nestedKey)?.toString().orEmpty()
                        }
                    }
                }
        }

        return data
    }

    private fun mediaFrom(data: Map<String, String>): BubblNotificationMedia? {
        val url = firstPresent(
            data,
            "media_url",
            "mediaUrl",
            "image",
            "image_url",
            "imageUrl",
            "picture",
            "pictureUrl",
            "gcm.n.image",
            "gcm.notification.image"
        )
            ?: return null

        return BubblNotificationMedia(
            url = url,
            type = firstPresent(data, "media_type", "mediaType", "image_type", "imageType"),
            altText = firstPresent(data, "media_alt", "mediaAlt", "alt", "altText")
        )
    }

    private fun ctaFrom(data: Map<String, String>): BubblNotificationCta? {
        val label = firstPresent(data, "cta_label", "ctaLabel", "button_label", "buttonLabel", "action_label", "actionLabel")
            ?: return null

        return BubblNotificationCta(
            label = label,
            url = firstPresent(data, "cta_url", "ctaUrl", "url", "deep_link", "deepLink"),
            action = firstPresent(data, "cta_action", "ctaAction", "action")
        )
    }

    private fun surveyFrom(data: Map<String, String>): BubblNotificationSurvey? {
        val rawQuestions = firstPresent(data, "questions", "survey_questions", "surveyQuestions") ?: return null
        val questions = runCatching {
            val json = JSONArray(rawQuestions)
            List(json.length()) { index ->
                val question = json.getJSONObject(index)
                BubblSurveyQuestion(
                    id = question.optString("id", question.optString("question_id", index.toString())),
                    title = question.optString("title", question.optString("question", "")),
                    type = question.optString("type", "single_choice"),
                    choices = choicesFrom(question.optJSONArray("choices") ?: question.optJSONArray("options"))
                )
            }
        }.getOrDefault(emptyList())

        return BubblNotificationSurvey(questions)
    }

    private fun choicesFrom(json: JSONArray?): List<BubblSurveyChoice> {
        if (json == null) return emptyList()

        return List(json.length()) { index ->
            val choice = json.getJSONObject(index)
            BubblSurveyChoice(
                id = choice.optString("id", choice.optString("choice_id", index.toString())),
                label = choice.optString("label", choice.optString("title", choice.optString("value", "")))
            )
        }
    }

    private fun firstPresent(data: Map<String, String>, vararg keys: String): String? =
        keys.firstNotNullOfOrNull { key -> data[key]?.trim()?.takeIf { it.isNotEmpty() } }

    private fun stableId(title: String, body: String, curatedNotificationId: String?, locationId: String?): String {
        val seed = listOfNotNull(curatedNotificationId, locationId, title, body).joinToString(":")
        return "bubbl-${seed.hashCode().absoluteValue}"
    }
}

internal object BubblRuntimeNotificationExtractor {
    fun fromRuntimeResponse(body: String): List<BubblNotificationPayload> =
        runCatching {
            val json = JSONObject(body)
            buildList {
                addAll(campaignNotifications(json.optJSONArray("pushCampaign"), BubblNotificationSource.Runtime))
                addAll(campaignNotifications(json.optJSONArray("geoCampaign"), BubblNotificationSource.Geofence))
            }
        }.getOrDefault(emptyList())

    private fun campaignNotifications(
        campaigns: JSONArray?,
        source: BubblNotificationSource
    ): List<BubblNotificationPayload> {
        if (campaigns == null) return emptyList()

        return buildList {
            for (campaignIndex in 0 until campaigns.length()) {
                val campaign = campaigns.optJSONObject(campaignIndex) ?: continue
                if (!campaign.isRuntimeCampaignEnabled()) continue

                val notifications = campaign.optJSONArray("notificationsArray") ?: continue
                for (notificationIndex in 0 until notifications.length()) {
                    val notification = notifications.optJSONObject(notificationIndex) ?: continue
                    if (!notification.optRuntimeBoolean("published", default = true)) continue

                    val payload = notificationPayload(campaign, notification, source)
                    if (payload != null) {
                        add(payload)
                    }
                }
            }
        }
    }

    internal fun notificationPayload(
        campaign: JSONObject,
        notification: JSONObject,
        source: BubblNotificationSource
    ): BubblNotificationPayload? =
        BubblNotificationPayloadParser.fromRuntimePayload(
            payload = runtimeNotificationMap(campaign, notification),
            source = source
        )

    private fun runtimeNotificationMap(campaign: JSONObject, notification: JSONObject): Map<String, String> {
        val data = campaign.toStringMap() + notification.toStringMap()
        val result = data.toMutableMap()

        result.putIfAbsent("campaignId", campaign.opt("campaignId")?.toString().orEmpty())
        result.putIfAbsent("campaignName", campaign.optString("campaignName"))
        result.putIfAbsent("locationId", notification.optNullableString("locationId") ?: campaignLocationId(campaign).orEmpty())

        val media = notification.optJSONArray("media")
        if (result["mediaUrl"].isNullOrBlank() && media != null && media.length() > 0) {
            val firstMedia = media.opt(0)
            if (firstMedia is JSONObject) {
                result["mediaUrl"] = firstMedia.firstString("url", "mediaUrl", "media_url", "image", "imageUrl").orEmpty()
                result["mediaType"] = firstMedia.firstString("type", "mediaType", "media_type").orEmpty()
            } else {
                result["mediaUrl"] = firstMedia?.toString().orEmpty()
            }
        }

        val cta = notification.optJSONArray("cta")
        if (result["ctaLabel"].isNullOrBlank() && cta != null && cta.length() > 0) {
            val firstCta = cta.optJSONObject(0)
            if (firstCta != null) {
                result["ctaLabel"] = firstCta.firstString("label", "ctaLabel", "title").orEmpty()
                result["ctaUrl"] = firstCta.firstString("url", "ctaUrl", "deepLink", "deep_link").orEmpty()
                result["ctaAction"] = firstCta.firstString("action", "ctaAction").orEmpty()
            }
        }

        return result.filterValues { it.isNotBlank() }
    }

    private fun campaignLocationId(campaign: JSONObject): String? {
        val locationsArray = campaign.optJSONObject("locationsArray")
        if (locationsArray != null) {
            locationsArray.opt("locationId")?.toString()?.takeIf { it.isNotBlank() }?.let { return it }
        }

        val locations = campaign.optJSONArray("locations")
        if (locations != null && locations.length() > 0) {
            return locations.opt(0)?.toString()
        }

        return null
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

    private fun JSONObject.isRuntimeCampaignEnabled(): Boolean {
        if (!optRuntimeBoolean("active", default = true)) return false
        if (optRuntimeBoolean("paused", default = false)) return false
        if (optRuntimeBoolean("campaignPaused", default = false)) return false
        if (optRuntimeBoolean("campaign_paused", default = false)) return false

        val status = firstString("status", "campaignStatus", "campaign_status")
            ?.trim()
            ?.lowercase()

        return status !in setOf("paused", "inactive", "disabled", "ended")
    }

    private fun JSONObject.toStringMap(): Map<String, String> {
        val result = mutableMapOf<String, String>()
        keys().forEach { key ->
            val value = opt(key)
            if (value != null && value != JSONObject.NULL) {
                result[key] = value.toString()
            }
        }
        return result
    }

    private fun JSONObject.firstString(vararg keys: String): String? =
        keys.firstNotNullOfOrNull { key -> optNullableString(key)?.takeIf { it.isNotBlank() } }
}

internal object BubblNotificationPayloadCodec {
    const val extraPayload = "tech.bubbl.sdk.extra.NOTIFICATION_PAYLOAD"
    const val extraAction = "tech.bubbl.sdk.extra.NOTIFICATION_ACTION"
    const val extraHandledByHost = "tech.bubbl.sdk.extra.NOTIFICATION_HANDLED_BY_HOST"
    const val extraForceDefaultModal = "tech.bubbl.sdk.extra.FORCE_DEFAULT_MODAL"
    const val actionDefault = "default"
    const val actionCta = "cta"

    fun isCtaAction(action: String?): Boolean =
        action != null && action != actionDefault

    fun addToIntent(intent: Intent, payload: BubblNotificationPayload, action: String? = null): Intent =
        intent
            .putExtra(extraPayload, toJson(payload).toString())
            .putExtra(extraAction, action ?: actionDefault)

    fun fromIntent(intent: Intent): BubblNotificationPayload? =
        intent.getStringExtra(extraPayload)?.let(::fromJsonString)

    fun fromJsonString(value: String): BubblNotificationPayload? =
        runCatching { fromJson(JSONObject(value)) }.getOrNull()

    fun toJson(payload: BubblNotificationPayload): JSONObject = JSONObject()
        .put("id", payload.id)
        .put("title", payload.title)
        .put("body", payload.body)
        .put("source", payload.source.name)
        .put("locationId", payload.locationId ?: JSONObject.NULL)
        .put("curatedNotificationId", payload.curatedNotificationId ?: JSONObject.NULL)
        .put("correlationId", payload.correlationId ?: JSONObject.NULL)
        .put("media", payload.media?.let(::mediaToJson) ?: JSONObject.NULL)
        .put("cta", payload.cta?.let(::ctaToJson) ?: JSONObject.NULL)
        .put("survey", payload.survey?.let(::surveyToJson) ?: JSONObject.NULL)
        .put("raw", JSONObject(payload.raw))

    private fun fromJson(json: JSONObject): BubblNotificationPayload =
        BubblNotificationPayload(
            id = json.getString("id"),
            title = json.optString("title"),
            body = json.optString("body"),
            source = enumValueOrDefault(json.optString("source"), BubblNotificationSource.Manual),
            locationId = json.optNullableString("locationId"),
            curatedNotificationId = json.optNullableString("curatedNotificationId"),
            correlationId = json.optNullableString("correlationId"),
            media = json.optJSONObject("media")?.let(::mediaFromJson),
            cta = json.optJSONObject("cta")?.let(::ctaFromJson),
            survey = json.optJSONObject("survey")?.let(::surveyFromJson),
            raw = json.optJSONObject("raw")?.toStringMap().orEmpty()
        )

    private fun mediaToJson(media: BubblNotificationMedia): JSONObject = JSONObject()
        .put("url", media.url)
        .put("type", media.type ?: JSONObject.NULL)
        .put("altText", media.altText ?: JSONObject.NULL)

    private fun mediaFromJson(json: JSONObject): BubblNotificationMedia =
        BubblNotificationMedia(
            url = json.getString("url"),
            type = json.optNullableString("type"),
            altText = json.optNullableString("altText")
        )

    private fun ctaToJson(cta: BubblNotificationCta): JSONObject = JSONObject()
        .put("label", cta.label)
        .put("url", cta.url ?: JSONObject.NULL)
        .put("action", cta.action ?: JSONObject.NULL)

    private fun ctaFromJson(json: JSONObject): BubblNotificationCta =
        BubblNotificationCta(
            label = json.getString("label"),
            url = json.optNullableString("url"),
            action = json.optNullableString("action")
        )

    private fun surveyToJson(survey: BubblNotificationSurvey): JSONObject = JSONObject()
        .put(
            "questions",
            JSONArray(survey.questions.map { question ->
                JSONObject()
                    .put("id", question.id)
                    .put("title", question.title)
                    .put("type", question.type)
                    .put(
                        "choices",
                        JSONArray(question.choices.map { choice ->
                            JSONObject()
                                .put("id", choice.id)
                                .put("label", choice.label)
                        })
                    )
            })
        )

    private fun surveyFromJson(json: JSONObject): BubblNotificationSurvey {
        val questions = json.optJSONArray("questions") ?: return BubblNotificationSurvey()
        return BubblNotificationSurvey(
            List(questions.length()) { index ->
                val question = questions.getJSONObject(index)
                val choices = question.optJSONArray("choices")
                BubblSurveyQuestion(
                    id = question.getString("id"),
                    title = question.optString("title"),
                    type = question.optString("type", "single_choice"),
                    choices = if (choices == null) {
                        emptyList()
                    } else {
                        List(choices.length()) { choiceIndex ->
                            val choice = choices.getJSONObject(choiceIndex)
                            BubblSurveyChoice(
                                id = choice.getString("id"),
                                label = choice.optString("label")
                            )
                        }
                    }
                )
            }
        )
    }

    private fun JSONObject.toStringMap(): Map<String, String> {
        val result = mutableMapOf<String, String>()
        keys().forEach { key ->
            result[key] = opt(key)?.toString().orEmpty()
        }
        return result
    }

    private inline fun <reified T : Enum<T>> enumValueOrDefault(value: String?, default: T): T =
        runCatching { enumValueOf<T>(value.orEmpty()) }.getOrDefault(default)
}

internal object BubblAndroidNotificationRuntime {
    private const val channelId = "bubbl_notifications"
    private const val channelName = "Bubbl notifications"
    private const val duplicateWindowMs = 60_000L
    private const val mediaDownloadTimeoutMs = 3_000

    fun show(context: Context, payload: BubblNotificationPayload): BubblNotificationDisplayResult {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            return BubblNotificationDisplayResult(displayed = false, reason = "post_notifications_permission_denied")
        }

        if (!BubblNotificationDeduper.markIfFresh(context, payload.id, duplicateWindowMs)) {
            return BubblNotificationDisplayResult(displayed = false, reason = "duplicate_notification")
        }

        ensureChannel(context)

        val image = payload.media
            ?.takeIf { renderPlan(payload).shouldUseBigPicture }
            ?.let { downloadBitmap(it.url) }
        val builder = NotificationCompat.Builder(context, channelId)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle(payload.title)
            .setContentText(payload.body)
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setContentIntent(contentIntent(context, payload, action = BubblNotificationPayloadCodec.actionDefault))

        if (image != null) {
            builder
                .setLargeIcon(image)
                .setStyle(
                    NotificationCompat.BigPictureStyle()
                        .bigPicture(image)
                        .setBigContentTitle(payload.title)
                        .setSummaryText(payload.body)
                )
        } else {
            builder.setStyle(NotificationCompat.BigTextStyle().bigText(payload.body))
        }

        payload.cta?.let { cta ->
            builder.addAction(
                android.R.drawable.ic_menu_view,
                cta.label,
                contentIntent(context, payload, action = cta.action ?: BubblNotificationPayloadCodec.actionCta)
            )
        }

        return runCatching {
            NotificationManagerCompat.from(context).notify(notificationId(payload), builder.build())
            BubblNotificationDisplayResult(displayed = true)
        }.getOrElse { error ->
            BubblNotificationDisplayResult(displayed = false, reason = error.message ?: "notification_display_failed")
        }
    }

    internal fun renderPlan(payload: BubblNotificationPayload): BubblAndroidNotificationRenderPlan =
        BubblAndroidNotificationRenderPlan(
            shouldUseBigPicture = payload.media?.let(::isImageMedia) == true,
            contentAction = BubblNotificationPayloadCodec.actionDefault,
            ctaAction = payload.cta?.action ?: payload.cta?.let { BubblNotificationPayloadCodec.actionCta }
        )

    private fun isImageMedia(media: BubblNotificationMedia): Boolean {
        val type = media.type?.lowercase(Locale.US)
        if (type != null) {
            return type == "image" || type.startsWith("image/")
        }

        val path = runCatching { Uri.parse(media.url).path.orEmpty().lowercase(Locale.US) }.getOrDefault("")
        return path.endsWith(".png") ||
            path.endsWith(".jpg") ||
            path.endsWith(".jpeg") ||
            path.endsWith(".webp") ||
            path.endsWith(".gif")
    }

    private fun downloadBitmap(url: String): Bitmap? =
        runCatching {
            val connection = URL(url).openConnection() as HttpURLConnection
            connection.connectTimeout = mediaDownloadTimeoutMs
            connection.readTimeout = mediaDownloadTimeoutMs
            connection.instanceFollowRedirects = true
            connection.inputStream.use(BitmapFactory::decodeStream)
        }.getOrNull()

    private fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val manager = context.getSystemService(NotificationManager::class.java)
        val existing = manager.getNotificationChannel(channelId)
        if (existing != null) {
            if (existing.importance != NotificationManager.IMPORTANCE_NONE &&
                existing.importance < NotificationManager.IMPORTANCE_HIGH
            ) {
                manager.deleteNotificationChannel(channelId)
            } else {
                return
            }
        }

        manager.createNotificationChannel(
            NotificationChannel(channelId, channelName, NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Campaign and location notifications from Bubbl."
                enableVibration(true)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }
        )
    }

    private fun contentIntent(context: Context, payload: BubblNotificationPayload, action: String): PendingIntent {
        val intent = Intent(context, BubblNotificationActivity::class.java).apply {
            this.action = "tech.bubbl.sdk.notification.$action"
            putExtra("bubbl_notification_id", payload.id)
            putExtra("bubbl_curated_notification_id", payload.curatedNotificationId)
            putExtra("bubbl_location_id", payload.locationId)
            payload.cta?.url?.let { putExtra("bubbl_cta_url", it) }
            payload.cta?.action?.let { putExtra("bubbl_cta_action", it) }
            payload.cta?.url?.takeIf { it.startsWith("http://") || it.startsWith("https://") }?.let {
                data = Uri.parse(it)
            }
        }
        BubblNotificationPayloadCodec.addToIntent(intent, payload, action)

        return PendingIntent.getActivity(
            context,
            (payload.id + action).hashCode().absoluteValue,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun notificationId(payload: BubblNotificationPayload): Int =
        payload.id.hashCode().absoluteValue
}

internal data class BubblAndroidNotificationRenderPlan(
    val shouldUseBigPicture: Boolean,
    val contentAction: String,
    val ctaAction: String?
)

private object BubblNotificationDeduper {
    private const val preferencesName = "bubbl_sdk_notifications"

    fun markIfFresh(context: Context, id: String, windowMs: Long): Boolean {
        val now = System.currentTimeMillis()
        val preferences = context.getSharedPreferences(preferencesName, Context.MODE_PRIVATE)
        val lastSeen = preferences.getLong(id, 0L)

        if (now - lastSeen in 0 until windowMs) {
            return false
        }

        preferences.edit().putLong(id, now).apply()
        return true
    }
}
