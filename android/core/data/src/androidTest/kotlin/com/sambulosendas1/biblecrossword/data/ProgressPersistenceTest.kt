package com.sambulosendas1.biblecrossword.data

import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.google.common.truth.Truth.assertThat
import com.sambulosendas1.biblecrossword.data.db.AppDatabase
import com.sambulosendas1.biblecrossword.data.db.toDomain
import com.sambulosendas1.biblecrossword.data.db.toEntity
import com.sambulosendas1.biblecrossword.data.repo.ProgressRepository
import com.sambulosendas1.biblecrossword.domain.content.ClueData
import com.sambulosendas1.biblecrossword.domain.content.ClueDirection
import com.sambulosendas1.biblecrossword.domain.content.Puzzle
import com.sambulosendas1.biblecrossword.domain.content.PuzzleDifficulty
import com.sambulosendas1.biblecrossword.domain.engine.GameEngine
import com.sambulosendas1.biblecrossword.domain.profile.PlayerProfile
import com.sambulosendas1.biblecrossword.domain.progress.PuzzleRecord
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.time.Instant

/**
 * Progress has to survive the process, not just the screen. These run against
 * a real Room database and a real engine, so what is asserted is the whole
 * round trip: solve a bit, persist, rebuild from scratch, resume.
 */
@RunWith(AndroidJUnit4::class)
class ProgressPersistenceTest {

    private lateinit var db: AppDatabase
    private lateinit var repo: ProgressRepository

    @Before fun setUp() {
        db = Room.inMemoryDatabaseBuilder(ApplicationProvider.getApplicationContext(), AppDatabase::class.java)
            .allowMainThreadQueries().build()
        repo = ProgressRepository(db.playerProfileDao(), db.puzzleRecordDao())
    }

    @After fun tearDown() = db.close()

    private fun puzzle() = Puzzle(
        id = "test-001", title = "Test", difficulty = PuzzleDifficulty.EASY,
        verse = "", reference = "", publishDate = "2026-01-01", size = 3,
        grid = listOf("CAT", "A.O", "TOP"),
        clues = listOf(
            ClueData(1, ClueDirection.ACROSS, 0, 0, "Feline", "CAT"),
            ClueData(3, ClueDirection.ACROSS, 2, 0, "Summit", "TOP"),
            ClueData(1, ClueDirection.DOWN, 0, 0, "Feline", "CAT"),
            ClueData(2, ClueDirection.DOWN, 0, 2, "Reverse of pot", "TOP"),
        ),
    )

    @Test
    fun aPartialSolveSurvivesRebuildingTheEngineFromStorage() = runTest {
        val puzzle = puzzle()
        val first = GameEngine(puzzle)
        // Type a word, pencil a letter, and take a hint — one of each kind of
        // state the record has to carry.
        first.select(first.allSlots.first { it.id == "1-across" })
        "CAT".forEach { first.enter(it) }
        first.select(first.allSlots.first { it.id == "2-down" })
        first.isPencilMode = true
        first.enter('T')
        first.isPencilMode = false
        first.select(first.allSlots.first { it.id == "3-across" })
        first.revealLetter()
        first.seedElapsed(137)

        repo.saveRecord(
            PuzzleRecord(
                puzzleID = puzzle.id,
                elapsedSeconds = first.elapsed(),
                entries = first.snapshot(),
                pencil = first.pencilSnapshot(),
                usedHint = true,
            )
        )

        // A whole new process would do exactly this.
        val saved = repo.record(puzzle.id)!!
        val resumed = GameEngine(puzzle)
        resumed.seedElapsed(saved.elapsedSeconds)
        resumed.restore(saved.entries, saved.pencil)

        assertThat(resumed.snapshot()).isEqualTo(first.snapshot())
        assertThat(resumed.pencilSnapshot()).isEqualTo(first.pencilSnapshot())
        assertThat(resumed.elapsed()).isEqualTo(137)
        assertThat(saved.usedHint).isTrue()
    }

    @Test
    fun aRevealedLetterStaysLockedAcrossTheRoundTrip() = runTest {
        val puzzle = puzzle()
        val first = GameEngine(puzzle)
        first.revealLetter()
        val revealedAt = first.snapshot().entries.first()
        // Lowercase is the lock, and it is what the database stores.
        assertThat(revealedAt.value.first().isLowerCase()).isTrue()

        repo.saveRecord(PuzzleRecord(puzzleID = puzzle.id, entries = first.snapshot()))
        val saved = repo.record(puzzle.id)!!
        val resumed = GameEngine(puzzle)
        resumed.restore(saved.entries)

        // Typing over it must skip rather than destroy what the player paid for.
        val pos = com.sambulosendas1.biblecrossword.domain.content.GridPos.fromStorageKey(revealedAt.key)!!
        resumed.tapCell(pos)
        val before = resumed.cell(pos).entry
        resumed.enter('Z')
        assertThat(resumed.cell(pos).entry).isEqualTo(before)
        assertThat(resumed.lockedEntryTick).isEqualTo(1)
    }

    @Test
    fun theProfileRowIsCreatedOnceAndThenReused() = runTest {
        val a = repo.profile()
        val b = repo.profile()
        assertThat(b.createdAt).isEqualTo(a.createdAt)

        repo.saveProfile(a.copy(currentStreak = 4, totalPuzzlesCompleted = 9))
        assertThat(repo.profile().currentStreak).isEqualTo(4)
        assertThat(repo.profile().totalPuzzlesCompleted).isEqualTo(9)
    }

    @Test
    fun everyProfileFieldRoundTripsThroughRoom() = runTest {
        val profile = PlayerProfile(
            username = "Sam", currentStreak = 7, bestStreak = 12, totalPuzzlesCompleted = 40,
            lastCompletedAt = Instant.ofEpochMilli(1_700_000_000_000),
            hintsUsedToday = 2, hintsAt = Instant.ofEpochMilli(1_700_000_100_000),
            unlockedAchievementIDs = listOf("bible-beginner", "unaided"),
            bestSolveSeconds = 231, noHintSolves = 5, hardCompleted = 3,
            completedPackIDs = listOf("first-steps"), completedQuestIDs = listOf("beginnings"),
            streakFreezes = 2, lastFreezeUsedAt = Instant.ofEpochMilli(1_700_000_200_000),
            createdAt = Instant.ofEpochMilli(1_600_000_000_000),
        )
        repo.saveProfile(profile)
        assertThat(repo.profile()).isEqualTo(profile)
        // And the mapper is its own inverse, independent of the database.
        assertThat(profile.toEntity().toDomain()).isEqualTo(profile)
    }
}
