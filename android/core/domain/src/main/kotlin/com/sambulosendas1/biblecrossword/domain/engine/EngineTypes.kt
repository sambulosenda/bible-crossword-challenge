package com.sambulosendas1.biblecrossword.domain.engine

import com.sambulosendas1.biblecrossword.domain.content.ClueDirection
import com.sambulosendas1.biblecrossword.domain.content.GridPos

/*
 * Runtime types of the crossword engine. Mirrors the runtime half of iOS
 * `Models/CrosswordModels.swift` and the enums at the top of
 * `ViewModels/GameViewModel.swift`.
 */

enum class HintType(val rawValue: String, val title: String, val cost: Int) {
    /** Fills + locks one cell. The standard unit. */
    LETTER("letter", "Reveal Letter", 1),
    /** Fills + locks the word — nearly an answer button. */
    WORD("word", "Reveal Word", 2),
    /** Opens the passage instead of touching the grid. Free: reading Scripture is the point. */
    VERSE("verse", "Show the Verse", 0),
    /** Fills the whole grid — the give-up button. Costs the entire pool. */
    PUZZLE("puzzle", "Reveal Puzzle", 3);
}

/** Granularity of a one-shot answer check. Checks are free and never reveal. */
enum class CheckScope(val rawValue: String) {
    LETTER("letter"), WORD("word"), PUZZLE("puzzle");
}

/** Which action the stall-nudge line offers — drives its copy and tap action. */
enum class StallNudgeKind(val rawValue: String) {
    CHECK_ANSWERS("check"), READ_VERSE("verse"), FREE_LETTER("free_letter");
}

data class CellState(
    val pos: GridPos,
    val isBlock: Boolean,
    val solution: Char?,
    val number: Int?,
    val entry: Char? = null,
    val isRevealed: Boolean = false,
    /** A provisional (pencil) letter. Pencil never counts toward completion. */
    val isPencil: Boolean = false,
    /** Marked wrong by a one-shot check; cleared the moment the cell is edited. */
    val isCheckedWrong: Boolean = false,
) {
    val isCorrect: Boolean
        get() = solution != null && entry != null && !isPencil && entry == solution
}

/** A placed word plus its clue. */
data class Slot(
    val number: Int,
    val direction: ClueDirection,
    val clue: String,
    val answer: String,
    val positions: List<GridPos>,
    /** Passage the answer comes from, once solved. Null when the clue has none. */
    val reference: String?,
) {
    val id: String get() = "$number-${direction.rawValue}"
    val length: Int get() = positions.size
}
