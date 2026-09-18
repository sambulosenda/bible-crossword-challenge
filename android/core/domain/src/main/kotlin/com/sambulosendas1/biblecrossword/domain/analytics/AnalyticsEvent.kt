package com.sambulosendas1.biblecrossword.domain.analytics

/**
 * The analytics vocabulary — the Kotlin half of iOS `Services/Analytics.swift`.
 *
 * **This file protects something already live.** The PostHog and Firebase
 * projects are shared with the iOS app, so an event name or parameter key that
 * differs by a character does not merely fail to measure Android: it pollutes
 * dashboards, saved insights, and the arms of the experiments currently
 * running. `spec/vectors/analytics.json` is generated from the shipping Swift
 * and the parity test asserts every name and key set against it.
 *
 * Every event also carries [PLATFORM_KEY] — see [AnalyticsService].
 */
sealed class AnalyticsEvent(val name: String, val parameters: Map<String, Any?> = emptyMap()) {

    data object AppOpen : AnalyticsEvent("app_open")

    class OnboardingStep(index: Int, stepName: String) :
        AnalyticsEvent("onboarding_step", mapOf("step_index" to index, "step_name" to stepName))

    class OnboardingFirstSolve(solved: Boolean, attempts: Int) :
        AnalyticsEvent("onboarding_first_solve", mapOf("solved" to solved, "attempts" to attempts))

    class OnboardingCompleted(solvedFirstClue: Boolean) :
        AnalyticsEvent("onboarding_completed", mapOf("solved_first_clue" to solvedFirstClue))

    /**
     * Fires on every entry to the game screen, so `is_resume` is what makes it
     * readable: without it a player who opens the daily four times counts as
     * four starts. `source` is the surface that pushed the screen.
     */
    class DailyPuzzleStarted(puzzleID: String, isResume: Boolean, source: String) :
        AnalyticsEvent("daily_puzzle_started", mapOf("puzzle_id" to puzzleID, "is_resume" to isResume, "source" to source))

    class DailyPuzzleCompleted(puzzleID: String, seconds: Int) :
        AnalyticsEvent("daily_puzzle_completed", mapOf("puzzle_id" to puzzleID, "seconds" to seconds))

    /**
     * Leaving the game screen mid-solve — the other half of the
     * start→complete funnel. `fill_percent` is where they stopped, `seconds`
     * the *active* clock, `wall_seconds` how long the screen was open, so a
     * fast bounce is distinguishable from a prewarm. `cell_taps` and
     * `key_presses` split the largest abandon bucket: quitting at 0% fill has
     * three very different causes.
     */
    class PuzzleAbandoned(
        puzzleID: String, fillPercent: Int, seconds: Int, wallSeconds: Int,
        hintsUsed: Int, cellTaps: Int, keyPresses: Int,
    ) : AnalyticsEvent(
        "puzzle_abandoned",
        mapOf(
            "puzzle_id" to puzzleID, "fill_percent" to fillPercent, "seconds" to seconds,
            "wall_seconds" to wallSeconds, "hints_used" to hintsUsed,
            "cell_taps" to cellTaps, "key_presses" to keyPresses,
            // Derived here, not at the call site, so one definition governs
            // every query on both platforms.
            "bounce" to (cellTaps == 0 && keyPresses == 0 && wallSeconds < BOUNCE_WALL_SECONDS),
        ),
    )

    class HintUsed(type: String, cost: Int) :
        AnalyticsEvent("hint_used", mapOf("type" to type, "cost" to cost))

    /** A paid hint tapped with no quota left — logged at the wall, not the paywall. */
    class HintLimitReached(type: String) :
        AnalyticsEvent("hint_limit_reached", mapOf("type" to type))

    class CheckUsed(scope: String, wrongCount: Int) :
        AnalyticsEvent("check_used", mapOf("scope" to scope, "wrong_count" to wrongCount))

    class StallNudgeShown(puzzleID: String, fillPercent: Int, idleSeconds: Int, kind: String) :
        AnalyticsEvent("stall_nudge_shown", mapOf("puzzle_id" to puzzleID, "fill_percent" to fillPercent, "idle_seconds" to idleSeconds, "kind" to kind))

    class StallNudgeTapped(puzzleID: String, fillPercent: Int, idleSeconds: Int, kind: String) :
        AnalyticsEvent("stall_nudge_tapped", mapOf("puzzle_id" to puzzleID, "fill_percent" to fillPercent, "idle_seconds" to idleSeconds, "kind" to kind))

    class StarterWordGifted(puzzleID: String, answerLength: Int) :
        AnalyticsEvent("starter_word_gifted", mapOf("puzzle_id" to puzzleID, "answer_length" to answerLength))

    class WidgetOpened(destination: String) :
        AnalyticsEvent("widget_opened", mapOf("destination" to destination))

    class StreakUpdated(streak: Int) : AnalyticsEvent("streak_updated", mapOf("streak" to streak))

    /** Fires once, on the launch that resets the streak, carrying what was lost. */
    class StreakBroken(previousLength: Int) :
        AnalyticsEvent("streak_broken", mapOf("previous_length" to previousLength))

    class StreakComebackStarted(source: String) :
        AnalyticsEvent("streak_comeback_started", mapOf("source" to source))

    class AchievementUnlocked(id: String) :
        AnalyticsEvent("achievement_unlocked", mapOf("achievement_id" to id))

    /**
     * `is_trial` is what the store actually applied, so a trial start and a
     * paid conversion are never the same row. `acquisition` tells a self-serve
     * tap apart from a grant that landed while the app was closed.
     */
    class PremiumPurchased(plan: String, source: String, isTrial: Boolean, amount: PurchaseAmount, acquisition: String) :
        AnalyticsEvent(
            "premium_purchased",
            mapOf(
                "plan" to plan, "source" to source, "is_trial" to isTrial,
                "acquisition" to acquisition, "currency" to amount.currencyCode,
                // The sticker price, and what was actually charged *now*. They
                // differ on a trial start, where revenue is zero — summing
                // revenue then gives real money rather than notional value.
                // Point PostHog's Revenue tab at revenue_minor_units.
                "price_minor_units" to amount.minorUnits,
                "revenue_minor_units" to if (isTrial) 0 else amount.minorUnits,
            ),
        )

    /** Real revenue, but not a new customer — deliberately not `premium_purchased`. */
    class SubscriptionRenewed(plan: String, isTrial: Boolean, amount: PurchaseAmount) :
        AnalyticsEvent(
            "subscription_renewed",
            mapOf(
                "plan" to plan, "is_trial" to isTrial, "currency" to amount.currencyCode,
                "price_minor_units" to amount.minorUnits,
                "revenue_minor_units" to if (isTrial) 0 else amount.minorUnits,
            ),
        )

    class PurchaseFailed(plan: String, source: String, reason: String) :
        AnalyticsEvent("purchase_failed", mapOf("plan" to plan, "source" to source, "reason" to reason))

    /** Pressed buy, saw the store sheet, backed out — the largest funnel leak. */
    class PurchaseCancelled(plan: String, source: String, offersTrial: Boolean, amount: PurchaseAmount) :
        AnalyticsEvent(
            "purchase_cancelled",
            mapOf("plan" to plan, "source" to source, "offers_trial" to offersTrial, "currency" to amount.currencyCode, "price_minor_units" to amount.minorUnits),
        )

    class PaywallOpened(source: String) : AnalyticsEvent("paywall_opened", mapOf("source" to source))

    class PaywallCTATapped(plan: String, source: String, offersTrial: Boolean) :
        AnalyticsEvent("paywall_cta_tapped", mapOf("plan" to plan, "source" to source, "offers_trial" to offersTrial))

    class PaywallDismissed(source: String, secondsOnScreen: Int, ctaTapped: Boolean, exit: PaywallExit) :
        AnalyticsEvent(
            "paywall_dismissed",
            mapOf("source" to source, "seconds_on_screen" to secondsOnScreen, "cta_tapped" to ctaTapped, "exit" to exit.rawValue),
        )

    /** Fired by **both** arms — without the control half the comparison measures engagement. */
    class PremiumAskAssigned(variant: String, completed: Int) :
        AnalyticsEvent("premium_ask_assigned", mapOf("variant" to variant, "completed" to completed))

    class NotificationPermission(granted: Boolean, source: String) :
        AnalyticsEvent("notification_permission", mapOf("granted" to granted, "source" to source))

    class ReminderAskShown(source: String) : AnalyticsEvent("reminder_ask_shown", mapOf("source" to source))
    class ReminderDeclined(source: String) : AnalyticsEvent("reminder_declined", mapOf("source" to source))
    class ReminderSettingChanged(enabled: Boolean) :
        AnalyticsEvent("reminder_setting_changed", mapOf("enabled" to enabled))

    class ReviewPromptRequested(trigger: String, totalCompleted: Int) :
        AnalyticsEvent("review_prompt_requested", mapOf("trigger" to trigger, "total_completed" to totalCompleted))

    class PackOpened(id: String, source: String) : AnalyticsEvent("pack_opened", mapOf("pack_id" to id, "source" to source))
    class PackCompleted(id: String) : AnalyticsEvent("pack_completed", mapOf("pack_id" to id))
    class QuestOpened(id: String, source: String) : AnalyticsEvent("quest_opened", mapOf("quest_id" to id, "source" to source))
    class QuestStepCompleted(id: String, step: Int, total: Int) :
        AnalyticsEvent("quest_step_completed", mapOf("quest_id" to id, "step" to step, "total" to total))
    class QuestCompleted(id: String) : AnalyticsEvent("quest_completed", mapOf("quest_id" to id))

    class ChallengeSent(puzzleID: String) : AnalyticsEvent("challenge_sent", mapOf("puzzle_id" to puzzleID))
    class ChallengeOpened(puzzleID: String, via: String) :
        // `via`, not `source`: how the link was reached (link / clipboard).
        AnalyticsEvent("challenge_opened", mapOf("puzzle_id" to puzzleID, "via" to via))
    class ChallengeCompleted(puzzleID: String, won: Boolean, deltaSeconds: Int) :
        AnalyticsEvent("challenge_completed", mapOf("puzzle_id" to puzzleID, "won" to won, "delta_seconds" to deltaSeconds))
    class ChallengeRematchSent(puzzleID: String) : AnalyticsEvent("challenge_rematch_sent", mapOf("puzzle_id" to puzzleID))
    class ChallengeShareCancelled(puzzleID: String) : AnalyticsEvent("challenge_share_cancelled", mapOf("puzzle_id" to puzzleID))

    class FamilyBoardStarted(puzzleID: String) : AnalyticsEvent("family_board_started", mapOf("puzzle_id" to puzzleID))
    class FamilyBoardOpened(puzzleID: String, size: Int) :
        AnalyticsEvent("family_board_opened", mapOf("puzzle_id" to puzzleID, "size" to size))
    class FamilyBoardShared(puzzleID: String, size: Int) :
        AnalyticsEvent("family_board_shared", mapOf("puzzle_id" to puzzleID, "size" to size))

    class ScriptureOpened(reference: String, source: String) :
        AnalyticsEvent("scripture_opened", mapOf("reference" to reference, "source" to source))
    class ReaderClosed(source: String, seconds: Int, chaptersPaged: Int, scrolledPastVerse: Boolean, expanded: Boolean) :
        AnalyticsEvent(
            "reader_closed",
            mapOf("source" to source, "seconds" to seconds, "chapters_paged" to chaptersPaged, "scrolled_past_verse" to scrolledPastVerse, "expanded" to expanded),
        )
    class VerseAction(kind: String, reference: String) :
        AnalyticsEvent("verse_action", mapOf("kind" to kind, "reference" to reference))
    class BookmarksOpened(count: Int) : AnalyticsEvent("bookmarks_opened", mapOf("count" to count))
    class ReadPuzzleChipsShown(book: String, chapter: Int, count: Int, lockedCount: Int, source: String) :
        AnalyticsEvent(
            "read_puzzle_chips_shown",
            mapOf("book" to book, "chapter" to chapter, "count" to count, "locked_count" to lockedCount, "source" to source),
        )
    class ReadPuzzleChipTapped(puzzleID: String, locked: Boolean, source: String) :
        AnalyticsEvent("read_puzzle_chip_tapped", mapOf("puzzle_id" to puzzleID, "locked" to locked, "source" to source))
    class ReadSearch(kind: String, results: Int) :
        AnalyticsEvent("read_search", mapOf("kind" to kind, "results" to results))

    class ShareOpened(kind: String) : AnalyticsEvent("share_opened", mapOf("kind" to kind))
    class ShareCompleted(kind: String, completed: Boolean) :
        AnalyticsEvent("share_completed", mapOf("kind" to kind, "completed" to completed))

    class PlanStarted(plan: String) : AnalyticsEvent("plan_started", mapOf("plan" to plan))
    class PlanChapterRead(plan: String, day: Int) : AnalyticsEvent("plan_chapter_read", mapOf("plan" to plan, "day" to day))
    class PlanCompleted(plan: String, days: Int) : AnalyticsEvent("plan_completed", mapOf("plan" to plan, "days" to days))
    class PlanStopped(plan: String, day: Int) : AnalyticsEvent("plan_stopped", mapOf("plan" to plan, "day" to day))

    class CompletionChainTapped(fromPuzzleID: String, toPuzzleID: String) :
        AnalyticsEvent("completion_chain_tapped", mapOf("from_puzzle_id" to fromPuzzleID, "to_puzzle_id" to toPuzzleID))

    class MemoryListOpened(source: String) : AnalyticsEvent("memory_list_opened", mapOf("source" to source))
    class MemoryVerseAdded(reference: String, source: String) :
        AnalyticsEvent("memory_verse_added", mapOf("reference" to reference, "source" to source))
    class MemoryVerseStarted(reference: String, level: Int, source: String) :
        AnalyticsEvent("memory_verse_started", mapOf("reference" to reference, "level" to level, "source" to source))
    class MemoryVerseCompleted(reference: String, level: Int, leveledUp: Boolean, hintsUsed: Int) :
        AnalyticsEvent(
            "memory_verse_completed",
            mapOf("reference" to reference, "level" to level, "leveled_up" to leveledUp, "hints_used" to hintsUsed),
        )
    class MemoryVerseMastered(reference: String) : AnalyticsEvent("memory_verse_mastered", mapOf("reference" to reference))

    class JourneyOpened(source: String) : AnalyticsEvent("journey_opened", mapOf("source" to source))
    class AchievementsOpened(source: String) : AnalyticsEvent("achievements_opened", mapOf("source" to source))

    /**
     * Crash and hang digests. iOS gets these from MetricKit; Android mirrors
     * them from Crashlytics/ANR so the day-0 "vanished" cohort stays the same
     * shape on both platforms.
     */
    class AppCrash(
        signal: Int?, exceptionType: Int?, exceptionCode: Int?, reason: String?,
        build: String, os: String, frames: String, appFrames: String,
    ) : AnalyticsEvent(
        "app_crash",
        mapOf(
            "signal" to signal, "exception_type" to exceptionType, "exception_code" to exceptionCode,
            "reason" to reason, "build" to build, "os" to os, "frames" to frames, "app_frames" to appFrames,
        ),
    )

    class AppHang(seconds: Double, build: String, os: String, frames: String, appFrames: String) :
        AnalyticsEvent(
            "app_hang",
            mapOf("seconds" to seconds, "build" to build, "os" to os, "frames" to frames, "app_frames" to appFrames),
        )

    companion object {
        /**
         * Present on every event. Without it Android rows are indistinguishable
         * from iOS ones in a shared project, which would silently pollute the
         * running experiments' arms.
         */
        const val PLATFORM_KEY = "platform"
        const val PLATFORM = "android"

        /**
         * Wall-clock ceiling for a `bounce` on [PuzzleAbandoned]: an exit with
         * no cell tap and no key press below this is someone who opened the
         * screen and left, not someone who tried and gave up.
         *
         * Fifteen seconds is where the iOS data separates rather than a round
         * number — of 152 zero-interaction exits in the 21 days to 2026-09-18,
         * 136 were under 15s wall and the rest fall off a cliff. Mirrors iOS
         * `AnalyticsEvent.bounceWallSeconds`; the two must not drift.
         */
        const val BOUNCE_WALL_SECONDS = 15
    }
}

/** Minor units and ISO 4217 code — never a float, and never `×100` (JPY has no minor unit). */
data class PurchaseAmount(val minorUnits: Int, val currencyCode: String)

/** The control a player used to leave a paywall surface. */
enum class PaywallExit(val rawValue: String) {
    CLOSE("close"),
    FREE_LINK("free_link"),
    SWIPE("swipe"),
    PURCHASE("purchase"),
    AFTER_CANCEL("after_cancel"),
    PREMIUM_CONTINUE("premium_continue"),
    NO_PLAN("no_plan"),
}

/**
 * Where events go. Implementations fan out to Firebase and PostHog; the
 * platform property is added here so no call site can forget it.
 */
interface AnalyticsService {
    fun log(event: AnalyticsEvent)
}

/** Discards everything — the default in tests and previews. */
object NoAnalytics : AnalyticsService {
    override fun log(event: AnalyticsEvent) = Unit
}
