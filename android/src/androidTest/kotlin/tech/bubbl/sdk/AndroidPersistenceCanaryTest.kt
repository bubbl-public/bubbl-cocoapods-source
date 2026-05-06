package tech.bubbl.sdk

import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AndroidPersistenceCanaryTest {
    private val context = ApplicationProvider.getApplicationContext<android.content.Context>()

    @Before
    fun resetQueue() = runTest {
        AndroidBubblStore(context).saveQueue(emptyList())
    }

    @Test
    fun dataStoreAndRoomPersistSdkStateConfigQueueAndRuntimeCache() = runTest {
        val store = AndroidBubblStore(context)
        val state = BubblStoredState(
            installId = "canary-install-id",
            correlationId = "canary-correlation",
            segments = listOf("vip", "metro"),
            pushToken = "canary-token"
        )
        val config = BubblConfig(
            apiKey = "canary-key",
            runtimeBaseUrl = "https://runtime.test",
            ingestBaseUrl = "https://ingest.test",
            segments = listOf("vip", "metro"),
            correlationId = "canary-correlation"
        )
        val queued = BubblQueuedRequest(
            path = BubblTransportMap.bootBatchPath,
            body = """{"device_registered":{"device_id":"canary-install-id"}}""",
            idempotencyKey = "canary-idempotency"
        )

        store.saveState(state)
        store.saveConfig(config)
        store.append(queued)
        store.saveRuntimeCache("config", """{"configuration":{"privacyText":"Cached"}}""")

        val restored = AndroidBubblStore(context)

        assertEquals(state, restored.loadState())
        assertEquals("canary-key", restored.loadConfig()?.apiKey)
        assertEquals(listOf("vip", "metro"), restored.loadConfig()?.segments)
        assertEquals(1, restored.pendingCount())
        assertEquals(BubblTransportMap.bootBatchPath, restored.loadQueue().single().path)
        assertEquals("canary-idempotency", restored.loadQueue().single().idempotencyKey)
        assertNotNull(restored.loadRuntimeCache("config"))
    }
}
