package com.sambulosendas1.biblecrossword.domain.asks

import java.time.Duration
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

/*
 * The app's four "should we speak up now?" rules, ported from iOS
 * `Models/PremiumAsk.swift`, `ReminderAsk.swift`, `ReviewAsk.swift` and
 * `TrialReoffer.swift`. Each is a pure decision over plain values: the screen
 * owns presentation and persistence, these own the rule — so the cross-surface
 * guarantees stay testable without any UI.
 */

/**
 * Whether to offer Premium to a player who has stuck around and never asked —
 * the app's one proactive ask outside onboarding.
 *
 * Deliberately narrow: it waits for a habit rather than a wall. Five solves is
 * past the learning window (three) with room to spare, and the install day is
 * excluded outright so this can never be a first-sitting interruption stacked
 * on top of onboarding's.
 */
object PremiumAsk {
    /** Solves before the app brings Premium up by itself. */
    const val MIN_COMPLETIONS = 5

    /** The paywall `source`, so its open → tap → purchase funnel reads on its own. */
    const val PAYWALL_SOURCE = "premium_ask"

    data class State(
        val isPremium: Boolean,
        /**
         * Whether [isPremium] is an answer yet. An unproven `false` is not a
         * free player, and this is the one ask that speaks first.
         */
        val entitlementsKnown: Boolean,
        val totalCompleted: Int,
        /** Already assigned an arm — the ask is once ever, in both arms. */
        val assigned: Boolean,
        /** Any surface asked this player for anything since launch. */
        val anyAskThisSession: Boolean,
        /** Today is the day the profile was created. */
        val isInstallDay: Boolean,
    )

    /**
     * Eligibility, not presentation. Answers "is this the moment the app would
     * speak up?" — *both* arms are assigned at that moment, so control isn't
     * every un-flagged player in the app (which would measure engagement
     * rather than the ask). The flag is read after this returns true.
     */
    fun isEligible(s: State): Boolean {
        if (!s.entitlementsKnown || s.isPremium) return false
        if (s.assigned) return false
        if (s.anyAskThisSession) return false
        if (s.isInstallDay) return false
        return s.totalCompleted >= MIN_COMPLETIONS
    }
}

/**
 * Whether a reminder opt-in ask may be shown on a given surface. Only players
 * the OS has never asked are eligible: that is the one state where a tap can
 * still reach the real system dialog. Players who reached it and said no
 * recover through the Settings deep-link, not another prompt.
 */
object ReminderAsk {
    /** Where an ask can appear. Raw values are the analytics `source`. */
    enum class Surface(val rawValue: String) {
        /** Completion screen, first few solves — the moment value was just proved. */
        COMPLETION("completion"),
        /** Home streak card, once there is a streak worth protecting. */
        STREAK_CARD("streak_card"),
        /**
         * The full sheet, once ever, over the completion screen of a solve on a
         * later day than the install. Raw value stays `prompt` so the old and
         * new placements compare directly in analytics.
         */
        RETURN_DAY_SHEET("prompt");
    }

    /** The completion ask retries across the first few solves until answered. */
    const val MAX_COMPLETION_ASKS = 3

    /** The streak card needs a streak worth protecting. */
    const val STREAK_CARD_FLOOR = 2

    data class State(
        val remindersEnabled: Boolean,
        /** OS permission is still undetermined — passed as a plain Bool. */
        val permissionUndetermined: Boolean,
        val totalCompleted: Int,
        val currentStreak: Int,
        val completionAsksShown: Int,
        val streakAskShown: Boolean,
        /** Day of the last ask on ANY surface. */
        val lastAskDay: LocalDate?,
        /** Any surface asked since process launch — two in one sitting reads as nagging. */
        val askedThisSession: Boolean,
        val returnDaySheetShown: Boolean = false,
        /** A first sitting is not a return, so the sheet has nothing true to say. */
        val isInstallDay: Boolean = false,
        val today: LocalDate,
    )

    fun decide(surface: Surface, s: State): Boolean {
        if (s.remindersEnabled || !s.permissionUndetermined || s.askedThisSession) return false
        if (s.lastAskDay == s.today) return false
        return when (surface) {
            Surface.COMPLETION -> s.totalCompleted >= 1 && s.completionAsksShown < MAX_COMPLETION_ASKS
            Surface.STREAK_CARD -> s.currentStreak >= STREAK_CARD_FLOOR && !s.streakAskShown
            Surface.RETURN_DAY_SHEET -> s.totalCompleted >= 1 && !s.returnDaySheetShown && !s.isInstallDay
        }
    }
}

/**
 * Whether the completion screen may call the system review prompt.
 *
 * Three triggers in priority order: solve-count milestones, the first 7-day
 * streak, and — for players well past the ladder's start — once per app
 * version. The spacing gap keeps a cluster of triggers from spending the
 * store's limited displays in one burst.
 */
object ReviewAsk {
    sealed interface Trigger {
        data class Milestone(val rung: Int) : Trigger
        data object Streak : Trigger
        data object Version : Trigger

        /** The analytics `trigger` value for `review_prompt_requested`. */
        val analyticsValue: String
            get() = when (this) {
                is Milestone -> "milestone_$rung"
                is Streak -> "streak"
                is Version -> "version"
            }
    }

    /** Solve counts worth celebrating with an ask. */
    val milestones = listOf(3, 10, 30, 75, 150, 300)

    /** A first week-long streak is a happier moment than any mid-ladder rung. */
    const val STREAK_FLOOR = 7

    /** Version re-asks are for proven loyalists, not everyone who updates. */
    const val VERSION_FLOOR = 30

    /** Minimum spacing between asks on any trigger. */
    val minimumGap: Duration = Duration.ofDays(14)

    /**
     * No ask before the install is this old. Solve counts include Minis, so the
     * first rung is reachable in one sitting — and a day-0 rating is a novelty
     * rating, spent on the player least likely to still be here.
     */
    val minimumInstallAge: Duration = Duration.ofDays(3)

    data class State(
        val totalCompleted: Int,
        val currentStreak: Int,
        /** Highest milestone already asked at. */
        val milestoneAsked: Int,
        val streakAsked: Boolean,
        /** Version at the last ask on ANY trigger — spending one spends that version's re-arm. */
        val versionAsked: String,
        val currentVersion: String,
        val lastAsk: Instant?,
        /** Null (unknown) is treated as old enough — a missing date must not silence a long-time player. */
        val installedAt: Instant?,
        val now: Instant,
    )

    fun decide(s: State): Trigger? {
        // Both floors block without spending: the trigger stays armed and
        // retries on a later solve once the time has passed.
        if (s.installedAt != null && Duration.between(s.installedAt, s.now) < minimumInstallAge) return null
        if (s.lastAsk != null && Duration.between(s.lastAsk, s.now) < minimumGap) return null

        val milestone = milestones.lastOrNull { s.totalCompleted >= it }
        if (milestone != null && milestone > s.milestoneAsked) return Trigger.Milestone(milestone)
        if (s.currentStreak >= STREAK_FLOOR && !s.streakAsked) return Trigger.Streak
        if (s.totalCompleted >= VERSION_FLOOR && s.currentVersion.isNotEmpty() && s.currentVersion != s.versionAsked) {
            return Trigger.Version
        }
        return null
    }
}

/**
 * Whether to offer the free trial again to a player who tapped the CTA and
 * then backed out of the store sheet — the warmest leads the app has.
 *
 * Deliberately narrow: once per abandon, never in the same sitting, and only
 * while the intent is still warm.
 */
object TrialReoffer {
    /** The paywall `source`, so it never re-records an abandon of itself. */
    const val PAYWALL_SOURCE = "trial_abandon"

    /**
     * How long a cancelled sheet stays worth revisiting. Two weeks: past that
     * the player has either settled into the free daily or left, and "still
     * waiting" would be a claim about a decision they don't remember.
     */
    val window: Duration = Duration.ofDays(14)

    data class State(
        /** When they last backed out on a plan that offered a trial. */
        val abandonedAt: Instant?,
        val isPremium: Boolean,
        val reofferShown: Boolean,
        /** When the current process launched. */
        val launchedAt: Instant,
        val now: Instant,
        val zone: ZoneId = ZoneId.systemDefault(),
    )

    /**
     * "A later sitting" is either a later process launch or a later calendar
     * day — the OS keeps processes alive for days, so launch alone would miss
     * someone who backed out in the morning and came back that evening; day
     * alone would re-ask within minutes of a force-quit and reopen.
     */
    fun decide(s: State): Boolean {
        if (s.isPremium || s.reofferShown) return false
        val at = s.abandonedAt ?: return false
        if (Duration.between(at, s.now) > window) return false
        val laterLaunch = at.isBefore(s.launchedAt)
        val laterDay = LocalDate.ofInstant(at, s.zone) != LocalDate.ofInstant(s.now, s.zone)
        return laterLaunch || laterDay
    }
}
