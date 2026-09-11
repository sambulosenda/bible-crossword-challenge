package com.sambulosendas1.biblecrossword.data.db

import com.sambulosendas1.biblecrossword.domain.profile.PlayerProfile
import com.sambulosendas1.biblecrossword.domain.progress.EntriesCodec
import com.sambulosendas1.biblecrossword.domain.progress.PuzzleRecord
import java.time.Instant

/*
 * Room entity <-> domain value. The domain types are plain JVM so every rule
 * stays testable against `spec/vectors` without an emulator; these two
 * functions are the only place the two shapes meet.
 *
 * Instants are stored as epoch millis, null meaning never.
 */

private fun Long?.toInstant(): Instant? = this?.let(Instant::ofEpochMilli)
private fun Instant?.toMillis(): Long? = this?.toEpochMilli()

fun PlayerProfileEntity.toDomain(): PlayerProfile = PlayerProfile(
    username = username,
    currentStreak = currentStreak,
    bestStreak = bestStreak,
    totalPuzzlesCompleted = totalPuzzlesCompleted,
    lastCompletedAt = lastCompletedAt.toInstant(),
    hintsUsedToday = hintsUsedToday,
    hintsAt = hintsAt.toInstant(),
    unlockedAchievementIDs = unlockedAchievementIDs,
    bestSolveSeconds = bestSolveSeconds,
    noHintSolves = noHintSolves,
    hardCompleted = hardCompleted,
    completedPackIDs = completedPackIDs,
    completedQuestIDs = completedQuestIDs,
    streakFreezes = streakFreezes,
    lastFreezeUsedAt = lastFreezeUsedAt.toInstant(),
    createdAt = Instant.ofEpochMilli(createdAt),
)

fun PlayerProfile.toEntity(): PlayerProfileEntity = PlayerProfileEntity(
    username = username,
    currentStreak = currentStreak,
    bestStreak = bestStreak,
    totalPuzzlesCompleted = totalPuzzlesCompleted,
    lastCompletedAt = lastCompletedAt.toMillis(),
    hintsUsedToday = hintsUsedToday,
    hintsAt = hintsAt.toMillis(),
    unlockedAchievementIDs = unlockedAchievementIDs,
    bestSolveSeconds = bestSolveSeconds,
    noHintSolves = noHintSolves,
    hardCompleted = hardCompleted,
    completedPackIDs = completedPackIDs,
    completedQuestIDs = completedQuestIDs,
    streakFreezes = streakFreezes,
    lastFreezeUsedAt = lastFreezeUsedAt.toMillis(),
    createdAt = createdAt.toEpochMilli(),
)

fun PuzzleRecordEntity.toDomain(): PuzzleRecord = PuzzleRecord(
    puzzleID = puzzleID,
    isCompleted = isCompleted,
    completedAt = completedAt.toInstant(),
    elapsedSeconds = elapsedSeconds,
    entries = EntriesCodec.decode(entriesData),
    pencil = EntriesCodec.decode(pencilData),
    usedHint = usedHint,
    updatedAt = Instant.ofEpochMilli(updatedAt),
)

fun PuzzleRecord.toEntity(): PuzzleRecordEntity = PuzzleRecordEntity(
    puzzleID = puzzleID,
    isCompleted = isCompleted,
    completedAt = completedAt.toMillis(),
    elapsedSeconds = elapsedSeconds,
    entriesData = EntriesCodec.encode(entries),
    pencilData = EntriesCodec.encode(pencil),
    usedHint = usedHint,
    updatedAt = updatedAt.toEpochMilli(),
)
