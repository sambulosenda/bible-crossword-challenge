package com.sambulosendas1.biblecrossword.domain.profile

import com.sambulosendas1.biblecrossword.domain.content.PuzzleDifficulty
import kotlin.math.min

/** Formats seconds as "m:ss" (or "h:mm:ss" past an hour). iOS `TimeFormat.clock`. */
fun clockText(seconds: Int): String {
    val s = maxOf(0, seconds)
    val hours = s / 3600
    val minutes = (s % 3600) / 60
    val secs = s % 60
    return if (hours > 0) "%d:%02d:%02d".format(hours, minutes, secs) else "%d:%02d".format(minutes, secs)
}

sealed interface Goal {
    data class Puzzles(val target: Int) : Goal
    data class Streak(val target: Int) : Goal
    data class FastSolve(val maxSeconds: Int) : Goal
    data class NoHints(val target: Int) : Goal
    data class Difficulty(val difficulty: PuzzleDifficulty, val target: Int) : Goal
    data class PacksCompleted(val target: Int) : Goal
    data class QuestsCompleted(val target: Int) : Goal
}

/**
 * One achievement. Mirrors iOS `struct Achievement`; [symbol] is the SF Symbol
 * name the iOS app uses, mapped to a drawable on Android (requirements §4.5).
 */
data class Achievement(
    val id: String,
    val title: String,
    val detail: String,
    val symbol: String,
    val goal: Goal,
) {
    fun isUnlocked(by: PlayerProfile): Boolean = progress(by) >= 1.0

    fun progress(p: PlayerProfile): Double = when (val g = goal) {
        is Goal.Puzzles -> min(1.0, p.totalPuzzlesCompleted.toDouble() / g.target)
        is Goal.Streak -> min(1.0, maxOf(p.bestStreak, p.currentStreak).toDouble() / g.target)
        // Binary: achieved once any solve beats the target time.
        is Goal.FastSolve -> p.bestSolveSeconds?.let { if (it <= g.maxSeconds) 1.0 else 0.0 } ?: 0.0
        is Goal.NoHints -> min(1.0, p.noHintSolves.toDouble() / g.target)
        is Goal.Difficulty -> min(1.0, count(g.difficulty, p).toDouble() / g.target)
        is Goal.PacksCompleted -> min(1.0, p.completedPackIDs.size.toDouble() / g.target)
        is Goal.QuestsCompleted -> min(1.0, p.completedQuestIDs.size.toDouble() / g.target)
    }

    /** e.g. "3 / 5" — current value over the goal target. */
    fun progressText(p: PlayerProfile): String = when (val g = goal) {
        is Goal.Puzzles -> "${min(p.totalPuzzlesCompleted, g.target)} / ${g.target}"
        is Goal.Streak -> "${min(maxOf(p.bestStreak, p.currentStreak), g.target)} / ${g.target}"
        is Goal.FastSolve -> "< ${clockText(g.maxSeconds)}"
        is Goal.NoHints -> "${min(p.noHintSolves, g.target)} / ${g.target}"
        is Goal.Difficulty -> "${min(count(g.difficulty, p), g.target)} / ${g.target}"
        is Goal.PacksCompleted -> "${min(p.completedPackIDs.size, g.target)} / ${g.target}"
        is Goal.QuestsCompleted -> "${min(p.completedQuestIDs.size, g.target)} / ${g.target}"
    }

    /** Completion count for a difficulty. Only hard is tracked today. */
    private fun count(difficulty: PuzzleDifficulty, p: PlayerProfile): Int =
        if (difficulty == PuzzleDifficulty.HARD) p.hardCompleted else 0
}

object Achievements {
    /** Order is display order and must match `spec/vectors/constants.json`. */
    val all: List<Achievement> = listOf(
        Achievement("bible-beginner", "Bible Beginner", "Complete 5 puzzles", "book", Goal.Puzzles(5)),
        Achievement("unaided", "Unaided", "Solve a puzzle without hints", "hand.raised.slash", Goal.NoHints(1)),
        Achievement("quick-wit", "Quick Wit", "Solve a puzzle in under 5 minutes", "bolt.fill", Goal.FastSolve(300)),
        Achievement("disciple", "Disciple", "Complete 25 puzzles", "figure.walk", Goal.Puzzles(25)),
        Achievement("lightning-round", "Lightning Round", "Solve a puzzle in under 2 minutes", "bolt.horizontal.fill", Goal.FastSolve(120)),
        Achievement("trial-by-fire", "Trial by Fire", "Complete 5 hard puzzles", "mountain.2.fill", Goal.Difficulty(PuzzleDifficulty.HARD, 5)),
        Achievement("purist", "Purist", "Solve 10 puzzles without hints", "sparkles", Goal.NoHints(10)),
        Achievement("scholar", "Scholar", "Complete 100 puzzles", "graduationcap", Goal.Puzzles(100)),
        Achievement("evangelist", "Evangelist", "Reach a 30 day streak", "flame", Goal.Streak(30)),
        Achievement("apostle", "Apostle", "Reach a 100 day streak", "crown", Goal.Streak(100)),
        Achievement("pathfinder", "Pathfinder", "Complete a puzzle pack", "square.stack.3d.up.fill", Goal.PacksCompleted(1)),
        Achievement("collector", "Collector", "Complete 3 puzzle packs", "books.vertical.fill", Goal.PacksCompleted(3)),
        Achievement("first-journey", "First Journey", "Walk a Journey to its end", "map.fill", Goal.QuestsCompleted(1)),
        Achievement("pilgrim", "Pilgrim", "Complete 3 Journeys", "signpost.right.fill", Goal.QuestsCompleted(3)),
    )

    /** Achievements newly satisfied that aren't already recorded on the profile. */
    fun newlyUnlocked(p: PlayerProfile): List<Achievement> {
        val already = p.unlockedAchievementIDs.toSet()
        return all.filter { it.isUnlocked(p) && it.id !in already }
    }
}
