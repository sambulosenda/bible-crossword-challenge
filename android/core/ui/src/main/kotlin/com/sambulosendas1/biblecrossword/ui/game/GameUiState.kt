package com.sambulosendas1.biblecrossword.ui.game

import androidx.compose.runtime.Immutable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.sambulosendas1.biblecrossword.domain.content.ClueDirection
import com.sambulosendas1.biblecrossword.domain.content.GridPos
import com.sambulosendas1.biblecrossword.domain.engine.GameEngine
import com.sambulosendas1.biblecrossword.domain.engine.Slot
import com.sambulosendas1.biblecrossword.domain.engine.StallNudgeKind

/**
 * One cell's visual inputs and nothing else.
 *
 * This is the direct analog of iOS making `CellView` `Equatable`: a 21×21
 * Sunday is 441 cells and a keystroke changes two of them, so the grid must
 * skip the rest. Compose skips a composable whose parameters are stable and
 * unchanged, which is exactly what this type buys — it deliberately carries no
 * reference to the engine, because a mutable one would defeat the skipping.
 */
@Immutable
data class CellUi(
    val row: Int,
    val col: Int,
    val isBlock: Boolean,
    val number: Int?,
    val letter: Char?,
    val isPencil: Boolean,
    /**
     * Whether this letter is actually right. Carried so a red mark can be
     * withheld from correct cells — under auto-check `showError` is true for
     * the whole grid, and iOS filters it by `!cell.isCorrect`. It leaks
     * nothing on its own: only [showError] and [showCorrect] decide what paints.
     */
    val isCorrect: Boolean,
    val isSelected: Boolean,
    val isInWord: Boolean,
    /** Marked wrong: auto-check, or a one-shot check until the cell is edited. */
    val showError: Boolean,
    /** Correct entries paint green. Never true in live play — see iOS `showCorrectOverlay`. */
    val showCorrect: Boolean,
)

@Immutable
data class ActiveClueUi(
    val id: String,
    val number: Int,
    val direction: ClueDirection,
    val text: String,
    val hasReference: Boolean,
)

/** Everything the game surfaces need, rebuilt whenever the engine mutates. */
@Immutable
data class GameUiState(
    val size: Int,
    val cells: List<CellUi>,
    val activeClue: ActiveClueUi?,
    val isPencilMode: Boolean,
    val isComplete: Boolean,
    val filled: Int,
    val total: Int,
    val remainingClues: Int,
    val isMini: Boolean,
    val elapsedSeconds: Int,
    val isStallNudgeActive: Boolean,
    val stallNudgeKind: StallNudgeKind,
) {
    fun cell(row: Int, col: Int): CellUi = cells[row * size + col]

    /**
     * Fraction of playable cells filled. Deliberately counts *filled*, not
     * *correct*, so the progress strip can't be used as a free answer checker.
     */
    val progress: Float get() = if (total == 0) 0f else filled.toFloat() / total

    /**
     * Endgame encouragement, for full-size grids only: with five clues a Mini
     * would show it mid-solve.
     */
    val endgameNudge: Int?
        get() = if (isMini || isComplete) null else remainingClues.takeIf { it in 1..2 }
}

/**
 * Holds a [GameEngine] and republishes an immutable [GameUiState] after every
 * mutation. The engine is a plain mutable object (ported line-for-line from
 * iOS and tested against the shared vectors); this is the only place that
 * knows how to show it to Compose.
 */
class GameStateHolder(val engine: GameEngine) {

    var state: GameUiState by mutableStateOf(snapshot())
        private set

    /** Cells currently showing a green pulse — animation state, owned by the UI. */
    var flashing: Set<GridPos> by mutableStateOf(emptySet())

    /** Run a mutation and republish. Every call site goes through this. */
    inline fun <T> mutate(block: (GameEngine) -> T): T {
        val result = block(engine)
        refresh()
        return result
    }

    fun refresh() {
        state = snapshot()
    }

    fun snapshot(): GameUiState {
        val active: Slot? = engine.activeSlot
        val activeWord = engine.activeWordPositions
        val size = engine.size
        val cells = ArrayList<CellUi>(size * size)
        for (r in 0 until size) {
            for (c in 0 until size) {
                val cell = engine.cell(r, c)
                cells += CellUi(
                    row = r,
                    col = c,
                    isBlock = cell.isBlock,
                    number = cell.number,
                    letter = cell.entry,
                    isPencil = cell.isPencil,
                    isCorrect = cell.isCorrect,
                    isSelected = engine.selected.row == r && engine.selected.col == c,
                    isInWord = GridPos(r, c) in activeWord,
                    showError = engine.autoCheck || cell.isCheckedWrong,
                    showCorrect = false,
                )
            }
        }
        return GameUiState(
            size = size,
            cells = cells,
            activeClue = active?.let {
                ActiveClueUi(it.id, it.number, it.direction, it.clue, it.reference != null)
            },
            isPencilMode = engine.isPencilMode,
            isComplete = engine.isComplete,
            filled = engine.filledPlayableCount,
            total = engine.totalPlayableCount,
            remainingClues = engine.remainingClueCount,
            isMini = engine.puzzle.isMini,
            elapsedSeconds = engine.elapsed(),
            isStallNudgeActive = engine.isStallNudgeActive,
            stallNudgeKind = engine.stallNudgeKind,
        )
    }
}
