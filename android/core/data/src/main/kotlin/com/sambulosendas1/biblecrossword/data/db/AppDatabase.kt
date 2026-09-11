package com.sambulosendas1.biblecrossword.data.db

import androidx.room.Dao
import androidx.room.Database
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.RoomDatabase
import androidx.room.TypeConverter
import androidx.room.TypeConverters
import androidx.room.Upsert
import kotlinx.coroutines.flow.Flow
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.json.Json

class Converters {
    private val json = Json
    private val strings = ListSerializer(String.serializer())

    @TypeConverter
    fun listToJson(value: List<String>): String = json.encodeToString(strings, value)

    @TypeConverter
    fun jsonToList(value: String): List<String> =
        runCatching { json.decodeFromString(strings, value) }.getOrDefault(emptyList())
}

@Dao
interface PlayerProfileDao {
    @Query("SELECT * FROM player_profile WHERE id = ${PlayerProfileEntity.SINGLETON_ID}")
    fun observe(): Flow<PlayerProfileEntity?>

    @Query("SELECT * FROM player_profile WHERE id = ${PlayerProfileEntity.SINGLETON_ID}")
    suspend fun get(): PlayerProfileEntity?

    @Upsert
    suspend fun upsert(profile: PlayerProfileEntity)

    /** Creates the single row if absent; never overwrites an existing one. */
    @Insert(onConflict = OnConflictStrategy.IGNORE)
    suspend fun insertIfAbsent(profile: PlayerProfileEntity)
}

@Dao
interface PuzzleRecordDao {
    @Query("SELECT * FROM puzzle_record WHERE puzzleID = :puzzleID")
    fun observe(puzzleID: String): Flow<PuzzleRecordEntity?>

    @Query("SELECT * FROM puzzle_record WHERE puzzleID = :puzzleID")
    suspend fun get(puzzleID: String): PuzzleRecordEntity?

    @Query("SELECT * FROM puzzle_record")
    fun observeAll(): Flow<List<PuzzleRecordEntity>>

    @Query("SELECT * FROM puzzle_record")
    suspend fun getAll(): List<PuzzleRecordEntity>

    @Query("SELECT * FROM puzzle_record WHERE isCompleted = 1")
    fun observeCompleted(): Flow<List<PuzzleRecordEntity>>

    @Upsert
    suspend fun upsert(record: PuzzleRecordEntity)
}

@Database(
    entities = [PlayerProfileEntity::class, PuzzleRecordEntity::class],
    version = 1,
    exportSchema = true,
)
@TypeConverters(Converters::class)
abstract class AppDatabase : RoomDatabase() {
    abstract fun playerProfileDao(): PlayerProfileDao
    abstract fun puzzleRecordDao(): PuzzleRecordDao

    companion object {
        /** Stable from day one — Auto Backup keys on the file name (plan §5). */
        const val NAME = "bible_crossword.db"
    }
}
