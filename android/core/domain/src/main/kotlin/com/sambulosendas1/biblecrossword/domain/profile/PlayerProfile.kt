package com.sambulosendas1.biblecrossword.domain.profile

import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

/**
 * The single local player, as a plain value. Mirrors iOS `PlayerProfile` in
 * `Models/Persistence.swift`; `:core:data` maps this to and from the Room
 * entity so every rule below stays JVM-pure and testable against
 * `spec/vectors`.
 *
 * Timestamps are [Instant]; null means never.
 */
data class PlayerProfile(
    val username: String = "Friend",
    val currentStreak: Int = 0,
    val bestStreak: Int = 0,
    /**
     * **Distinct puzzles solved**, not completions — a replay of a puzzle
     * already finished doesn't count. Never recomputed downward: counts
     * inflated by replays before the rule existed are left alone, because
     * recalculating would take back achievements players have been shown.
     */
    val totalPuzzlesCompleted: Int = 0,
    val lastCompletedAt: Instant? = null,
    val hintsUsedToday: Int = 0,
    val hintsAt: Instant? = null,
    val unlockedAchievementIDs: List<String> = emptyList(),
    /** Fastest completed solve, in seconds. */
    val bestSolveSeconds: Int? = null,
    /** Puzzles first solved without any hint. */
    val noHintSolves: Int = 0,
    /** Hard puzzles completed (first completion only). */
    val hardCompleted: Int = 0,
    val completedPackIDs: List<String> = emptyList(),
    val completedQuestIDs: List<String> = emptyList(),
    /** Each auto-forgives a single missed day. Every player starts with one. */
    val streakFreezes: Int = 1,
    val lastFreezeUsedAt: Instant? = null,
    val createdAt: Instant = Instant.EPOCH,
) {
    /**
     * A player still inside their first three completions. The starter gift,
     * the seeded auto-check and free hints all key off this: the daily quota
     * was paywalling day-0 players mid-first-puzzle, and day-one completion is
     * the strongest D1 signal the app has.
     */
    val isStillLearning: Boolean get() = totalPuzzlesCompleted < LEARNING_WINDOW_COMPLETIONS

    /**
     * Hints left today. [UNLIMITED] for premium and for the learning window.
     * The limit is a parameter, not a constant read, so the `hint-quota-one`
     * experiment can hand in a different one without this type learning about
     * PostHog.
     */
    fun hintsRemaining(
        isPremium: Boolean,
        limit: Int = FREE_HINT_LIMIT,
        now: Instant,
        zone: ZoneId = ZoneId.systemDefault(),
    ): Int {
        if (isPremium || isStillLearning) return UNLIMITED
        val usedToday = if (isSameDay(hintsAt, now, zone)) hintsUsedToday else 0
        return maxOf(0, limit - usedToday)
    }

    /**
     * Spends [cost] from today's pool. Free hints (the verse rung) never touch
     * the count or stamp the date, and the learning window pays for nothing.
     */
    fun consumeHint(cost: Int = 1, now: Instant, zone: ZoneId = ZoneId.systemDefault()): PlayerProfile {
        if (cost <= 0 || isStillLearning) return this
        val base = if (isSameDay(hintsAt, now, zone)) hintsUsedToday else 0
        return copy(hintsUsedToday = base + cost, hintsAt = now)
    }

    companion object {
        /** The daily hint pool a free player past the learning window gets. */
        const val FREE_HINT_LIMIT = 3

        /**
         * The tightened pool under test. At 1, [com.sambulosendas1.biblecrossword.domain.engine.HintType.WORD]
         * (2) and `PUZZLE` (3) can never be afforded, so the ladder collapses to
         * the free verse rung, one letter, and the paywall. That is the
         * mechanism, not a side effect.
         */
        const val REDUCED_HINT_LIMIT = 1

        /** Most freezes a player can hold at once. */
        const val MAX_STREAK_FREEZES = 3

        const val LEARNING_WINDOW_COMPLETIONS = 3

        /** What an unlimited pool reads as. The vectors emit -1 for Swift's `Int.max`. */
        const val UNLIMITED = -1

        fun isSameDay(a: Instant?, b: Instant, zone: ZoneId): Boolean =
            a != null && LocalDate.ofInstant(a, zone) == LocalDate.ofInstant(b, zone)
    }
}

/** Streak rules — iOS `enum Streaks`. */
object Streaks {

    /**
     * What a [normalize] pass did. `Broken` carries the length that was lost
     * and is reported **only** on the pass that actually resets it — a second
     * pass the same day finds the streak already at zero and reports
     * [Unchanged], which is what keeps the comeback card from re-firing.
     */
    sealed interface Outcome {
        data object Unchanged : Outcome
        data object FreezeSaved : Outcome
        data class Broken(val previous: Int) : Outcome
    }

    data class NormalizeResult(val profile: PlayerProfile, val outcome: Outcome)

    /**
     * Called on launch: drops a stale streak to zero if a day was missed,
     * unless a single missed day can be bridged by spending a freeze.
     */
    fun normalize(
        profile: PlayerProfile,
        now: Instant,
        zone: ZoneId = ZoneId.systemDefault(),
    ): NormalizeResult {
        val last = profile.lastCompletedAt
            ?: return NormalizeResult(profile.copy(currentStreak = 0), Outcome.Unchanged)

        val today = LocalDate.ofInstant(now, zone)
        val lastDay = LocalDate.ofInstant(last, zone)
        val yesterday = today.minusDays(1)
        // Solved today or yesterday — streak is current, nothing to do.
        if (!lastDay.isBefore(yesterday)) return NormalizeResult(profile, Outcome.Unchanged)

        // A freeze bridges exactly one missed day. Larger gaps reset regardless.
        val dayBeforeYesterday = today.minusDays(2)
        if (lastDay == dayBeforeYesterday && profile.currentStreak > 0 && profile.streakFreezes > 0) {
            return NormalizeResult(
                profile.copy(
                    streakFreezes = profile.streakFreezes - 1,
                    // Fill the gap so later same-day passes don't spend another.
                    lastCompletedAt = startOfDay(yesterday, zone),
                    lastFreezeUsedAt = startOfDay(today, zone),
                ),
                Outcome.FreezeSaved,
            )
        }
        // Only a streak that was actually running can break.
        if (profile.currentStreak <= 0) return NormalizeResult(profile, Outcome.Unchanged)
        return NormalizeResult(profile.copy(currentStreak = 0), Outcome.Broken(profile.currentStreak))
    }

    data class CompletionResult(val profile: PlayerProfile, val advanced: Boolean)

    /**
     * Called when a puzzle is completed. [isReplay] marks a puzzle already
     * finished: the streak still advances — a replay is a real day's play, and
     * after the rotation wraps it is the *only* play available — but it doesn't
     * add to the solved count, which counts distinct puzzles.
     */
    fun registerCompletion(
        profile: PlayerProfile,
        isReplay: Boolean = false,
        now: Instant,
        zone: ZoneId = ZoneId.systemDefault(),
    ): CompletionResult {
        val today = LocalDate.ofInstant(now, zone)
        var streak = profile.currentStreak
        var advanced = false

        val last = profile.lastCompletedAt
        if (last != null) {
            val lastDay = LocalDate.ofInstant(last, zone)
            when {
                // Already completed a puzzle today — count the puzzle, leave the streak.
                lastDay == today -> Unit
                lastDay == today.minusDays(1) -> { streak += 1; advanced = true }
                else -> { streak = 1; advanced = true }
            }
        } else {
            streak = 1
            advanced = true
        }

        val lastDayNow = profile.lastCompletedAt?.let { LocalDate.ofInstant(it, zone) }
        val newLastCompleted = if (lastDayNow != today) startOfDay(today, zone) else profile.lastCompletedAt

        // Reward sustained streaks: a freeze each time it crosses a 7-day
        // milestone, capped so it can't grow without bound.
        val freezes = if (advanced && streak % FREEZE_MILESTONE_DAYS == 0) {
            minOf(profile.streakFreezes + 1, PlayerProfile.MAX_STREAK_FREEZES)
        } else {
            profile.streakFreezes
        }

        return CompletionResult(
            profile.copy(
                currentStreak = streak,
                bestStreak = maxOf(profile.bestStreak, streak),
                totalPuzzlesCompleted = profile.totalPuzzlesCompleted + if (isReplay) 0 else 1,
                lastCompletedAt = newLastCompleted,
                streakFreezes = freezes,
            ),
            advanced,
        )
    }

    const val FREEZE_MILESTONE_DAYS = 7

    private fun startOfDay(day: LocalDate, zone: ZoneId): Instant = day.atStartOfDay(zone).toInstant()
}
