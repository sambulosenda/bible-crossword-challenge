//
//  PuzzleStatus.swift
//  Bible Crossword Challenge
//
//  Shared play-state for a puzzle, derived from its saved record. Used by both
//  the Today card and the Archive list.
//

import Foundation

enum PuzzleStatus {
    case start
    case inProgress
    case completed

    init(record: PuzzleRecord?) {
        guard let record else { self = .start; return }
        if record.isCompleted { self = .completed }
        else if !record.entries.isEmpty { self = .inProgress }
        else { self = .start }
    }

    var actionTitle: String {
        switch self {
        case .start: return "Start Puzzle"
        case .inProgress: return "Continue"
        case .completed: return "Play Again"
        }
    }

    var actionSymbol: String {
        switch self {
        case .start: return "play.fill"
        case .inProgress: return "arrow.forward.circle.fill"
        case .completed: return "arrow.clockwise"
        }
    }
}
