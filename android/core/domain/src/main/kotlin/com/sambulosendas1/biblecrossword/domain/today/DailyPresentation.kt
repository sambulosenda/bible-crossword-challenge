package com.sambulosendas1.biblecrossword.domain.today

import com.sambulosendas1.biblecrossword.domain.content.Puzzle
import com.sambulosendas1.biblecrossword.domain.progress.PuzzleRecord
import java.time.DayOfWeek
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

/** How a puzzle card presents itself today. Mirrors iOS `PuzzleStatus`. */
enum class PuzzleStatus { NOT_STARTED, IN_PROGRESS, SOLVED_TODAY, SOLVED_EARLIER }

/**
 * The state of one puzzle card on Today — whether to invite, resume, or
 * celebrate, and how far along the ring is.
 */
data class DailyPresentation(
    val puzzle: Puzzle,
    val status: PuzzleStatus,
    /** Filled fraction, for the resume ring. Null when not started or done. */
    val progress: Float?,
    val solveSeconds: Int?,
) {
    companion object {
        fun of(
            puzzle: Puzzle,
            record: PuzzleRecord?,
            now: Instant,
            zone: ZoneId = ZoneId.systemDefault(),
        ): DailyPresentation {
            val playable = puzzle.grid.sumOf { row -> row.count { it != '.' } }
            return when {
                record == null -> DailyPresentation(puzzle, PuzzleStatus.NOT_STARTED, null, null)
                record.isCompleted -> {
                    val today = record.completedAt?.let {
                        LocalDate.ofInstant(it, zone) == LocalDate.ofInstant(now, zone)
                    } ?: false
                    DailyPresentation(
                        puzzle,
                        if (today) PuzzleStatus.SOLVED_TODAY else PuzzleStatus.SOLVED_EARLIER,
                        null,
                        record.elapsedSeconds,
                    )
                }
                // Pencil is not progress, so the ring counts pen letters only —
                // the same convention the record's `entries` keeps everywhere.
                record.entries.isEmpty() -> DailyPresentation(puzzle, PuzzleStatus.NOT_STARTED, null, null)
                else -> DailyPresentation(
                    puzzle,
                    PuzzleStatus.IN_PROGRESS,
                    if (playable == 0) null else record.entries.size.toFloat() / playable,
                    null,
                )
            }
        }
    }
}

/**
 * The week row on the streak card: which weekdays already carry a completion.
 * The week begins on Sunday, matching how the Sunday Special rotates and how
 * the iOS row reads.
 */
object StreakWeek {
    fun completedWeekdays(
        completionDates: List<Instant>,
        now: Instant,
        zone: ZoneId = ZoneId.systemDefault(),
    ): Set<DayOfWeek> {
        val today = LocalDate.ofInstant(now, zone)
        // Most recent Sunday, inclusive of today if today is Sunday.
        val sunday = today.minusDays((today.dayOfWeek.value % 7).toLong())
        return completionDates
            .map { LocalDate.ofInstant(it, zone) }
            .filter { !it.isBefore(sunday) && !it.isAfter(today) }
            .map { it.dayOfWeek }
            .toSet()
    }

    /** Sunday-first weekday order, for rendering the row. */
    val weekOrder: List<DayOfWeek> = listOf(
        DayOfWeek.SUNDAY, DayOfWeek.MONDAY, DayOfWeek.TUESDAY, DayOfWeek.WEDNESDAY,
        DayOfWeek.THURSDAY, DayOfWeek.FRIDAY, DayOfWeek.SATURDAY,
    )
}
