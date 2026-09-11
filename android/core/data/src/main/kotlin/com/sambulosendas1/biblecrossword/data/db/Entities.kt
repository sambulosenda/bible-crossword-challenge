package com.sambulosendas1.biblecrossword.data.db

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.PrimaryKey
import com.sambulosendas1.biblecrossword.domain.progress.EntriesCodec

/*
 * The two persisted models, mirroring iOS `Models/Persistence.swift` field for
 * field. Dates are epoch milliseconds (null = never). String lists are stored
 * as JSON arrays via [Converters].
 *
 * Column defaults are declared inline so an additive migration can fill them:
 * a new non-null column without a default crashes on update (the same rule
 * the iOS SwiftData models learned the hard way).
 */

/** The single local player. Exactly one row, id 1. */
@Entity(tableName = "player_profile")
data class PlayerProfileEntity(
    @PrimaryKey val id: Int = SINGLETON_ID,
    @ColumnInfo(defaultValue = "Friend") val username: String = "Friend",
    @ColumnInfo(defaultValue = "0") val currentStreak: Int = 0,
    @ColumnInfo(defaultValue = "0") val bestStreak: Int = 0,
    /** Distinct puzzles solved — never recomputed downward. */
    @ColumnInfo(defaultValue = "0") val totalPuzzlesCompleted: Int = 0,
    val lastCompletedAt: Long? = null,
    @ColumnInfo(defaultValue = "0") val hintsUsedToday: Int = 0,
    val hintsAt: Long? = null,
    @ColumnInfo(defaultValue = "[]") val unlockedAchievementIDs: List<String> = emptyList(),
    val bestSolveSeconds: Int? = null,
    @ColumnInfo(defaultValue = "0") val noHintSolves: Int = 0,
    @ColumnInfo(defaultValue = "0") val hardCompleted: Int = 0,
    @ColumnInfo(defaultValue = "[]") val completedPackIDs: List<String> = emptyList(),
    @ColumnInfo(defaultValue = "[]") val completedQuestIDs: List<String> = emptyList(),
    /** Every player starts with one; more are earned at streak milestones. */
    @ColumnInfo(defaultValue = "1") val streakFreezes: Int = 1,
    val lastFreezeUsedAt: Long? = null,
    val createdAt: Long = System.currentTimeMillis(),
) {
    companion object {
        const val SINGLETON_ID = 1
    }
}

/** Per-puzzle progress / completion record. One row per puzzle id. */
@Entity(tableName = "puzzle_record")
data class PuzzleRecordEntity(
    @PrimaryKey val puzzleID: String,
    @ColumnInfo(defaultValue = "0") val isCompleted: Boolean = false,
    val completedAt: Long? = null,
    @ColumnInfo(defaultValue = "0") val elapsedSeconds: Int = 0,
    /** [EntriesCodec]-encoded pen letters; lowercase = hint-locked. Null = none. */
    val entriesData: String? = null,
    /** [EntriesCodec]-encoded pencil letters, kept apart — pencil is not progress. */
    val pencilData: String? = null,
    /** True once any hint was revealed on this puzzle — survives resume. */
    @ColumnInfo(defaultValue = "0") val usedHint: Boolean = false,
    val updatedAt: Long = System.currentTimeMillis(),
) {
    val entries: Map<String, String> get() = EntriesCodec.decode(entriesData)
    val pencil: Map<String, String> get() = EntriesCodec.decode(pencilData)

    /** The player typed or pencilled something themselves — revealed cells don't count. */
    val hasPlayerEntries: Boolean get() = EntriesCodec.hasPlayerEntries(entries, pencil)

    fun withEntries(entries: Map<String, String>, pencil: Map<String, String>): PuzzleRecordEntity =
        copy(entriesData = EntriesCodec.encode(entries), pencilData = EntriesCodec.encode(pencil))
}
