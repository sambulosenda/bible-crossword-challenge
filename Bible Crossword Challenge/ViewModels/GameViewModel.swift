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
    /// Opens the passage the answer comes from instead of touching the grid —
    /// the player finds the word in Scripture themselves. Only offered on
    /// clues that carry a `reference`.
    case verse
    /// Fills the whole grid — the give-up button. Confirmed before use.
    case puzzle

    /// The rung's name, as the menu lists it.
    ///
    /// Here rather than in the view because two surfaces say it now — the menu
    /// row and the wall that refuses it — and a wall naming a rung the menu
    /// calls something else is worse than a wall that names nothing.
    var title: String {
        switch self {
        case .verse: "Show the Verse"
        case .letter: "Reveal Letter"
        case .word: "Reveal Word"
        case .puzzle: "Reveal Puzzle"
        }
    }

    /// Daily-quota cost. The ladder: verse is free (the player still does the
    /// finding — and reading Scripture is the point), a letter is the standard
    /// unit, a whole word — nearly an answer button — costs two, and the
    /// give-up fill costs the entire 3/day pool.
    var cost: Int {
        switch self {
        case .verse: 0
        case .letter: 1
        case .word: 2
        case .puzzle: 3
        }
    }
}

/// Granularity of a one-shot answer check. Checks are free and never reveal:
/// they mark wrong filled letters, which is a different economy from hints.
enum CheckScope: String {
    case letter
    case word
    case puzzle
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
    /// Pencil (provisional) entry mode, toggled from the keyboard. Letters
    /// typed while on land as `isPencil` and never complete anything.
    var isPencilMode: Bool = false
    /// Persistent as-you-type mistake marking, mirrored from the
    /// "autoCheckErrors" default by the owning view. Unlike the one-shot
    /// checks (whose wrong-marks clear when the cell is edited), this stays on
    /// and marks only *wrong* letters — correct ones earn nothing until the
    /// word completes, so it can't be milked as a free answer-by-color oracle.
    var autoCheck: Bool = false
    #if DEBUG
    /// Screenshot-only: paints correct cells green without a check action.
    var showCorrectOverlay: Bool = false
    #endif
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
    /// True while the verse-hint reader sheet is up. A sheet leaves the grid
    /// attached and rendering, so window attachment alone can't stop the
    /// clock — and time spent reading Scripture must not count against the
    /// solve.
    var isTimerSuppressed = false

    // Side-effect callbacks owned by the view.
    var onComplete: ((Int) -> Void)?
    var onEntryChanged: (() -> Void)?
    /// Fired with the word the moment the player fills it in correctly. The view
    /// uses it to flash the word's cells, play feedback, and announce the solve
    /// to VoiceOver.
    var onWordCompleted: ((Slot) -> Void)?
    /// Fired after a one-shot check with the correct positions (for a brief
    /// green flash) and how many cells were marked wrong (for the shake).
    var onCheckResult: (([GridPos], Int) -> Void)?

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

    /// Increments when typing lands on a hint-revealed (locked) cell. The
    /// letter is skipped to protect what the player paid for, but the skip
    /// was silent — a new player typing into their gifted word saw nothing
    /// happen and read it as the keyboard being broken. The view reacts with
    /// a brief flash on `lockedEntryPos` and a haptic.
    private(set) var lockedEntryTick = 0
    private(set) var lockedEntryPos: GridPos?

    /// Increments when the player has been idle long enough on the active
    /// clock that abandonment data says walking away comes next. Two tiers:
    ///
    /// - The mid-solve tier (≥ 40% fill, `stallNudgeSeconds` idle): there's
    ///   material on the grid. The kind is chosen from the grid's state — see
    ///   `midSolveRescueKind` — and the tier re-arms after every input, up to
    ///   `maxMidSolveNudges` per sitting. It used to fire once, after 75s: in
    ///   the 30 days to 2026-09-02 the 50–74% band logged 175 abandons and 17
    ///   nudges, because players left before the single nudge was due. 88 of
    ///   the 92 abandons never finished had used no hint that sitting — the
    ///   stuck player does not ask, so the offer has to come sooner and again.
    ///   The 75% gate this shipped with missed most of the stuck players
    ///   (see 2026-08-23 histogram in git history), hence 40%.
    /// - `.freeLetter` (< 40% fill, `earlyNudgeSeconds` idle, once): the early
    ///   stall. 43% of abandons in the 30 days to 2026-08-28 happened under
    ///   10% fill, and no help could fire there: the check nudge needs fill,
    ///   the hint menu is an unlabeled glyph. Nothing to check yet — the
    ///   useful action is a foothold, so the tap buys a letter free of quota.
    ///
    /// The view reacts with a quiet action line and logs the impression.
    private(set) var stallNudgeTick = 0
    /// Which action the nudge line offers — drives its copy and tap action.
    enum StallNudgeKind: String {
        case checkAnswers = "check"
        case readVerse = "verse"
        case freeLetter = "free_letter"
    }
    private(set) var stallNudgeKind: StallNudgeKind = .checkAnswers
    /// True from the stall moment until the next input clears it — drives the
    /// nudge line's visibility.
    private(set) var isStallNudgeActive = false
    /// Mid-solve nudges fired this sitting. Capped so a nudge stays a nudge.
    private(set) var midSolveNudgeCount = 0
    static let maxMidSolveNudges = 3
    private var earlyNudged = false
    /// Active seconds at the last player input. Measured on the solve clock,
    /// not wall time, so backgrounded or verse-reading stretches never count
    /// as "stuck".
    private var lastInputSeconds = 0
    /// Idle threshold before the check-answers stall nudge fires. Grid must
    /// also be ≥ 40% filled — the same fill convention `puzzle_abandoned`
    /// reports.
    let stallNudgeSeconds: Int
    /// Idle threshold for the early (< 40% fill) free-letter nudge. Shorter
    /// than the check tier: the quick-close cohort it exists for is mostly
    /// gone by a minute. Never longer than `stallNudgeSeconds`, so the DEBUG
    /// `-uiStallNudgeSeconds` override shortens both tiers together.
    var earlyNudgeSeconds: Int {
        min(isLearning ? Self.learningEarlyNudgeSeconds : Self.earlyNudgeCap, stallNudgeSeconds)
    }

    /// A player inside the learning window (under three completions — the
    /// same gate as free hints and the starter word). Their thresholds are
    /// shorter because their sittings are: on 2.0–2.6 builds, day-0
    /// non-finishers spent 1–40 active seconds on the grid before leaving
    /// under 10% fill (30 of 65 abandons to 2026-09-03), and the 40%+ band
    /// sat 40–250s. The 30s/45s tiers fired for 5 of those 35 players. The
    /// nudge has to arrive inside the patience they actually have.
    let isLearning: Bool

    /// The stall-nudge holdout (`FeatureFlag.stallNudge`), resolved by the
    /// creating view. A plain Bool so this model — and its tests — never
    /// touches the flag SDK; a control-group device simply never nudges.
    ///
    /// Gates *both* tiers. The holdout's question is whether the rescue helps
    /// at all, and a control group that still got the early free letter would
    /// be answering a different one.
    let stallNudgeEnabled: Bool

    /// Mid-solve idle threshold for everyone past the learning window.
    static let standardStallNudgeSeconds = 45
    /// Mid-solve idle threshold inside the learning window.
    static let learningStallNudgeSeconds = 20
    /// Early (< 40% fill) idle threshold past the learning window.
    static let earlyNudgeCap = 30
    /// Early idle threshold inside the learning window.
    static let learningEarlyNudgeSeconds = 12

    static func defaultStallNudgeSeconds(learning: Bool) -> Int {
        learning ? learningStallNudgeSeconds : standardStallNudgeSeconds
    }

    /// Active seconds since the last player input — for nudge analytics.
    var secondsSinceLastInput: Int { accumulatedSeconds - lastInputSeconds }

    init(
        puzzle: Puzzle,
        learning: Bool = false,
        now: Date = Date(),
        stallNudgeEnabled: Bool = true
    ) {
        self.puzzle = puzzle
        self.size = puzzle.size
        self.startDate = now
        self.isLearning = learning
        self.stallNudgeEnabled = stallNudgeEnabled

        #if DEBUG
        // `-uiStallNudgeSeconds 5` shortens the stall wait for UI testing —
        // same family as -uiRotationDate.
        let args = ProcessInfo.processInfo.arguments
        if let flag = args.firstIndex(of: "-uiStallNudgeSeconds"), flag + 1 < args.count,
           let secs = Int(args[flag + 1]), secs > 0 {
            self.stallNudgeSeconds = secs
        } else {
            self.stallNudgeSeconds = Self.defaultStallNudgeSeconds(learning: learning)
        }
        #else
        // 45, down from 75: the mid-fill abandoner's median sitting was ~5
        // minutes, and the old nudge fired in 17 of 175 such abandons. 20 in
        // the learning window — see `isLearning`.
        self.stallNudgeSeconds = Self.defaultStallNudgeSeconds(learning: learning)
        #endif

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

        // Initial selection: the shortest answer in the grid, not 1 Across.
        // The empty grid is where a third of abandons happen (200 of 496 in
        // the 30 days to 2026-08-23 quit under 10% fill, ~23s in): opening on
        // the puzzle's easiest foothold gives that player a first win instead
        // of a first wall. Ties go across-then-lower-number, so grids whose
        // shortest answer is 1 Across behave exactly as before. A resumed
        // puzzle restores entries but keeps this selection — same as the old
        // 1-Across start, which never followed progress either.
        if let easiest = (across + down).min(by: {
            ($0.answer.count, $0.direction == .down ? 1 : 0, $0.number)
                < ($1.answer.count, $1.direction == .down ? 1 : 0, $1.number)
        }) {
            self.selected = easiest.positions[0]
            self.direction = easiest.direction
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

    // MARK: - Input bookkeeping

    /// Every deliberate player action lands here: it resets the stall clock
    /// and dismisses an active stall nudge (acting *is* unsticking).
    private func noteInput() {
        lastInputSeconds = accumulatedSeconds
        isStallNudgeActive = false
    }

    // MARK: - Selection

    func select(_ pos: GridPos) {
        guard isSelectable(pos) else { return }
        noteInput()
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
    }

    func toggleDirection() {
        if slot(at: selected, direction: direction.toggled) != nil {
            direction = direction.toggled
        }
    }

    func select(slot: Slot) {
        noteInput()
        direction = slot.direction
        // Land on the first empty cell, else the first cell.
        selected = slot.positions.first { grid[$0.row][$0.col].entry == nil } ?? slot.positions[0]
    }

    /// Hardware-keyboard cursor movement (iPad / Bluetooth): one step in the
    /// given direction, walking over blocks to the next playable cell and
    /// stopping at the grid's edge. Routed through `select`, so the typing
    /// direction keeps its usual follow-the-word behaviour — and never lands
    /// on the current cell, so a held arrow can't toggle across/down.
    func moveSelection(rowDelta: Int, colDelta: Int) {
        var r = selected.row + rowDelta
        var c = selected.col + colDelta
        while r >= 0, r < size, c >= 0, c < size {
            if !grid[r][c].isBlock {
                select(GridPos(row: r, col: c))
                return
            }
            r += rowDelta
            c += colDelta
        }
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
        noteInput()
        // Hint-revealed cells are locked — typing skips over them instead of
        // destroying a letter the player paid for. Announced, not silent:
        // see `lockedEntryTick`.
        guard !grid[selected.row][selected.col].isRevealed else {
            lockedEntryPos = selected
            lockedEntryTick += 1
            advanceWithinWord()
            return
        }
        let upper = Character(letter.uppercased())
        let edited = selected
        grid[edited.row][edited.col].entry = upper
        grid[edited.row][edited.col].isPencil = isPencilMode
        grid[edited.row][edited.col].isCheckedWrong = false
        onEntryChanged?()
        checkCompletion()
        if !isComplete {
            refreshSolvedSlots(around: [edited])
            advanceWithinWord()
        }
    }

    func delete() {
        noteInput()
        var cleared: GridPos?
        let current = grid[selected.row][selected.col]
        if current.entry != nil, !current.isRevealed {
            clearCell(selected)
            cleared = selected
        } else if let prev = previousCellInWord() {
            // Step back; clear the previous cell unless it's a locked reveal.
            selected = prev
            if grid[prev.row][prev.col].entry != nil, !grid[prev.row][prev.col].isRevealed {
                clearCell(prev)
                cleared = prev
            }
        }
        onEntryChanged?()
        if let cleared {
            refreshSolvedSlots(around: [cleared])
            // The grid is no longer full, so the next fill-with-errors moment
            // should announce again (checkCompletion isn't run on deletes).
            wasFullWithErrors = false
        }
    }

    private func clearCell(_ pos: GridPos) {
        grid[pos.row][pos.col].entry = nil
        grid[pos.row][pos.col].isPencil = false
        grid[pos.row][pos.col].isCheckedWrong = false
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

    /// Select the next word to work on once `slot` is full. Crossing words
    /// come first: each already holds at least one letter from the word just
    /// finished, so they're the natural foothold — and among them the one
    /// closest to done compounds the win. With no incomplete crosser, the
    /// nearest incomplete word by grid distance: the old across-then-down
    /// wrap could teleport the cursor to a far corner of a 15×15, which reads
    /// as the app losing the player's place. Ties keep the old
    /// across-then-lower-number order, so small grids behave as they always
    /// did. No-op when every remaining cell is filled.
    private func advanceToNextIncompleteSlot(after slot: Slot) {
        func emptyCount(_ s: Slot) -> Int {
            s.positions.count { grid[$0.row][$0.col].entry == nil }
        }
        let crossers = slotsContaining(slot.positions).filter {
            $0.direction != slot.direction && emptyCount($0) > 0
        }
        if let target = crossers.min(by: {
            (emptyCount($0), $0.number) < (emptyCount($1), $1.number)
        }) {
            select(slot: target)
            return
        }
        // `selected` still sits inside the finished word — the anchor the
        // player's eye is on.
        let anchor = selected
        func distance(_ s: Slot) -> Int {
            s.positions.map { abs($0.row - anchor.row) + abs($0.col - anchor.col) }.min() ?? .max
        }
        let target = (acrossSlots + downSlots)
            .filter { $0 != slot && emptyCount($0) > 0 }
            .min {
                (distance($0), $0.direction == .down ? 1 : 0, $0.number)
                    < (distance($1), $1.direction == .down ? 1 : 0, $1.number)
            }
        if let target { select(slot: target) }
    }

    private func previousCellInWord() -> GridPos? {
        guard let slot = activeSlot,
              let idx = slot.positions.firstIndex(of: selected), idx > 0 else { return nil }
        return slot.positions[idx - 1]
    }

    // MARK: - Hints

    @discardableResult
    func revealLetter() -> Bool {
        noteInput()
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
        grid[target.row][target.col].isPencil = false
        grid[target.row][target.col].isCheckedWrong = false
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
        noteInput()
        // Refuse when the word is already fully correct — no progress to buy.
        guard let slot = activeSlot, !slotSolved(slot) else { return false }
        for (i, pos) in slot.positions.enumerated() {
            let ch = Array(slot.answer)[i]
            // Leave the player's own correct pen letters alone (and unlocked).
            // A pencilled letter is not a commitment, even when it's right —
            // the reveal converts it to a locked pen letter like any other.
            guard !grid[pos.row][pos.col].isCorrect else { continue }
            grid[pos.row][pos.col].entry = ch
            grid[pos.row][pos.col].isRevealed = true
            grid[pos.row][pos.col].isPencil = false
            grid[pos.row][pos.col].isCheckedWrong = false
        }
        hintsUsed += 1
        onEntryChanged?()
        checkCompletion()
        if !isComplete { refreshSolvedSlots(around: slot.positions) }
        return true
    }

    /// Fill the whole grid — the give-up button. Refuses when the puzzle is
    /// already effectively solved (nothing left to buy). Locks every cell it
    /// fills, leaving the player's own correct pen letters unlocked.
    @discardableResult
    func revealPuzzle() -> Bool {
        noteInput()
        guard grid.contains(where: { row in
            row.contains { !$0.isBlock && !$0.isCorrect }
        }) else { return false }
        for r in 0..<size {
            for c in 0..<size where !grid[r][c].isBlock {
                guard !grid[r][c].isCorrect else { continue }
                grid[r][c].entry = grid[r][c].solution
                grid[r][c].isRevealed = true
                grid[r][c].isPencil = false
                grid[r][c].isCheckedWrong = false
            }
        }
        hintsUsed += 1
        onEntryChanged?()
        checkCompletion()
        return true
    }

    /// A verse hint touches no cells — the hint is the reading, not a reveal.
    /// This only keeps the session hint counter honest for abandonment
    /// analytics.
    func noteVerseHint() {
        noteInput()
        hintsUsed += 1
    }

    /// New-player gift: fill the starter word (the initial selection is
    /// already the shortest answer) and move the player to a crossing word, so
    /// a new player faces a grid with a foothold instead of an empty one
    /// — 287 of 675 abandons in the 30 days to 2026-08-27 happened under 10%
    /// fill. Free by design: no `hintsUsed` bump, and the caller must not set
    /// the record's `usedHint`. Cells lock like any reveal so the gift can't
    /// be deleted (and persists lowercase in the snapshot). Refuses on any
    /// existing progress — a resume must never be overwritten.
    @discardableResult
    func giftStarterWord() -> Slot? {
        guard !isComplete, !hasAnyEntries, let slot = activeSlot else { return nil }
        for (i, pos) in slot.positions.enumerated() {
            grid[pos.row][pos.col].entry = Array(slot.answer)[i]
            grid[pos.row][pos.col].isRevealed = true
        }
        // Loud on purpose: the cascade flash and flame pulse are the win
        // moment the gift was built to manufacture — silent, it read as
        // pre-filled furniture, not a head start. No completion check — a
        // gift must never finish a puzzle, and every shipped grid has more
        // than one word.
        refreshSolvedSlots(around: slot.positions)
        advanceToNextIncompleteSlot(after: slot)
        return slot
    }

    // MARK: - Word completion tracking

    private func slotSolved(_ slot: Slot) -> Bool {
        for p in slot.positions where !grid[p.row][p.col].isCorrect {
            return false
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

    /// One-shot answer check at the given granularity. Free — never reveals a
    /// letter and never touches the hint economy. Wrong filled cells (pencil
    /// included) are marked until edited; correct positions are returned via
    /// `onCheckResult` for a brief flash, deliberately not stored — persistent
    /// green would accumulate into a free answer oracle.
    ///
    /// Returns the number of cells marked wrong, or nil when the scope had no
    /// filled cells to judge.
    @discardableResult
    func check(_ scope: CheckScope) -> Int? {
        noteInput()
        let positions: [GridPos]
        switch scope {
        case .letter: positions = isSelectable(selected) ? [selected] : []
        case .word: positions = activeSlot?.positions ?? []
        case .puzzle: positions = grid.flatMap { $0 }.filter { !$0.isBlock }.map(\.pos)
        }
        var wrong = 0
        var correct: [GridPos] = []
        var judged = false
        for pos in positions {
            let cell = grid[pos.row][pos.col]
            guard let entry = cell.entry else { continue }
            judged = true
            // Pencil letters are judged like any other: a right guess flashes
            // green (that conversion is what check is for), a wrong one marks.
            if entry == cell.solution {
                correct.append(pos)
            } else {
                grid[pos.row][pos.col].isCheckedWrong = true
                wrong += 1
            }
        }
        guard judged else { return nil }
        onCheckResult?(correct, wrong)
        return wrong
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
                // A pencil letter is not a commitment: it neither completes the
                // puzzle nor counts as "filled" for the full-but-wrong nudge.
                if cell.entry == nil || cell.isPencil { full = false }
                if !cell.isCorrect { correct = false }
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
        guard isAttachedToWindow, !isTimerSuppressed else {
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
            maybeNudgeStall()
        }
    }

    /// The stall watch, tiered by fill. Fill counts entries like
    /// `puzzle_abandoned` does (pencil included) — a grid full of pencil
    /// guesses is still a player who stopped. At or above 40% the offer is
    /// chosen from the grid (`midSolveRescueKind`) and re-arms after each
    /// input, up to the cap; below it there's nothing worth judging, so after
    /// a shorter idle the answer is a free letter — a foothold for the player
    /// the mid tier could never reach — once per sitting.
    private func maybeNudgeStall() {
        // While a line is up there is nothing to add; input takes it down and
        // restarts the idle clock, which is what re-arms the mid tier.
        guard stallNudgeEnabled, !isComplete, !isStallNudgeActive else { return }
        let idle = accumulatedSeconds - lastInputSeconds
        let total = totalPlayableCount
        guard total > 0 else { return }
        if Double(filledPlayableCount) / Double(total) >= 0.40 {
            guard midSolveNudgeCount < Self.maxMidSolveNudges, idle >= stallNudgeSeconds else { return }
            midSolveNudgeCount += 1
            stallNudgeKind = midSolveRescueKind
        } else {
            guard !earlyNudged, idle >= earlyNudgeSeconds else { return }
            earlyNudged = true
            stallNudgeKind = .freeLetter
        }
        isStallNudgeActive = true
        stallNudgeTick += 1
    }

    /// The mid-solve offer, read off the grid. Wrong letters the player can't
    /// see yet → a check, because judging what's there is the fastest unstick.
    /// Nothing wrong (they're stuck on a clue, not a mistake) → the passage
    /// the answer comes from, free, when the clue has one; else a free letter.
    /// Cells already marked wrong (a prior check, or auto-check) don't count:
    /// telling a player to check what's already red is the empty nudge.
    var midSolveRescueKind: StallNudgeKind {
        if unmarkedWrongEntryCount > 0 { return .checkAnswers }
        if activeSlot?.reference != nil { return .readVerse }
        return .freeLetter
    }

    /// Filled cells that are wrong and not yet marked as such.
    var unmarkedWrongEntryCount: Int {
        grid.reduce(0) { acc, row in
            acc + row.filter { cell in
                !cell.isBlock && cell.entry != nil && !cell.isCorrect && !cell.isCheckedWrong
            }.count
        }
    }

    /// Takes the nudge line down for an action that doesn't touch the grid
    /// (opening the verse). Counts as input: the clock restarts and the mid
    /// tier can offer again later.
    func acknowledgeStallNudge() {
        noteInput()
    }

    /// Seed cumulative time from a saved record when resuming an in-progress
    /// puzzle. The clock starts counting again from the next rendered tick.
    func seedElapsed(_ seconds: Int) {
        accumulatedSeconds = max(0, seconds)
        // Resuming is not idling: without this a puzzle carrying an hour of
        // recorded time would trip the stall nudge on its first tick.
        lastInputSeconds = accumulatedSeconds
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
        showCorrectOverlay = true
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
        showCorrectOverlay = true
        if let next = acrossSlots.first(where: { !slotSolved($0) }) {
            direction = .across
            selected = next.positions.first { grid[$0.row][$0.col].entry == nil }
                ?? next.positions[0]
        }
        onEntryChanged?()
    }
    #endif

    // MARK: - Resume snapshot

    /// Committed (pen) letters only — pencil marks live in `pencilSnapshot()`,
    /// so the entries payload keeps meaning "real progress" everywhere it's
    /// counted (resume ring, in-progress status, completion restore).
    func snapshot() -> [String: String] {
        var out: [String: String] = [:]
        for row in grid {
            for cell in row where !cell.isBlock && !cell.isPencil {
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

    /// Provisional (pencil) letters, keyed like `snapshot()`.
    func pencilSnapshot() -> [String: String] {
        var out: [String: String] = [:]
        for row in grid {
            for cell in row where !cell.isBlock && cell.isPencil {
                if let entry = cell.entry {
                    out[cell.pos.storageKey] = String(entry)
                }
            }
        }
        return out
    }

    /// Seeds the "autoCheckErrors" default the first time it's consulted:
    /// ON for a player still inside their first three solves, OFF for anyone
    /// who learned the grid without it — flipping a veteran's game behavior
    /// under them is worse than making a beginner find a toggle. Called at
    /// launch from RootView; the game view keeps a call as a belt-and-braces
    /// for a puzzle opened before that task runs.
    static func seedAutoCheckIfNeeded(totalCompleted: Int) {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: "autoCheckErrors") == nil else { return }
        defaults.set(totalCompleted < 3, forKey: "autoCheckErrors")
    }

    func restore(_ entries: [String: String], pencil: [String: String] = [:]) {
        for (key, value) in entries {
            let parts = key.split(separator: ",").compactMap { Int($0) }
            guard parts.count == 2, let raw = value.first,
                  let letter = value.uppercased().first else { continue }
            let r = parts[0], c = parts[1]
            guard r >= 0, r < size, c >= 0, c < size, !grid[r][c].isBlock else { continue }
            grid[r][c].entry = letter
            grid[r][c].isRevealed = raw.isLowercase
        }
        for (key, value) in pencil {
            let parts = key.split(separator: ",").compactMap { Int($0) }
            guard parts.count == 2, let letter = value.uppercased().first else { continue }
            let r = parts[0], c = parts[1]
            guard r >= 0, r < size, c >= 0, c < size, !grid[r][c].isBlock,
                  grid[r][c].entry == nil else { continue } // pen letters win
            grid[r][c].entry = letter
            grid[r][c].isPencil = true
        }
        checkCompletion(announceFullMiss: false)
        seedSolvedSlots()
        // The init picked the shortest answer as the opening selection, but a
        // resume can land that on a word with nothing left to do (the gifted
        // starter word is the common case). Move to the next word that still
        // has an empty cell so the player resumes on work, not on a done word.
        if !isComplete, let slot = activeSlot,
           !slot.positions.contains(where: { grid[$0.row][$0.col].entry == nil }) {
            advanceToNextIncompleteSlot(after: slot)
        }
    }
}
