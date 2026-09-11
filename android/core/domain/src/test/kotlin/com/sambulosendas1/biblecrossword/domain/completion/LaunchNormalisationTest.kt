package com.sambulosendas1.biblecrossword.domain.completion

import com.google.common.truth.Truth.assertThat
import com.sambulosendas1.biblecrossword.domain.content.PuzzlePack
import com.sambulosendas1.biblecrossword.domain.profile.PlayerProfile
import com.sambulosendas1.biblecrossword.domain.profile.Streaks
import com.sambulosendas1.biblecrossword.domain.today.DailyPresentation
import com.sambulosendas1.biblecrossword.domain.today.PuzzleStatus
import com.sambulosendas1.biblecrossword.domain.today.StreakWeek
import com.sambulosendas1.biblecrossword.domain.content.ClueData
import com.sambulosendas1.biblecrossword.domain.content.ClueDirection
import com.sambulosendas1.biblecrossword.domain.content.Puzzle
import com.sambulosendas1.biblecrossword.domain.content.PuzzleDifficulty
import com.sambulosendas1.biblecrossword.domain.progress.PuzzleRecord
import org.junit.jupiter.api.Test
import java.time.DayOfWeek
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset

class LaunchNormalisationTest {

    private val utc = ZoneOffset.UTC
    /** 2026-08-08 is a Saturday. */
    private val now: Instant = LocalDate.of(2026, 8, 8).atTime(12, 0).toInstant(ZoneOffset.UTC)
    private fun daysAgo(n: Int) = now.minusSeconds(n * 86_400L)

    private fun pack(id: String, vararg ids: String) =
        PuzzlePack(id = id, title = id, blurb = "", coverSymbol = "book", isPremium = false, puzzleIDs = ids.toList())

    @Test
    fun `a missed day breaks the streak and owes the comeback card exactly once`() {
        val profile = PlayerProfile(currentStreak = 9, lastCompletedAt = daysAgo(3), streakFreezes = 0)
        val first = LaunchNormalisation.run(profile, emptySet(), emptyList(), emptyList(), now, utc)
        assertThat(first.outcome).isEqualTo(Streaks.Outcome.Broken(9))
        assertThat(first.pendingStreakBreak).isEqualTo(9)

        // A second pass the same day finds the streak already at zero. Without
        // this the card would re-fire on every launch.
        val second = LaunchNormalisation.run(first.profile, emptySet(), emptyList(), emptyList(), now, utc)
        assertThat(second.outcome).isEqualTo(Streaks.Outcome.Unchanged)
        assertThat(second.pendingStreakBreak).isEqualTo(0)
    }

    @Test
    fun `a single missed day is bridged by a freeze and owes nothing`() {
        val profile = PlayerProfile(currentStreak = 9, lastCompletedAt = daysAgo(2), streakFreezes = 1)
        val result = LaunchNormalisation.run(profile, emptySet(), emptyList(), emptyList(), now, utc)
        assertThat(result.outcome).isEqualTo(Streaks.Outcome.FreezeSaved)
        assertThat(result.pendingStreakBreak).isEqualTo(0)
        assertThat(result.profile.currentStreak).isEqualTo(9)
        assertThat(result.profile.streakFreezes).isEqualTo(0)
    }

    @Test
    fun `packs finished before the feature existed are credited on launch`() {
        val result = LaunchNormalisation.run(
            PlayerProfile(),
            solvedPuzzleIDs = setOf("a", "b"),
            packs = listOf(pack("done", "a", "b"), pack("partial", "a", "c")),
            quests = emptyList(),
            now = now, zone = utc,
        )
        assertThat(result.reconciledPacks.map { it.id }).containsExactly("done")
        assertThat(result.profile.completedPackIDs).containsExactly("done")
    }

    @Test
    fun `already-credited packs are not credited again`() {
        val result = LaunchNormalisation.run(
            PlayerProfile(completedPackIDs = listOf("done")),
            solvedPuzzleIDs = setOf("a", "b"),
            packs = listOf(pack("done", "a", "b")),
            quests = emptyList(),
            now = now, zone = utc,
        )
        assertThat(result.reconciledPacks).isEmpty()
        assertThat(result.profile.completedPackIDs).containsExactly("done")
    }
}

class DailyPresentationTest {

    private val utc = ZoneOffset.UTC
    private val now: Instant = LocalDate.of(2026, 8, 8).atTime(12, 0).toInstant(ZoneOffset.UTC)

    private val puzzle = Puzzle(
        id = "daily-001", title = "T", difficulty = PuzzleDifficulty.EASY, verse = "", reference = "",
        publishDate = "2026-01-01", size = 3, grid = listOf("AAA", "A.A", "AAA"),
        clues = listOf(ClueData(1, ClueDirection.ACROSS, 0, 0, "c", "AAA")),
    )

    @Test
    fun `no record invites, entries resume, completion celebrates`() {
        assertThat(DailyPresentation.of(puzzle, null, now, utc).status).isEqualTo(PuzzleStatus.NOT_STARTED)

        val started = PuzzleRecord("daily-001", entries = mapOf("0,0" to "A", "0,1" to "A"))
        val resume = DailyPresentation.of(puzzle, started, now, utc)
        assertThat(resume.status).isEqualTo(PuzzleStatus.IN_PROGRESS)
        // 8 playable cells, 2 filled.
        assertThat(resume.progress).isWithin(1e-6f).of(0.25f)

        val today = PuzzleRecord("daily-001", isCompleted = true, completedAt = now, elapsedSeconds = 90)
        assertThat(DailyPresentation.of(puzzle, today, now, utc).status).isEqualTo(PuzzleStatus.SOLVED_TODAY)

        val earlier = today.copy(completedAt = now.minusSeconds(3 * 86_400))
        assertThat(DailyPresentation.of(puzzle, earlier, now, utc).status).isEqualTo(PuzzleStatus.SOLVED_EARLIER)
    }

    @Test
    fun `an empty record still reads as not started`() {
        val touched = PuzzleRecord("daily-001")
        assertThat(DailyPresentation.of(puzzle, touched, now, utc).status).isEqualTo(PuzzleStatus.NOT_STARTED)
    }

    @Test
    fun `the week row runs Sunday to today and ignores earlier weeks`() {
        // Saturday 2026-08-08; the week began Sunday 2026-08-02.
        val days = listOf(
            now,                                  // Saturday
            now.minusSeconds(6 * 86_400),         // Sunday, the start of this week
            now.minusSeconds(9 * 86_400),         // last week — excluded
        )
        val completed = StreakWeek.completedWeekdays(days, now, utc)
        assertThat(completed).containsExactly(DayOfWeek.SATURDAY, DayOfWeek.SUNDAY)
        assertThat(StreakWeek.weekOrder.first()).isEqualTo(DayOfWeek.SUNDAY)
    }
}
