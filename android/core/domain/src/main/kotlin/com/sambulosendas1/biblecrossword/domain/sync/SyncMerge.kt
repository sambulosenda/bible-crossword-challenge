package com.sambulosendas1.biblecrossword.domain.sync

import com.sambulosendas1.biblecrossword.domain.profile.PlayerProfile
import com.sambulosendas1.biblecrossword.domain.progress.PuzzleRecord
import java.time.Instant

/**
 * Collapsing duplicate profiles and records — iOS `enum SyncMerge` in
 * `Models/Persistence.swift`.
 *
 * Android v1 is local-only (plan §5), so nothing calls this yet. It is ported
 * now, with its vectors, because the merge *semantics* are the hard part and
 * they are settled: **always keep the most generous value of each field**, so
 * a sync race never costs the player anything they earned on either device.
 * That makes adding Play Games Saved Games later a feature, not a migration.
 */
object SyncMerge {

    /**
     * Collapses profiles into the oldest one. Returns the survivor, or null
     * for an empty list.
     */
    fun mergeProfiles(profiles: List<PlayerProfile>): PlayerProfile? {
        var primary = profiles.minByOrNull { it.createdAt } ?: return null
        for (other in profiles) {
            if (other === primary) continue
            primary = primary.copy(
                // "Friend" is the placeholder, so a real name always wins.
                username = if (primary.username == "Friend" && other.username != "Friend") other.username else primary.username,
                currentStreak = maxOf(primary.currentStreak, other.currentStreak),
                bestStreak = maxOf(primary.bestStreak, other.bestStreak),
                totalPuzzlesCompleted = maxOf(primary.totalPuzzlesCompleted, other.totalPuzzlesCompleted),
                lastCompletedAt = later(primary.lastCompletedAt, other.lastCompletedAt),
                unlockedAchievementIDs = union(primary.unlockedAchievementIDs, other.unlockedAchievementIDs),
                completedPackIDs = union(primary.completedPackIDs, other.completedPackIDs),
                completedQuestIDs = union(primary.completedQuestIDs, other.completedQuestIDs),
                bestSolveSeconds = lower(primary.bestSolveSeconds, other.bestSolveSeconds),
                noHintSolves = maxOf(primary.noHintSolves, other.noHintSolves),
                hardCompleted = maxOf(primary.hardCompleted, other.hardCompleted),
                streakFreezes = minOf(maxOf(primary.streakFreezes, other.streakFreezes), PlayerProfile.MAX_STREAK_FREEZES),
                lastFreezeUsedAt = later(primary.lastFreezeUsedAt, other.lastFreezeUsedAt),
            ).let { merged ->
                // The device that spent hints most recently owns today's count:
                // date and count move together, or the pair goes incoherent.
                if (isAfter(other.hintsAt, merged.hintsAt)) {
                    merged.copy(hintsAt = other.hintsAt, hintsUsedToday = other.hintsUsedToday)
                } else {
                    merged
                }
            }
        }
        return primary
    }

    /**
     * Collapses duplicate records for one puzzle into the most advanced
     * (completed beats in-progress, then most recently updated).
     */
    fun mergeRecords(records: List<PuzzleRecord>): PuzzleRecord? {
        var primary = records.maxWithOrNull(
            compareBy({ if (it.isCompleted) 1 else 0 }, { it.updatedAt })
        ) ?: return null
        for (other in records) {
            if (other === primary) continue
            primary = primary.copy(
                // The earliest completion is the historically accurate one.
                completedAt = earlier(primary.completedAt, other.completedAt),
                usedHint = primary.usedHint || other.usedHint,
            )
        }
        return primary
    }

    /** Groups by puzzle id and merges each group — the whole-store sweep. */
    fun mergeDuplicateRecords(records: List<PuzzleRecord>): List<PuzzleRecord> =
        records.groupBy { it.puzzleID }.values.mapNotNull { mergeRecords(it) }

    private fun union(a: List<String>, b: List<String>): List<String> =
        a + b.filterNot { it in a }

    private fun later(a: Instant?, b: Instant?): Instant? = when {
        a == null -> b
        b == null -> a
        else -> if (b.isAfter(a)) b else a
    }

    private fun earlier(a: Instant?, b: Instant?): Instant? = when {
        a == null -> b
        b == null -> a
        else -> if (b.isBefore(a)) b else a
    }

    private fun lower(a: Int?, b: Int?): Int? = when {
        a == null -> b
        b == null -> a
        else -> minOf(a, b)
    }

    private fun isAfter(candidate: Instant?, current: Instant?): Boolean = when {
        candidate == null -> false
        current == null -> true
        else -> candidate.isAfter(current)
    }
}
