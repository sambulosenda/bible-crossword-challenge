//
//  CrosswordModels.swift
//  Bible Crossword Challenge
//
//  Value types describing a puzzle and its runtime grid. These are decoded
//  from the bundled `puzzles.json` and consumed by the game engine.
//

import SwiftUI

// MARK: - Difficulty

enum PuzzleDifficulty: String, Codable, CaseIterable, Hashable {
    case easy, medium, hard

    var label: String { rawValue.capitalized }

    var tint: Color {
        switch self {
        case .easy: return .green
        case .medium: return .orange
        case .hard: return .red
        }
    }
}

// MARK: - Direction

enum ClueDirection: String, Codable, Hashable, CaseIterable {
    case across, down

    var label: String { self == .across ? "Across" : "Down" }
    var toggled: ClueDirection { self == .across ? .down : .across }
}

// MARK: - Grid position

struct GridPos: Hashable, Codable {
    let row: Int
    let col: Int

    var storageKey: String { "\(row),\(col)" }
}

// MARK: - Puzzle (decoded from JSON)

struct Puzzle: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let difficulty: PuzzleDifficulty
    let verse: String
    let reference: String
    let publishDate: String
    let size: Int
    let grid: [String]
    let clues: [ClueData]

    var clueCount: Int { clues.count }
}

struct ClueData: Codable, Hashable {
    let number: Int
    let direction: ClueDirection
    let row: Int
    let col: Int
    let text: String
    let answer: String

    var start: GridPos { GridPos(row: row, col: col) }

    /// Ordered cell positions this clue's answer occupies.
    var positions: [GridPos] {
        (0..<answer.count).map { i in
            switch direction {
            case .across: return GridPos(row: row, col: col + i)
            case .down:   return GridPos(row: row + i, col: col)
            }
        }
    }
}

// MARK: - Runtime cell

struct CellState: Hashable {
    let pos: GridPos
    let isBlock: Bool
    let solution: Character?
    let number: Int?
    var entry: Character?
    var isRevealed: Bool = false

    var isCorrect: Bool {
        guard let solution, let entry else { return false }
        return entry == solution
    }
}

// MARK: - Slot (a placed word + its clue)

struct Slot: Identifiable, Hashable {
    let number: Int
    let direction: ClueDirection
    let clue: String
    let answer: String
    let positions: [GridPos]

    var id: String { "\(number)-\(direction.rawValue)" }
    var length: Int { positions.count }
}
