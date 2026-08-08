//
//  BibleJourneyTests.swift
//  Bible Crossword ChallengeTests
//
//  The journey is derived arithmetic over the bundle, so the tests that matter
//  are the ones guarding its two edges: the canon list agreeing with the Bible
//  it was copied from, and every shipped puzzle actually landing on a book.
//

import Testing
import Foundation
@testable import Bible_Crossword_Challenge

struct BibleJourneyTests {
    private func puzzle(_ id: String, reference: String) -> Puzzle {
        Puzzle(
            id: id, title: id, difficulty: .easy,
            verse: "…", reference: reference,
            publishDate: "2026-01-01", size: 5, grid: ["....."], clues: []
        )
    }

    // MARK: - Canon

    /// `BibleCanon` is a hand-copied table so the journey needn't decode the
    /// 4.6 MB Bible. That's only safe while the two agree exactly — this is the
    /// test that makes the duplication honest rather than a slow drift.
    @Test func theCanonMatchesTheBundledBible() {
        let bible = ScriptureProvider.shared.books
        #expect(bible.isEmpty == false, "bsb.json failed to load")
        #expect(BibleCanon.books.count == bible.count)
        #expect(BibleCanon.books.map(\.name) == bible.map(\.name))
        #expect(BibleCanon.books.map(\.testament) == bible.map(\.testament))
    }

    @Test func theCanonIsSixtySixBooksSplitAtMatthew() {
        #expect(BibleCanon.books.count == 66)
        #expect(BibleCanon.books(in: .old).count == 39)
        #expect(BibleCanon.books(in: .new).count == 27)
        #expect(BibleCanon.books(in: .new).first?.name == "Matthew")
    }

    @Test func bookLookupIgnoresCaseAndSurroundingSpace() {
        #expect(BibleCanon.book(named: "genesis")?.name == "Genesis")
        #expect(BibleCanon.book(named: "  1 Corinthians ")?.name == "1 Corinthians")
        #expect(BibleCanon.book(named: "Book of Mormon") == nil)
    }

    // MARK: - Anchoring a puzzle to a book

    @Test func aPuzzleIsAnchoredByItsVerseReference() {
        #expect(BibleJourney.book(for: puzzle("a", reference: "Genesis 1:1"))?.name == "Genesis")
        // Multi-word books survive: the parser splits on the *last* space.
        #expect(BibleJourney.book(for: puzzle("b", reference: "1 Corinthians 13:4-7"))?.name == "1 Corinthians")
        #expect(BibleJourney.book(for: puzzle("c", reference: "Song of Solomon 2:1"))?.name == "Song of Solomon")
    }

    @Test func anUnrecognisedReferenceCostsOnlyThatPuzzle() {
        let odd = puzzle("odd", reference: "Sirach 3:1")
        let junk = puzzle("junk", reference: "")
        #expect(BibleJourney.book(for: odd) == nil)
        #expect(BibleJourney.book(for: junk) == nil)

        // The rest of the map still adds up around it.
        let rows = BibleJourney.progress(
            completedPuzzleIDs: ["odd", "junk", "ok"],
            puzzles: [odd, junk, puzzle("ok", reference: "John 3:16")]
        )
        #expect(rows.first { $0.name == "John" }?.solved == 1)
        #expect(rows.count == 66)
    }

    // MARK: - Progress arithmetic

    @Test func progressCountsSolvedAgainstWhatExists() {
        let puzzles = [
            puzzle("g1", reference: "Genesis 1:1"),
            puzzle("g2", reference: "Genesis 2:7"),
            puzzle("j1", reference: "John 3:16"),
        ]
        let rows = BibleJourney.progress(completedPuzzleIDs: ["g1"], puzzles: puzzles)

        let genesis = rows.first { $0.name == "Genesis" }
        #expect(genesis?.solved == 1)
        #expect(genesis?.available == 2)
        #expect(genesis?.state == .touched)

        let john = rows.first { $0.name == "John" }
        #expect(john?.solved == 0)
        #expect(john?.available == 1)
        #expect(john?.state == .untouched)
    }

    /// Two thirds of the canon has no puzzle written for it. Those books must
    /// read as "nothing here yet", not as the player's unfinished business.
    @Test func aBookWithNoPuzzlesIsEmptyNotUntouched() {
        let rows = BibleJourney.progress(
            completedPuzzleIDs: [],
            puzzles: [puzzle("g1", reference: "Genesis 1:1")]
        )
        #expect(rows.first { $0.name == "Obadiah" }?.state == .empty)
        #expect(rows.first { $0.name == "Genesis" }?.state == .untouched)
    }

    /// Fourteen books ship with only one or two puzzles. Exhausting one has to
    /// count, or those books are permanently second-class on the map.
    @Test func exhaustingASmallBookCountsAsDeep() {
        let puzzles = [
            puzzle("r1", reference: "Ruth 1:16"),
            puzzle("r2", reference: "Ruth 2:12"),
        ]
        let rows = BibleJourney.progress(completedPuzzleIDs: ["r1", "r2"], puzzles: puzzles)
        let ruth = rows.first { $0.name == "Ruth" }
        #expect(ruth?.state == .deep)
        #expect(ruth?.isComplete == true)

        // One of the two is still only a visit.
        let partial = BibleJourney.progress(completedPuzzleIDs: ["r1"], puzzles: puzzles)
        #expect(partial.first { $0.name == "Ruth" }?.state == .touched)
        #expect(partial.first { $0.name == "Ruth" }?.isComplete == false)
    }

    @Test func aBookGoesDeepAtTheThreshold() {
        let puzzles = (1...BibleJourney.deepThreshold).map {
            puzzle("p\($0)", reference: "Psalm \($0):1")
        }
        let ids = Set(puzzles.map(\.id))
        let rows = BibleJourney.progress(completedPuzzleIDs: ids, puzzles: puzzles)
        #expect(rows.first { $0.name == "Psalm" }?.state == .deep)

        let allButOne = Set(puzzles.dropLast().map(\.id))
        let shallower = BibleJourney.progress(completedPuzzleIDs: allButOne, puzzles: puzzles)
        #expect(shallower.first { $0.name == "Psalm" }?.state == .touched)
    }

    @Test func rowsComeBackInReadingOrder() {
        let rows = BibleJourney.progress(completedPuzzleIDs: [], puzzles: [])
        #expect(rows.first?.name == "Genesis")
        #expect(rows.last?.name == "Revelation")
    }

    @Test func booksTouchedIgnoresUnsolvedPuzzles() {
        let puzzles = [
            puzzle("g1", reference: "Genesis 1:1"),
            puzzle("j1", reference: "John 3:16"),
        ]
        #expect(BibleJourney.booksTouched(completedPuzzleIDs: ["g1"], puzzles: puzzles) == ["Genesis"])
        #expect(BibleJourney.booksTouched(completedPuzzleIDs: [], puzzles: puzzles).isEmpty)
    }

    // MARK: - The shipped content

    /// Every puzzle that ships has to land somewhere, or it silently vanishes
    /// from the map. This is the test that catches a typo'd reference in new
    /// content before a player notices their solve didn't count.
    @Test func everyBundledPuzzleAnchorsToACanonicalBook() {
        let puzzles = PuzzleProvider.shared.allPuzzles
        #expect(puzzles.isEmpty == false)
        let orphans = puzzles.filter { BibleJourney.book(for: $0) == nil }
        #expect(orphans.isEmpty, "unanchored: \(orphans.map { "\($0.id) (\($0.reference))" })")
    }
}
