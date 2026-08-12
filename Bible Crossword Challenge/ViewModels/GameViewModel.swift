//
//  GameViewModel.swift
//  Bible Crossword Challenge
//
//  The crossword engine: builds the grid and word slots from a Puzzle, tracks
//  selection/entry, validates answers, and exposes hint actions. It is fully
//  persistence-agnostic so it can be unit tested in isolation — the owning view
//  handles loading/saving and side effects via the callbacks below.
//

import SwiftUI
import Observation

enum HintType: String {
    case letter
    case word
}

@Observable
final class GameViewModel {
    let puzzle: Puzzle
    let size: Int

    /// size x size grid of cells (blocks included).
    private(set) var grid: [[CellState]]

    let acrossSlots: [Slot]
    let downSlots: [Slot]

    var selected: GridPos
    var direction: ClueDirection
    var showErrors: Bool = false
    /// Persistent as-you-type mistake marking, mirrored from the
    /// "autoCheckErrors" default by the owning view. Unlike the manual check
    /// (`showErrors`, cleared on the next keystroke), this stays on and marks
    /// only *wrong* letters — correct ones earn nothing until the word
    /// completes, so it can't be milked as a free answer-by-color oracle.
    var autoCheck: Bool = false
    private(set) var hintsUsed: Int = 0
    private(set) var isComplete: Bool = false

    /// Immutable creation time — used only as the `TimelineView` cadence anchor.
    let startDate: Date
    private(set) var completionSeconds: Int = 0

    // Active-time accounting. The clock advances only from render ticks of the
    // visible toolbar timer (see `tick(now:)`), so time on other tabs, under
    // covers, or in the background never accrues. Survives across sessions, so
    // the recorded solve time is the sum of every sitting.
    private(set) var accumulatedSeconds: Int = 0
    private var lastTick: Date?
    /// Sub-second remainder carried between ticks so the clock doesn't drift.
    private var tickFraction: Double = 0
    /// True while the game screen's UIView is attached to a window — the only
    /// reliable "actually on screen" signal. SwiftUI can keep hidden tab
    /// content alive and rendering (ticks keep arriving), and can prewarm
    /// navigation destinations that were never shown; both must not count.
    var isAttachedToWindow = false

    // Side-effect callbacks owned by the view.
    var onComplete: ((Int) -> Void)?
    var onEntryChanged: (() -> Void)?
    /// Fired with the word the moment the player fills it in correctly. The view
    /// uses it to flash the word's cells, play feedback, and announce the solve
    /// to VoiceOver.
    var onWordCompleted: ((Slot) -> Void)?

    private var slotIndex: [ClueDirection: [GridPos: Int]] = [.across: [:], .down: [:]]

    /// Slot ids whose cells are all filled correctly. Tracks the transition into
    /// "solved" so the word-complete flash fires once, not on every keystroke.
    private var solvedSlotIDs: Set<String> = []

    /// Monotonic count of word-solve moments this session (including the final
    /// solve). Observable trigger for UI that reacts to each solve, e.g. the
    /// toolbar streak-flame pulse.
    private(set) var wordSolveTick = 0

    /// Increments each time the grid transitions into "every square filled but
    /// at least one letter wrong" — the moment a player would otherwise sit
    /// stranded wondering why nothing happened. The view reacts with a nudge.
    private(set) var gridFullWithErrorsTick = 0
    private var wasFullWithErrors = false

    init(puzzle: Puzzle, now: Date = Date()) {
        self.puzzle = puzzle
        self.size = puzzle.size
        self.startDate = now

        // Build slots from clue data.
        var across: [Slot] = []
        var down: [Slot] = []
        for clue in puzzle.clues {
            let slot = Slot(
                number: clue.number,
                direction: clue.direction,
                clue: clue.text,
                answer: clue.answer.uppercased(),
                positions: clue.positions,
                reference: clue.reference
            )
            if clue.direction == .across { across.append(slot) } else { down.append(slot) }
        }
        across.sort { $0.number < $1.number }
        down.sort { $0.number < $1.number }
        self.acrossSlots = across
        self.downSlots = down

        // Numbers per starting cell.
        var numbers: [GridPos: Int] = [:]
        for clue in puzzle.clues { numbers[clue.start] = clue.number }

        // Build the cell grid from the solution rows.
        let rows = puzzle.grid.map { Array($0.uppercased()) }
        var cells: [[CellState]] = []
        for r in 0..<size {
            var rowCells: [CellState] = []
            for c in 0..<size {
                let pos = GridPos(row: r, col: c)
                let ch: Character = (r < rows.count && c < rows[r].count) ? rows[r][c] : "."
                let isBlock = (ch == ".")
                rowCells.append(CellState(
                    pos: pos,
                    isBlock: isBlock,
                    solution: isBlock ? nil : ch,
                    number: numbers[pos],
                    entry: nil
                ))
            }
            cells.append(rowCells)
        }
        self.grid = cells

        // Position -> slot index lookup.
        var acrossIdx: [GridPos: Int] = [:]
        for (i, slot) in across.enumerated() { for p in slot.positions { acrossIdx[p] = i } }
        var downIdx: [GridPos: Int] = [:]
        for (i, slot) in down.enumerated() { for p in slot.positions { downIdx[p] = i } }
        self.slotIndex = [.across: acrossIdx, .down: downIdx]

        // Initial selection: first across slot, else first down, else origin.
        if let first = across.first {
            self.selected = first.positions[0]
            self.direction = .across
        } else if let first = down.first {
            self.selected = first.positions[0]
            self.direction = .down
        } else {
            self.selected = GridPos(row: 0, col: 0)
            self.direction = .across
        }
    }

    // MARK: - Derived state

    var allSlots: [Slot] { acrossSlots + downSlots }

    func cell(at pos: GridPos) -> CellState {
        grid[pos.row][pos.col]
    }

    var activeSlot: Slot? {
        slot(at: selected, direction: direction) ?? slot(at: selected, direction: direction.toggled)
    }

    var activeWordPositions: Set<GridPos> {
        Set(activeSlot?.positions ?? [])
    }

    private func slot(at pos: GridPos, direction: ClueDirection) -> Slot? {
        guard let idx = slotIndex[direction]?[pos] else { return nil }
        return direction == .across ? acrossSlots[idx] : downSlots[idx]
    }

    func isSelectable(_ pos: GridPos) -> Bool {
        !grid[pos.row][pos.col].isBlock
    }

    // MARK: - Selection

    func select(_ pos: GridPos) {
        guard isSelectable(pos) else { return }
        if pos == selected {
            toggleDirection()
            return
        }
        selected = pos
        // Prefer a direction that actually has a word at this cell.
        if slot(at: pos, direction: direction) == nil,
           slot(at: pos, direction: direction.toggled) != nil {
            direction = direction.toggled
        }
        showErrors = false
    }

    func toggleDirection() {
        if slot(at: selected, direction: direction.toggled) != nil {
            direction = direction.toggled
        }
    }

    func select(slot: Slot) {
        direction = slot.direction
        // Land on the first empty cell, else the first cell.
        selected = slot.positions.first { grid[$0.row][$0.col].entry == nil } ?? slot.positions[0]
        showErrors = false
    }

    // MARK: - Clue navigation

    func advanceClue(by offset: Int) {
        let ordered = acrossSlots + downSlots
        guard !ordered.isEmpty, let current = activeSlot,
              let idx = ordered.firstIndex(of: current) else { return }
        let next = ordered[((idx + offset) % ordered.count + ordered.count) % ordered.count]
        select(slot: next)
    }

    // MARK: - Entry

    func enter(_ letter: Character) {
        guard isSelectable(selected) else { return }
        // Hint-revealed cells are locked — typing skips over them instead of
        // destroying a letter the player paid for.
        guard !grid[selected.row][selected.col].isRevealed else {
            advanceWithinWord()
            return
        }
        let upper = Character(letter.uppercased())
        let edited = selected
        grid[edited.row][edited.col].entry = upper
        showErrors = false
        onEntryChanged?()
        checkCompletion()
        if !isComplete {
            refreshSolvedSlots(around: [edited])
            advanceWithinWord()
        }
    }

    func delete() {
        var cleared: GridPos?
        let current = grid[selected.row][selected.col]
        if current.entry != nil, !current.isRevealed {
            grid[selected.row][selected.col].entry = nil
            cleared = selected
        } else if let prev = previousCellInWord() {
            // Step back; clear the previous cell unless it's a locked reveal.
            selected = prev
            if grid[prev.row][prev.col].entry != nil, !grid[prev.row][prev.col].isRevealed {
                grid[prev.row][prev.col].entry = nil
                cleared = prev
            }
        }
        showErrors = false
        onEntryChanged?()
        if let cleared {
            refreshSolvedSlots(around: [cleared])
            // The grid is no longer full, so the next fill-with-errors moment
            // should announce again (checkCompletion isn't run on deletes).
            wasFullWithErrors = false
        }
    }

    private func advanceWithinWord() {
        guard let slot = activeSlot,
              let idx = slot.positions.firstIndex(of: selected) else { return }
        // Next empty cell after the current one, else the immediate next cell.
        if let nextEmpty = slot.positions[(idx + 1)...].first(where: { grid[$0.row][$0.col].entry == nil }) {
            selected = nextEmpty
        } else if idx + 1 < slot.positions.count {
            selected = slot.positions[idx + 1]
        } else if let gap = slot.positions.first(where: { grid[$0.row][$0.col].entry == nil }) {
            // At the word's end with a gap left behind (the player jumped in
            // mid-word): wrap back to it.
            selected = gap
        } else {
            // Word is full: move on to the next word that still needs letters.
            advanceToNextIncompleteSlot(after: slot)
        }
    }

    /// Select the next slot (in across-then-down order, wrapping) that still
    /// has at least one empty cell. No-op when every remaining cell is filled.
    private func advanceToNextIncompleteSlot(after slot: Slot) {
        let ordered = acrossSlots + downSlots
        guard let idx = ordered.firstIndex(of: slot) else { return }
        for step in 1..<ordered.count {
            let candidate = ordered[(idx + step) % ordered.count]
            if candidate.positions.contains(where: { grid[$0.row][$0.col].entry == nil }) {
                select(slot: candidate)
                return
            }
        }
    }

    private func previousCellInWord() -> GridPos? {
        guard let slot = activeSlot,
              let idx = slot.positions.firstIndex(of: selected), idx > 0 else { return nil }
        return slot.positions[idx - 1]
    }

    // MARK: - Hints

    @discardableResult
    func revealLetter() -> Bool {
        // A hint must always buy progress: if the selected cell already holds
        // the right letter, fall back to the active word's first not-yet-correct
        // cell; if the whole word is correct, refuse (the caller refunds).
        var target = selected
        if !isSelectable(target) || grid[target.row][target.col].isCorrect {
            guard let fallback = activeSlot?.positions.first(where: { !grid[$0.row][$0.col].isCorrect }) else {
                return false
            }
            target = fallback
        }
        guard let solution = grid[target.row][target.col].solution else { return false }
        selected = target
        grid[target.row][target.col].entry = solution
        grid[target.row][target.col].isRevealed = true
        hintsUsed += 1
        onEntryChanged?()
        checkCompletion()
        if !isComplete {
            refreshSolvedSlots(around: [target])
            advanceWithinWord()
        }
        return true
    }

    @discardableResult
    func revealWord() -> Bool {
        // Refuse when the word is already fully correct — no progress to buy.
        guard let slot = activeSlot, !slotSolved(slot) else { return false }
        for (i, pos) in slot.positions.enumerated() {
            let ch = Array(slot.answer)[i]
            // Leave the player's own correct letters alone (and unlocked).
            guard grid[pos.row][pos.col].entry != ch else { continue }
            grid[pos.row][pos.col].entry = ch
            grid[pos.row][pos.col].isRevealed = true
        }
        hintsUsed += 1
        onEntryChanged?()
        checkCompletion()
        if !isComplete { refreshSolvedSlots(around: slot.positions) }
        return true
    }

    // MARK: - Word completion tracking

    private func slotSolved(_ slot: Slot) -> Bool {
        for p in slot.positions {
            let cell = grid[p.row][p.col]
            if cell.entry == nil || cell.entry != cell.solution { return false }
        }
        return true
    }

    /// The (deduplicated) slots passing through any of `positions`.
    private func slotsContaining(_ positions: [GridPos]) -> [Slot] {
        var seen = Set<String>()
        var result: [Slot] = []
        for p in positions {
            if let i = slotIndex[.across]?[p], seen.insert(acrossSlots[i].id).inserted {
                result.append(acrossSlots[i])
            }
            if let i = slotIndex[.down]?[p], seen.insert(downSlots[i].id).inserted {
                result.append(downSlots[i])
            }
        }
        return result
    }

    /// Re-evaluate the words touching `positions`, firing `onWordCompleted` for
    /// any that just became fully correct. Pass `silent` to seed the bookkeeping
    /// without firing (used when restoring saved progress).
    private func refreshSolvedSlots(around positions: [GridPos], silent: Bool = false) {
        for slot in slotsContaining(positions) {
            if slotSolved(slot) {
                if solvedSlotIDs.insert(slot.id).inserted, !silent {
                    wordSolveTick += 1
                    onWordCompleted?(slot)
                }
            } else {
                solvedSlotIDs.remove(slot.id)
            }
        }
    }

    /// Reseed solved-word bookkeeping from the whole grid without firing, so
    /// pre-filled words don't flash on the next keystroke after a restore.
    private func seedSolvedSlots() {
        solvedSlotIDs.removeAll()
        for slot in allSlots where slotSolved(slot) { solvedSlotIDs.insert(slot.id) }
    }

    // MARK: - Validation

    func toggleCheck() {
        showErrors.toggle()
    }

    /// Completes the puzzle when every playable cell holds the correct letter.
    /// Also watches for the "grid full but wrong" moment, announced via
    /// `gridFullWithErrorsTick` on the transition into that state. Pass
    /// `announceFullMiss: false` when restoring, so resuming a full-but-wrong
    /// grid seeds the bookkeeping without greeting the player with an alert.
    func checkCompletion(announceFullMiss: Bool = true) {
        var full = true
        var correct = true
        for row in grid {
            for cell in row where !cell.isBlock {
                if cell.entry == nil { full = false }
                if cell.entry != cell.solution { correct = false }
            }
        }
        guard correct else {
            if full, !wasFullWithErrors, announceFullMiss {
                gridFullWithErrorsTick += 1
            }
            wasFullWithErrors = full
            return
        }
        guard !isComplete else { return }
        isComplete = true
        // The final word skips refreshSolvedSlots (see enter), so pulse here.
        wordSolveTick += 1
        pauseTimer() // freeze the clock at the solve moment
        completionSeconds = accumulatedSeconds
        onComplete?(completionSeconds)
    }

    var hasAnyEntries: Bool {
        grid.contains { row in row.contains { !$0.isBlock && $0.entry != nil } }
    }

    /// True when any filled cell holds the wrong letter — drives the check shake.
    var hasVisibleErrors: Bool {
        grid.contains { row in
            row.contains { !$0.isBlock && $0.entry != nil && $0.entry != $0.solution }
        }
    }

    /// Words not yet fully correct. Drives the "2 clues to go" encouragement —
    /// counts *solved* words (not filled), so a grid full of guesses doesn't
    /// congratulate anyone.
    var remainingClueCount: Int {
        allSlots.count - solvedSlotIDs.count
    }

    var filledPlayableCount: Int {
        grid.reduce(0) { acc, row in
            acc + row.filter { !$0.isBlock && $0.entry != nil }.count
        }
    }

    var totalPlayableCount: Int {
        grid.reduce(0) { acc, row in acc + row.filter { !$0.isBlock }.count }
    }

    // MARK: - Timing
    //
    // Tick-driven: the toolbar timer's `TimelineView` reports each rendered
    // tick via `tick(now:)`. `TimelineView` pauses whenever it isn't actually
    // on screen, and each delta is capped near the 1s cadence, so hidden time
    // can never leak into the clock — no lifecycle events required. (Events
    // like tab switches don't reach hidden views anyway, which is why a
    // pause/resume model can't work here.)

    /// Total active seconds so far.
    func elapsed() -> Int { accumulatedSeconds }

    /// Advance the clock from a rendered timer tick. The delta since the last
    /// tick is capped just above the 1s cadence, so any stretch where the
    /// timer wasn't rendering counts for at most one tick.
    func tick(now: Date) {
        guard !isComplete else { return }
        guard isAttachedToWindow else {
            lastTick = nil
            return
        }
        defer { lastTick = now }
        guard let last = lastTick else { return }
        let delta = now.timeIntervalSince(last)
        guard delta > 0 else { return }
        tickFraction += min(delta, 1.5)
        let whole = Int(tickFraction)
        if whole > 0 {
            accumulatedSeconds += whole
            tickFraction -= Double(whole)
        }
    }

    /// Seed cumulative time from a saved record when resuming an in-progress
    /// puzzle. The clock starts counting again from the next rendered tick.
    func seedElapsed(_ seconds: Int) {
        accumulatedSeconds = max(0, seconds)
        lastTick = nil
    }

    /// Drop the tick baseline (e.g. on backgrounding or at the solve moment)
    /// so the gap until the next rendered tick counts nothing.
    func pauseTimer() {
        lastTick = nil
    }

    #if DEBUG
    /// Development-only: fill every playable cell with its solution and trigger
    /// completion. Used to capture the completion screen for App Store assets.
    func autoSolve() {
        for r in 0..<size {
            for c in 0..<size where !grid[r][c].isBlock {
                grid[r][c].entry = grid[r][c].solution
            }
        }
        onEntryChanged?()
        checkCompletion()
    }

    /// Development-only: fill every cell with its solution and show the correct
    /// (green) state WITHOUT triggering completion, so the solved grid stays
    /// visible for App Store screenshots.
    func fillSolvedNoComplete() {
        for r in 0..<size {
            for c in 0..<size where !grid[r][c].isBlock {
                grid[r][c].entry = grid[r][c].solution
            }
        }
        showErrors = true
        onEntryChanged?()
    }

    /// Development-only: fill roughly `fraction` of the grid correctly, leaving
    /// the rest empty — the mid-solve state App Store screenshots need.
    ///
    /// Fills *whole answers* rather than a scattering of letters, because that
    /// is what a real half-finished grid looks like: someone works a clue at a
    /// time, so the empty cells cluster into the words they haven't cracked yet.
    /// A percentage of randomly-chosen cells reads as a bug, not as progress.
    ///
    /// Selection lands on the first word still outstanding, so the clue bar
    /// shows something being worked on rather than something already solved.
    func fillPartial(fraction: Double = 0.5) {
        let playable = grid.flatMap { $0 }.filter { !$0.isBlock }.count
        guard playable > 0 else { return }
        let target = Int((Double(playable) * fraction).rounded())

        var filled = 0
        for slot in acrossSlots {
            guard filled < target else { break }
            for (i, pos) in slot.positions.enumerated() {
                guard grid[pos.row][pos.col].entry == nil else { continue }
                grid[pos.row][pos.col].entry = Array(slot.answer)[i]
                filled += 1
            }
        }

        seedSolvedSlots()
        // Green ticks on what's done. Every filled letter came from the answer,
        // so this can only render as correct.
        showErrors = true
        if let next = acrossSlots.first(where: { !slotSolved($0) }) {
            direction = .across
            selected = next.positions.first { grid[$0.row][$0.col].entry == nil }
                ?? next.positions[0]
        }
        onEntryChanged?()
    }
    #endif

    // MARK: - Resume snapshot

    func snapshot() -> [String: String] {
        var out: [String: String] = [:]
        for row in grid {
            for cell in row where !cell.isBlock {
                if let entry = cell.entry {
                    // Lowercase marks a hint-revealed (locked) cell, so the lock
                    // survives relaunch without a record-schema change.
                    out[cell.pos.storageKey] = cell.isRevealed
                        ? String(entry).lowercased()
                        : String(entry)
                }
            }
        }
        return out
    }

    /// Seeds the "autoCheckErrors" default the first time it's consulted:
    /// ON for a player still inside their first three solves, OFF for anyone
    /// who learned the grid without it — flipping a veteran's game behavior
    /// under them is worse than making a beginner find a toggle. Called from
    /// every surface that reads the key, so whichever screen is seen first
    /// (game or Profile) agrees with the others.
    static func seedAutoCheckIfNeeded(totalCompleted: Int) {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: "autoCheckErrors") == nil else { return }
        defaults.set(totalCompleted < 3, forKey: "autoCheckErrors")
    }

    func restore(_ entries: [String: String]) {
        for (key, value) in entries {
            let parts = key.split(separator: ",").compactMap { Int($0) }
            guard parts.count == 2, let raw = value.first,
                  let letter = value.uppercased().first else { continue }
            let r = parts[0], c = parts[1]
            guard r >= 0, r < size, c >= 0, c < size, !grid[r][c].isBlock else { continue }
            grid[r][c].entry = letter
            grid[r][c].isRevealed = raw.isLowercase
        }
        checkCompletion(announceFullMiss: false)
        seedSolvedSlots()
    }
}
