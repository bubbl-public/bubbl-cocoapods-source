package tech.bubbl.sdk

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import androidx.room.Dao
import androidx.room.Database
import androidx.room.Entity
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.PrimaryKey
import androidx.room.Query
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.room.Transaction
import kotlinx.coroutines.flow.first
import org.json.JSONObject

private val Context.bubblSdkDataStore: DataStore<Preferences> by preferencesDataStore(name = "bubbl_sdk_state")

internal class AndroidBubblStore(context: Context) : BubblStore {
    private val appContext = context.applicationContext
    private val dataStore = appContext.bubblSdkDataStore
    private val database = Room.databaseBuilder(
        appContext,
        BubblIngestDatabase::class.java,
        "bubbl-sdk-ingest.db"
    ).build()

    override suspend fun loadState(): BubblStoredState {
        val preferences = dataStore.data.first()
        val stateJson = preferences[STATE_KEY]

        if (stateJson.isNullOrBlank()) {
            val fresh = BubblStoredState.fresh()
            saveState(fresh)
            return fresh
        }

        return BubblStoredState.fromJson(JSONObject(stateJson))
    }

    override suspend fun saveState(state: BubblStoredState) {
        dataStore.edit { preferences ->
            preferences[STATE_KEY] = state.toJson().toString()
        }
    }

    override suspend fun loadConfig(): BubblConfig? {
        val configJson = dataStore.data.first()[CONFIG_KEY] ?: return null
        return bubblConfigFromJson(JSONObject(configJson))
    }

    override suspend fun saveConfig(config: BubblConfig) {
        dataStore.edit { preferences ->
            preferences[CONFIG_KEY] = config.toJson().toString()
        }
    }

    override suspend fun append(request: BubblQueuedRequest) {
        database.queueDao().insert(BubblQueueEntity.fromDomain(request))
    }

    override suspend fun loadQueue(): List<BubblQueuedRequest> =
        database.queueDao().loadAll().map { it.toDomain() }

    override suspend fun saveQueue(queue: List<BubblQueuedRequest>) {
        database.queueDao().replaceAll(queue.map(BubblQueueEntity::fromDomain))
    }

    override suspend fun saveRuntimeCache(name: String, body: String) {
        dataStore.edit { preferences ->
            preferences[runtimeCacheKey(name)] = body
        }
    }

    override suspend fun loadRuntimeCache(name: String): String? =
        dataStore.data.first()[runtimeCacheKey(name)]

    override suspend fun pendingCount(): Int =
        database.queueDao().count()

    private companion object {
        val STATE_KEY = stringPreferencesKey("state")
        val CONFIG_KEY = stringPreferencesKey("config")

        fun runtimeCacheKey(name: String): Preferences.Key<String> =
            stringPreferencesKey("runtime_cache_$name")
    }
}

@Entity(tableName = "bubbl_ingest_queue")
internal data class BubblQueueEntity(
    @PrimaryKey val id: String,
    val path: String,
    val body: String,
    val idempotencyKey: String,
    val attempts: Int,
    val createdAt: String
) {
    fun toDomain(): BubblQueuedRequest = BubblQueuedRequest(
        id = id,
        path = path,
        body = body,
        idempotencyKey = idempotencyKey,
        attempts = attempts,
        createdAt = createdAt
    )

    companion object {
        fun fromDomain(request: BubblQueuedRequest): BubblQueueEntity = BubblQueueEntity(
            id = request.id,
            path = request.path,
            body = request.body,
            idempotencyKey = request.idempotencyKey,
            attempts = request.attempts,
            createdAt = request.createdAt
        )
    }
}

@Dao
internal abstract class BubblQueueDao {
    @Query("SELECT * FROM bubbl_ingest_queue ORDER BY createdAt ASC")
    abstract suspend fun loadAll(): List<BubblQueueEntity>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    abstract suspend fun insert(entity: BubblQueueEntity)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    abstract suspend fun insertAll(entities: List<BubblQueueEntity>)

    @Query("DELETE FROM bubbl_ingest_queue")
    abstract suspend fun deleteAll()

    @Query("SELECT COUNT(*) FROM bubbl_ingest_queue")
    abstract suspend fun count(): Int

    @Transaction
    open suspend fun replaceAll(entities: List<BubblQueueEntity>) {
        deleteAll()
        insertAll(entities)
    }
}

@Database(entities = [BubblQueueEntity::class], version = 1, exportSchema = false)
internal abstract class BubblIngestDatabase : RoomDatabase() {
    abstract fun queueDao(): BubblQueueDao
}
