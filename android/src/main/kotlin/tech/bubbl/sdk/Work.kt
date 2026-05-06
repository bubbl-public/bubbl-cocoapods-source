package tech.bubbl.sdk

import android.content.Context
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import java.time.Duration
import java.util.concurrent.TimeUnit

internal object BubblWorkScheduler {
    private const val FLUSH_WORK_NAME = "bubbl-sdk-flush"
    private const val REFRESH_WORK_NAME = "bubbl-sdk-refresh"

    fun scheduleFlush(context: Context) {
        val request = OneTimeWorkRequestBuilder<BubblFlushWorker>()
            .setConstraints(networkConstraints())
            .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.SECONDS)
            .build()

        WorkManager.getInstance(context.applicationContext)
            .enqueueUniqueWork(FLUSH_WORK_NAME, ExistingWorkPolicy.KEEP, request)
    }

    fun schedulePeriodicWork(context: Context, config: BubblConfig) {
        val repeatInterval = Duration.ofSeconds(config.refreshIntervalSeconds.toLong())
            .coerceAtLeast(Duration.ofMinutes(15))
        val request = PeriodicWorkRequestBuilder<BubblRefreshWorker>(repeatInterval)
            .setConstraints(networkConstraints())
            .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.SECONDS)
            .build()

        WorkManager.getInstance(context.applicationContext)
            .enqueueUniquePeriodicWork(REFRESH_WORK_NAME, ExistingPeriodicWorkPolicy.UPDATE, request)
    }

    private fun networkConstraints(): Constraints =
        Constraints.Builder()
            .setRequiredNetworkType(NetworkType.CONNECTED)
            .build()
}

public class BubblFlushWorker(
    appContext: Context,
    workerParameters: WorkerParameters
) : CoroutineWorker(appContext, workerParameters) {
    override suspend fun doWork(): Result {
        BubblSdk.install(applicationContext)

        if (!BubblSdk.restoreForBackground()) {
            return Result.success()
        }

        val result = BubblSdk.flush()

        return if (result.pendingCount == 0) Result.success() else Result.retry()
    }
}

public class BubblRefreshWorker(
    appContext: Context,
    workerParameters: WorkerParameters
) : CoroutineWorker(appContext, workerParameters) {
    override suspend fun doWork(): Result {
        BubblSdk.install(applicationContext)

        if (!BubblSdk.restoreForBackground()) {
            return Result.success()
        }

        return runCatching {
            BubblSdk.refresh()
            BubblSdk.refreshGeofenceFromLastKnownLocation(applicationContext)
            BubblSdk.flush()
        }.fold(
            onSuccess = { Result.success() },
            onFailure = { Result.retry() }
        )
    }
}
