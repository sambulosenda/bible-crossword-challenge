//
//  ChapterPuzzleIndexTests.swift
//  Bible Crossword ChallengeTests
//
//  The reader's puzzle chips: which puzzles a chapter offers, in what order,
//  and how many. Built from synthetic puzzles so the rules are checked apart
//  from whatever the bundle happens to contain today; one bundle check keeps
//  the shipped index honest.
//

import Testing
import Foundation
@testable import Bible_Crossword_Challenge

private func puzzle(_ id: String, reference: String, clueRefs: [String?] = []) -> Puzzle {
    Puzzle(
        id: id, title: id, difficulty: .easy,
        verse: "…", reference: reference,
        publishDate: "2026-01-01", size: 5, grid: ["....."],
        clues: clueRefs.enumerated().map { i, ref in
            ClueData(number: i + 1, direction: .across, row: 0, col: 0, text: "c", answer: "A", reference: ref)
        }
    )
}

struct ChapterPuzzleIndexTests {

    @Test func themeVerseLinksItsChapter() {
        let index = ChapterPuzzleIndex(puzzles: [puzzle("a", reference: "John 3:16")])
        #expect(index.puzzleIDs(book: "John", chapter: 3) == ["a"])
        #expect(index.puzzleIDs(book: "John", chapter: 4).isEmpty)
        #expect(index.puzzleIDs(book: "Psalms", chapter: 23).isEmpty)
    }

    @Test func clueReferencesLinkTheirChapters() {
        let index = ChapterPuzzleIndex(puzzles: [
            puzzle("a", reference: "Isaiah 11:6", clueRefs: ["Jonah 1:17", "Daniel 6:16", nil]),
        ])
        #expect(index.puzzleIDs(book: "Jonah", chapter: 1) == ["a"])
        #expect(index.puzzleIDs(book: "Daniel", chapter: 6) == ["a"])
        #expect(index.puzzleIDs(book: "Isaiah", chapter: 11) == ["a"])
    }

    @Test func aPuzzleAppearsOncePerChapter() {
        let index = ChapterPuzzleIndex(puzzles: [
            puzzle("a", reference: "Genesis 1:1", clueRefs: ["Genesis 1:3", "Genesis 1:26"]),
        ])
        #expect(index.puzzleIDs(book: "Genesis", chapter: 1) == ["a"])
    }

    @Test func themeFirstThenByCitationCountThenBundleOrder() {
        let index = ChapterPuzzleIndex(puzzles: [
            puzzle("one-clue", reference: "Ruth 1:1", clueRefs: ["Luke 22:19"]),
            puzzle("theme", reference: "Luke 22:42", clueRefs: []),
            puzzle("three-clues", reference: "Ruth 2:1", clueRefs: ["Luke 22:1", "Luke 22:2", "Luke 22:3"]),
            puzzle("also-one-clue", reference: "Ruth 3:1", clueRefs: ["Luke 22:20"]),
        ])
        #expect(index.puzzleIDs(book: "Luke", chapter: 22) == ["theme", "three-clues", "one-clue", "also-one-clue"])
    }

    @Test func cappedAtFive() {
        let puzzles = (1...8).map { puzzle("p\($0)", reference: "Acts 2:\($0)") }
        let index = ChapterPuzzleIndex(puzzles: puzzles)
        let ids = index.puzzleIDs(book: "Acts", chapter: 2)
        #expect(ids.count == ChapterPuzzleIndex.cap)
        #expect(ids == ["p1", "p2", "p3", "p4", "p5"])
    }

    @Test func unparseableReferencesAreIgnored() {
        let index = ChapterPuzzleIndex(puzzles: [
            puzzle("a", reference: "Various", clueRefs: ["", "Psalm"]),
        ])
        #expect(index.chapterCount == 0)
    }

    @Test func multiWordBooksResolve() {
        let index = ChapterPuzzleIndex(puzzles: [
            puzzle("a", reference: "1 Corinthians 13:4-7", clueRefs: ["Song of Solomon 2:1"]),
        ])
        #expect(index.puzzleIDs(book: "1 Corinthians", chapter: 13) == ["a"])
        #expect(index.puzzleIDs(book: "Song of Solomon", chapter: 2) == ["a"])
    }

    /// The shipped index: every id it hands the reader must resolve to a
    /// bundled puzzle, and a chapter the catalogue leans on must have chips.
    @Test func bundledIndexResolvesAndCoversJohn3() {
        let provider = PuzzleProvider.shared
        let index = provider.chapterIndex
        #expect(index.chapterCount > 100)
        #expect(!index.puzzleIDs(book: "John", chapter: 3).isEmpty)
        for book in ScriptureProvider.shared.books {
            for chapter in book.chapters {
                let ids = index.puzzleIDs(book: book.name, chapter: chapter.number)
                #expect(ids.count <= ChapterPuzzleIndex.cap)
                for id in ids {
                    #expect(provider.puzzle(id: id) != nil, "\(book.name) \(chapter.number) → \(id)")
                }
            }
        }
    }
}
