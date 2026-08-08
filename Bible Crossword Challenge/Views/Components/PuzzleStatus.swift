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

// MARK: - Today's rotated puzzle

/// How today's daily (or mini) should be presented.
///
/// The daily is a rotation, not a dated archive — `index = daysSinceEpoch %
/// pool.count` — so any finite pool eventually comes back around to a puzzle
/// the player already finished. On 21 September 2026 the 82-puzzle daily pool
/// serves `daily-001` again to everyone who has played since launch.
///
/// `isCompleted` cannot tell those apart, and reading it alone is what makes the
/// wrap dangerous: the card would celebrate a puzzle finished in July, the
/// player would reasonably conclude the day was done, and the streak would break
/// on a day they were perfectly willing to play. The distinction that matters is
/// *when* it was completed, not whether.
///
/// Deliberately separate from `PuzzleStatus`, which stays a plain reading of the
/// record: "repeat" is only meaningful where the app claims a puzzle is today's.
/// In Archive and pack lists a completed puzzle is simply completed.
enum DailyPresentation: Equatable {
    /// Never finished — start it, or carry on.
    case play(PuzzleStatus)
    /// Finished today. The win moment, and the only state that celebrates.
    case solvedToday(seconds: Int?)
    /// Finished on an earlier day; the rotation has come round again.
    case playedBefore(previousSeconds: Int?)

    /// Pure in `(record, date, calendar)` so the wrap dates can be tested
    /// without a wall clock.
    static func of(
        record: PuzzleRecord?,
        on date: Date,
        calendar: Calendar = .current
    ) -> DailyPresentation {
        let status = PuzzleStatus(record: record)
        guard status == .completed, let record else { return .play(status) }

        let seconds = record.elapsedSeconds > 0 ? record.elapsedSeconds : nil
        guard let completedDate = record.completedDate else {
            // Completed but undated — a record written before the field existed,
            // or arrived through sync without it. Treat it as a repeat: offering
            // a replay on a day already solved costs nothing, where announcing
            // "done" on a day that isn't costs a streak.
            return .playedBefore(previousSeconds: seconds)
        }

        return calendar.isDate(completedDate, inSameDayAs: date)
            ? .solvedToday(seconds: seconds)
            : .playedBefore(previousSeconds: seconds)
    }

    /// The record's own reading, for the parts of a card that don't care when.
    var status: PuzzleStatus {
        switch self {
        case .play(let status): status
        case .solvedToday, .playedBefore: .completed
        }
    }
}
