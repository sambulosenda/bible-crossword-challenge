package com.sambulosendas1.biblecrossword.domain.content

import java.time.LocalDate
import java.time.temporal.ChronoUnit

/**
 * The decoded content and the daily rotation over it — the rule half of iOS
 * `Services/PuzzleProvider.swift`. Loading the files is the data layer's job;
 * this takes the decoded lists so it is testable against `spec/vectors/
 * rotation.json` on the JVM.
 *
 * Dates are `LocalDate` — the rotation is a function of the calendar day and
 * nothing else, which is exactly what the iOS code computes with
 * `Calendar.startOfDay`. The vectors evaluate ISO days in UTC; a `LocalDate`
 * has no zone, so they agree by construction.
 */
class PuzzleCatalogue(
    /** Everything in the bundle, including `pack-` exclusives. */
    val allPuzzles: List<Puzzle>,
    val packs: List<PuzzlePack> = emptyList(),
    val quests: List<QuestLine> = emptyList(),
) {
    /**
     * Full-size dailies only — the pool the daily rotation and Library draw
     * from. Pack exclusives and Sundays are kept out so the rotation index
     * stays content-stable for every existing player.
     */
    val puzzles: List<Puzzle> = allPuzzles.filter { !it.isMini && !it.isSunday && !it.isPackExclusive }

    /** Quick 7×7 minis, rotating on their own index. */
    val minis: List<Puzzle> = allPuzzles.filter { it.isMini }

    /** Weekly 21×21 Sunday Specials, rotating by week. */
    val sundays: List<Puzzle> = allPuzzles.filter { it.isSunday }

    /** Everything a Premium player can play. */
    val totalPuzzleCount: Int get() = allPuzzles.size

    private val byID: Map<String, Puzzle> = allPuzzles.associateBy { it.id }

    /** puzzleID → owning packID; the first pack listing a puzzle wins. */
    private val packByPuzzleID: Map<String, String> = buildMap {
        for (pack in packs) for (pid in pack.puzzleIDs) putIfAbsent(pid, pack.id)
    }

    fun puzzle(id: String): Puzzle? = byID[id]

    // MARK: - Rotation

    /** Whole days from the content epoch. Negative before it. */
    fun dayIndex(date: LocalDate): Int = ChronoUnit.DAYS.between(EPOCH, date).toInt()

    /**
     * Whole weeks from the epoch where a week begins on **Sunday** regardless
     * of locale — the Special is a Sunday tradition. Two dates share an index
     * exactly when they share a most-recent Sunday.
     */
    fun weekIndex(date: LocalDate): Int {
        val day = dayIndex(date)
        // Gregorian weekday, 1 = Sunday … 7 = Saturday (java's MONDAY=1 … SUNDAY=7).
        val weekday = date.dayOfWeek.value % 7 + 1
        val sundayDay = day - (weekday - 1)
        return Math.floorDiv(sundayDay, 7)
    }

    fun dailyPuzzle(date: LocalDate): Puzzle? = rotated(puzzles, date)

    fun dailyMini(date: LocalDate): Puzzle? = rotated(minis, date)

    /** This week's Special — lingers Sunday through Saturday. */
    fun sundaySpecial(date: LocalDate): Puzzle? {
        if (sundays.isEmpty()) return null
        val week = weekIndex(date) - SUNDAY_ROTATION_OFFSET
        return sundays[Math.floorMod(week, sundays.size)]
    }

    /**
     * The `length` puzzles currently open in `pool`: today's, then the ones
     * served before it, walking the rotation backwards and wrapping with it.
     * Positions, not dates — the answer stays defined after the pool wraps.
     */
    fun rotationWindow(pool: List<Puzzle>, date: LocalDate, length: Int): List<Puzzle> {
        if (pool.isEmpty() || length <= 0) return emptyList()
        val today = dayIndex(date)
        val span = minOf(length, pool.size)
        return (0 until span).map { offset -> pool[Math.floorMod(today - offset, pool.size)] }
    }

    private fun rotated(pool: List<Puzzle>, date: LocalDate): Puzzle? {
        if (pool.isEmpty()) return null
        return pool[Math.floorMod(dayIndex(date), pool.size)]
    }

    // MARK: - Packs

    fun pack(id: String): PuzzlePack? = packs.firstOrNull { it.id == id }

    /** The pack a puzzle primarily belongs to — drives "next in pack". */
    fun packForPuzzle(puzzleID: String): PuzzlePack? = packByPuzzleID[puzzleID]?.let(::pack)

    /** Every pack listing this puzzle — a shared puzzle can complete several at once. */
    fun packsContaining(puzzleID: String): List<PuzzlePack> = packs.filter { puzzleID in it.puzzleIDs }

    /** A pack's puzzles in authored order; unknown ids are dropped, never crash. */
    fun puzzlesIn(pack: PuzzlePack): List<Puzzle> = pack.puzzleIDs.mapNotNull(::puzzle)

    // MARK: - Quests

    fun quest(id: String): QuestLine? = quests.firstOrNull { it.id == id }

    fun questsContaining(puzzleID: String): List<QuestLine> = quests.filter { puzzleID in it.puzzleIDs }

    fun puzzlesIn(quest: QuestLine): List<Puzzle> = quest.puzzleIDs.mapNotNull(::puzzle)

    companion object {
        /** Day-index 0: the first puzzle in the rotation. */
        val EPOCH: LocalDate = LocalDate.of(2026, 7, 1)

        /**
         * Weeks subtracted from the week index before it picks a Special, so
         * an append-only bank walks forward through new puzzles instead of
         * replaying the oldest. Re-derive whenever the bank grows — see the
         * iOS comment on `sundayRotationOffset`. Set 2026-09-04: (8 - 5) % 13 == 3.
         */
        const val SUNDAY_ROTATION_OFFSET = 5
    }
}
