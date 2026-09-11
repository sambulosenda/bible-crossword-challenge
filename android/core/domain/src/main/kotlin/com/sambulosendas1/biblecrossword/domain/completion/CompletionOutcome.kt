package com.sambulosendas1.biblecrossword.domain.completion

import com.sambulosendas1.biblecrossword.domain.content.Puzzle
import com.sambulosendas1.biblecrossword.domain.content.PuzzleDifficulty
import com.sambulosendas1.biblecrossword.domain.content.PuzzlePack
import com.sambulosendas1.biblecrossword.domain.content.QuestLine
import com.sambulosendas1.biblecrossword.domain.profile.Achievement
import com.sambulosendas1.biblecrossword.domain.profile.Achievements
import com.sambulosendas1.biblecrossword.domain.profile.PlayerProfile
import com.sambulosendas1.biblecrossword.domain.profile.Streaks
import com.sambulosendas1.biblecrossword.domain.progress.PuzzleRecord
import java.time.Instant
import java.time.ZoneId

/**
 * What a completed solve does to the player's state — the port of iOS
 * `CrosswordGameView.handleCompletion`.
 *
 * On iOS this is a hundred lines inside a view, entangled with SwiftData.
 * Here it is a pure function: hand it the profile, the record, and which
 * puzzles are already solved, and it returns the new profile, the new record,
 * and everything the screen needs to announce. That makes the *ordering* —
 * which is the whole point of this code — testable rather than a comment.
 *
 * The ordering constraints, each load-bearing:
 *
 *  1. `firstCompletion` is read from the record **before** anything writes to
 *     it. A replay must not re-count.
 *  2. The streak advances before achievements are evaluated, so a streak
 *     achievement can unlock on the solve that earned it.
 *  3. Best time updates on every solve; the once-per-puzzle stats only on a
 *     first completion.
 *  4. Minis count toward totals and the streak, but a 7×7 cannot earn the
 *     fast-solve or no-hint achievements meant for full puzzles.
 *  5. Pack and quest credit is recorded **before** achievements, so a pack
 *     badge lands on this completion screen rather than the next one.
 *  6. The current puzzle counts as solved when judging packs and quests, even
 *     though its record has not been written yet.
 *  7. Achievements are evaluated last, against the fully-updated profile.
 */
object CompletionOutcome {

    data class Context(
        val puzzle: Puzzle,
        val seconds: Int,
        val profile: PlayerProfile,
        /** The record as it stands *before* this completion. Null when none exists. */
        val record: PuzzleRecord?,
        /** Every puzzle already marked completed. The current one need not be in it. */
        val solvedPuzzleIDs: Set<String>,
        val packs: List<PuzzlePack>,
        val quests: List<QuestLine>,
        /** The streak length lost at the last launch-time break, 0 if none is owed. */
        val pendingStreakBreak: Int = 0,
        /** How the comeback was reached, for analytics. Empty means organic. */
        val comebackSource: String = "",
        val now: Instant,
        val zone: ZoneId = ZoneId.systemDefault(),
    )

    data class QuestStep(val questID: String, val step: Int, val total: Int)

    data class Result(
        val profile: PlayerProfile,
        val record: PuzzleRecord,
        /** False for a replay of a puzzle already finished. */
        val firstCompletion: Boolean,
        /** The streak moved to a new day (as opposed to a second solve today). */
        val streakAdvanced: Boolean,
        /** A 7-day milestone granted a freeze on this solve. */
        val earnedFreeze: Boolean,
        /** This solve answered a broken streak. */
        val isComeback: Boolean,
        /** Present only when [isComeback]; "organic" when the card wasn't used. */
        val comebackSource: String?,
        val completedPacks: List<PuzzlePack>,
        val questSteps: List<QuestStep>,
        val completedQuests: List<QuestLine>,
        val newAchievements: List<Achievement>,
        /**
         * Whether to post this time to the weekly leaderboard: first
         * completion, a Mini, and unaided. A replay knows the answers, and any
         * hint — above all Reveal Puzzle, which is one tap — buys a time
         * nobody solved for.
         */
        val submitToLeaderboard: Boolean,
    )

    fun resolve(context: Context): Result = with(context) {
        val existing = record ?: PuzzleRecord(puzzleID = puzzle.id)
        // (1) Read before anything writes.
        val firstCompletion = !existing.isCompleted

        // (2) Streak first, so a streak achievement can unlock on this solve.
        val freezesBefore = profile.streakFreezes
        val registered = Streaks.registerCompletion(
            profile, isReplay = !firstCompletion, now = now, zone = zone,
        )
        var updated = registered.profile
        val earnedFreeze = updated.streakFreezes > freezesBefore

        // The solve that answers a broken streak. Any solve counts, not just
        // one launched from the card: a player who ignores it and plays the
        // daily has still come back, and the source records which it was.
        val isComeback = pendingStreakBreak > 0 && updated.currentStreak > 0

        // (3)(4) Best time on every solve; a Mini can't earn the full-puzzle stats.
        if (!puzzle.isMini) {
            updated = updated.copy(
                bestSolveSeconds = minOf(updated.bestSolveSeconds ?: Int.MAX_VALUE, seconds)
            )
        }

        var completedPacks = emptyList<PuzzlePack>()
        var questSteps = emptyList<QuestStep>()
        var completedQuests = emptyList<QuestLine>()

        if (firstCompletion) {
            if (!existing.usedHint && !puzzle.isMini) {
                updated = updated.copy(noHintSolves = updated.noHintSolves + 1)
            }
            if (puzzle.difficulty == PuzzleDifficulty.HARD) {
                updated = updated.copy(hardCompleted = updated.hardCompleted + 1)
            }

            // (5)(6) Pack and quest credit before achievements; this puzzle
            // counts as solved even though its record isn't written yet.
            val isSolved: (String) -> Boolean = { it == puzzle.id || it in solvedPuzzleIDs }

            val packCandidates = packs.filter { puzzle.id in it.puzzleIDs }
            completedPacks = packCandidates.filter { pack ->
                pack.id !in updated.completedPackIDs && pack.puzzleIDs.isNotEmpty() && pack.puzzleIDs.all(isSolved)
            }
            if (completedPacks.isNotEmpty()) {
                updated = updated.copy(completedPackIDs = updated.completedPackIDs + completedPacks.map { it.id })
            }

            val questCandidates = quests.filter { puzzle.id in it.puzzleIDs }
            questSteps = questCandidates.mapNotNull { quest ->
                quest.puzzleIDs.indexOf(puzzle.id).takeIf { it >= 0 }?.let {
                    QuestStep(quest.id, it + 1, quest.puzzleIDs.size)
                }
            }
            completedQuests = questCandidates.filter { quest ->
                quest.id !in updated.completedQuestIDs && quest.puzzleIDs.isNotEmpty() && quest.puzzleIDs.all(isSolved)
            }
            if (completedQuests.isNotEmpty()) {
                updated = updated.copy(completedQuestIDs = updated.completedQuestIDs + completedQuests.map { it.id })
            }
        }

        // (7) Achievements last, against the fully-updated profile.
        val newAchievements = Achievements.newlyUnlocked(updated)
        if (newAchievements.isNotEmpty()) {
            updated = updated.copy(
                unlockedAchievementIDs = updated.unlockedAchievementIDs + newAchievements.map { it.id }
            )
        }

        val finishedRecord = existing.copy(
            isCompleted = true,
            completedAt = existing.completedAt ?: now,
            elapsedSeconds = seconds,
            // A completed grid has no provisional letters left.
            pencil = emptyMap(),
            updatedAt = now,
        )

        Result(
            profile = updated,
            record = finishedRecord,
            firstCompletion = firstCompletion,
            streakAdvanced = registered.advanced,
            earnedFreeze = earnedFreeze,
            isComeback = isComeback,
            comebackSource = if (isComeback) comebackSource.ifEmpty { "organic" } else null,
            completedPacks = completedPacks,
            questSteps = questSteps,
            completedQuests = completedQuests,
            newAchievements = newAchievements,
            submitToLeaderboard = firstCompletion && puzzle.isMini && !existing.usedHint,
        )
    }

    /**
     * How long to hold the grid before the completion screen covers it, so the
     * celebration wave (a diagonal sweep, 40 ms per diagonal) finishes playing.
     */
    fun celebrationHoldMillis(size: Int, reduceMotion: Boolean): Long =
        if (reduceMotion) 0 else (2L * (size - 1) * 40) + 550
}
