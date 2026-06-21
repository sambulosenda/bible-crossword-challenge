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
    private(set) var hintsUsed: Int = 0
    private(set) var isComplete: Bool = false

    let startDate: Date
    private(set) var completionSeconds: Int = 0

    // Side-effect callbacks owned by the view.
    var onComplete: ((Int) -> Void)?
    var onEntryChanged: (() -> Void)?

    private var slotIndex: [ClueDirection: [GridPos: Int]] = [.across: [:], .down: [:]]

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
                positions: clue.positions
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
        let upper = Character(letter.uppercased())
        grid[selected.row][selected.col].entry = upper
        grid[selected.row][selected.col].isRevealed = false
        showErrors = false
        onEntryChanged?()
        checkCompletion()
        if !isComplete { advanceWithinWord() }
    }

    func delete() {
        if grid[selected.row][selected.col].entry != nil {
            grid[selected.row][selected.col].entry = nil
        } else if let prev = previousCellInWord() {
            selected = prev
            grid[prev.row][prev.col].entry = nil
        }
        showErrors = false
        onEntryChanged?()
    }

    private func advanceWithinWord() {
        guard let slot = activeSlot,
              let idx = slot.positions.firstIndex(of: selected) else { return }
        // Next empty cell after the current one, else the immediate next cell.
        if let nextEmpty = slot.positions[(idx + 1)...].first(where: { grid[$0.row][$0.col].entry == nil }) {
            selected = nextEmpty
        } else if idx + 1 < slot.positions.count {
            selected = slot.positions[idx + 1]
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
        guard isSelectable(selected),
              let solution = grid[selected.row][selected.col].solution else { return false }
        grid[selected.row][selected.col].entry = solution
        grid[selected.row][selected.col].isRevealed = true
        hintsUsed += 1
        onEntryChanged?()
        checkCompletion()
        if !isComplete { advanceWithinWord() }
        return true
    }

    @discardableResult
    func revealWord() -> Bool {
        guard let slot = activeSlot else { return false }
        for (i, pos) in slot.positions.enumerated() {
            let ch = Array(slot.answer)[i]
            grid[pos.row][pos.col].entry = ch
            grid[pos.row][pos.col].isRevealed = true
        }
        hintsUsed += 1
        onEntryChanged?()
        checkCompletion()
        return true
    }

    // MARK: - Validation

    func toggleCheck() {
        showErrors.toggle()
    }

    /// True when every playable cell holds the correct letter.
    func checkCompletion() {
        for row in grid {
            for cell in row where !cell.isBlock {
                if cell.entry != cell.solution { return }
            }
        }
        guard !isComplete else { return }
        isComplete = true
        completionSeconds = max(0, Int(Date().timeIntervalSince(startDate)))
        onComplete?(completionSeconds)
    }

    var hasAnyEntries: Bool {
        grid.contains { row in row.contains { !$0.isBlock && $0.entry != nil } }
    }

    var filledPlayableCount: Int {
        grid.reduce(0) { acc, row in
            acc + row.filter { !$0.isBlock && $0.entry != nil }.count
        }
    }

    var totalPlayableCount: Int {
        grid.reduce(0) { acc, row in acc + row.filter { !$0.isBlock }.count }
    }

    // MARK: - Resume snapshot

    func snapshot() -> [String: String] {
        var out: [String: String] = [:]
        for row in grid {
            for cell in row where !cell.isBlock {
                if let entry = cell.entry { out[cell.pos.storageKey] = String(entry) }
            }
        }
        return out
    }

    func restore(_ entries: [String: String]) {
        for (key, value) in entries {
            let parts = key.split(separator: ",").compactMap { Int($0) }
            guard parts.count == 2, let letter = value.uppercased().first else { continue }
            let r = parts[0], c = parts[1]
            guard r >= 0, r < size, c >= 0, c < size, !grid[r][c].isBlock else { continue }
            grid[r][c].entry = letter
        }
        checkCompletion()
    }
}
