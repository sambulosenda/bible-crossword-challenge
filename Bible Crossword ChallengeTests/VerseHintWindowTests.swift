//
//  VerseHintWindowTests.swift
//  Bible Crossword ChallengeTests
//
//  The verse-first hint sheet's window into a chapter, against the bundled
//  Bible: the clue's verse with one on each side, clamped at the chapter's
//  ends, and the opening verses for a chapter-only reference.
//

import Testing
import Foundation
@testable import Bible_Crossword_Challenge

struct VerseHintWindowTests {
    private let scripture = ScriptureProvider.shared

    @Test func verseWithNeighbours() {
        let target = ReaderRouter.Target(book: "Genesis", chapter: 28, verse: 12, source: "hint")
        let window = VerseHintSheet.window(around: target, in: scripture)
        #expect(window.map(\.number) == [11, 12, 13])
    }

    @Test func firstVerseClampsAtTheStart() {
        let target = ReaderRouter.Target(book: "John", chapter: 1, verse: 1, source: "hint")
        let window = VerseHintSheet.window(around: target, in: scripture)
        #expect(window.map(\.number) == [1, 2])
    }

    @Test func lastVerseClampsAtTheEnd() {
        let target = ReaderRouter.Target(book: "Jude", chapter: 1, verse: 25, source: "hint")
        let window = VerseHintSheet.window(around: target, in: scripture)
        #expect(window.map(\.number) == [24, 25])
    }

    @Test func chapterOnlyReferenceShowsTheOpening() {
        let target = ReaderRouter.Target(book: "Psalm", chapter: 23, verse: nil, source: "clue")
        let window = VerseHintSheet.window(around: target, in: scripture)
        #expect(window.map(\.number) == [1, 2])
    }

    @Test func unknownPassageIsEmpty() {
        let target = ReaderRouter.Target(book: "Hezekiah", chapter: 3, verse: 4, source: "clue")
        #expect(VerseHintSheet.window(around: target, in: scripture).isEmpty)
    }

    @Test func targetKeepsItsSourceOutOfIdentity() {
        // Same passage from two doors coalesces as one presented item.
        let a = ReaderRouter.Target(reference: "Isaiah 11:6", source: "hint")
        let b = ReaderRouter.Target(reference: "Isaiah 11:6", source: "clue")
        #expect(a?.id == b?.id)
        #expect(a?.source == "hint")
    }
}
