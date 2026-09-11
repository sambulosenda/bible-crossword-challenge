package com.sambulosendas1.biblecrossword.domain.access

import com.sambulosendas1.biblecrossword.domain.content.Puzzle
import com.sambulosendas1.biblecrossword.domain.content.PuzzleCatalogue
import java.time.LocalDate

/**
 * Who may play what — iOS `Services/PuzzleAccess.swift`. One source of truth,
 * so Library, packs and any future entry point can't drift into disagreeing
 * about the free tier.
 *
 * The free tier is a soft gate, not a hard lock. Two rules, both stateless:
 *
 *  1. A rolling window of the puzzles currently in rotation — today's and the
 *     six served before it, per pool.
 *  2. Anything the player has already started stays theirs.
 *
 * Rule 2 exists because rule 1 slides: without it a puzzle begun on its last
 * windowed day would lock overnight with the player's own progress inside it,
 * and a soft gate that takes something back is not softer than a hard one.
 */
class PuzzleAccess(
    catalogue: PuzzleCatalogue,
    date: LocalDate,
    windowLength: Int = WINDOW_LENGTH,
    /**
     * Puzzles a friend has challenged this player on. An invite that lands on
     * a paywall is not an invite, so the puzzle it names is playable while the
     * challenge is pending — outside the window, and even a pack exclusive.
     * Kept apart from the window so Library doesn't frame it as "free this week".
     */
    private val challengedIDs: Set<String> = emptySet(),
) {
    private val windowIDs: Set<String> = buildSet {
        // Each pool rotates on its own index, so each gets its own window.
        addAll(catalogue.rotationWindow(catalogue.puzzles, date, windowLength).map { it.id })
        addAll(catalogue.rotationWindow(catalogue.minis, date, windowLength).map { it.id })
        // The Sunday pool's window is a single puzzle: this week's Special is
        // free for everyone, the back catalogue is Premium's shelf.
        catalogue.sundaySpecial(date)?.let { add(it.id) }
    }

    /** In the current rolling window, regardless of entitlement or progress. */
    fun isInWindow(puzzle: Puzzle): Boolean = puzzle.id in windowIDs

    /**
     * Whether the player may open [puzzle].
     *
     * [hasProgress] is "a record exists", which the game writes on the first
     * letter entered — not on merely opening a puzzle. So the grandfather
     * clause covers work the player actually did.
     */
    fun canPlay(puzzle: Puzzle, isPremium: Boolean, hasProgress: Boolean): Boolean {
        if (isPremium) return true
        if (puzzle.id in challengedIDs) return true
        // Pack exclusives are sold with their pack and never enter a rotation.
        // Checked ahead of `hasProgress` so a lapsed subscriber's pack history
        // can't reopen them for free.
        if (puzzle.isPackExclusive) return false
        if (hasProgress) return true
        return puzzle.id in windowIDs
    }

    companion object {
        /**
         * How many puzzles per pool sit inside the rolling window. Seven, so it
         * is worth returning to weekly without handing over a meaningful share
         * of the archive.
         */
        const val WINDOW_LENGTH = 7
    }
}
