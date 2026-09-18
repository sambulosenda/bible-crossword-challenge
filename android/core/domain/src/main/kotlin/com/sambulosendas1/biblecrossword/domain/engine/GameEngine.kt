package com.sambulosendas1.biblecrossword.domain.engine

import com.sambulosendas1.biblecrossword.domain.content.ClueDirection
import com.sambulosendas1.biblecrossword.domain.content.GridPos
import com.sambulosendas1.biblecrossword.domain.content.Puzzle
import com.sambulosendas1.biblecrossword.domain.progress.EntriesCodec
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlin.math.abs
import kotlin.math.min

/**
 * The crossword engine — a line-for-line port of iOS
 * `ViewModels/GameViewModel.swift`. Builds the grid and word slots from a
 * [Puzzle], tracks selection/entry, validates answers, exposes hints and the
 * stall watch, and keeps the active-time clock. Persistence-agnostic and
 * Android-free, so `spec/vectors/engine_traces.json` and `engine_timer.json`
 * replay against it on the JVM.
 *
 * Every behaviour here is deliberate and measured on iOS — do not simplify.
 * The owning screen handles loading/saving and side effects via the
 * callbacks. Compose observes [revision], which advances on every mutation.
 */
class GameEngine(
    val puzzle: Puzzle,
    /** Inside the learning window (under three completions): shorter nudge thresholds. */
    val isLearning: Boolean = false,
    /** The `stall-nudge` holdout, resolved by the creating screen. Gates both tiers. */
    val stallNudgeEnabled: Boolean = true,
) {
    val size: Int = puzzle.size

    private val grid: Array<Array<CellState>>

    val acrossSlots: List<Slot>
    val downSlots: List<Slot>

    var selected: GridPos private set
    var direction: ClueDirection private set

    /** Pencil (provisional) entry mode, toggled from the keyboard. */
    var isPencilMode: Boolean = false

    /**
     * Persistent as-you-type mistake marking, mirrored from the
     * `autoCheckErrors` preference by the owning screen. Marks only *wrong*
     * letters — correct ones earn nothing until the word completes.
     */
    var autoCheck: Boolean = false

    var hintsUsed: Int = 0; private set
    var isComplete: Boolean = false; private set
    var completionSeconds: Int = 0; private set

    // Active-time accounting — see [tick].
    var accumulatedSeconds: Int = 0; private set
    private var lastTickMillis: Long? = null
    /** Sub-second remainder carried between ticks so the clock doesn't drift. */
    private var tickFraction: Double = 0.0

    /** True while the game screen is genuinely on screen — the analog of iOS's window probe. */
    var isVisible: Boolean = false

    /**
     * Timer suppression, as a depth: the verse-hint sheet suppresses, and on
     * Android sheets can stack (a paywall over the verse sheet), so a Bool that
     * the inner dismiss clears would un-suppress the outer.
     */
    var suppressionDepth: Int = 0; private set
    val isTimerSuppressed: Boolean get() = suppressionDepth > 0
    fun pushSuppression() { suppressionDepth += 1; lastTickMillis = null }
    fun popSuppression() { suppressionDepth = (suppressionDepth - 1).coerceAtLeast(0) }

    // Side-effect callbacks owned by the screen.
    var onComplete: ((Int) -> Unit)? = null
    var onEntryChanged: (() -> Unit)? = null
    /** Fired with the word the moment the player fills it in correctly. */
    var onWordCompleted: ((Slot) -> Unit)? = null
    /** Fired after a one-shot check with the correct positions and the wrong count. */
    var onCheckResult: ((List<GridPos>, Int) -> Unit)? = null

    private val slotIndex: Map<ClueDirection, Map<GridPos, Int>>

    /** Slot ids whose cells are all filled correctly — so the flash fires once. */
    private val solvedSlotIDs = mutableSetOf<String>()

    /** Monotonic count of word-solve moments this session (including the final solve). */
    var wordSolveTick: Int = 0; private set

    /** Increments on the transition into "every square filled but at least one wrong". */
    var gridFullWithErrorsTick: Int = 0; private set
    private var wasFullWithErrors = false

    /** Increments when typing lands on a hint-locked cell; the letter is skipped, never silently. */
    var lockedEntryTick: Int = 0; private set
    var lockedEntryPos: GridPos? = null; private set

    /** The stall watch — see [maybeNudgeStall]. */
    var stallNudgeTick: Int = 0; private set
    var stallNudgeKind: StallNudgeKind = StallNudgeKind.CHECK_ANSWERS; private set
    var isStallNudgeActive: Boolean = false; private set
    var midSolveNudgeCount: Int = 0; private set
    private var earlyNudged = false
    /** Active seconds at the last player input — measured on the solve clock, not wall time. */
    private var lastInputSeconds = 0

    /** Idle threshold before the mid-solve stall nudge fires. */
    val stallNudgeSeconds: Int = defaultStallNudgeSeconds(isLearning)

    /** Idle threshold for the early (< 40% fill) free-letter nudge. Never longer than [stallNudgeSeconds]. */
    val earlyNudgeSeconds: Int
        get() = min(if (isLearning) LEARNING_EARLY_NUDGE_SECONDS else EARLY_NUDGE_CAP, stallNudgeSeconds)

    val secondsSinceLastInput: Int get() = accumulatedSeconds - lastInputSeconds

    /** Grid taps and key presses this sitting — attempts, not effects. Reported on `puzzle_abandoned`. */
    var cellTaps: Int = 0; private set
    var keyPresses: Int = 0; private set

    /** The starter gift mid-reveal: the slot being filled and how many letters have landed. */
    private var pendingGift: Pair<Slot, Int>? = null
    val isRevealingStarterWord: Boolean get() = pendingGift != null

    /** Advances on every observable mutation so a Compose holder can re-snapshot. */
    var revision: Long = 0; private set
    private fun bump() { revision++ }

    init {
        val across = mutableListOf<Slot>()
        val down = mutableListOf<Slot>()
        for (clue in puzzle.clues) {
            val slot = Slot(
                number = clue.number, direction = clue.direction, clue = clue.text,
                answer = clue.answer.uppercase(), positions = clue.positions, reference = clue.reference,
            )
            if (clue.direction == ClueDirection.ACROSS) across += slot else down += slot
        }
        across.sortBy { it.number }
        down.sortBy { it.number }
        acrossSlots = across
        downSlots = down

        val numbers = HashMap<GridPos, Int>()
        for (clue in puzzle.clues) numbers[clue.start] = clue.number

        val rows = puzzle.grid.map { it.uppercase() }
        grid = Array(size) { r ->
            Array(size) { c ->
                val pos = GridPos(r, c)
                val ch = if (r < rows.size && c < rows[r].length) rows[r][c] else '.'
                val isBlock = ch == '.'
                CellState(pos = pos, isBlock = isBlock, solution = if (isBlock) null else ch, number = numbers[pos])
            }
        }

        val acrossIdx = HashMap<GridPos, Int>()
        across.forEachIndexed { i, slot -> for (p in slot.positions) acrossIdx[p] = i }
        val downIdx = HashMap<GridPos, Int>()
        down.forEachIndexed { i, slot -> for (p in slot.positions) downIdx[p] = i }
        slotIndex = mapOf(ClueDirection.ACROSS to acrossIdx, ClueDirection.DOWN to downIdx)

        // Opening selection: the shortest answer in the grid, not 1 Across —
        // the empty grid is where a third of abandons happen, so open on the
        // easiest foothold. Ties go across-then-lower-number.
        val easiest = (across + down).minWithOrNull(
            compareBy<Slot>({ it.answer.length }, { if (it.direction == ClueDirection.DOWN) 1 else 0 }, { it.number })
        )
        if (easiest != null) {
            selected = easiest.positions[0]
            direction = easiest.direction
        } else {
            selected = GridPos(0, 0)
            direction = ClueDirection.ACROSS
        }
    }

    // MARK: - Derived state

    val allSlots: List<Slot> get() = acrossSlots + downSlots

    fun cell(pos: GridPos): CellState = grid[pos.row][pos.col]
    fun cell(row: Int, col: Int): CellState = grid[row][col]

    /** Every cell, row-major — for rendering. */
    fun cells(): List<List<CellState>> = grid.map { it.toList() }

    val activeSlot: Slot?
        get() = slotAt(selected, direction) ?: slotAt(selected, direction.toggled)

    val activeWordPositions: Set<GridPos> get() = activeSlot?.positions?.toSet() ?: emptySet()

    private fun slotAt(pos: GridPos, direction: ClueDirection): Slot? {
        val idx = slotIndex[direction]?.get(pos) ?: return null
        return if (direction == ClueDirection.ACROSS) acrossSlots[idx] else downSlots[idx]
    }

    fun isSelectable(pos: GridPos): Boolean = !grid[pos.row][pos.col].isBlock

    private fun set(pos: GridPos, transform: (CellState) -> CellState) {
        grid[pos.row][pos.col] = transform(grid[pos.row][pos.col])
    }

    // MARK: - Input bookkeeping

    /** Every deliberate player action: resets the stall clock and dismisses an active nudge. */
    private fun noteInput() {
        lastInputSeconds = accumulatedSeconds
        isStallNudgeActive = false
    }

    // MARK: - Selection

    /** A genuine finger on a cell. Counted before the selectable guard. */
    fun tapCell(pos: GridPos) {
        cellTaps += 1
        flushStarterGift()
        select(pos)
    }

    fun select(pos: GridPos) {
        if (!isSelectable(pos)) return
        noteInput()
        if (pos == selected) {
            toggleDirection()
            return
        }
        selected = pos
        // Prefer a direction that actually has a word at this cell.
        if (slotAt(pos, direction) == null && slotAt(pos, direction.toggled) != null) {
            direction = direction.toggled
        }
        bump()
    }

    fun toggleDirection() {
        if (slotAt(selected, direction.toggled) != null) {
            direction = direction.toggled
            bump()
        }
    }

    fun select(slot: Slot) {
        noteInput()
        direction = slot.direction
        // Land on the first empty cell, else the first cell.
        selected = slot.positions.firstOrNull { cell(it).entry == null } ?: slot.positions[0]
        bump()
    }

    /** Hardware-keyboard cursor movement: one step, walking over blocks, stopping at the edge. */
    fun moveSelection(rowDelta: Int, colDelta: Int) {
        var r = selected.row + rowDelta
        var c = selected.col + colDelta
        while (r in 0 until size && c in 0 until size) {
            if (!grid[r][c].isBlock) {
                select(GridPos(r, c))
                return
            }
            r += rowDelta
            c += colDelta
        }
    }

    // MARK: - Clue navigation

    fun advanceClue(by: Int) {
        val ordered = acrossSlots + downSlots
        if (ordered.isEmpty()) return
        val current = activeSlot ?: return
        val idx = ordered.indexOf(current)
        if (idx < 0) return
        val next = ordered[Math.floorMod(idx + by, ordered.size)]
        select(next)
    }

    // MARK: - Entry

    fun enter(letter: Char) {
        keyPresses += 1
        flushStarterGift()
        if (!isSelectable(selected)) return
        noteInput()
        // Hint-revealed cells are locked — typing skips over them. Announced.
        if (cell(selected).isRevealed) {
            lockedEntryPos = selected
            lockedEntryTick += 1
            advanceWithinWord()
            bump()
            return
        }
        val upper = letter.uppercaseChar()
        val edited = selected
        set(edited) { it.copy(entry = upper, isPencil = isPencilMode, isCheckedWrong = false) }
        onEntryChanged?.invoke()
        checkCompletion()
        if (!isComplete) {
            refreshSolvedSlots(listOf(edited))
            advanceWithinWord()
        }
        bump()
    }

    fun delete() {
        keyPresses += 1
        flushStarterGift()
        noteInput()
        var cleared: GridPos? = null
        val current = cell(selected)
        if (current.entry != null && !current.isRevealed) {
            clearCell(selected)
            cleared = selected
        } else {
            val prev = previousCellInWord()
            if (prev != null) {
                // Step back; clear the previous cell unless it's a locked reveal.
                selected = prev
                val p = cell(prev)
                if (p.entry != null && !p.isRevealed) {
                    clearCell(prev)
                    cleared = prev
                }
            }
        }
        onEntryChanged?.invoke()
        if (cleared != null) {
            refreshSolvedSlots(listOf(cleared))
            // The grid is no longer full, so the next fill-with-errors moment
            // should announce again (checkCompletion isn't run on deletes).
            wasFullWithErrors = false
        }
        bump()
    }

    private fun clearCell(pos: GridPos) {
        set(pos) { it.copy(entry = null, isPencil = false, isCheckedWrong = false) }
    }

    private fun advanceWithinWord() {
        val slot = activeSlot ?: return
        val idx = slot.positions.indexOf(selected)
        if (idx < 0) return
        val after = slot.positions.drop(idx + 1)
        val nextEmpty = after.firstOrNull { cell(it).entry == null }
        val gap = slot.positions.firstOrNull { cell(it).entry == null }
        when {
            nextEmpty != null -> selected = nextEmpty
            idx + 1 < slot.positions.size -> selected = slot.positions[idx + 1]
            // At the word's end with a gap left behind: wrap back to it.
            gap != null -> selected = gap
            // Word is full: move on to the next word that still needs letters.
            else -> advanceToNextIncompleteSlot(slot)
        }
    }

    /**
     * Select the next word to work on once `slot` is full. Crossing words
     * first (closest to done wins); else the nearest incomplete word by grid
     * distance, ties across-then-lower-number. No-op when everything is filled.
     */
    private fun advanceToNextIncompleteSlot(slot: Slot) {
        fun emptyCount(s: Slot) = s.positions.count { cell(it).entry == null }
        val crossers = slotsContaining(slot.positions).filter { it.direction != slot.direction && emptyCount(it) > 0 }
        val crosser = crossers.minWithOrNull(compareBy({ emptyCount(it) }, { it.number }))
        if (crosser != null) {
            select(crosser)
            return
        }
        // `selected` still sits inside the finished word — the anchor the player's eye is on.
        val anchor = selected
        fun distance(s: Slot) = s.positions.minOf { abs(it.row - anchor.row) + abs(it.col - anchor.col) }
        val target = (acrossSlots + downSlots)
            .filter { it != slot && emptyCount(it) > 0 }
            .minWithOrNull(compareBy({ distance(it) }, { if (it.direction == ClueDirection.DOWN) 1 else 0 }, { it.number }))
        if (target != null) select(target)
    }

    private fun previousCellInWord(): GridPos? {
        val slot = activeSlot ?: return null
        val idx = slot.positions.indexOf(selected)
        if (idx <= 0) return null
        return slot.positions[idx - 1]
    }

    // MARK: - Hints

    /** A hint must always buy progress; refuses (caller refunds) when nothing is left in the word. */
    fun revealLetter(): Boolean {
        noteInput()
        var target = selected
        if (!isSelectable(target) || cell(target).isCorrect) {
            target = activeSlot?.positions?.firstOrNull { !cell(it).isCorrect } ?: return false
        }
        val solution = cell(target).solution ?: return false
        selected = target
        set(target) { it.copy(entry = solution, isRevealed = true, isPencil = false, isCheckedWrong = false) }
        hintsUsed += 1
        onEntryChanged?.invoke()
        checkCompletion()
        if (!isComplete) {
            refreshSolvedSlots(listOf(target))
            advanceWithinWord()
        }
        bump()
        return true
    }

    fun revealWord(): Boolean {
        noteInput()
        val slot = activeSlot ?: return false
        if (slotSolved(slot)) return false
        slot.positions.forEachIndexed { i, pos ->
            val ch = slot.answer[i]
            // Leave the player's own correct pen letters alone (and unlocked).
            if (cell(pos).isCorrect) return@forEachIndexed
            set(pos) { it.copy(entry = ch, isRevealed = true, isPencil = false, isCheckedWrong = false) }
        }
        hintsUsed += 1
        onEntryChanged?.invoke()
        checkCompletion()
        if (!isComplete) refreshSolvedSlots(slot.positions)
        bump()
        return true
    }

    /** Fill the whole grid — the give-up button. Refuses when nothing is left to buy. */
    fun revealPuzzle(): Boolean {
        noteInput()
        val anythingLeft = grid.any { row -> row.any { !it.isBlock && !it.isCorrect } }
        if (!anythingLeft) return false
        for (r in 0 until size) for (c in 0 until size) {
            val cellState = grid[r][c]
            if (cellState.isBlock || cellState.isCorrect) continue
            grid[r][c] = cellState.copy(entry = cellState.solution, isRevealed = true, isPencil = false, isCheckedWrong = false)
        }
        hintsUsed += 1
        onEntryChanged?.invoke()
        checkCompletion()
        bump()
        return true
    }

    /** A verse hint touches no cells; this keeps the session hint counter honest. */
    fun noteVerseHint() {
        noteInput()
        hintsUsed += 1
        bump()
    }

    // MARK: - Starter gift

    /**
     * New-player gift: fill the starter word (the opening selection is the
     * shortest answer) and move to a crossing word. Free: no `hintsUsed` bump,
     * and the caller must not set `usedHint`. Refuses on any existing progress.
     */
    fun giftStarterWord(): Slot? {
        val slot = beginStarterGift() ?: return null
        while (placeNextStarterLetter()) { /* place all */ }
        commitStarterGift()
        return slot
    }

    /**
     * Paced twin: letters land one at a time so the player *watches* the
     * mechanic happen. Cancellation-safe — a cancelled wait places the
     * remainder without waiting, so a dismissed screen still leaves a whole,
     * committed gift.
     */
    suspend fun giftStarterWordPaced(letterIntervalMs: Long = STARTER_LETTER_INTERVAL_MS): Slot? {
        val slot = beginStarterGift() ?: return null
        var cancelled: CancellationException? = null
        while (placeNextStarterLetter()) {
            bump()
            if (cancelled == null) {
                try {
                    delay(letterIntervalMs)
                } catch (e: CancellationException) {
                    cancelled = e
                }
            }
        }
        // Null already when player input flushed the gift mid-reveal.
        if (pendingGift != null) commitStarterGift()
        cancelled?.let { throw it }
        return slot
    }

    private fun beginStarterGift(): Slot? {
        if (isComplete || hasAnyEntries || pendingGift != null) return null
        val slot = activeSlot ?: return null
        pendingGift = slot to 0
        return slot
    }

    private fun placeNextStarterLetter(): Boolean {
        val (slot, placed) = pendingGift ?: return false
        if (placed >= slot.positions.size) return false
        val pos = slot.positions[placed]
        set(pos) { it.copy(entry = slot.answer[placed], isRevealed = true, isGift = true) }
        pendingGift = slot to placed + 1
        return true
    }

    /** Close the gift: land anything outstanding, fire the win moment, move on. */
    private fun commitStarterGift(): Slot? {
        val (slot, _) = pendingGift ?: return null
        while (placeNextStarterLetter()) { /* land the rest */ }
        pendingGift = null
        // Loud on purpose: the cascade flash is the win moment the gift was
        // built to manufacture. No completion check — a gift must never
        // finish a puzzle.
        refreshSolvedSlots(slot.positions)
        advanceToNextIncompleteSlot(slot)
        bump()
        return slot
    }

    /** Player input lands the rest of the gift at once, before the input applies. */
    private fun flushStarterGift() {
        if (pendingGift == null) return
        commitStarterGift()
    }

    // MARK: - Word completion tracking

    private fun slotSolved(slot: Slot): Boolean = slot.positions.all { cell(it).isCorrect }

    /** The (deduplicated) slots passing through any of `positions`. */
    private fun slotsContaining(positions: List<GridPos>): List<Slot> {
        val seen = mutableSetOf<String>()
        val result = mutableListOf<Slot>()
        for (p in positions) {
            slotIndex[ClueDirection.ACROSS]?.get(p)?.let { i -> if (seen.add(acrossSlots[i].id)) result += acrossSlots[i] }
            slotIndex[ClueDirection.DOWN]?.get(p)?.let { i -> if (seen.add(downSlots[i].id)) result += downSlots[i] }
        }
        return result
    }

    private fun refreshSolvedSlots(positions: List<GridPos>, silent: Boolean = false) {
        for (slot in slotsContaining(positions)) {
            if (slotSolved(slot)) {
                if (solvedSlotIDs.add(slot.id) && !silent) {
                    wordSolveTick += 1
                    onWordCompleted?.invoke(slot)
                }
            } else {
                solvedSlotIDs.remove(slot.id)
            }
        }
    }

    private fun seedSolvedSlots() {
        solvedSlotIDs.clear()
        for (slot in allSlots) if (slotSolved(slot)) solvedSlotIDs.add(slot.id)
    }

    // MARK: - Validation

    /**
     * One-shot answer check. Free — never reveals, never touches the hint
     * economy. Wrong filled cells (pencil included) are marked until edited;
     * correct positions are reported for a flash and deliberately not stored.
     * Returns the wrong count, or null when nothing was filled to judge.
     */
    fun check(scope: CheckScope): Int? {
        noteInput()
        val positions: List<GridPos> = when (scope) {
            CheckScope.LETTER -> if (isSelectable(selected)) listOf(selected) else emptyList()
            CheckScope.WORD -> activeSlot?.positions ?: emptyList()
            CheckScope.PUZZLE -> grid.flatMap { row -> row.filter { !it.isBlock }.map { it.pos } }
        }
        var wrong = 0
        val correct = mutableListOf<GridPos>()
        var judged = false
        for (pos in positions) {
            val c = cell(pos)
            val entry = c.entry ?: continue
            judged = true
            if (entry == c.solution) {
                correct += pos
            } else {
                set(pos) { it.copy(isCheckedWrong = true) }
                wrong += 1
            }
        }
        if (!judged) return null
        onCheckResult?.invoke(correct, wrong)
        bump()
        return wrong
    }

    /**
     * Completes the puzzle when every playable cell holds the correct letter.
     * Also watches for the "grid full but wrong" moment.
     */
    fun checkCompletion(announceFullMiss: Boolean = true) {
        var full = true
        var correct = true
        for (row in grid) for (c in row) {
            if (c.isBlock) continue
            if (c.entry == null || c.isPencil) full = false
            if (!c.isCorrect) correct = false
        }
        if (!correct) {
            if (full && !wasFullWithErrors && announceFullMiss) gridFullWithErrorsTick += 1
            wasFullWithErrors = full
            return
        }
        if (isComplete) return
        isComplete = true
        // The final word skips refreshSolvedSlots (see enter), so pulse here.
        wordSolveTick += 1
        pauseTimer()
        completionSeconds = accumulatedSeconds
        onComplete?.invoke(completionSeconds)
        bump()
    }

    val hasAnyEntries: Boolean get() = grid.any { row -> row.any { !it.isBlock && it.entry != null } }

    /** Words not yet fully correct — counts *solved* words, not filled. */
    val remainingClueCount: Int get() = allSlots.size - solvedSlotIDs.size

    val filledPlayableCount: Int get() = grid.sumOf { row -> row.count { !it.isBlock && it.entry != null } }

    val totalPlayableCount: Int get() = grid.sumOf { row -> row.count { !it.isBlock } }

    // MARK: - Timing

    fun elapsed(): Int = accumulatedSeconds

    /**
     * Advance the clock from a rendered tick. Only while visible and
     * unsuppressed; each delta is capped just above the 1 s cadence, so any
     * stretch where the screen wasn't ticking counts for at most one tick.
     */
    fun tick(nowMillis: Long) {
        if (isComplete) return
        if (!isVisible || isTimerSuppressed) {
            lastTickMillis = null
            return
        }
        val last = lastTickMillis
        lastTickMillis = nowMillis
        if (last == null) return
        val delta = (nowMillis - last) / 1000.0
        if (delta <= 0) return
        tickFraction += min(delta, MAX_TICK_DELTA_SECONDS)
        val whole = tickFraction.toInt()
        if (whole > 0) {
            accumulatedSeconds += whole
            tickFraction -= whole
            maybeNudgeStall()
            bump()
        }
    }

    /**
     * The stall watch, tiered by fill. At or above 40% the offer is chosen
     * from the grid and re-arms after each input, up to the cap; below it,
     * after a shorter idle, a free letter — once per sitting.
     */
    private fun maybeNudgeStall() {
        if (!stallNudgeEnabled || isComplete || isStallNudgeActive) return
        val idle = accumulatedSeconds - lastInputSeconds
        val total = totalPlayableCount
        if (total <= 0) return
        if (filledPlayableCount.toDouble() / total >= MID_SOLVE_FILL_THRESHOLD) {
            if (midSolveNudgeCount >= MAX_MID_SOLVE_NUDGES || idle < stallNudgeSeconds) return
            midSolveNudgeCount += 1
            stallNudgeKind = midSolveRescueKind
        } else {
            if (earlyNudged || idle < earlyNudgeSeconds) return
            earlyNudged = true
            stallNudgeKind = StallNudgeKind.FREE_LETTER
        }
        isStallNudgeActive = true
        stallNudgeTick += 1
    }

    /** Wrong letters the player can't see yet → check; else the passage, free, when the clue has one; else a free letter. */
    val midSolveRescueKind: StallNudgeKind
        get() = when {
            unmarkedWrongEntryCount > 0 -> StallNudgeKind.CHECK_ANSWERS
            activeSlot?.reference != null -> StallNudgeKind.READ_VERSE
            else -> StallNudgeKind.FREE_LETTER
        }

    /** Filled cells that are wrong and not yet marked as such. */
    val unmarkedWrongEntryCount: Int
        get() = grid.sumOf { row -> row.count { !it.isBlock && it.entry != null && !it.isCorrect && !it.isCheckedWrong } }

    /** Takes the nudge line down for an action that doesn't touch the grid. Counts as input. */
    fun acknowledgeStallNudge() {
        noteInput()
        bump()
    }

    /** Seed cumulative time from a saved record. Resuming is not idling. */
    fun seedElapsed(seconds: Int) {
        accumulatedSeconds = seconds.coerceAtLeast(0)
        lastInputSeconds = accumulatedSeconds
        lastTickMillis = null
    }

    /** Drop the tick baseline so the gap until the next tick counts nothing. */
    fun pauseTimer() {
        lastTickMillis = null
    }

    // MARK: - Resume snapshot

    /**
     * Committed (pen) letters only; lowercase marks a hint-revealed cell, and
     * a gifted one carries [EntriesCodec.GIFT_MARKER] on top of the lock.
     */
    fun snapshot(): Map<String, String> {
        val out = LinkedHashMap<String, String>()
        for (row in grid) for (c in row) {
            if (c.isBlock || c.isPencil) continue
            val entry = c.entry ?: continue
            out[c.pos.storageKey] = when {
                !c.isRevealed -> entry.toString()
                c.isGift -> entry.toString().lowercase() + EntriesCodec.GIFT_MARKER
                else -> entry.toString().lowercase()
            }
        }
        return out
    }

    /** Provisional (pencil) letters, keyed like [snapshot]. */
    fun pencilSnapshot(): Map<String, String> {
        val out = LinkedHashMap<String, String>()
        for (row in grid) for (c in row) {
            if (c.isBlock || !c.isPencil) continue
            val entry = c.entry ?: continue
            out[c.pos.storageKey] = entry.toString()
        }
        return out
    }

    fun restore(entries: Map<String, String>, pencil: Map<String, String> = emptyMap()) {
        for ((key, value) in entries) {
            val pos = GridPos.fromStorageKey(key) ?: continue
            val raw = value.firstOrNull() ?: continue
            val letter = value.uppercase().firstOrNull() ?: continue
            if (pos.row !in 0 until size || pos.col !in 0 until size || cell(pos).isBlock) continue
            set(pos) {
                it.copy(
                    entry = letter,
                    isRevealed = raw.isLowerCase(),
                    isGift = EntriesCodec.isGift(value),
                )
            }
        }
        for ((key, value) in pencil) {
            val pos = GridPos.fromStorageKey(key) ?: continue
            val letter = value.uppercase().firstOrNull() ?: continue
            if (pos.row !in 0 until size || pos.col !in 0 until size || cell(pos).isBlock) continue
            if (cell(pos).entry != null) continue // pen letters win
            set(pos) { it.copy(entry = letter, isPencil = true) }
        }
        checkCompletion(announceFullMiss = false)
        seedSolvedSlots()
        // Resume on work, not on a done word (the gifted starter is the common case).
        if (!isComplete) {
            val slot = activeSlot
            if (slot != null && slot.positions.none { cell(it).entry == null }) {
                advanceToNextIncompleteSlot(slot)
            }
        }
        bump()
    }

    companion object {
        const val STANDARD_STALL_NUDGE_SECONDS = 45
        const val LEARNING_STALL_NUDGE_SECONDS = 20
        const val EARLY_NUDGE_CAP = 30
        const val LEARNING_EARLY_NUDGE_SECONDS = 12
        const val MAX_MID_SOLVE_NUDGES = 3
        const val MID_SOLVE_FILL_THRESHOLD = 0.40
        const val MAX_TICK_DELTA_SECONDS = 1.5
        const val STARTER_LETTER_INTERVAL_MS = 170L

        fun defaultStallNudgeSeconds(learning: Boolean): Int =
            if (learning) LEARNING_STALL_NUDGE_SECONDS else STANDARD_STALL_NUDGE_SECONDS

        /** The `autoCheckErrors` seed rule: ON inside the learning window, OFF after. */
        fun seedAutoCheck(totalCompleted: Int): Boolean = totalCompleted < 3
    }
}
