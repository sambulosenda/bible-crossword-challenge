//
//  PastPuzzles.swift
//  Bible Crossword Challenge
//
//  The days a calendar of past puzzles can honestly show.
//
//  The daily rotates, so a puzzle belongs to a date only for one trip round
//  its pool: walk back far enough and the same puzzle is served again (see
//  `PuzzleProvider.rotationWindow` and the note at the top of `LibraryView`).
//  The calendar therefore ends where the first repeat would begin. Inside
//  that span every day names one puzzle and every puzzle names one day, so
//  "solved" on a cell can't light a second cell.
//
//  A solved cell is a plain reading of the record, as in the Library: the
//  puzzle is finished, whenever that happened. Only Today claims a puzzle is
//  *today's* and has to tell a repeat from a win (`DailyPresentation`).
//

import Foundation

/// Which rotating pool a calendar shows. The Sunday Special rolls weekly and
/// is not a day's puzzle, so it has no calendar.
enum PastPuzzleKind: String, CaseIterable, Identifiable {
    case daily
    case mini

    var id: String { rawValue }

    var label: String {
        switch self {
        case .daily: "Daily"
        case .mini: "Mini"
        }
    }
}

/// One day and the puzzle it served.
struct PastPuzzleDay: Identifiable, Hashable {
    /// Start of the local day.
    let date: Date
    let puzzle: Puzzle

    var id: Date { date }
}

/// A month of the calendar, laid out for a seven-column grid.
struct PastPuzzleMonth: Identifiable {
    enum Cell: Identifiable {
        /// Padding before the 1st, so the 1st lands under its weekday.
        case blank(Int)
        /// A day of the month the calendar doesn't reach: after today, or
        /// before the span began.
        case outside(Date)
        case day(PastPuzzleDay)

        var id: String {
            switch self {
            case .blank(let index): "blank-\(index)"
            case .outside(let date): "outside-\(date.timeIntervalSinceReferenceDate)"
            case .day(let day): "day-\(day.date.timeIntervalSinceReferenceDate)"
            }
        }
    }

    /// The first day of the month.
    let start: Date
    let cells: [Cell]

    var id: Date { start }

    var days: [PastPuzzleDay] {
        cells.compactMap { if case .day(let day) = $0 { day } else { nil } }
    }
}

enum PastPuzzles {
    /// Today and the days before it, newest first, for as long as each day
    /// names a puzzle no later day in the span already named.
    ///
    /// Bounded by the pool's size as well as by the first repeat: a pool
    /// pinned by `schedule.json` could in principle run longer without one,
    /// and the calendar promises one rotation, not a history.
    static func days(
        _ kind: PastPuzzleKind,
        provider: PuzzleProvider,
        today: Date,
        calendar: Calendar = .current
    ) -> [PastPuzzleDay] {
        let pool = kind == .daily ? provider.puzzles : provider.minis
        guard !pool.isEmpty else { return [] }
        let start = calendar.startOfDay(for: today)
        var seen = Set<String>()
        var days: [PastPuzzleDay] = []
        for offset in 0..<pool.count {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: start) else { break }
            let puzzle = kind == .daily
                ? provider.dailyPuzzle(for: date, calendar: calendar)
                : provider.dailyMini(for: date, calendar: calendar)
            guard let puzzle, seen.insert(puzzle.id).inserted else { break }
            days.append(PastPuzzleDay(date: date, puzzle: puzzle))
        }
        return days
    }

    /// `days` grouped into months, newest month first, each padded so its
    /// 1st sits under the right weekday for `calendar.firstWeekday`, and
    /// trimmed to the weeks the span touches.
    static func months(_ days: [PastPuzzleDay], calendar: Calendar = .current) -> [PastPuzzleMonth] {
        let byDate = Dictionary(days.map { ($0.date, $0) }, uniquingKeysWith: { first, _ in first })
        var starts: [Date] = []
        for day in days {
            guard let month = calendar.dateInterval(of: .month, for: day.date)?.start else { continue }
            if starts.last != month { starts.append(month) }
        }
        return starts.map { start in
            let weekday = calendar.component(.weekday, from: start)
            let leading = (weekday - calendar.firstWeekday + 7) % 7
            let count = calendar.range(of: .day, in: .month, for: start)?.count ?? 0
            var cells: [PastPuzzleMonth.Cell] = (0..<leading).map { .blank($0) }
            for index in 0..<count {
                guard let date = calendar.date(byAdding: .day, value: index, to: start) else { continue }
                let key = calendar.startOfDay(for: date)
                cells.append(byDate[key].map { .day($0) } ?? .outside(key))
            }
            return PastPuzzleMonth(start: start, cells: weeksWithADay(cells))
        }
    }

    /// Drops the weeks no day of the span falls in: the rest of this month
    /// after today's week, and the oldest month before the span begins.
    /// A fortnight of greyed numerals said nothing and pushed last month
    /// off the first screen.
    private static func weeksWithADay(_ cells: [PastPuzzleMonth.Cell]) -> [PastPuzzleMonth.Cell] {
        stride(from: 0, to: cells.count, by: 7).flatMap { start -> [PastPuzzleMonth.Cell] in
            let week = Array(cells[start..<min(start + 7, cells.count)])
            let hasDay = week.contains { if case .day = $0 { true } else { false } }
            return hasDay ? week : []
        }
    }

    /// Weekday initials in the order the grid's columns run.
    static func weekdaySymbols(calendar: Calendar = .current) -> [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let shift = calendar.firstWeekday - 1
        return Array(symbols[shift...] + symbols[..<shift])
    }
}
