//
//  ChapterPuzzleIndex.swift
//  Bible Crossword Challenge
//
//  Which puzzles a chapter of the Bible appears in. Built once from the bundle:
//  a puzzle is linked to the chapter of its theme verse and to the chapter of
//  every clue reference it carries. The reader shows the result at the foot
//  of a chapter, so reading feeds the grid the way the completion screen's
//  "Read the passage" feeds the reader — until 2.9 that loop only ran one way.
//

import Foundation

struct ChapterPuzzleIndex {
    /// The most puzzles a chapter offers. Five is a row of chips, not a list;
    /// Daniel 3 and Genesis 1 are the only chapters that come near it.
    static let cap = 5

    struct Key: Hashable {
        let book: String
        let chapter: Int
    }

    private struct Link {
        let puzzleID: String
        /// The puzzle's theme verse is in this chapter.
        var isTheme = false
        /// How many of the puzzle's clues cite this chapter.
        var clueRefs = 0
        /// Bundle order, so equal ranks stay in catalogue order.
        let order: Int
    }

    private let byChapter: [Key: [String]]

    init(puzzles: [Puzzle]) {
        var links: [Key: [String: Link]] = [:]
        func link(_ reference: String, _ puzzle: Puzzle, order: Int, theme: Bool) {
            guard let ref = ScriptureRef(reference) else { return }
            let key = Key(book: ref.book, chapter: ref.chapter)
            var entry = links[key, default: [:]][puzzle.id] ?? Link(puzzleID: puzzle.id, order: order)
            if theme { entry.isTheme = true } else { entry.clueRefs += 1 }
            links[key, default: [:]][puzzle.id] = entry
        }
        for (order, puzzle) in puzzles.enumerated() {
            link(puzzle.reference, puzzle, order: order, theme: true)
            for clue in puzzle.clues {
                if let reference = clue.reference { link(reference, puzzle, order: order, theme: false) }
            }
        }
        // Theme-verse puzzles first — the chapter is what the puzzle is about,
        // not one clue's citation — then by how often the chapter is cited.
        byChapter = links.mapValues { entries in
            entries.values.sorted { a, b in
                if a.isTheme != b.isTheme { return a.isTheme }
                if a.clueRefs != b.clueRefs { return a.clueRefs > b.clueRefs }
                return a.order < b.order
            }
            .prefix(Self.cap)
            .map(\.puzzleID)
        }
    }

    /// Puzzle ids for a chapter, best first, at most `cap`. Empty for a chapter
    /// no puzzle touches — the reader shows nothing rather than an empty state.
    func puzzleIDs(book: String, chapter: Int) -> [String] {
        byChapter[Key(book: book, chapter: chapter)] ?? []
    }

    /// Chapters that have at least one puzzle.
    var chapterCount: Int { byChapter.count }
}
