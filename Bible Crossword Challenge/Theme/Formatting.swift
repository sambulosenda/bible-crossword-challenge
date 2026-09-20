//
//  Formatting.swift
//  Bible Crossword Challenge
//

import Foundation

enum TimeFormat {
    /// Formats seconds as "m:ss" (or "h:mm:ss" past an hour).
    static func clock(_ seconds: Int) -> String {
        let s = max(0, seconds)
        let hours = s / 3600
        let minutes = (s % 3600) / 60
        let secs = s % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    /// A wait, rounded up to the minute: "3h 40m", "40m", or "under a
    /// minute". For a countdown read once, not a ticking clock.
    static func countdown(_ seconds: TimeInterval) -> String {
        guard seconds >= 60 else { return "under a minute" }
        let minutes = Int((seconds / 60).rounded(.up))
        let hours = minutes / 60
        let rest = minutes % 60
        if hours > 0 {
            return rest > 0 ? "\(hours)h \(rest)m" : "\(hours)h"
        }
        return "\(minutes)m"
    }
}

enum ShareGrid {
    /// Message-friendly width — Wordle-scale, well under iMessage line wrap.
    static let targetSize = 8

    /// One solve, rendered for a message.
    struct Render {
        let text: String
        /// Coarse cells after trimming — the artifact's real size, logged so we
        /// can tell whether a shape that reads as a crossword sends better than
        /// one that doesn't.
        let cells: Int

        var isEmpty: Bool { text.isEmpty }

        static let empty = Render(text: "", cells: 0)
    }

    /// How a finished cell came to be filled.
    ///
    /// Ordered on purpose: when downsampling folds several source cells into
    /// one, the worst case wins, so a shared grid can only ever understate the
    /// solve. `gift` outranks `clean` but sits below `hint` — a gifted cell is
    /// help the player never asked for, and reading it as a hint would stamp
    /// every learning-window player's first share with a debt they didn't take.
    private enum Fill: Int, Comparable {
        case block = 0, clean, gift, hint

        init(_ cell: CellState) {
            if cell.isBlock { self = .block }
            else if cell.isGift { self = .gift }      // also `isRevealed` — test first
            else if cell.isRevealed { self = .hint }
            else { self = .clean }
        }

        static func < (a: Fill, b: Fill) -> Bool { a.rawValue < b.rawValue }

        var emoji: String {
            switch self {
            case .block: return "\u{2B1B}"
            case .clean: return "\u{1F7E6}"
            case .gift:  return "\u{2B1C}"
            case .hint:  return "\u{1F7E8}"
            }
        }
    }

    /// Renders the finished grid as a spoiler-free emoji block: shape plus how
    /// each cell was filled. No letters, no answers, no clue order — two people
    /// who solved the same puzzle differently get visibly different blocks,
    /// which is the entire reason to send one.
    ///
    /// Replaces a renderer that drew `puzzle.grid`, the *authored* silhouette:
    /// byte-identical for everyone who solved it, and on the 21x21 Sunday a
    /// solid 7x7 rectangle (2% black) once downsampled.
    static func result(for grid: [[CellState]]) -> Render {
        // A closure, not `Fill.init` as a value: the initializer is main-actor
        // isolated like everything here, and a bare function reference is a
        // nonisolated value that can't carry that.
        var fills = grid.map { $0.map { Fill($0) } }

        // Trim all-block border rows and columns. 39 of 138 dailies carry an
        // all-block last row as authored padding; at eight coarse rows that is
        // an eighth of a scarce artifact spent on nothing.
        while fills.first?.allSatisfy({ $0 == .block }) == true { fills.removeFirst() }
        while fills.last?.allSatisfy({ $0 == .block }) == true { fills.removeLast() }
        guard !fills.isEmpty, !fills.contains(where: \.isEmpty) else { return .empty }
        // Every surviving row holds a letter, so neither loop can empty a row.
        while fills.allSatisfy({ $0.first == .block }) {
            for i in fills.indices { fills[i].removeFirst() }
        }
        while fills.allSatisfy({ $0.last == .block }) {
            for i in fills.indices { fills[i].removeLast() }
        }

        let rows = fills.count
        let cols = fills[0].count
        guard rows > 0, cols > 0 else { return .empty }

        let scale = max(1, Int((Double(max(rows, cols)) / Double(targetSize)).rounded(.up)))
        let coarseRows = Int((Double(rows) / Double(scale)).rounded(.up))
        let coarseCols = Int((Double(cols) / Double(scale)).rounded(.up))

        var lines: [String] = []
        lines.reserveCapacity(coarseRows)
        for cr in 0..<coarseRows {
            var line = ""
            for cc in 0..<coarseCols {
                var worst = Fill.block
                for r in (cr * scale)..<min((cr + 1) * scale, rows) {
                    for c in (cc * scale)..<min((cc + 1) * scale, cols) {
                        worst = max(worst, fills[r][c])
                    }
                }
                line += worst.emoji
            }
            lines.append(line)
        }
        return Render(text: lines.joined(separator: "\n"), cells: coarseRows * coarseCols)
    }
}
