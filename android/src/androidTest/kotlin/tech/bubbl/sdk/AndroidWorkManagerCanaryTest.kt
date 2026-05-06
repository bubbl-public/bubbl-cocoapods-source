package tech.bubbl.sdk

import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.work.Configuration
import androidx.work.WorkInfo
import androidx.work.WorkManager
import androidx.work.testing.SynchronousExecutor
import androidx.work.testing.WorkManagerTestInitHelper
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.util.concurrent.TimeUnit

@RunWith(AndroidJUnit4::class)
class AndroidWorkManagerCanaryTest {
    private val context = ApplicationProvider.getApplicationContext<android.content.Context>()

    @Before
    fun setUpWorkManager() {
        val config = Configuration.Builder()
            .setExecutor(SynchronousExecutor())
            .setMinimumLoggingLevel(android.util.Log.DEBUG)
            .build()
        WorkManagerTestInitHelper.initializeTestWorkManager(context, config)
        WorkManager.getInstance(context).cancelAllWork().result.get(5, TimeUnit.SECONDS)
    }

    @Test
    fun schedulesConstrainedFlushWork() {
        BubblWorkScheduler.scheduleFlush(context)

        val work = WorkManager.getInstance(context)
            .getWorkInfosForUniqueWork("bubbl-sdk-flush")
            .get(5, TimeUnit.SECONDS)

        assertEquals(1, work.size)
        assertTrue(work.single().state in listOf(WorkInfo.State.ENQUEUED, WorkInfo.State.BLOCKED))
    }

    @Test
    fun schedulesPeriodicRefreshWork() {
        BubblWorkScheduler.schedulePeriodicWork(
            context,
            BubblConfig(apiKey = "canary-key", refreshIntervalSeconds = 60)
        )

        val work = WorkManager.getInstance(context)
            .getWorkInfosForUniqueWork("bubbl-sdk-refresh")
            .get(5, TimeUnit.SECONDS)

        assertEquals(1, work.size)
        assertTrue(work.single().state in listOf(WorkInfo.State.ENQUEUED, WorkInfo.State.BLOCKED))
    }
}
