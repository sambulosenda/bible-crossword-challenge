package com.sambulosendas1.biblecrossword.domain.completion

import com.google.common.truth.Truth.assertThat
import com.sambulosendas1.biblecrossword.domain.content.ClueData
import com.sambulosendas1.biblecrossword.domain.content.ClueDirection
import com.sambulosendas1.biblecrossword.domain.content.Puzzle
import com.sambulosendas1.biblecrossword.domain.content.PuzzleDifficulty
import com.sambulosendas1.biblecrossword.domain.content.PuzzleKind
import com.sambulosendas1.biblecrossword.domain.content.PuzzlePack
import com.sambulosendas1.biblecrossword.domain.content.QuestLine
import com.sambulosendas1.biblecrossword.domain.profile.PlayerProfile
import com.sambulosendas1.biblecrossword.domain.progress.PuzzleRecord
import org.junit.jupiter.api.Test
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset

/**
 * The completion ordering. Each test names a constraint that a reasonable
 * refactor would break, and that the shared vectors cannot reach because the
 * iOS original is entangled with its persistence layer.
 */
class CompletionOutcomeTest {

    private val utc = ZoneOffset.UTC
    private val now: Instant = LocalDate.of(2026, 8, 8).atTime(12, 0).toInstant(ZoneOffset.UTC)
    private fun daysAgo(n: Int) = now.minusSeconds(n * 86_400L)

    private fun puzzle(
        id: String = "daily-001",
        kind: PuzzleKind? = null,
        difficulty: PuzzleDifficulty = PuzzleDifficulty.EASY,
        size: Int = 5,
    ) = Puzzle(
        id = id, title = "T", difficulty = difficulty, verse = "", reference = "",
        publishDate = "2026-01-01", size = size, grid = List(size) { "A".repeat(size) },
        clues = listOf(ClueData(1, ClueDirection.ACROSS, 0, 0, "c", "A".repeat(size))),
        kind = kind,
    )

    private fun context(
        puzzle: Puzzle = puzzle(),
        seconds: Int = 200,
        profile: PlayerProfile = PlayerProfile(),
        record: PuzzleRecord? = null,
        solved: Set<String> = emptySet(),
        packs: List<PuzzlePack> = emptyList(),
        quests: List<QuestLine> = emptyList(),
        pendingStreakBreak: Int = 0,
        comebackSource: String = "",
    ) = CompletionOutcome.Context(
        puzzle = puzzle, seconds = seconds, profile = profile, record = record,
        solvedPuzzleIDs = solved, packs = packs, quests = quests,
        pendingStreakBreak = pendingStreakBreak, comebackSource = comebackSource,
        now = now, zone = utc,
    )

    private fun pack(id: String, vararg ids: String, premium: Boolean = false) =
        PuzzlePack(id = id, title = id, blurb = "", coverSymbol = "book", isPremium = premium, puzzleIDs = ids.toList())

    private fun quest(id: String, vararg ids: String) =
        QuestLine(id = id, title = id, blurb = "", coverSymbol = "map", isPremium = false, puzzleIDs = ids.toList())

    @Test
    fun `a first completion counts, advances the streak, and records the time`() {
        val result = CompletionOutcome.resolve(
            context(profile = PlayerProfile(lastCompletedAt = daysAgo(1), currentStreak = 3))
        )
        assertThat(result.firstCompletion).isTrue()
        assertThat(result.streakAdvanced).isTrue()
        assertThat(result.profile.currentStreak).isEqualTo(4)
        assertThat(result.profile.totalPuzzlesCompleted).isEqualTo(1)
        assertThat(result.profile.bestSolveSeconds).isEqualTo(200)
        assertThat(result.record.isCompleted).isTrue()
        assertThat(result.record.pencil).isEmpty()
    }

    @Test
    fun `a replay advances the streak but does not re-count the puzzle`() {
        val result = CompletionOutcome.resolve(
            context(
                profile = PlayerProfile(totalPuzzlesCompleted = 9, currentStreak = 2, lastCompletedAt = daysAgo(1)),
                record = PuzzleRecord("daily-001", isCompleted = true, completedAt = daysAgo(5)),
            )
        )
        assertThat(result.firstCompletion).isFalse()
        assertThat(result.profile.currentStreak).isEqualTo(3)
        assertThat(result.profile.totalPuzzlesCompleted).isEqualTo(9)
        // The historically accurate completion date is the first one.
        assertThat(result.record.completedAt).isEqualTo(daysAgo(5))
    }

    @Test
    fun `a Mini counts toward the streak but earns no full-puzzle stats`() {
        val result = CompletionOutcome.resolve(
            context(puzzle = puzzle("mini-001", kind = PuzzleKind.MINI), seconds = 30)
        )
        assertThat(result.profile.totalPuzzlesCompleted).isEqualTo(1)
        assertThat(result.profile.bestSolveSeconds).isNull()
        assertThat(result.profile.noHintSolves).isEqualTo(0)
    }

    @Test
    fun `a no-hint solve counts only when no hint was spent, in any sitting`() {
        val unaided = CompletionOutcome.resolve(context())
        assertThat(unaided.profile.noHintSolves).isEqualTo(1)

        // usedHint survives resume, so a hint spent earlier still disqualifies.
        val hinted = CompletionOutcome.resolve(
            context(record = PuzzleRecord("daily-001", usedHint = true))
        )
        assertThat(hinted.profile.noHintSolves).isEqualTo(0)
    }

    @Test
    fun `hard puzzles are counted, and only on a first completion`() {
        val first = CompletionOutcome.resolve(context(puzzle = puzzle(difficulty = PuzzleDifficulty.HARD)))
        assertThat(first.profile.hardCompleted).isEqualTo(1)

        val replay = CompletionOutcome.resolve(
            context(
                puzzle = puzzle(difficulty = PuzzleDifficulty.HARD),
                profile = PlayerProfile(hardCompleted = 1),
                record = PuzzleRecord("daily-001", isCompleted = true),
            )
        )
        assertThat(replay.profile.hardCompleted).isEqualTo(1)
    }

    @Test
    fun `finishing a pack credits it and unlocks its achievement on the same solve`() {
        val result = CompletionOutcome.resolve(
            context(
                packs = listOf(pack("first-steps", "daily-001", "daily-002")),
                solved = setOf("daily-002"),
            )
        )
        assertThat(result.completedPacks.map { it.id }).containsExactly("first-steps")
        assertThat(result.profile.completedPackIDs).contains("first-steps")
        // The ordering constraint: the badge lands on *this* completion screen.
        assertThat(result.newAchievements.map { it.id }).contains("pathfinder")
    }

    @Test
    fun `a pack is not credited twice`() {
        val result = CompletionOutcome.resolve(
            context(
                profile = PlayerProfile(completedPackIDs = listOf("first-steps")),
                record = PuzzleRecord("daily-001", isCompleted = true),
                packs = listOf(pack("first-steps", "daily-001")),
            )
        )
        assertThat(result.completedPacks).isEmpty()
        assertThat(result.profile.completedPackIDs).containsExactly("first-steps")
    }

    @Test
    fun `a quest reports its step, and completes when the last one lands`() {
        val q = quest("beginnings", "daily-000", "daily-001", "daily-002")
        val midway = CompletionOutcome.resolve(context(quests = listOf(q), solved = setOf("daily-000")))
        assertThat(midway.questSteps).containsExactly(CompletionOutcome.QuestStep("beginnings", 2, 3))
        assertThat(midway.completedQuests).isEmpty()

        val last = CompletionOutcome.resolve(
            context(quests = listOf(q), solved = setOf("daily-000", "daily-002"))
        )
        assertThat(last.completedQuests.map { it.id }).containsExactly("beginnings")
        assertThat(last.newAchievements.map { it.id }).contains("first-journey")
    }

    @Test
    fun `the streak advances before achievements, so a streak badge lands on its own solve`() {
        val result = CompletionOutcome.resolve(
            context(profile = PlayerProfile(currentStreak = 29, bestStreak = 29, lastCompletedAt = daysAgo(1)))
        )
        assertThat(result.profile.currentStreak).isEqualTo(30)
        assertThat(result.newAchievements.map { it.id }).contains("evangelist")
    }

    @Test
    fun `crossing a seven-day milestone earns a freeze`() {
        val result = CompletionOutcome.resolve(
            context(profile = PlayerProfile(currentStreak = 6, lastCompletedAt = daysAgo(1), streakFreezes = 1))
        )
        assertThat(result.earnedFreeze).isTrue()
        assertThat(result.profile.streakFreezes).isEqualTo(2)
    }

    @Test
    fun `a solve answers an owed broken streak, and names how it was reached`() {
        val organic = CompletionOutcome.resolve(context(pendingStreakBreak = 12))
        assertThat(organic.isComeback).isTrue()
        assertThat(organic.comebackSource).isEqualTo("organic")

        val fromCard = CompletionOutcome.resolve(context(pendingStreakBreak = 12, comebackSource = "comeback_card"))
        assertThat(fromCard.comebackSource).isEqualTo("comeback_card")

        val nothingOwed = CompletionOutcome.resolve(context())
        assertThat(nothingOwed.isComeback).isFalse()
        assertThat(nothingOwed.comebackSource).isNull()
    }

    @Test
    fun `only an unaided first Mini is worth posting to the leaderboard`() {
        val mini = puzzle("mini-001", kind = PuzzleKind.MINI)
        assertThat(CompletionOutcome.resolve(context(puzzle = mini)).submitToLeaderboard).isTrue()
        // A hint buys a time nobody solved for.
        assertThat(
            CompletionOutcome.resolve(context(puzzle = mini, record = PuzzleRecord("mini-001", usedHint = true)))
                .submitToLeaderboard
        ).isFalse()
        // A replay knows the answers.
        assertThat(
            CompletionOutcome.resolve(context(puzzle = mini, record = PuzzleRecord("mini-001", isCompleted = true)))
                .submitToLeaderboard
        ).isFalse()
        // The board is the Mini board.
        assertThat(CompletionOutcome.resolve(context()).submitToLeaderboard).isFalse()
    }

    @Test
    fun `the celebration hold covers the diagonal sweep, and is skipped under reduce motion`() {
        // 15x15: 28 diagonals at 40ms, plus the tail.
        assertThat(CompletionOutcome.celebrationHoldMillis(15, reduceMotion = false)).isEqualTo(1670)
        assertThat(CompletionOutcome.celebrationHoldMillis(15, reduceMotion = true)).isEqualTo(0)
    }
}
