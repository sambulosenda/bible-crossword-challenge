//
//  BookmarkStoreTests.swift
//  Bible Crossword ChallengeTests
//

import Testing
import Foundation
@testable import Bible_Crossword_Challenge

private func makeStore() -> (store: BookmarkStore, defaults: UserDefaults) {
    let defaults = UserDefaults(suiteName: "bookmark-tests-\(UUID().uuidString)")!
    var t = Date(timeIntervalSince1970: 1_700_000_000)
    let store = BookmarkStore(defaults: defaults, now: { t += 1; return t })
    return (store, defaults)
}

struct BookmarkStoreTests {

    @Test func toggleAddsThenRemoves() {
        let (store, _) = makeStore()
        #expect(store.toggle(book: "John", chapter: 3, verse: 16, verseText: "For God so loved"))
        #expect(store.isBookmarked(book: "John", chapter: 3, verse: 16))
        #expect(store.entries.first?.reference == "John 3:16")
        #expect(!store.toggle(book: "John", chapter: 3, verse: 16, verseText: "For God so loved"))
        #expect(store.entries.isEmpty)
    }

    @Test func newestFirstAndPerChapterLookup() {
        let (store, _) = makeStore()
        store.toggle(book: "John", chapter: 3, verse: 16, verseText: "a")
        store.toggle(book: "John", chapter: 3, verse: 17, verseText: "b")
        store.toggle(book: "Psalm", chapter: 23, verse: 1, verseText: "c")
        #expect(store.entries.map(\.reference) == ["Psalm 23:1", "John 3:17", "John 3:16"])
        #expect(store.bookmarkedVerses(book: "John", chapter: 3) == [16, 17])
        #expect(store.bookmarkedVerses(book: "John", chapter: 4).isEmpty)
    }

    @Test func keyIsCaseInsensitiveOnTheBook() {
        let (store, _) = makeStore()
        store.toggle(book: "John", chapter: 3, verse: 16, verseText: "a")
        #expect(store.isBookmarked(book: "john", chapter: 3, verse: 16))
    }

    @Test func survivesRelaunch() {
        let (store, defaults) = makeStore()
        store.toggle(book: "John", chapter: 3, verse: 16, verseText: "a")
        let reloaded = BookmarkStore(defaults: defaults)
        #expect(reloaded.entries.count == 1)
        reloaded.remove(id: reloaded.entries[0].id)
        #expect(BookmarkStore(defaults: defaults).entries.isEmpty)
    }
}
