//
//  ScriptureSearchTests.swift
//  Bible Crossword ChallengeTests
//
//  The Read tab's search box, against the bundled Bible: references in the
//  ways people actually type them, books on their own, and word search.
//

import Testing
import Foundation
@testable import Bible_Crossword_Challenge

struct ScriptureSearchTests {
    private let books = ScriptureProvider.shared.books

    private func ref(_ q: String) -> ScriptureRef? { ScriptureSearch.search(q, in: books).reference }
    private func book(_ q: String) -> String? { ScriptureSearch.search(q, in: books).book?.name }

    @Test func referencesInTheWaysPeopleTypeThem() {
        #expect(ref("John 3:16") == ScriptureRef(book: "John", chapter: 3, verse: 16))
        #expect(ref("john 3 16") == ScriptureRef(book: "John", chapter: 3, verse: 16))
        #expect(ref("jn 3.16") == ScriptureRef(book: "John", chapter: 3, verse: 16))
        #expect(ref("john3:16") == ScriptureRef(book: "John", chapter: 3, verse: 16))
        #expect(ref("1cor13:4") == ScriptureRef(book: "1 Corinthians", chapter: 13, verse: 4))
        #expect(ref("I Corinthians 13") == ScriptureRef(book: "1 Corinthians", chapter: 13, verse: nil))
        #expect(ref("first kings 19") == ScriptureRef(book: "1 Kings", chapter: 19, verse: nil))
        #expect(ref("ps 23") == ScriptureRef(book: "Psalm", chapter: 23, verse: nil))
        #expect(ref("Psalms 23:1") == ScriptureRef(book: "Psalm", chapter: 23, verse: 1))
        #expect(ref("song of songs 2:1") == ScriptureRef(book: "Song of Solomon", chapter: 2, verse: 1))
        #expect(ref("rev 21") == ScriptureRef(book: "Revelation", chapter: 21, verse: nil))
        #expect(ref("Gen 1:1") == ScriptureRef(book: "Genesis", chapter: 1, verse: 1))
    }

    @Test func aBookAloneIsABook() {
        #expect(book("Ruth") == "Ruth")
        #expect(book("job") == "Job")
        #expect(book("revelations") == "Revelation")
        #expect(book("1 cor") == "1 Corinthians")
        // Prefix picks canon order: Judges sits before Jude.
        #expect(book("jud") == "Judges")
        #expect(ref("Ruth") == nil)
    }

    @Test func aChapterTheBookLacksOffersTheBook() {
        let results = ScriptureSearch.search("Jude 3", in: books)
        #expect(results.reference == nil)
        #expect(results.book?.name == "Jude")
    }

    @Test func wordsSearchTheText() {
        // The BSB sets it "a still, small voice" — a phrase search is literal.
        let results = ScriptureSearch.search("small voice", in: books)
        #expect(results.kind == "word")
        #expect(results.verses.contains { $0.book == "1 Kings" && $0.chapter == 19 && $0.verse == 12 })
        #expect(results.verses.allSatisfy { $0.text.localizedCaseInsensitiveContains("small voice") })

        let shepherd = ScriptureSearch.search("shepherd", in: books)
        #expect(shepherd.verses.count == ScriptureSearch.maxHits)
        #expect(shepherd.verses.first?.book == "Genesis")
    }

    @Test func tooShortOrUnknownIsEmpty() {
        #expect(ScriptureSearch.search("ab", in: books).isEmpty)
        #expect(ScriptureSearch.search("", in: books).isEmpty)
        #expect(ScriptureSearch.search("xyzzyqq", in: books).kind == "none")
        // One letter never matches a book: "j" would always be Joshua.
        #expect(ScriptureSearch.search("j 3", in: books).reference == nil)
    }

    @Test func recentChaptersDedupeAndCap() {
        var raw = ""
        raw = RecentChapters.recording(book: "John", chapter: 3, in: raw)
        raw = RecentChapters.recording(book: "Psalm", chapter: 23, in: raw)
        raw = RecentChapters.recording(book: "John", chapter: 3, in: raw)
        #expect(RecentChapters.entries(from: raw).map(\.reference) == ["John 3", "Psalm 23"])
        for c in 1...9 { raw = RecentChapters.recording(book: "Genesis", chapter: c, in: raw) }
        let entries = RecentChapters.entries(from: raw)
        #expect(entries.count == RecentChapters.limit)
        #expect(entries.first?.reference == "Genesis 9")
    }
}
