package com.sambulosendas1.biblecrossword.domain

import com.google.common.truth.Truth.assertWithMessage
import com.sambulosendas1.biblecrossword.domain.access.PuzzleAccess
import com.sambulosendas1.biblecrossword.domain.asks.ReminderAsk
import com.sambulosendas1.biblecrossword.domain.asks.ReviewAsk
import com.sambulosendas1.biblecrossword.domain.asks.TrialReoffer
import com.sambulosendas1.biblecrossword.domain.challenge.ChallengeLink
import com.sambulosendas1.biblecrossword.domain.profile.Achievements
import com.sambulosendas1.biblecrossword.domain.profile.PlayerProfile
import com.sambulosendas1.biblecrossword.domain.profile.Streaks
import com.sambulosendas1.biblecrossword.domain.progress.PuzzleRecord
import com.sambulosendas1.biblecrossword.domain.spec.TestContent
import com.sambulosendas1.biblecrossword.domain.spec.Vectors
import com.sambulosendas1.biblecrossword.domain.sync.SyncMerge
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.double
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.jupiter.api.DynamicTest
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.TestFactory
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset

/**
 * Every rule family in `spec/vectors` except the engine (see
 * [com.sambulosendas1.biblecrossword.domain.engine.EngineVectorsTest]).
 *
 * The relative-date families were generated on a **UTC** calendar against an
 * unemitted fixed now; the rotation and access families on the *local*
 * calendar (see `spec/README.md`). Both are reconstructed here the same way,
 * which is what makes the corpus zone-independent.
 */
class RulesVectorsTest {

    private val utc = ZoneOffset.UTC

    /** The iOS generator's fixed now: 2026-08-08T12:00Z. */
    private val fixedNow: Instant = LocalDate.of(2026, 8, 8).atTime(12, 0).toInstant(ZoneOffset.UTC)

    private fun daysAgo(n: Int): Instant = fixedNow.minusSeconds(n * 86_400L)
    private fun daysAgoOrNull(v: kotlinx.serialization.json.JsonElement?): Instant? =
        if (v == null || v is JsonNull) null else daysAgo(v.jsonPrimitive.int)

    /** Whole days between an instant and the fixed now, on the UTC calendar. */
    private fun daysBetween(instant: Instant?): Int? = instant?.let {
        java.time.temporal.ChronoUnit.DAYS.between(
            LocalDate.ofInstant(it, utc), LocalDate.ofInstant(fixedNow, utc)
        ).toInt()
    }

    // MARK: - Hint quota

    @TestFactory
    fun `hint quota`(): List<DynamicTest> = Vectors.cases("hint_quota").map { case ->
        val name = case["name"]!!.jsonPrimitive.content
        DynamicTest.dynamicTest(name) {
            val g = case["given"]!!.jsonObject
            val e = case["expect"]!!.jsonObject
            val profile = PlayerProfile(
                totalPuzzlesCompleted = g["totalCompleted"]!!.jsonPrimitive.int,
                hintsUsedToday = g["hintsUsedToday"]!!.jsonPrimitive.int,
                hintsAt = daysAgoOrNull(g["hintsDaysAgo"]),
            )
            if (g["op"]?.jsonPrimitive?.content == "consumeHint") {
                val after = profile.consumeHint(g["cost"]!!.jsonPrimitive.int, fixedNow, utc)
                assertWithMessage("$name · hintsUsedToday").that(after.hintsUsedToday)
                    .isEqualTo(e["hintsUsedToday"]!!.jsonPrimitive.int)
                val expectedDays = e["hintsDaysAgo"]!!.let { if (it is JsonNull) null else it.jsonPrimitive.int }
                assertWithMessage("$name · hintsDaysAgo").that(daysBetween(after.hintsAt)).isEqualTo(expectedDays)
            } else {
                val remaining = profile.hintsRemaining(
                    isPremium = g["isPremium"]!!.jsonPrimitive.boolean,
                    limit = g["limit"]!!.jsonPrimitive.int,
                    now = fixedNow,
                    zone = utc,
                )
                assertWithMessage(name).that(remaining).isEqualTo(e["remaining"]!!.jsonPrimitive.int)
            }
        }
    }

    // MARK: - Streaks

    @TestFactory
    fun `streaks`(): List<DynamicTest> = Vectors.cases("streaks").map { case ->
        val name = case["name"]!!.jsonPrimitive.content
        DynamicTest.dynamicTest(name) {
            val g = case["given"]!!.jsonObject
            val e = case["expect"]!!.jsonObject
            val profile = PlayerProfile(
                currentStreak = g["currentStreak"]!!.jsonPrimitive.int,
                bestStreak = g["bestStreak"]?.jsonPrimitive?.int ?: 0,
                totalPuzzlesCompleted = g["totalPuzzlesCompleted"]?.jsonPrimitive?.int ?: 0,
                lastCompletedAt = daysAgoOrNull(g["lastCompletedDaysAgo"]),
                streakFreezes = g["streakFreezes"]!!.jsonPrimitive.int,
            )
            if (g["op"]!!.jsonPrimitive.content == "normalize") {
                val (after, outcome) = Streaks.normalize(profile, fixedNow, utc)
                val expected = e["outcome"]!!.jsonObject
                val kind = when (outcome) {
                    is Streaks.Outcome.Unchanged -> "unchanged"
                    is Streaks.Outcome.FreezeSaved -> "freezeSaved"
                    is Streaks.Outcome.Broken -> "broken"
                }
                assertWithMessage("$name · outcome").that(kind).isEqualTo(expected["kind"]!!.jsonPrimitive.content)
                if (outcome is Streaks.Outcome.Broken) {
                    assertWithMessage("$name · previous").that(outcome.previous)
                        .isEqualTo(expected["previous"]!!.jsonPrimitive.int)
                }
                assertWithMessage("$name · currentStreak").that(after.currentStreak).isEqualTo(e["currentStreak"]!!.jsonPrimitive.int)
                assertWithMessage("$name · streakFreezes").that(after.streakFreezes).isEqualTo(e["streakFreezes"]!!.jsonPrimitive.int)
                assertWithMessage("$name · lastCompletedDaysAgo").that(daysBetween(after.lastCompletedAt))
                    .isEqualTo(e["lastCompletedDaysAgo"]!!.let { if (it is JsonNull) null else it.jsonPrimitive.int })
                assertWithMessage("$name · lastFreezeUsedDaysAgo").that(daysBetween(after.lastFreezeUsedAt))
                    .isEqualTo(e["lastFreezeUsedDaysAgo"]!!.let { if (it is JsonNull) null else it.jsonPrimitive.int })
            } else {
                val (after, advanced) = Streaks.registerCompletion(
                    profile, isReplay = g["isReplay"]!!.jsonPrimitive.boolean, now = fixedNow, zone = utc,
                )
                assertWithMessage("$name · advanced").that(advanced).isEqualTo(e["advanced"]!!.jsonPrimitive.boolean)
                assertWithMessage("$name · currentStreak").that(after.currentStreak).isEqualTo(e["currentStreak"]!!.jsonPrimitive.int)
                assertWithMessage("$name · bestStreak").that(after.bestStreak).isEqualTo(e["bestStreak"]!!.jsonPrimitive.int)
                assertWithMessage("$name · total").that(after.totalPuzzlesCompleted).isEqualTo(e["totalPuzzlesCompleted"]!!.jsonPrimitive.int)
                assertWithMessage("$name · streakFreezes").that(after.streakFreezes).isEqualTo(e["streakFreezes"]!!.jsonPrimitive.int)
                assertWithMessage("$name · lastCompletedDaysAgo").that(daysBetween(after.lastCompletedAt))
                    .isEqualTo(e["lastCompletedDaysAgo"]!!.let { if (it is JsonNull) null else it.jsonPrimitive.int })
            }
        }
    }

    // MARK: - Achievements

    @TestFactory
    fun `achievements`(): List<DynamicTest> = Vectors.cases("achievements").map { case ->
        val name = case["name"]!!.jsonPrimitive.content
        DynamicTest.dynamicTest(name) {
            val g = case["given"]!!.jsonObject
            val e = case["expect"]!!.jsonObject
            val profile = PlayerProfile(
                totalPuzzlesCompleted = g["totalPuzzlesCompleted"]!!.jsonPrimitive.int,
                bestStreak = g["bestStreak"]!!.jsonPrimitive.int,
                currentStreak = g["currentStreak"]!!.jsonPrimitive.int,
                bestSolveSeconds = g["bestSolveSeconds"]!!.let { if (it is JsonNull) null else it.jsonPrimitive.int },
                noHintSolves = g["noHintSolves"]!!.jsonPrimitive.int,
                hardCompleted = g["hardCompleted"]!!.jsonPrimitive.int,
                completedPackIDs = (0 until g["completedPackCount"]!!.jsonPrimitive.int).map { "pack-$it" },
                completedQuestIDs = (0 until g["completedQuestCount"]!!.jsonPrimitive.int).map { "quest-$it" },
                unlockedAchievementIDs = g["unlockedAchievementIDs"]!!.jsonArray.map { it.jsonPrimitive.content },
            )
            assertWithMessage("$name · newlyUnlocked").that(Achievements.newlyUnlocked(profile).map { it.id })
                .isEqualTo(e["newlyUnlocked"]!!.jsonArray.map { it.jsonPrimitive.content })
            val progress = e["progress"]!!.jsonObject
            for (achievement in Achievements.all) {
                val expected = progress[achievement.id]!!.jsonObject
                assertWithMessage("$name · ${achievement.id} progress").that(achievement.progress(profile))
                    .isWithin(1e-9).of(expected["progress"]!!.jsonPrimitive.double)
                assertWithMessage("$name · ${achievement.id} text").that(achievement.progressText(profile))
                    .isEqualTo(expected["text"]!!.jsonPrimitive.content)
                assertWithMessage("$name · ${achievement.id} unlocked").that(achievement.isUnlocked(profile))
                    .isEqualTo(expected["unlocked"]!!.jsonPrimitive.boolean)
            }
        }
    }

    @Test
    fun `the achievement catalogue matches the one iOS pinned`() {
        val pinned = Vectors.family("constants")["constants"]!!.jsonObject["achievements"]!!.jsonArray.map { it.jsonObject }
        assertWithMessage("catalogue size").that(Achievements.all).hasSize(pinned.size)
        for ((i, expected) in pinned.withIndex()) {
            val a = Achievements.all[i]
            assertWithMessage("achievement $i id").that(a.id).isEqualTo(expected["id"]!!.jsonPrimitive.content)
            assertWithMessage("achievement $i title").that(a.title).isEqualTo(expected["title"]!!.jsonPrimitive.content)
            assertWithMessage("achievement $i detail").that(a.detail).isEqualTo(expected["detail"]!!.jsonPrimitive.content)
            assertWithMessage("achievement $i symbol").that(a.symbol).isEqualTo(expected["symbol"]!!.jsonPrimitive.content)
        }
    }

    // MARK: - Puzzle access

    @TestFactory
    fun `puzzle access`(): List<DynamicTest> = Vectors.cases("puzzle_access").map { case ->
        val name = case["name"]!!.jsonPrimitive.content
        DynamicTest.dynamicTest(name) {
            val g = case["given"]!!.jsonObject
            val e = case["expect"]!!.jsonObject
            val catalogue = TestContent.catalogue
            val puzzleID = g["puzzleID"]!!.jsonPrimitive.content
            val puzzle = catalogue.puzzle(puzzleID) ?: error("puzzle $puzzleID missing")
            val challenged = if (g["isChallenged"]!!.jsonPrimitive.boolean) setOf(puzzleID) else emptySet()
            val access = PuzzleAccess(
                catalogue = catalogue,
                date = LocalDate.parse(g["date"]!!.jsonPrimitive.content),
                challengedIDs = challenged,
            )
            assertWithMessage("$name · canPlay").that(
                access.canPlay(
                    puzzle,
                    isPremium = g["isPremium"]!!.jsonPrimitive.boolean,
                    hasProgress = g["hasProgress"]!!.jsonPrimitive.boolean,
                )
            ).isEqualTo(e["canPlay"]!!.jsonPrimitive.boolean)
            assertWithMessage("$name · isInWindow").that(access.isInWindow(puzzle))
                .isEqualTo(e["isInWindow"]!!.jsonPrimitive.boolean)
        }
    }

    // MARK: - Asks

    @TestFactory
    fun `reminder ask`(): List<DynamicTest> = Vectors.cases("reminder_ask").map { case ->
        val name = case["name"]!!.jsonPrimitive.content
        DynamicTest.dynamicTest(name) {
            val g = case["given"]!!.jsonObject
            val e = case["expect"]!!.jsonObject
            val today = LocalDate.ofInstant(fixedNow, utc)
            val state = ReminderAsk.State(
                remindersEnabled = g["remindersEnabled"]!!.jsonPrimitive.boolean,
                permissionUndetermined = g["permissionUndetermined"]!!.jsonPrimitive.boolean,
                totalCompleted = g["totalCompleted"]!!.jsonPrimitive.int,
                currentStreak = g["currentStreak"]!!.jsonPrimitive.int,
                completionAsksShown = g["completionAsksShown"]!!.jsonPrimitive.int,
                streakAskShown = g["streakAskShown"]!!.jsonPrimitive.boolean,
                lastAskDay = g["lastAskDaysAgo"]!!.let { if (it is JsonNull) null else today.minusDays(it.jsonPrimitive.int.toLong()) },
                askedThisSession = g["askedThisSession"]!!.jsonPrimitive.boolean,
                returnDaySheetShown = g["returnDaySheetShown"]!!.jsonPrimitive.boolean,
                isInstallDay = g["isInstallDay"]!!.jsonPrimitive.boolean,
                today = today,
            )
            for (surface in ReminderAsk.Surface.entries) {
                assertWithMessage("$name · ${surface.rawValue}").that(ReminderAsk.decide(surface, state))
                    .isEqualTo(e[surface.rawValue]!!.jsonPrimitive.boolean)
            }
        }
    }

    @TestFactory
    fun `review ask`(): List<DynamicTest> = Vectors.cases("review_ask").map { case ->
        val name = case["name"]!!.jsonPrimitive.content
        DynamicTest.dynamicTest(name) {
            val g = case["given"]!!.jsonObject
            fun days(key: String): Instant? = g[key]!!.let {
                if (it is JsonNull) null else fixedNow.minusMillis((it.jsonPrimitive.double * 86_400_000).toLong())
            }
            val state = ReviewAsk.State(
                totalCompleted = g["totalCompleted"]!!.jsonPrimitive.int,
                currentStreak = g["currentStreak"]!!.jsonPrimitive.int,
                milestoneAsked = g["milestoneAsked"]!!.jsonPrimitive.int,
                streakAsked = g["streakAsked"]!!.jsonPrimitive.boolean,
                versionAsked = g["versionAsked"]!!.jsonPrimitive.content,
                currentVersion = g["currentVersion"]!!.jsonPrimitive.content,
                lastAsk = days("lastAskDaysAgo"),
                installedAt = days("installedDaysAgo"),
                now = fixedNow,
            )
            val expected = case["expect"]!!.jsonObject["trigger"]!!.let { if (it is JsonNull) null else it.jsonPrimitive.content }
            assertWithMessage(name).that(ReviewAsk.decide(state)?.analyticsValue).isEqualTo(expected)
        }
    }

    @TestFactory
    fun `trial reoffer`(): List<DynamicTest> = Vectors.cases("trial_reoffer").map { case ->
        val name = case["name"]!!.jsonPrimitive.content
        DynamicTest.dynamicTest(name) {
            val g = case["given"]!!.jsonObject
            fun hours(key: String): Instant? = g[key]!!.let {
                if (it is JsonNull) null else fixedNow.minusMillis((it.jsonPrimitive.double * 3_600_000).toLong())
            }
            val state = TrialReoffer.State(
                abandonedAt = hours("abandonedHoursAgo"),
                isPremium = g["isPremium"]!!.jsonPrimitive.boolean,
                reofferShown = g["reofferShown"]!!.jsonPrimitive.boolean,
                launchedAt = hours("launchedHoursAgo")!!,
                now = fixedNow,
                zone = utc,
            )
            assertWithMessage(name).that(TrialReoffer.decide(state))
                .isEqualTo(case["expect"]!!.jsonObject["show"]!!.jsonPrimitive.boolean)
        }
    }

    // MARK: - Sync merge

    @TestFactory
    fun `sync merge`(): List<DynamicTest> = Vectors.cases("sync_merge").map { case ->
        val name = case["name"]!!.jsonPrimitive.content
        DynamicTest.dynamicTest(name) {
            val g = case["given"]!!.jsonObject
            val survivor = case["expect"]!!.jsonObject["survivor"]!!.jsonObject
            when (g["op"]!!.jsonPrimitive.content) {
                "mergeProfiles" -> {
                    val profiles = g["profiles"]!!.jsonArray.map { profileFrom(it.jsonObject) }
                    val merged = SyncMerge.mergeProfiles(profiles)!!
                    assertWithMessage("$name · username").that(merged.username).isEqualTo(survivor["username"]!!.jsonPrimitive.content)
                    assertWithMessage("$name · currentStreak").that(merged.currentStreak).isEqualTo(survivor["currentStreak"]!!.jsonPrimitive.int)
                    assertWithMessage("$name · bestStreak").that(merged.bestStreak).isEqualTo(survivor["bestStreak"]!!.jsonPrimitive.int)
                    assertWithMessage("$name · total").that(merged.totalPuzzlesCompleted).isEqualTo(survivor["totalPuzzlesCompleted"]!!.jsonPrimitive.int)
                    assertWithMessage("$name · hintsUsedToday").that(merged.hintsUsedToday).isEqualTo(survivor["hintsUsedToday"]!!.jsonPrimitive.int)
                    assertWithMessage("$name · hintsDaysAgo").that(daysBetween(merged.hintsAt))
                        .isEqualTo(survivor["hintsDaysAgo"]!!.let { if (it is JsonNull) null else it.jsonPrimitive.int })
                    assertWithMessage("$name · lastCompletedDaysAgo").that(daysBetween(merged.lastCompletedAt))
                        .isEqualTo(survivor["lastCompletedDaysAgo"]!!.let { if (it is JsonNull) null else it.jsonPrimitive.int })
                    assertWithMessage("$name · achievements").that(merged.unlockedAchievementIDs.sorted())
                        .isEqualTo(survivor["unlockedAchievementIDs"]!!.jsonArray.map { it.jsonPrimitive.content }.sorted())
                    assertWithMessage("$name · packs").that(merged.completedPackIDs.sorted())
                        .isEqualTo(survivor["completedPackIDs"]!!.jsonArray.map { it.jsonPrimitive.content }.sorted())
                    assertWithMessage("$name · quests").that(merged.completedQuestIDs.sorted())
                        .isEqualTo(survivor["completedQuestIDs"]!!.jsonArray.map { it.jsonPrimitive.content }.sorted())
                    assertWithMessage("$name · bestSolveSeconds").that(merged.bestSolveSeconds)
                        .isEqualTo(survivor["bestSolveSeconds"]!!.let { if (it is JsonNull) null else it.jsonPrimitive.int })
                    assertWithMessage("$name · noHintSolves").that(merged.noHintSolves).isEqualTo(survivor["noHintSolves"]!!.jsonPrimitive.int)
                    assertWithMessage("$name · hardCompleted").that(merged.hardCompleted).isEqualTo(survivor["hardCompleted"]!!.jsonPrimitive.int)
                    assertWithMessage("$name · streakFreezes").that(merged.streakFreezes).isEqualTo(survivor["streakFreezes"]!!.jsonPrimitive.int)
                    assertWithMessage("$name · lastFreezeUsedDaysAgo").that(daysBetween(merged.lastFreezeUsedAt))
                        .isEqualTo(survivor["lastFreezeUsedDaysAgo"]!!.let { if (it is JsonNull) null else it.jsonPrimitive.int })
                    assertWithMessage("$name · createdDaysAgo").that(daysBetween(merged.createdAt))
                        .isEqualTo(survivor["createdDaysAgo"]!!.let { if (it is JsonNull) null else it.jsonPrimitive.int })
                }
                "mergeRecords" -> {
                    val records = g["records"]!!.jsonArray.map { recordFrom(it.jsonObject) }
                    val merged = SyncMerge.mergeRecords(records)!!
                    assertWithMessage("$name · puzzleID").that(merged.puzzleID).isEqualTo(survivor["puzzleID"]!!.jsonPrimitive.content)
                    assertWithMessage("$name · isCompleted").that(merged.isCompleted).isEqualTo(survivor["isCompleted"]!!.jsonPrimitive.boolean)
                    assertWithMessage("$name · elapsedSeconds").that(merged.elapsedSeconds).isEqualTo(survivor["elapsedSeconds"]!!.jsonPrimitive.int)
                    assertWithMessage("$name · usedHint").that(merged.usedHint).isEqualTo(survivor["usedHint"]!!.jsonPrimitive.boolean)
                    assertWithMessage("$name · entries").that(merged.entries)
                        .isEqualTo(survivor["entries"]!!.jsonObject.mapValues { it.value.jsonPrimitive.content })
                    assertWithMessage("$name · completedDaysAgo").that(daysBetween(merged.completedAt))
                        .isEqualTo(survivor["completedDaysAgo"]!!.let { if (it is JsonNull) null else it.jsonPrimitive.int })
                    assertWithMessage("$name · updatedDaysAgo").that(daysBetween(merged.updatedAt))
                        .isEqualTo(survivor["updatedDaysAgo"]!!.let { if (it is JsonNull) null else it.jsonPrimitive.int })
                }
                else -> error("unknown op")
            }
        }
    }

    private fun profileFrom(o: JsonObject) = PlayerProfile(
        username = o["username"]!!.jsonPrimitive.content,
        currentStreak = o["currentStreak"]!!.jsonPrimitive.int,
        bestStreak = o["bestStreak"]!!.jsonPrimitive.int,
        totalPuzzlesCompleted = o["totalPuzzlesCompleted"]!!.jsonPrimitive.int,
        lastCompletedAt = daysAgoOrNull(o["lastCompletedDaysAgo"]),
        hintsUsedToday = o["hintsUsedToday"]!!.jsonPrimitive.int,
        hintsAt = daysAgoOrNull(o["hintsDaysAgo"]),
        unlockedAchievementIDs = o["unlockedAchievementIDs"]!!.jsonArray.map { it.jsonPrimitive.content },
        bestSolveSeconds = o["bestSolveSeconds"]!!.let { if (it is JsonNull) null else it.jsonPrimitive.int },
        noHintSolves = o["noHintSolves"]!!.jsonPrimitive.int,
        hardCompleted = o["hardCompleted"]!!.jsonPrimitive.int,
        completedPackIDs = o["completedPackIDs"]!!.jsonArray.map { it.jsonPrimitive.content },
        completedQuestIDs = o["completedQuestIDs"]!!.jsonArray.map { it.jsonPrimitive.content },
        streakFreezes = o["streakFreezes"]!!.jsonPrimitive.int,
        lastFreezeUsedAt = daysAgoOrNull(o["lastFreezeUsedDaysAgo"]),
        createdAt = daysAgoOrNull(o["createdDaysAgo"]) ?: fixedNow,
    )

    private fun recordFrom(o: JsonObject) = PuzzleRecord(
        puzzleID = o["puzzleID"]!!.jsonPrimitive.content,
        isCompleted = o["isCompleted"]!!.jsonPrimitive.boolean,
        completedAt = daysAgoOrNull(o["completedDaysAgo"]),
        elapsedSeconds = o["elapsedSeconds"]!!.jsonPrimitive.int,
        entries = o["entries"]!!.jsonObject.mapValues { it.value.jsonPrimitive.content },
        pencil = o["pencil"]!!.jsonObject.mapValues { it.value.jsonPrimitive.content },
        usedHint = o["usedHint"]!!.jsonPrimitive.boolean,
        updatedAt = daysAgoOrNull(o["updatedDaysAgo"]) ?: fixedNow,
    )

    // MARK: - Challenge links

    @TestFactory
    fun `challenge links`(): List<DynamicTest> = Vectors.cases("challenge_links").map { case ->
        val name = case["name"]!!.jsonPrimitive.content
        DynamicTest.dynamicTest(name) {
            val g = case["given"]!!.jsonObject
            val e = case["expect"]!!.jsonObject
            if (g["op"]!!.jsonPrimitive.content == "parse") {
                val outcome = ChallengeLink.parse(g["url"]!!.jsonPrimitive.content) {
                    it in setOf("daily-001", "mini-001")
                }
                val expected = e["outcome"]!!.jsonObject
                val kind = when (outcome) {
                    is ChallengeLink.ParseOutcome.Valid -> "valid"
                    ChallengeLink.ParseOutcome.NeedsUpdate -> "needsUpdate"
                    ChallengeLink.ParseOutcome.NotAChallenge -> "notAChallenge"
                }
                assertWithMessage("$name · kind").that(kind).isEqualTo(expected["kind"]!!.jsonPrimitive.content)
                if (outcome is ChallengeLink.ParseOutcome.Valid) {
                    assertWithMessage("$name · puzzleID").that(outcome.challenge.puzzleID).isEqualTo(expected["puzzleID"]!!.jsonPrimitive.content)
                    assertWithMessage("$name · name").that(outcome.challenge.challengerName).isEqualTo(expected["challengerName"]!!.jsonPrimitive.content)
                    assertWithMessage("$name · seconds").that(outcome.challenge.seconds).isEqualTo(expected["seconds"]!!.jsonPrimitive.int)
                }
            } else {
                val id = g["puzzleID"]!!.jsonPrimitive.content
                val seconds = g["seconds"]!!.jsonPrimitive.int
                val who = g["name"]!!.jsonPrimitive.content
                assertWithMessage("$name · webURL").that(ChallengeLink.webURL(id, seconds, who))
                    .isEqualTo(e["webURL"]!!.jsonPrimitive.content)
                assertWithMessage("$name · schemeURL").that(ChallengeLink.schemeURL(id, seconds, who))
                    .isEqualTo(e["schemeURL"]!!.jsonPrimitive.content)
            }
        }
    }
}
