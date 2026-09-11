package com.sambulosendas1.biblecrossword.domain.analytics

import com.google.common.truth.Truth.assertThat
import com.google.common.truth.Truth.assertWithMessage
import com.sambulosendas1.biblecrossword.domain.spec.Vectors
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.jupiter.api.Test

/**
 * The gate: Android must speak exactly the vocabulary iOS already speaks.
 *
 * The projects are shared, so a name or key that differs by a character
 * corrupts live dashboards and the arms of running experiments. This asserts
 * the Kotlin events against `spec/vectors/analytics.json`, which is generated
 * from the shipping Swift.
 */
class AnalyticsParityTest {

    private val amount = PurchaseAmount(1299, "USD")

    /** One instance of every event, with the same shape the iOS generator used. */
    private val events: List<AnalyticsEvent> = listOf(
        AnalyticsEvent.AppOpen,
        AnalyticsEvent.OnboardingStep(1, "welcome"),
        AnalyticsEvent.OnboardingFirstSolve(true, 2),
        AnalyticsEvent.OnboardingCompleted(true),
        AnalyticsEvent.DailyPuzzleStarted("daily-001", false, "home"),
        AnalyticsEvent.DailyPuzzleCompleted("daily-001", 154),
        AnalyticsEvent.PuzzleAbandoned("daily-001", 40, 60, 70, 1, 3, 9),
        AnalyticsEvent.HintUsed("letter", 1),
        AnalyticsEvent.HintLimitReached("word"),
        AnalyticsEvent.CheckUsed("word", 2),
        AnalyticsEvent.StallNudgeShown("daily-001", 50, 45, "check"),
        AnalyticsEvent.StallNudgeTapped("daily-001", 50, 45, "check"),
        AnalyticsEvent.StarterWordGifted("daily-001", 5),
        AnalyticsEvent.WidgetOpened("daily"),
        AnalyticsEvent.StreakUpdated(7),
        AnalyticsEvent.StreakBroken(12),
        AnalyticsEvent.StreakComebackStarted("organic"),
        AnalyticsEvent.AchievementUnlocked("bible-beginner"),
        AnalyticsEvent.PremiumPurchased("yearly", "onboarding", true, amount, "purchase"),
        AnalyticsEvent.SubscriptionRenewed("yearly", false, amount),
        AnalyticsEvent.PurchaseFailed("yearly", "onboarding", "network"),
        AnalyticsEvent.PurchaseCancelled("yearly", "onboarding", true, amount),
        AnalyticsEvent.PaywallOpened("hint_limit"),
        AnalyticsEvent.PaywallCTATapped("yearly", "hint_limit", true),
        AnalyticsEvent.PaywallDismissed("hint_limit", 12, false, PaywallExit.CLOSE),
        AnalyticsEvent.PremiumAskAssigned("treatment", 5),
        AnalyticsEvent.NotificationPermission(true, "completion"),
        AnalyticsEvent.ReminderAskShown("completion"),
        AnalyticsEvent.ReminderDeclined("completion"),
        AnalyticsEvent.ReminderSettingChanged(true),
        AnalyticsEvent.ReviewPromptRequested("milestone_10", 10),
        AnalyticsEvent.PackOpened("first-steps", "packs"),
        AnalyticsEvent.PackCompleted("first-steps"),
        AnalyticsEvent.QuestOpened("beginnings", "home"),
        AnalyticsEvent.QuestStepCompleted("beginnings", 2, 5),
        AnalyticsEvent.QuestCompleted("beginnings"),
        AnalyticsEvent.ChallengeSent("daily-001"),
        AnalyticsEvent.ChallengeOpened("daily-001", "link"),
        AnalyticsEvent.ChallengeCompleted("daily-001", true, -12),
        AnalyticsEvent.ChallengeRematchSent("daily-001"),
        AnalyticsEvent.ChallengeShareCancelled("daily-001"),
        AnalyticsEvent.FamilyBoardStarted("daily-001"),
        AnalyticsEvent.FamilyBoardOpened("daily-001", 3),
        AnalyticsEvent.FamilyBoardShared("daily-001", 3),
        AnalyticsEvent.ScriptureOpened("John 3:16", "hint"),
        AnalyticsEvent.ReaderClosed("hint", 30, 1, true, false),
        AnalyticsEvent.VerseAction("bookmark", "John 3:16"),
        AnalyticsEvent.BookmarksOpened(4),
        AnalyticsEvent.ReadPuzzleChipsShown("John", 3, 2, 1, "read"),
        AnalyticsEvent.ReadPuzzleChipTapped("daily-001", false, "read"),
        AnalyticsEvent.ReadSearch("reference", 1),
        AnalyticsEvent.ShareOpened("scorecard"),
        AnalyticsEvent.ShareCompleted("scorecard", true),
        AnalyticsEvent.PlanStarted("john"),
        AnalyticsEvent.PlanChapterRead("john", 3),
        AnalyticsEvent.PlanCompleted("john", 21),
        AnalyticsEvent.PlanStopped("john", 3),
        AnalyticsEvent.CompletionChainTapped("daily-001", "mini-001"),
        AnalyticsEvent.MemoryListOpened("completion"),
        AnalyticsEvent.MemoryVerseAdded("John 3:16", "completion"),
        AnalyticsEvent.MemoryVerseStarted("John 3:16", 1, "memory"),
        AnalyticsEvent.MemoryVerseCompleted("John 3:16", 1, true, 0),
        AnalyticsEvent.MemoryVerseMastered("John 3:16"),
        AnalyticsEvent.JourneyOpened("profile"),
        AnalyticsEvent.AchievementsOpened("profile"),
        AnalyticsEvent.AppCrash(11, 1, 0, "x", "21", "26.0", "a", "b"),
        AnalyticsEvent.AppHang(2.5, "21", "26.0", "a", "b"),
    )

    @Test
    fun `every iOS event exists here, with the same parameter keys`() {
        val expected = Vectors.cases("analytics").associate { case ->
            val e = case["expect"]!!.jsonObject
            e["name"]!!.jsonPrimitive.content to e["parameterKeys"]!!.jsonArray.map { it.jsonPrimitive.content }
        }
        val actual = events.associate { it.name to it.parameters.keys.sorted() }

        // Nothing missing, nothing invented.
        assertWithMessage("events only iOS has").that(expected.keys - actual.keys).isEmpty()
        assertWithMessage("events only Android has").that(actual.keys - expected.keys).isEmpty()

        for ((name, keys) in expected) {
            assertWithMessage("parameter keys for $name").that(actual[name]).isEqualTo(keys)
        }
    }

    @Test
    fun `the vocabulary is the whole vocabulary, and every name is distinct`() {
        val count = Vectors.family("analytics")["constants"]!!.jsonObject["eventCount"]!!.jsonPrimitive.content.toInt()
        assertThat(events).hasSize(count)
        assertThat(events.map { it.name }.toSet()).hasSize(count)
    }

    @Test
    fun `paywall exit values match iOS exactly`() {
        val expected = Vectors.family("analytics")["constants"]!!.jsonObject["paywallExits"]!!
            .jsonArray.map { it.jsonPrimitive.content }
        assertThat(PaywallExit.entries.map { it.rawValue }).isEqualTo(expected)
    }

    @Test
    fun `the platform property is declared, because a shared project needs it`() {
        assertThat(AnalyticsEvent.PLATFORM_KEY).isEqualTo("platform")
        assertThat(AnalyticsEvent.PLATFORM).isEqualTo("android")
        // No event may define it itself — the service adds it once, so a call
        // site cannot forget it or spell it differently.
        for (event in events) {
            assertWithMessage("${event.name} must not set the platform property")
                .that(event.parameters).doesNotContainKey(AnalyticsEvent.PLATFORM_KEY)
        }
    }
}
