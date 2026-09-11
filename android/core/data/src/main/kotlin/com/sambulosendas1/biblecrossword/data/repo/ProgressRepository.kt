package com.sambulosendas1.biblecrossword.data.repo

import com.sambulosendas1.biblecrossword.data.db.PlayerProfileDao
import com.sambulosendas1.biblecrossword.data.db.PuzzleRecordDao
import com.sambulosendas1.biblecrossword.data.db.toDomain
import com.sambulosendas1.biblecrossword.data.db.toEntity
import com.sambulosendas1.biblecrossword.domain.profile.PlayerProfile
import com.sambulosendas1.biblecrossword.domain.progress.PuzzleRecord
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import java.time.Instant
import javax.inject.Inject
import javax.inject.Singleton

/**
 * The player's profile and per-puzzle progress, as domain values.
 *
 * Everything above this line works in [PlayerProfile] / [PuzzleRecord]; the
 * Room shapes stop here.
 */
@Singleton
class ProgressRepository @Inject constructor(
    private val profileDao: PlayerProfileDao,
    private val recordDao: PuzzleRecordDao,
) {
    fun observeProfile(): Flow<PlayerProfile> =
        profileDao.observe().map { it?.toDomain() ?: PlayerProfile() }

    /**
     * The single profile row, created on first read. Mirrors iOS
     * `RootView.ensureProfile` — the app has exactly one local player and
     * never asks whether they exist.
     */
    suspend fun profile(): PlayerProfile {
        profileDao.get()?.let { return it.toDomain() }
        val fresh = PlayerProfile(createdAt = Instant.now())
        profileDao.insertIfAbsent(fresh.toEntity())
        return profileDao.get()?.toDomain() ?: fresh
    }

    suspend fun saveProfile(profile: PlayerProfile) {
        profileDao.upsert(profile.toEntity())
    }

    suspend fun record(puzzleID: String): PuzzleRecord? = recordDao.get(puzzleID)?.toDomain()

    fun observeRecords(): Flow<Map<String, PuzzleRecord>> =
        recordDao.observeAll().map { list -> list.associate { it.puzzleID to it.toDomain() } }

    /** A one-shot read of every record, keyed by puzzle id. */
    suspend fun observeRecordsSnapshot(): Map<String, PuzzleRecord> =
        recordDao.getAll().associate { it.puzzleID to it.toDomain() }

    suspend fun saveRecord(record: PuzzleRecord) {
        recordDao.upsert(record.copy(updatedAt = Instant.now()).toEntity())
    }

    /** Puzzles the player has actually worked on — the free tier's grandfather clause. */
    suspend fun startedPuzzleIDs(): Set<String> = recordDao.getAll().map { it.puzzleID }.toSet()

    /** Puzzles actually finished — what pack and quest credit is judged against. */
    suspend fun completedPuzzleIDs(): Set<String> =
        recordDao.getAll().filter { it.isCompleted }.map { it.puzzleID }.toSet()
}
