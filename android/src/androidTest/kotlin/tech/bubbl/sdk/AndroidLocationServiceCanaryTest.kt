package tech.bubbl.sdk

import android.Manifest
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.async
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.filterIsInstance
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.net.URI
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

@RunWith(AndroidJUnit4::class)
class AndroidLocationServiceCanaryTest {
    private val context = ApplicationProvider.getApplicationContext<Context>()

    @Before
    fun grantLocationPermissionsAndResetStore() {
        val permissions = buildList {
            add(Manifest.permission.ACCESS_COARSE_LOCATION)
            add(Manifest.permission.ACCESS_FINE_LOCATION)
            add(Manifest.permission.POST_NOTIFICATIONS)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                add(Manifest.permission.ACCESS_BACKGROUND_LOCATION)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                add(Manifest.permission.FOREGROUND_SERVICE_LOCATION)
            }
        }.toTypedArray()

        androidx.test.platform.app.InstrumentationRegistry.getInstrumentation().uiAutomation
            .adoptShellPermissionIdentity(*permissions)

        runBlocking {
            val store = AndroidBubblStore(context)
            store.saveQueue(emptyList())
            store.saveRuntimeCache("geofence-state", BubblGeofenceState().toJson().toString())
        }
    }

    @After
    fun tearDown() {
        BubblLocationUpdatesService.stop(context)
        androidx.test.platform.app.InstrumentationRegistry.getInstrumentation().uiAutomation
            .dropShellPermissionIdentity()
    }

    @Test
    fun foregroundServiceTestLocationRoutesThroughGeofenceRefresh() = runBlocking {
        val geofenceRefreshObserved = CountDownLatch(1)
        val requests = CopyOnWriteArrayList<BubblHttpRequest>()
        val transport = BubblHttpTransport { request ->
            requests += request
            val body = when (URI(request.url).path) {
                "/api/check-geofence" -> {
                    geofenceRefreshObserved.countDown()
                    geofenceRuntimeResponse()
                }
                else -> """{"success":true,"queued":true}"""
            }

            BubblHttpResponse(statusCode = 200, body = body)
        }

        BubblSdk.install(context, transport)
        BubblSdk.boot(
            BubblConfig(
                apiKey = "canary-key",
                runtimeBaseUrl = "https://runtime.test",
                ingestBaseUrl = "https://ingest.test",
                enableLocationTracking = true,
                notificationRenderingMode = BubblNotificationRenderingMode.HostRendered
            )
        )

        val locationEvent = async(start = CoroutineStart.UNDISPATCHED) {
            withTimeout(5_000) {
                BubblSdk.events.filterIsInstance<BubblEvent.LocationUpdated>().first()
            }
        }
        val geofenceEvent = async(start = CoroutineStart.UNDISPATCHED) {
            withTimeout(5_000) {
                BubblSdk.events.filterIsInstance<BubblEvent.GeofenceEntered>().first()
            }
        }

        context.startForegroundService(
            Intent(context, BubblLocationUpdatesService::class.java)
                .setAction(BubblLocationUpdatesService.ACTION_TEST_LOCATION_UPDATE)
                .putExtra(BubblLocationUpdatesService.EXTRA_TEST_LATITUDE, 51.50158)
                .putExtra(BubblLocationUpdatesService.EXTRA_TEST_LONGITUDE, -0.141)
                .putExtra(BubblLocationUpdatesService.EXTRA_STOP_AFTER_TEST_LOCATION, true)
        )

        assertTrue(geofenceRefreshObserved.await(10, TimeUnit.SECONDS))
        assertEquals(51.50158, locationEvent.await().location.latitude, 0.00001)
        assertEquals("10", geofenceEvent.await().transition.locationId)
        assertTrue(requests.any { URI(it.url).path == "/api/check-geofence" })
        val pendingCount = waitForPendingIngestAtLeast(3)
        assertTrue("Expected geofence telemetry to be queued, pendingCount=$pendingCount", pendingCount >= 3)
    }

    private suspend fun waitForPendingIngestAtLeast(expected: Int): Int {
        var pendingCount = 0
        withTimeout(5_000) {
            while (pendingCount < expected) {
                pendingCount = BubblSdk.diagnostics().pendingIngestCount
                if (pendingCount < expected) {
                    delay(50)
                }
            }
        }

        return pendingCount
    }

    private fun geofenceRuntimeResponse(): String =
        """
            {
              "geoCampaign": [
                {
                  "campaignId": 123,
                  "campaignName": "Service canary",
                  "type": "GEO",
                  "active": true,
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
                      "published": true
                    }
                  ]
                }
              ],
              "pushCampaign": [],
              "configuration": {"notificationsCount":10,"daysCount":1,"batteryCount":10,"privacyText":"Privacy"}
            }
        """.trimIndent()
}
