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

    /// Renders the puzzle's silhouette as a spoiler-free emoji grid: the
    /// letter cells become 🟩, blocks ⬛. Grids wider than `targetSize` are
    /// downsampled by marking a coarse cell filled when any source cell in
    /// its block holds a letter, preserving the rough shape.
    static func emoji(for puzzle: Puzzle) -> String {
        let rows = puzzle.grid.map(Array.init)
        let size = rows.count
        guard size > 0 else { return "" }

        let scale = max(1, Int((Double(size) / Double(targetSize)).rounded(.up)))
        let coarse = Int((Double(size) / Double(scale)).rounded(.up))

        var lines: [String] = []
        for cr in 0..<coarse {
            var line = ""
            for cc in 0..<coarse {
                let filled = (cr * scale..<min((cr + 1) * scale, size)).contains { r in
                    (cc * scale..<min((cc + 1) * scale, size)).contains { c in
                        c < rows[r].count && rows[r][c] != "."
                    }
                }
                line += filled ? "🟩" : "⬛"
            }
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }
}
