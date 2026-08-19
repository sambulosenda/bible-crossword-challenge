//
//  MemoryCloze.swift
//  Bible Crossword Challenge
//
//  Builds the memory-verse practice grid: the verse laid out in reading order
//  as rows of letter cells, each word an across-only slot, with a block column
//  between words. Blocks render clear, so the grid reads as typeset text with
//  gaps — cloze deletion wearing the crossword's clothes.
//
//  Deliberately NOT the interlocking generator (tools/generate_puzzles.py):
//  a real crossword scatters words to maximize crossings, which destroys the
//  one thing memorization trains — sequence. This layout preserves order and
//  duplicates, and cannot fail to place a word.
//
//  Everything here is pure and deterministic: the same verse and level always
//  produce the identical puzzle, and each level's blanks are a superset of the
//  previous level's, so a player never sees a word they already recalled come
//  back pre-filled.
//

import Foundation

enum MemoryCloze {

    /// Grid ids for this mode. Like the `pack-` prefix, the namespace is the
    /// contract: `memory-` puzzles exist only in memory, never in
    /// `puzzles.json`, any rotation pool, or a `PuzzleRecord`.
    static let idPrefix = "memory-"

    /// Words per verse the layout accepts. Below 2 there is nothing to blank
    /// against; above 40 the grid outgrows both the screen and the pedagogy
    /// (memorize long passages a verse at a time).
    static let wordRange = 2...40

    /// A word's a-priori memorization value. Glue words stay revealed until the
    /// top levels — blanking "the" teaches nothing until the full-recall test.
    /// Deliberately small and lowercase-only: this is a ranking nudge, not NLP.
    private static let stopwords: Set<String> = [
        "A", "AN", "THE", "AND", "BUT", "OR", "NOR", "FOR", "SO", "YET",
        "OF", "IN", "ON", "AT", "TO", "BY", "AS", "IS", "ARE", "WAS", "WERE",
        "BE", "BEEN", "AM", "DO", "DID", "HAS", "HAVE", "HAD", "NOT", "NO",
        "HE", "SHE", "IT", "HIS", "HER", "ITS", "THEY", "THEM", "THEIR",
        "YOU", "YOUR", "WE", "US", "OUR", "MY", "ME", "WHO", "WHOM", "THAT",
        "THIS", "WITH", "FROM", "INTO", "UNTO", "UPON", "WILL", "SHALL",
    ]

    // MARK: - Tokenization

    /// The verse reduced to typeable words: uppercase A–Z, apostrophes dropped
    /// ("God's" → GODS, the crossword convention), hyphens splitting, all other
    /// punctuation stripped. Order and duplicates are preserved — repetition is
    /// exactly what people trip on when reciting.
    static func tokenize(_ verse: String) -> [String] {
        verse
            .uppercased()
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "\u{2019}", with: "")
            .split(whereSeparator: { !$0.isLetter && $0 != "-" })
            .flatMap { $0.split(separator: "-") }
            .map { String($0.unicodeScalars.filter { ("A"..."Z").contains($0) }) }
            .filter { !$0.isEmpty }
    }

    // MARK: - Layout

    struct Layout {
        let size: Int
        /// Solution rows, `size` strings of `size` characters, "." for blocks.
        let grid: [String]
        /// Per word (in verse order): its starting cell. Length always equals
        /// the word count — this layout cannot drop a word.
        let starts: [GridPos]
        let words: [String]
    }

    /// Word-wrap the verse into the squarest grid that fits 15×15. Tries every
    /// width the longest word allows and keeps the candidate whose bounding
    /// square is smallest (ties: closest to square). Returns nil when the verse
    /// can't fit — such verses simply don't appear in the mode.
    static func layout(words: [String]) -> Layout? {
        guard wordRange.contains(words.count),
              let longest = words.map(\.count).max(), longest <= 15 else { return nil }

        var best: (width: Int, rows: [[String]], score: (Int, Int))?
        for width in max(longest, 4)...15 {
            let rows = wrap(words: words, width: width)
            guard rows.count <= 15 else { continue }
            let score = (max(width, rows.count), abs(width - rows.count))
            if best == nil || score < best!.score {
                best = (width, rows, score)
            }
        }
        guard let best else { return nil }

        let size = max(best.width, best.rows.count)
        let rowOffset = (size - best.rows.count) / 2

        var grid = [String](repeating: String(repeating: ".", count: size), count: size)
        var starts: [GridPos] = []
        var rowIndex = rowOffset
        for row in best.rows {
            var line = ""
            for word in row {
                if !line.isEmpty { line += "." }
                starts.append(GridPos(row: rowIndex, col: line.count))
                line += word
            }
            grid[rowIndex] = line.padding(toLength: size, withPad: ".", startingAt: 0)
            rowIndex += 1
        }
        return Layout(size: size, grid: grid, starts: starts, words: words)
    }

    private static func wrap(words: [String], width: Int) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var used = 0
        for word in words {
            let needed = row.isEmpty ? word.count : used + 1 + word.count
            if !row.isEmpty, needed > width {
                rows.append(row)
                row = []
                used = 0
            }
            used = row.isEmpty ? word.count : used + 1 + word.count
            row.append(word)
        }
        if !row.isEmpty { rows.append(row) }
        return rows
    }

    // MARK: - Blanking

    /// Fraction of the verse's words blanked at each mastery level. Level 5
    /// (mastered) replays the full-recall grid.
    static func blankFraction(level: Int) -> Double {
        switch level {
        case ...1: return 0.25
        case 2: return 0.40
        case 3: return 0.65
        default: return 1.0
        }
    }

    /// Word indices to blank at `level`. The priority order is fixed per verse
    /// — content words longest-first (names and long words are the recall
    /// anchors), glue words last, ties broken by verse position — and each
    /// level takes a prefix of it, so blanks nest monotonically across levels.
    /// Always at least one, so a freshly restored grid can never be complete.
    static func blankedWordIndices(words: [String], level: Int) -> Set<Int> {
        let priority = words.indices.sorted { a, b in
            let aStop = stopwords.contains(words[a])
            let bStop = stopwords.contains(words[b])
            if aStop != bStop { return bStop }
            if words[a].count != words[b].count { return words[a].count > words[b].count }
            return a < b
        }
        let k = min(words.count, max(1, Int((blankFraction(level: level) * Double(words.count)).rounded(.up))))
        return Set(priority.prefix(k))
    }

    // MARK: - Puzzle assembly

    struct Built {
        let puzzle: Puzzle
        /// Snapshot for `GameViewModel.restore(_:)` covering every cell of every
        /// non-blanked word. Lowercase, so the engine marks them revealed and
        /// typing-locked — the existing hint-lock convention doing cloze duty.
        let prefill: [String: String]
        let blankedWordIndices: Set<Int>
        let wordCount: Int
    }

    /// The playable practice grid for a verse at a mastery level, or nil when
    /// the verse doesn't fit the mode.
    static func build(reference: String, verseText: String, level: Int) -> Built? {
        let words = tokenize(verseText)
        guard let layout = layout(words: words) else { return nil }

        let count = words.count
        let clues = layout.words.enumerated().map { i, word in
            ClueData(
                number: i + 1,
                direction: .across,
                row: layout.starts[i].row,
                col: layout.starts[i].col,
                text: "\(reference) — word \(i + 1) of \(count)",
                answer: word
            )
        }
        let puzzle = Puzzle(
            id: idPrefix + referenceKey(reference),
            title: reference,
            difficulty: .easy,
            verse: verseText,
            reference: reference,
            publishDate: "",
            size: layout.size,
            grid: layout.grid,
            clues: clues
        )

        let blanked = blankedWordIndices(words: words, level: level)
        var prefill: [String: String] = [:]
        for (i, word) in layout.words.enumerated() where !blanked.contains(i) {
            let start = layout.starts[i]
            for (offset, letter) in word.enumerated() {
                let pos = GridPos(row: start.row, col: start.col + offset)
                prefill[pos.storageKey] = String(letter).lowercased()
            }
        }
        return Built(puzzle: puzzle, prefill: prefill, blankedWordIndices: blanked, wordCount: count)
    }

    /// True when the verse can appear in the mode at all.
    static func isEligible(verseText: String) -> Bool {
        layout(words: tokenize(verseText)) != nil
    }

    /// Normalized identity for a scripture reference, used as the storage key
    /// and the `memory-` id suffix: trimmed, lowercased, spaces collapsed to
    /// single hyphens ("1 John 4:19" → "1-john-4:19").
    static func referenceKey(_ reference: String) -> String {
        reference
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(separator: " ")
            .joined(separator: "-")
    }
}
