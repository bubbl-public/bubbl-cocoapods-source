package tech.bubbl.sdk

import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.async
import kotlinx.coroutines.flow.filterIsInstance
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import androidx.core.app.NotificationCompat
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.io.IOException
import java.net.URI
import java.nio.file.Files
import java.time.Instant

class BubblSdkTest {
    @Test
    fun bootQueuesLegacyMirroredDeviceDataAndFlushPostsIt() = runBlocking {
        val requests = mutableListOf<BubblHttpRequest>()
        val transport = BubblHttpTransport { request ->
            requests += request
            BubblHttpResponse(
                statusCode = 200,
                body = """{"success":true,"queued":true,"data":{"ingest_message_id":"1","status":"queued"}}"""
            )
        }
        BubblSdk.install(storageDirectory = temporaryDirectory(), transport = transport)

        BubblSdk.boot(
            BubblConfig(
                apiKey = "sdk-key",
                runtimeBaseUrl = "https://runtime.test",
                ingestBaseUrl = "https://ingest.test",
                segments = listOf("vip")
            )
        )

        assertEquals(1, BubblSdk.diagnostics().pendingIngestCount)

        val flush = BubblSdk.flush()

        assertEquals(0, flush.pendingCount)
        assertEquals(1, requests.size)
        assertEquals("/api/device-data", URI(requests.single().url).path)
        assertEquals("POST", requests.single().method)
        assertEquals("sdk-key", requests.single().headers["ApiKey"])
        assertEquals("4.0.1", requests.single().headers["X-Bubbl-SDK-Version"])
        assertEquals("android", requests.single().headers["X-Bubbl-SDK-Platform"])
        assertNotNull(requests.single().headers["Idempotency-Key"])
        assertNotNull(requests.single().headers["X-Bubbl-Install-ID"])
    }

    @Test
    fun registerPushTokenQueuesDeviceUpdateWithRealToken() = runBlocking {
        val requests = mutableListOf<BubblHttpRequest>()
        val transport = BubblHttpTransport { request ->
            requests += request
            BubblHttpResponse(
                statusCode = 200,
                body = """{"success":true,"queued":true,"data":{"ingest_message_id":"1","status":"queued"}}"""
            )
        }
        BubblSdk.install(storageDirectory = temporaryDirectory(), transport = transport)

        BubblSdk.boot(
            BubblConfig(
                apiKey = "sdk-key",
                runtimeBaseUrl = "https://runtime.test",
                ingestBaseUrl = "https://ingest.test"
            )
        )
        BubblSdk.registerPushToken("real-fcm-token")

        assertEquals(0, BubblSdk.flush().pendingCount)
        assertEquals(2, requests.size)
        assertEquals("/api/device-data", URI(requests.first().url).path)
        assertEquals("/api/device-registerd/create", URI(requests.last().url).path)
        assertEquals("real-fcm-token", JSONObject(requests.last().body.orEmpty()).getString("device_token"))
    }

    @Test
    fun runtimeConfigurationFallsBackToCachedResponse() = runBlocking {
        var online = true
        val transport = BubblHttpTransport {
            if (!online) throw IOException("offline")

            BubblHttpResponse(
                statusCode = 200,
                body = """{"configuration":{"notificationsCount":3,"daysCount":2,"batteryCount":1,"privacyText":"Cached privacy"}}"""
            )
        }
        BubblSdk.install(storageDirectory = temporaryDirectory(), transport = transport)

        BubblSdk.boot(
            BubblConfig(
                apiKey = "sdk-key",
                runtimeBaseUrl = "https://runtime.test",
                ingestBaseUrl = "https://ingest.test"
            )
        )

        assertEquals("Cached privacy", BubblSdk.getConfiguration()?.privacyText)

        online = false

        assertEquals("Cached privacy", BubblSdk.getConfiguration()?.privacyText)
    }

    @Test
    fun defaultEnvironmentEndpointsUseRenewedSplitHostsAndConvertPublicMetersForTransmission() = runBlocking {
        val cases = listOf(
            Triple(BubblEnvironment.Development, "staging.transmission.bubbl.tech", "staging.ingest.bubbl.tech"),
            Triple(BubblEnvironment.Staging, "staging.transmission.bubbl.tech", "staging.ingest.bubbl.tech"),
            Triple(BubblEnvironment.Production, "transmission.bubbl.tech", "ingest.bubbl.tech")
        )

        cases.forEach { (environment, expectedRuntimeHost, expectedIngestHost) ->
            val requests = mutableListOf<BubblHttpRequest>()
            val transport = BubblHttpTransport { request ->
                requests += request
                val body = if (URI(request.url).path == "/api/check-geofence") {
                    """{"geoCampaign":[],"pushCampaign":[],"configuration":{"notificationsCount":0,"daysCount":0,"batteryCount":0,"privacyText":""}}"""
                } else {
                    """{"success":true,"queued":true,"data":{"ingest_message_id":"1","status":"queued"}}"""
                }
                BubblHttpResponse(statusCode = 200, body = body)
            }
            BubblSdk.install(storageDirectory = temporaryDirectory(), transport = transport)
            BubblSdk.boot(
                BubblConfig(
                    apiKey = "sdk-key",
                    environment = environment,
                    defaultDistanceMeters = 1609
                )
            )

            BubblSdk.refreshGeofence(BubblLocation(latitude = 51.5072, longitude = -0.1276))
            BubblSdk.flush()

            val runtimeRequest = requests.first { URI(it.url).path == "/api/check-geofence" }
            val ingestRequest = requests.first { URI(it.url).path == "/api/device-data" }
            val runtimeBody = JSONObject(runtimeRequest.body ?: "{}")

            assertEquals(expectedRuntimeHost, URI(runtimeRequest.url).host)
            assertEquals(expectedIngestHost, URI(ingestRequest.url).host)
            assertEquals(1.0, runtimeBody.getDouble("distance"), 0.001)
            assertEquals("x-api-key", BubblTransportMap.runtimeAuthHeader)
            assertEquals("ApiKey", BubblTransportMap.ingestAuthHeader)
        }
    }

    @Test
    fun restoreForBackgroundUsesPersistedConfigAndFlushesQueue() = runBlocking {
        val storageDirectory = temporaryDirectory()
        val requests = mutableListOf<BubblHttpRequest>()
        val transport = BubblHttpTransport { request ->
            requests += request
            BubblHttpResponse(
                statusCode = 200,
                body = """{"success":true,"queued":true,"data":{"ingest_message_id":"1","status":"queued"}}"""
            )
        }
        BubblSdk.install(storageDirectory = storageDirectory, transport = transport)
        BubblSdk.boot(
            BubblConfig(
                apiKey = "sdk-key",
                runtimeBaseUrl = "https://runtime.test",
                ingestBaseUrl = "https://ingest.test"
            )
        )
        BubblSdk.shutdown()

        BubblSdk.install(storageDirectory = storageDirectory, transport = transport)

        assertEquals(true, BubblSdk.restoreForBackground())
        assertEquals(0, BubblSdk.flush().pendingCount)
        assertEquals("/api/device-data", URI(requests.single().url).path)
        assertEquals("sdk-key", requests.single().headers["ApiKey"])
    }

    @Test
    fun parsesFirebaseNotificationPayloadWithMediaCtaAndSurvey() {
        val payload = BubblNotificationPayloadParser.fromFirebasePayload(
            payload = mapOf(
                "notification_data" to """
                    {
                      "headline":"Welcome back",
                      "message":"Tap for your offer",
                      "curated_notification_id":"42",
                      "location_id":"7",
                      "media_url":"https://cdn.test/offer.png",
                      "cta_label":"Open",
                      "cta_url":"https://bubbl.test/offers/42",
                      "questions":"[{\"id\":\"1\",\"title\":\"How was it?\",\"type\":\"single_choice\",\"choices\":[{\"id\":\"5\",\"label\":\"Great\"}]}]"
                    }
                """.trimIndent()
            ),
            messageId = "fcm-message"
        )

        assertNotNull(payload)
        assertEquals("Welcome back", payload?.title)
        assertEquals("Tap for your offer", payload?.body)
        assertEquals("42", payload?.curatedNotificationId)
        assertEquals("7", payload?.locationId)
        assertEquals("https://cdn.test/offer.png", payload?.media?.url)
        assertEquals("Open", payload?.cta?.label)
        assertEquals("1", payload?.survey?.questions?.single()?.id)
        assertEquals("5", payload?.survey?.questions?.single()?.choices?.single()?.id)
        assertEquals("Great", payload?.survey?.questions?.single()?.choices?.single()?.label)
    }

    @Test
    fun parsesFirebaseSurveyOptionsAliasAsSelectableChoices() {
        val payload = BubblNotificationPayloadParser.fromFirebasePayload(
            payload = mapOf(
                "title" to "Survey",
                "body" to "Pick one",
                "questions" to """[{"id":"1","title":"How was it?","type":"single_choice","options":[{"id":"5","label":"Great"}]}]"""
            )
        )

        val choice = payload?.survey?.questions?.single()?.choices?.single()
        assertNotNull(choice)
        assertEquals("5", choice?.id)
        assertEquals("Great", choice?.label)
    }

    @Test
    fun parsesFirebaseNotificationExtrasUsedByAutomaticNotificationLaunches() {
        val payload = BubblNotificationPayloadParser.fromFirebasePayload(
            payload = mapOf(
                "gcm.n.title" to "Auto push",
                "gcm.n.body" to "Opened from Firebase notification tray",
                "google.message_id" to "fcm-auto-1",
                "curated_notification_id" to "42",
                "location_id" to "7",
                "gcm.n.image" to "https://cdn.test/push.png"
            )
        )

        assertNotNull(payload)
        assertEquals("Auto push", payload?.title)
        assertEquals("Opened from Firebase notification tray", payload?.body)
        assertEquals("fcm-auto-1", payload?.id)
        assertEquals("42", payload?.curatedNotificationId)
        assertEquals("7", payload?.locationId)
        assertEquals("https://cdn.test/push.png", payload?.media?.url)
    }

    @Test
    fun parsesLegacyNotificationIdAliasAsCuratedNotificationId() {
        val payload = BubblNotificationPayloadParser.fromFirebasePayload(
            payload = mapOf(
                "title" to "Legacy push",
                "body" to "Uses n_id",
                "n_id" to "42"
            )
        )

        assertEquals("42", payload?.curatedNotificationId)
        assertEquals("42", payload?.id)
    }

    @Test
    fun keepsProviderNotificationIdOutOfCuratedNotificationId() {
        val payload = BubblNotificationPayloadParser.fromFirebasePayload(
            payload = mapOf(
                "title" to "Provider push",
                "body" to "Has a provider id",
                "notification_id" to "provider-123"
            )
        )

        assertEquals("provider-123", payload?.id)
        assertNull(payload?.curatedNotificationId)
    }

    @Test
    fun rejectsEmptyFirebaseNotificationPayload() {
        assertNull(BubblNotificationPayloadParser.fromFirebasePayload(emptyMap()))
    }

    @Test
    fun extractsGeofenceRuntimeCampaignNotifications() {
        val response = """
            {
              "geoCampaign": [
                {
                  "campaignId": 123,
                  "campaignName": "Spring offers",
                  "type": "GEO",
                  "active": "true",
                  "locationsArray": {"locationId": 10},
                  "notificationsArray": [
                    {
                      "curatedNotificationId": 456,
                      "headline": "Welcome",
                      "body": "Thanks for visiting",
                      "type": "notification",
                      "ctaLabel": "Open",
                      "ctaUrl": "https://bubbl.tech",
                      "published": true
                    }
                  ]
                }
              ],
              "pushCampaign": [],
              "configuration": {"notificationsCount":10,"daysCount":1,"batteryCount":10,"privacyText":"Privacy"}
            }
        """.trimIndent()

        val payload = BubblRuntimeNotificationExtractor.fromRuntimeResponse(response).single()

        assertEquals(BubblNotificationSource.Geofence, payload.source)
        assertEquals("Welcome", payload.title)
        assertEquals("Thanks for visiting", payload.body)
        assertEquals("456", payload.curatedNotificationId)
        assertEquals("10", payload.locationId)
        assertEquals("Open", payload.cta?.label)
    }

    @Test
    fun ignoresPausedRuntimeCampaignNotifications() {
        val response = """
            {
              "geoCampaign": [
                {
                  "campaignId": "paused",
                  "campaignName": "Paused offers",
                  "active": true,
                  "paused": true,
                  "locationsArray": {"locationId": 10},
                  "notificationsArray": [
                    {
                      "curatedNotificationId": "paused-notification",
                      "headline": "Do not send",
                      "body": "Paused campaign",
                      "published": true
                    }
                  ]
                },
                {
                  "campaignId": "status-paused",
                  "campaignName": "Status paused offers",
                  "active": true,
                  "status": "paused",
                  "locationsArray": {"locationId": 11},
                  "notificationsArray": [
                    {
                      "curatedNotificationId": "status-paused-notification",
                      "headline": "Do not send either",
                      "body": "Status paused campaign",
                      "published": true
                    }
                  ]
                }
              ],
              "pushCampaign": [],
              "configuration": {"notificationsCount":10,"daysCount":1,"batteryCount":10,"privacyText":"Privacy"}
            }
        """.trimIndent()

        assertEquals(emptyList<BubblNotificationPayload>(), BubblRuntimeNotificationExtractor.fromRuntimeResponse(response))
    }

    @Test
    fun refreshPushDispatchesRuntimeCampaignNotificationEvents() = runBlocking {
        val transport = BubblHttpTransport { request ->
            val body = if (URI(request.url).path == "/api/check-push") {
                """
                    {
                      "pushCampaign": [
                        {
                          "campaignId": 321,
                          "campaignName": "Push offers",
                          "type": "PUSH",
                          "active": true,
                          "notificationsArray": [
                            {
                              "curatedNotificationId": 654,
                              "headline": "Push hello",
                              "body": "Runtime push",
                              "type": "notification",
                              "published": true
                            }
                          ]
                        }
                      ],
                      "configuration": {"notificationsCount":10,"daysCount":1,"batteryCount":10,"privacyText":"Privacy"}
                    }
                """.trimIndent()
            } else {
                """{"success":true,"queued":true,"data":{"ingest_message_id":"1","status":"queued"}}"""
            }
            BubblHttpResponse(statusCode = 200, body = body)
        }
        BubblSdk.install(storageDirectory = temporaryDirectory(), transport = transport)
        BubblSdk.boot(
            BubblConfig(
                apiKey = "sdk-key",
                runtimeBaseUrl = "https://runtime.test",
                ingestBaseUrl = "https://ingest.test",
                notificationRenderingMode = BubblNotificationRenderingMode.HostRendered
            )
        )

        val event = async(start = CoroutineStart.UNDISPATCHED) {
            withTimeout(1_000) {
                BubblSdk.events.filterIsInstance<BubblEvent.NotificationReceived>().first()
            }
        }

        BubblSdk.refreshPush()

        assertEquals("Push hello", event.await().payload.title)
    }

    @Test
    fun refreshGeofenceEmitsRuntimeShapeSnapshot() = runBlocking {
        val transport = BubblHttpTransport {
            BubblHttpResponse(statusCode = 200, body = geofenceRuntimeResponse())
        }
        BubblSdk.install(storageDirectory = temporaryDirectory(), transport = transport)
        BubblSdk.boot(
            BubblConfig(
                apiKey = "sdk-key",
                runtimeBaseUrl = "https://runtime.test",
                ingestBaseUrl = "https://ingest.test"
            )
        )

        val snapshotEvent = async(start = CoroutineStart.UNDISPATCHED) {
            withTimeout(1_000) {
                BubblSdk.events.filterIsInstance<BubblEvent.GeofenceSnapshot>().first()
            }
        }

        BubblSdk.refreshGeofence(BubblLocation(latitude = 51.50158, longitude = -0.141))

        val snapshot = snapshotEvent.await().snapshot
        assertEquals(1, snapshot.stats.campaignsTotal)
        assertEquals(1, snapshot.stats.polygonsTotal)
        assertEquals("123", snapshot.polygons.single().campaignId)
        assertEquals("Spring offers", snapshot.polygons.single().campaignName)
        assertEquals("10", snapshot.polygons.single().locationId)
        assertEquals(3, snapshot.polygons.single().vertices.size)
        assertEquals(1, snapshot.circles.size)
    }

    @Test
    fun refreshGeofenceSnapshotOnlyIncludesActiveCampaignsWithEligibleNotifications() = runBlocking {
        val transport = BubblHttpTransport {
            BubblHttpResponse(statusCode = 200, body = geofenceRuntimeResponseWithIneligibleCampaigns())
        }
        BubblSdk.install(storageDirectory = temporaryDirectory(), transport = transport)
        BubblSdk.boot(
            BubblConfig(
                apiKey = "sdk-key",
                runtimeBaseUrl = "https://runtime.test",
                ingestBaseUrl = "https://ingest.test"
            )
        )

        val snapshotEvent = async(start = CoroutineStart.UNDISPATCHED) {
            withTimeout(1_000) {
                BubblSdk.events.filterIsInstance<BubblEvent.GeofenceSnapshot>().first()
            }
        }

        BubblSdk.refreshGeofence(BubblLocation(latitude = 51.50158, longitude = -0.141))

        val snapshot = snapshotEvent.await().snapshot
        assertEquals(1, snapshot.stats.campaignsTotal)
        assertEquals(1, snapshot.stats.polygonsTotal)
        assertEquals("eligible", snapshot.polygons.single().campaignId)
        assertEquals("Eligible campaign", snapshot.polygons.single().campaignName)
    }

    @Test
    fun geofenceEngineFiresEnterExitNotificationsWithCooldownAndMaximumTriggers() {
        val response = geofenceRuntimeResponse()
        val inside = BubblLocation(latitude = 51.50158, longitude = -0.141)
        val outside = BubblLocation(latitude = 51.500, longitude = -0.141)
        val now = Instant.parse("2026-05-05T10:00:00Z")

        val entered = BubblGeofenceEngine.evaluate(
            runtimeResponse = response,
            location = inside,
            state = BubblGeofenceState(),
            now = now
        )
        val repeated = BubblGeofenceEngine.evaluate(
            runtimeResponse = response,
            location = inside,
            state = entered.nextState,
            now = now.plusSeconds(60)
        )
        val exited = BubblGeofenceEngine.evaluate(
            runtimeResponse = response,
            location = outside,
            state = repeated.nextState,
            now = now.plusSeconds(120)
        )
        val reenteredAfterCooldown = BubblGeofenceEngine.evaluate(
            runtimeResponse = response,
            location = inside,
            state = exited.nextState,
            now = now.plusSeconds(7200)
        )

        assertEquals(BubblGeofenceTransitionType.Enter, entered.transitions.single().type)
        assertEquals("Welcome", entered.notifications.single().payload.title)
        assertEquals(emptyList<BubblGeofenceTransition>(), repeated.transitions)
        assertEquals(BubblGeofenceTransitionType.Exit, exited.transitions.single().type)
        assertEquals("Goodbye", exited.notifications.single().payload.title)
        assertEquals(BubblGeofenceTransitionType.Enter, reenteredAfterCooldown.transitions.single().type)
        assertEquals(emptyList<BubblGeofenceNotificationDispatch>(), reenteredAfterCooldown.notifications)
    }

    @Test
    fun geofenceEngineIgnoresPausedCampaigns() {
        val response = """
            {
              "geoCampaign": [
                {
                  "campaignId": "paused",
                  "campaignName": "Paused campaign",
                  "active": true,
                  "paused": true,
                  "locationsArray": {
                    "locationId": 10,
                    "geofence": [
                      { "position": 1, "latitude": "51.501476", "longitude": "-0.140112" },
                      { "position": 2, "latitude": "51.501800", "longitude": "-0.141000" },
                      { "position": 3, "latitude": "51.501476", "longitude": "-0.142000" }
                    ]
                  },
                  "notificationsArray": [
                    {
                      "curatedNotificationId": 456,
                      "headline": "Paused welcome",
                      "body": "Should not send",
                      "activation": "ON_ENTER",
                      "published": true
                    }
                  ]
                },
                {
                  "campaignId": "status-paused",
                  "campaignName": "Status paused campaign",
                  "active": true,
                  "status": "paused",
                  "locationsArray": {
                    "locationId": 11,
                    "geofence": [
                      { "position": 1, "latitude": "51.501476", "longitude": "-0.140112" },
                      { "position": 2, "latitude": "51.501800", "longitude": "-0.141000" },
                      { "position": 3, "latitude": "51.501476", "longitude": "-0.142000" }
                    ]
                  },
                  "notificationsArray": [
                    {
                      "curatedNotificationId": 457,
                      "headline": "Status paused welcome",
                      "body": "Should not send",
                      "activation": "ON_ENTER",
                      "published": true
                    }
                  ]
                }
              ],
              "pushCampaign": [],
              "configuration": {"notificationsCount":10,"daysCount":1,"batteryCount":10,"privacyText":"Privacy"}
            }
        """.trimIndent()

        val evaluation = BubblGeofenceEngine.evaluate(
            runtimeResponse = response,
            location = BubblLocation(latitude = 51.50158, longitude = -0.141),
            state = BubblGeofenceState(),
            now = Instant.parse("2026-05-05T10:00:00Z")
        )

        assertTrue(evaluation.transitions.isEmpty())
        assertTrue(evaluation.notifications.isEmpty())
    }

    @Test
    fun geofenceEngineUsesNestedDeliveryPolicyAndCtaSuspend() {
        val response = geofenceRuntimeResponseWithDeliveryPolicy(
            deliveryPolicy = """
                {
                  "activation": "ON_ENTER",
                  "coolingPeriodSeconds": 120,
                  "maximumTriggers": 2,
                  "ctaSuspend": true
                }
            """.trimIndent(),
            configurationFrequencyDefaults = """
                {
                  "coolingPeriodSeconds": 600,
                  "maximumTriggers": 5,
                  "ctaSuspend": false
                }
            """.trimIndent()
        )
        val inside = BubblLocation(latitude = 51.50158, longitude = -0.141)
        val outside = BubblLocation(latitude = 51.500, longitude = -0.141)
        val now = Instant.parse("2026-05-05T10:00:00Z")

        val entered = BubblGeofenceEngine.evaluate(
            runtimeResponse = response,
            location = inside,
            state = BubblGeofenceState(),
            now = now
        )
        val triggerKey = entered.notifications.single().payload.raw[BubblGeofenceTriggerMetadata.triggerKey]
        val exited = BubblGeofenceEngine.evaluate(
            runtimeResponse = response,
            location = outside,
            state = entered.nextState,
            now = now.plusSeconds(10)
        )
        val reenteredAfterCta = BubblGeofenceEngine.evaluate(
            runtimeResponse = response,
            location = inside,
            state = exited.nextState.copy(ctaSuspensions = setOf(triggerKey!!)),
            now = now.plusSeconds(240)
        )

        assertEquals("true", entered.notifications.single().payload.raw[BubblGeofenceTriggerMetadata.ctaSuspend])
        assertEquals(BubblGeofenceTransitionType.Enter, reenteredAfterCta.transitions.single().type)
        assertEquals(emptyList<BubblGeofenceNotificationDispatch>(), reenteredAfterCta.notifications)
    }

    @Test
    fun geofenceEngineUsesConfigurationFrequencyDefaultsWhenNotificationPolicyIsMissing() {
        val response = geofenceRuntimeResponseWithDeliveryPolicy(
            deliveryPolicy = null,
            configurationFrequencyDefaults = """
                {
                  "coolingPeriodSeconds": 0,
                  "maximumTriggers": 1,
                  "ctaSuspend": false
                }
            """.trimIndent()
        )
        val inside = BubblLocation(latitude = 51.50158, longitude = -0.141)
        val outside = BubblLocation(latitude = 51.500, longitude = -0.141)
        val now = Instant.parse("2026-05-05T10:00:00Z")

        val entered = BubblGeofenceEngine.evaluate(
            runtimeResponse = response,
            location = inside,
            state = BubblGeofenceState(),
            now = now
        )
        val exited = BubblGeofenceEngine.evaluate(
            runtimeResponse = response,
            location = outside,
            state = entered.nextState,
            now = now.plusSeconds(10)
        )
        val reentered = BubblGeofenceEngine.evaluate(
            runtimeResponse = response,
            location = inside,
            state = exited.nextState,
            now = now.plusSeconds(20)
        )

        assertEquals("Policy hello", entered.notifications.single().payload.title)
        assertEquals(BubblGeofenceTransitionType.Enter, reentered.transitions.single().type)
        assertEquals(emptyList<BubblGeofenceNotificationDispatch>(), reentered.notifications)
    }

    @Test
    fun geofenceEngineGatesSameNotificationAcrossCampaignLocations() {
        val response = geofenceRuntimeResponseWithTwoLocationsSameNotification()
        val firstLocation = BubblLocation(latitude = 51.50158, longitude = -0.141)
        val secondLocation = BubblLocation(latitude = 51.50358, longitude = -0.141)
        val outside = BubblLocation(latitude = 51.500, longitude = -0.141)
        val now = Instant.parse("2026-05-05T10:00:00Z")

        val firstEntered = BubblGeofenceEngine.evaluate(
            runtimeResponse = response,
            location = firstLocation,
            state = BubblGeofenceState(),
            now = now
        )
        val exited = BubblGeofenceEngine.evaluate(
            runtimeResponse = response,
            location = outside,
            state = firstEntered.nextState,
            now = now.plusSeconds(30)
        )
        val secondEntered = BubblGeofenceEngine.evaluate(
            runtimeResponse = response,
            location = secondLocation,
            state = exited.nextState,
            now = now.plusSeconds(60)
        )

        assertEquals("Welcome", firstEntered.notifications.single().payload.title)
        assertEquals(BubblGeofenceTransitionType.Enter, secondEntered.transitions.single().type)
        assertEquals(emptyList<BubblGeofenceNotificationDispatch>(), secondEntered.notifications)
    }

    @Test
    fun geofenceEngineAllowsDistinctNotificationsInSameCampaign() {
        val entered = BubblGeofenceEngine.evaluate(
            runtimeResponse = geofenceRuntimeResponseWithDistinctEnterNotifications(),
            location = BubblLocation(latitude = 51.50158, longitude = -0.141),
            state = BubblGeofenceState(),
            now = Instant.parse("2026-05-05T10:00:00Z")
        )

        assertEquals(
            listOf("First welcome", "Second welcome"),
            entered.notifications.map { it.payload.title }
        )
    }

    @Test
    fun refreshGeofenceRoutesEnterTransitionThroughNotificationEngine() = runBlocking {
        val requests = mutableListOf<BubblHttpRequest>()
        val transport = BubblHttpTransport { request ->
            requests += request
            val body = if (URI(request.url).path == "/api/check-geofence") {
                geofenceRuntimeResponse()
            } else {
                """{"success":true,"queued":true,"data":{"ingest_message_id":"1","status":"queued"}}"""
            }
            BubblHttpResponse(statusCode = 200, body = body)
        }
        BubblSdk.install(storageDirectory = temporaryDirectory(), transport = transport)
        BubblSdk.boot(
            BubblConfig(
                apiKey = "sdk-key",
                runtimeBaseUrl = "https://runtime.test",
                ingestBaseUrl = "https://ingest.test",
                notificationRenderingMode = BubblNotificationRenderingMode.HostRendered
            )
        )

        val event = async(start = CoroutineStart.UNDISPATCHED) {
            withTimeout(1_000) {
                BubblSdk.events.filterIsInstance<BubblEvent.NotificationReceived>().first()
            }
        }

        BubblSdk.refreshGeofence(BubblLocation(latitude = 51.50158, longitude = -0.141))

        assertEquals("Welcome", event.await().payload.title)
        assertEquals(0, BubblSdk.diagnostics().pendingIngestCount)
        assertEquals(
            true,
            requests.any { request ->
                URI(request.url).path == "/api/activities" &&
                    JSONObject(request.body ?: "{}").optString("activity") == "notification_sent"
            }
        )
    }

    @Test
    fun notificationPayloadRoundTripsThroughDefaultUiCodec() {
        val payload = BubblNotificationPayload(
            id = "notification-1",
            title = "Detail",
            body = "Body",
            source = BubblNotificationSource.Firebase,
            locationId = "7",
            curatedNotificationId = "42",
            media = BubblNotificationMedia(url = "https://cdn.test/image.png", altText = "Image"),
            cta = BubblNotificationCta(label = "Open", url = "https://bubbl.test", action = "open"),
            survey = BubblNotificationSurvey(
                questions = listOf(
                    BubblSurveyQuestion(
                        id = "1",
                        title = "Question",
                        type = "single_choice",
                        choices = listOf(BubblSurveyChoice(id = "5", label = "Great"))
                    )
                )
            ),
            raw = mapOf("headline" to "Detail")
        )

        val restored = BubblNotificationPayloadCodec.fromJsonString(
            BubblNotificationPayloadCodec.toJson(payload).toString()
        )

        assertEquals(payload, restored)
    }

    @Test
    fun androidNotificationRenderPlanUsesBigPictureForImageMediaAndCtaActions() {
        val payload = BubblNotificationPayload(
            id = "notification-rich",
            title = "Rich",
            body = "Body",
            media = BubblNotificationMedia(url = "https://cdn.test/image.png", type = "image/png"),
            cta = BubblNotificationCta(label = "Open", url = "https://bubbl.test", action = "open_offer")
        )

        val plan = BubblAndroidNotificationRuntime.renderPlan(payload)

        assertEquals(true, plan.shouldUseBigPicture)
        assertEquals(BubblNotificationPayloadCodec.actionDefault, plan.contentAction)
        assertEquals("open_offer", plan.ctaAction)
        assertEquals(NotificationCompat.PRIORITY_HIGH, plan.notificationPriority)
        assertEquals(NotificationCompat.CATEGORY_MESSAGE, plan.notificationCategory)
        assertEquals(NotificationCompat.DEFAULT_ALL, plan.notificationDefaults)
    }

    @Test
    fun androidNotificationRenderPlanUsesYoutubeThumbnailForYoutubeMedia() {
        val payload = BubblNotificationPayload(
            id = "notification-youtube",
            title = "Video",
            body = "Body",
            media = BubblNotificationMedia(
                url = "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
                type = "youtube"
            )
        )

        val plan = BubblAndroidNotificationRuntime.renderPlan(payload)
        val media = requireNotNull(payload.media)

        assertEquals(true, plan.shouldUseBigPicture)
        assertEquals("dQw4w9WgXcQ", BubblMediaUrls.youtubeVideoId(media.url))
        assertEquals(
            "https://img.youtube.com/vi/dQw4w9WgXcQ/hqdefault.jpg",
            BubblMediaUrls.notificationImageUrl(media)
        )
        assertEquals(
            "https://www.youtube.com/embed/dQw4w9WgXcQ?playsinline=1&rel=0&origin=https%3A%2F%2Fbubbl.tech",
            BubblMediaUrls.youtubeEmbedUrl(media.url)
        )
    }

    @Test
    fun androidNotificationRenderPlanFallsBackToTextForNonImageMedia() {
        val payload = BubblNotificationPayload(
            id = "notification-audio",
            title = "Audio",
            body = "Body",
            media = BubblNotificationMedia(url = "https://cdn.test/audio.mp3", type = "audio/mpeg")
        )

        val plan = BubblAndroidNotificationRuntime.renderPlan(payload)

        assertEquals(false, plan.shouldUseBigPicture)
        assertNull(plan.ctaAction)
    }

    @Test
    fun defaultNotificationModalMediaHtmlRendersMediaInline() {
        val imageHtml = BubblMediaUrls.inlineMediaHtml(
            BubblNotificationMedia(url = "https://cdn.test/offer.png", type = "image/png", altText = "Offer")
        )
        val audioHtml = BubblMediaUrls.inlineMediaHtml(
            BubblNotificationMedia(url = "https://cdn.test/audio.mp3", type = "audio/mpeg")
        )
        val videoHtml = BubblMediaUrls.inlineMediaHtml(
            BubblNotificationMedia(url = "https://cdn.test/video.mp4", type = "video/mp4")
        )

        assertTrue(imageHtml.contains("<img src=\"https://cdn.test/offer.png\""))
        assertTrue(audioHtml.contains("<audio src=\"https://cdn.test/audio.mp3\" controls"))
        assertTrue(videoHtml.contains("<video src=\"https://cdn.test/video.mp4\" controls"))
        assertFalse(imageHtml.contains("window.open"))
        assertFalse(audioHtml.contains("window.open"))
        assertFalse(videoHtml.contains("window.open"))
    }

    @Test
    fun notificationInteractionsQueueAnalyticsEvents() = runBlocking {
        val requests = mutableListOf<BubblHttpRequest>()
        val transport = BubblHttpTransport { request ->
            requests += request
            BubblHttpResponse(
                statusCode = 200,
                body = """{"success":true,"queued":true,"data":{"ingest_message_id":"1","status":"queued"}}"""
            )
        }
        BubblSdk.install(storageDirectory = temporaryDirectory(), transport = transport)
        BubblSdk.boot(
            BubblConfig(
                apiKey = "sdk-key",
                runtimeBaseUrl = "https://runtime.test",
                ingestBaseUrl = "https://ingest.test"
            )
        )
        val payload = BubblNotificationPayload(
            id = "notification-2",
            title = "Opened",
            body = "Body",
            locationId = "8",
            curatedNotificationId = "43"
        )

        BubblSdk.handleNotificationOpen(payload)
        BubblSdk.handleNotificationCta(payload, action = "open")
        BubblSdk.handleNotificationMediaViewed(payload)
        BubblSdk.handleNotificationSurveyRequested(payload)

        assertEquals(3, BubblSdk.diagnostics().pendingIngestCount)
        BubblSdk.flush()

        val activities = requests
            .filter { request -> URI(request.url).path == "/api/activities" }
            .map { request -> JSONObject(request.body ?: "{}").optString("activity") }

        assertEquals(1, activities.count { activity -> activity == "cta_engagment" })
        assertEquals(true, activities.contains("media_viewed"))
    }

    @Test
    fun hostRenderedFirebaseNotificationDoesNotRequireAndroidContext() = runBlocking {
        val requests = mutableListOf<BubblHttpRequest>()
        val transport = BubblHttpTransport { request ->
            requests += request
            BubblHttpResponse(
                statusCode = 200,
                body = """{"success":true,"queued":true,"data":{"ingest_message_id":"1","status":"queued"}}"""
            )
        }
        BubblSdk.install(storageDirectory = temporaryDirectory(), transport = transport)
        BubblSdk.boot(
            BubblConfig(
                apiKey = "sdk-key",
                runtimeBaseUrl = "https://runtime.test",
                ingestBaseUrl = "https://ingest.test",
                notificationRenderingMode = BubblNotificationRenderingMode.HostRendered
            )
        )

        val payload = BubblSdk.handleFirebasePayload(
            payload = mapOf(
                "title" to "Host modal",
                "body" to "Render this in the app",
                "curated_notification_id" to "21"
            ),
            messageId = "fcm-21"
        )

        assertEquals("Host modal", payload?.title)
        assertEquals(0, BubblSdk.diagnostics().pendingIngestCount)
        assertEquals(
            true,
            requests.any { request ->
                URI(request.url).path == "/api/activities" &&
                    JSONObject(request.body ?: "{}").optString("activity") == "notification_sent"
            }
        )
    }

    @Test
    fun hostRenderedFirebaseNotificationWithoutCuratedIdDoesNotHitDashboardActivityLookup() = runBlocking {
        val requests = mutableListOf<BubblHttpRequest>()
        val transport = BubblHttpTransport { request ->
            requests += request
            BubblHttpResponse(
                statusCode = 200,
                body = """{"success":true,"queued":true,"data":{"ingest_message_id":"1","status":"queued"}}"""
            )
        }
        BubblSdk.install(storageDirectory = temporaryDirectory(), transport = transport)
        BubblSdk.boot(
            BubblConfig(
                apiKey = "sdk-key",
                runtimeBaseUrl = "https://runtime.test",
                ingestBaseUrl = "https://ingest.test",
                notificationRenderingMode = BubblNotificationRenderingMode.HostRendered
            )
        )

        val payload = BubblSdk.handleFirebasePayload(
            payload = mapOf(
                "title" to "Host modal",
                "body" to "Render this in the app",
                "notification_id" to "provider-21"
            )
        )

        assertEquals("provider-21", payload?.id)
        assertNull(payload?.curatedNotificationId)
        assertEquals(0, BubblSdk.diagnostics().pendingIngestCount)
        assertEquals(
            false,
            requests.any { request ->
                URI(request.url).path == "/api/activities" &&
                    JSONObject(request.body ?: "{}").optString("activity") == "notification_sent"
            }
        )
    }

    @Test
    fun defaultNotificationModalTogglePersistsForBackgroundRestores() = runBlocking {
        val directory = temporaryDirectory()
        val transport = BubblHttpTransport {
            BubblHttpResponse(statusCode = 200, body = """{"success":true}""")
        }

        BubblSdk.install(storageDirectory = directory, transport = transport)
        BubblSdk.boot(
            BubblConfig(
                apiKey = "sdk-key",
                runtimeBaseUrl = "https://runtime.test",
                ingestBaseUrl = "https://ingest.test"
            )
        )

        BubblSdk.setDefaultNotificationModalEnabled(false)
        assertFalse(BubblSdk.defaultNotificationModalEnabled())

        BubblSdk.shutdown()
        BubblSdk.install(storageDirectory = directory, transport = transport)

        assertTrue(BubblSdk.restoreForBackground())
        assertFalse(BubblSdk.defaultNotificationModalEnabled())
    }

    @Test
    fun notificationOpenQueuesPendingTapWhenNoEventSubscriber() = runBlocking {
        BubblSdk.drainPendingNotificationTaps()
        BubblSdk.install(
            storageDirectory = temporaryDirectory(),
            transport = BubblHttpTransport { BubblHttpResponse(statusCode = 200, body = """{"success":true}""") }
        )
        BubblSdk.boot(
            BubblConfig(
                apiKey = "sdk-key",
                runtimeBaseUrl = "https://runtime.test",
                ingestBaseUrl = "https://ingest.test"
            )
        )

        val payload = BubblNotificationPayload(
            id = "tap-1",
            title = "Opened",
            body = "From tray",
            source = BubblNotificationSource.Firebase,
            curatedNotificationId = "42",
            locationId = "7"
        )

        BubblSdk.handleNotificationOpen(payload, "default")

        val pending = BubblSdk.drainPendingNotificationTaps()
        assertEquals(1, pending.size)
        assertEquals("tap-1", pending.single().payload.id)
        assertEquals("default", pending.single().action)
        assertTrue(BubblSdk.drainPendingNotificationTaps().isEmpty())
    }

    private fun temporaryDirectory(): File =
        Files.createTempDirectory("bubbl-sdk-android-tests").toFile()

    private fun geofenceRuntimeResponse(): String =
        """
            {
              "geoCampaign": [
                {
                  "campaignId": 123,
                  "campaignName": "Spring offers",
                  "type": "GEO",
                  "active": "true",
                  "locationsArray": {
                    "locationId": 10,
                    "geofence": [
                      { "position": 1, "latitude": "51.501476", "longitude": "-0.140112" },
                      { "position": 2, "latitude": "51.501800", "longitude": "-0.141000" },
                      { "position": 3, "latitude": "51.501476", "longitude": "-0.142000" }
                    ]
                  },
                  "notificationsArray": [
                    {
                      "curatedNotificationId": 456,
                      "headline": "Welcome",
                      "body": "Thanks for visiting",
                      "type": "notification",
                      "activation": "ON_ENTER",
                      "published": true,
                      "coolingPeriodSeconds": 3600,
                      "maximumTriggers": 1
                    },
                    {
                      "curatedNotificationId": 457,
                      "headline": "Goodbye",
                      "body": "See you soon",
                      "type": "notification",
                      "activation": "ON_EXIT",
                      "published": true
                    }
                  ]
                }
              ],
              "pushCampaign": [],
              "configuration": {"notificationsCount":10,"daysCount":1,"batteryCount":10,"privacyText":"Privacy"}
            }
        """.trimIndent()

    private fun geofenceRuntimeResponseWithIneligibleCampaigns(): String =
        """
            {
              "geoCampaign": [
                {
                  "campaignId": "eligible",
                  "campaignName": "Eligible campaign",
                  "active": true,
                  "locationsArray": {
                    "locationId": "eligible-location",
                    "geofence": [
                      { "latitude": "51.501476", "longitude": "-0.140112" },
                      { "latitude": "51.501800", "longitude": "-0.141000" },
                      { "latitude": "51.501476", "longitude": "-0.142000" }
                    ]
                  },
                  "notificationsArray": [
                    {
                      "curatedNotificationId": "eligible-notification",
                      "headline": "Welcome",
                      "body": "Thanks for visiting",
                      "published": true
                    }
                  ]
                },
                {
                  "campaignId": "paused",
                  "campaignName": "Paused campaign",
                  "active": true,
                  "paused": true,
                  "locationsArray": {
                    "locationId": "paused-location",
                    "geofence": [
                      { "latitude": "51.501476", "longitude": "-0.140112" },
                      { "latitude": "51.501800", "longitude": "-0.141000" },
                      { "latitude": "51.501476", "longitude": "-0.142000" }
                    ]
                  },
                  "notificationsArray": [
                    {
                      "curatedNotificationId": "paused-notification",
                      "headline": "Paused",
                      "body": "Do not draw",
                      "published": true
                    }
                  ]
                },
                {
                  "campaignId": "status-paused",
                  "campaignName": "Status paused campaign",
                  "active": true,
                  "status": "paused",
                  "locationsArray": {
                    "locationId": "status-paused-location",
                    "geofence": [
                      { "latitude": "51.501476", "longitude": "-0.140112" },
                      { "latitude": "51.501800", "longitude": "-0.141000" },
                      { "latitude": "51.501476", "longitude": "-0.142000" }
                    ]
                  },
                  "notificationsArray": [
                    {
                      "curatedNotificationId": "status-paused-notification",
                      "headline": "Status paused",
                      "body": "Do not draw",
                      "published": true
                    }
                  ]
                },
                {
                  "campaignId": "inactive",
                  "campaignName": "Inactive campaign",
                  "active": false,
                  "locationsArray": {
                    "locationId": "inactive-location",
                    "geofence": [
                      { "latitude": "51.501476", "longitude": "-0.140112" },
                      { "latitude": "51.501800", "longitude": "-0.141000" },
                      { "latitude": "51.501476", "longitude": "-0.142000" }
                    ]
                  },
                  "notificationsArray": [
                    {
                      "curatedNotificationId": "inactive-notification",
                      "headline": "Inactive",
                      "body": "Do not draw",
                      "published": true
                    }
                  ]
                },
                {
                  "campaignId": "unpublished",
                  "campaignName": "Unpublished notification campaign",
                  "active": true,
                  "locationsArray": {
                    "locationId": "unpublished-location",
                    "geofence": [
                      { "latitude": "51.501476", "longitude": "-0.140112" },
                      { "latitude": "51.501800", "longitude": "-0.141000" },
                      { "latitude": "51.501476", "longitude": "-0.142000" }
                    ]
                  },
                  "notificationsArray": [
                    {
                      "curatedNotificationId": "unpublished-notification",
                      "headline": "Unpublished",
                      "body": "Do not draw",
                      "published": false
                    }
                  ]
                },
                {
                  "campaignId": "empty",
                  "campaignName": "No notification campaign",
                  "active": true,
                  "locationsArray": {
                    "locationId": "empty-location",
                    "geofence": [
                      { "latitude": "51.501476", "longitude": "-0.140112" },
                      { "latitude": "51.501800", "longitude": "-0.141000" },
                      { "latitude": "51.501476", "longitude": "-0.142000" }
                    ]
                  },
                  "notificationsArray": []
                }
              ],
              "pushCampaign": [],
              "configuration": {"notificationsCount":10,"daysCount":1,"batteryCount":10,"privacyText":"Privacy"}
            }
        """.trimIndent()

    private fun geofenceRuntimeResponseWithDeliveryPolicy(
        deliveryPolicy: String?,
        configurationFrequencyDefaults: String
    ): String {
        val policyBlock = deliveryPolicy?.let { ""","deliveryPolicy": $it""" }.orEmpty()

        return """
            {
              "geoCampaign": [
                {
                  "campaignId": 123,
                  "campaignName": "Policy campaign",
                  "type": "GEO",
                  "active": "true",
                  "locationsArray": {
                    "locationId": 10,
                    "geofence": [
                      { "position": 1, "latitude": "51.501476", "longitude": "-0.140112" },
                      { "position": 2, "latitude": "51.501800", "longitude": "-0.141000" },
                      { "position": 3, "latitude": "51.501476", "longitude": "-0.142000" }
                    ]
                  },
                  "notificationsArray": [
                    {
                      "curatedNotificationId": 789,
                      "headline": "Policy hello",
                      "body": "Policy body",
                      "type": "notification",
                      "activation": "ON_ENTER",
                      "published": true
                      $policyBlock
                    }
                  ]
                }
              ],
              "pushCampaign": [],
              "configuration": {
                "notificationsCount":10,
                "daysCount":1,
                "batteryCount":10,
                "privacyText":"Privacy",
                "frequencyDefaults": $configurationFrequencyDefaults
              }
            }
        """.trimIndent()
    }

    private fun geofenceRuntimeResponseWithTwoLocationsSameNotification(): String =
        """
            {
              "geoCampaign": [
                {
                  "campaignId": 123,
                  "campaignName": "Multi-location campaign",
                  "type": "GEO",
                  "active": "true",
                  "locationsArray": [
                    {
                      "locationId": 10,
                      "geofence": [
                        { "position": 1, "latitude": "51.501476", "longitude": "-0.140112" },
                        { "position": 2, "latitude": "51.501800", "longitude": "-0.141000" },
                        { "position": 3, "latitude": "51.501476", "longitude": "-0.142000" }
                      ]
                    },
                    {
                      "locationId": 11,
                      "geofence": [
                        { "position": 1, "latitude": "51.503476", "longitude": "-0.140112" },
                        { "position": 2, "latitude": "51.503800", "longitude": "-0.141000" },
                        { "position": 3, "latitude": "51.503476", "longitude": "-0.142000" }
                      ]
                    }
                  ],
                  "notificationsArray": [
                    {
                      "curatedNotificationId": 456,
                      "headline": "Welcome",
                      "body": "Thanks for visiting",
                      "type": "notification",
                      "activation": "ON_ENTER",
                      "published": true,
                      "coolingPeriodSeconds": 3600,
                      "maximumTriggers": 1
                    }
                  ]
                }
              ],
              "pushCampaign": [],
              "configuration": {"notificationsCount":10,"daysCount":1,"batteryCount":10,"privacyText":"Privacy"}
            }
        """.trimIndent()

    private fun geofenceRuntimeResponseWithDistinctEnterNotifications(): String =
        """
            {
              "geoCampaign": [
                {
                  "campaignId": 123,
                  "campaignName": "Distinct notifications",
                  "type": "GEO",
                  "active": "true",
                  "locationsArray": {
                    "locationId": 10,
                    "geofence": [
                      { "position": 1, "latitude": "51.501476", "longitude": "-0.140112" },
                      { "position": 2, "latitude": "51.501800", "longitude": "-0.141000" },
                      { "position": 3, "latitude": "51.501476", "longitude": "-0.142000" }
                    ]
                  },
                  "notificationsArray": [
                    {
                      "curatedNotificationId": 456,
                      "headline": "First welcome",
                      "body": "First",
                      "type": "notification",
                      "activation": "ON_ENTER",
                      "published": true,
                      "maximumTriggers": 1
                    },
                    {
                      "curatedNotificationId": 457,
                      "headline": "Second welcome",
                      "body": "Second",
                      "type": "notification",
                      "activation": "ON_ENTER",
                      "published": true,
                      "maximumTriggers": 1
                    }
                  ]
                }
              ],
              "pushCampaign": [],
              "configuration": {"notificationsCount":10,"daysCount":1,"batteryCount":10,"privacyText":"Privacy"}
            }
        """.trimIndent()
}
