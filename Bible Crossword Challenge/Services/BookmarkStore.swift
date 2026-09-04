//
//  BookmarkStore.swift
//  Bible Crossword Challenge
//
//  Verses the reader has kept. UserDefaults for the same reason memory verses
//  are (see `MemoryVerseStore`): a new synced model means a CloudKit schema
//  deploy, and a bookmark is low-stakes, re-creatable state. Entries are
//  Codable so a later move to a synced model is additive.
//

import Foundation
import Observation
import os

@Observable
final class BookmarkStore {
    static let shared = BookmarkStore()

    struct Entry: Codable, Equatable, Hashable, Identifiable {
        let book: String
        let chapter: Int
        let verse: Int
        /// Denormalised so the list renders without a bundle decode.
        let verseText: String
        let addedAt: Date

        var id: String { BookmarkStore.key(book: book, chapter: chapter, verse: verse) }
        var reference: String { "\(book) \(chapter):\(verse)" }
    }

    private let defaults: UserDefaults
    private let now: () -> Date
    private let storageKey = "read.bookmarks"

    /// Newest first.
    private(set) var entries: [Entry] = []

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.now = now
        self.entries = Self.load(from: defaults, key: storageKey)
    }

    static func key(book: String, chapter: Int, verse: Int) -> String {
        "\(book.lowercased())|\(chapter)|\(verse)"
    }

    func isBookmarked(book: String, chapter: Int, verse: Int) -> Bool {
        let key = Self.key(book: book, chapter: chapter, verse: verse)
        return entries.contains { $0.id == key }
    }

    /// Verses bookmarked in one chapter — what a page needs to mark its rows.
    func bookmarkedVerses(book: String, chapter: Int) -> Set<Int> {
        Set(entries.filter { $0.book == book && $0.chapter == chapter }.map(\.verse))
    }

    /// Adds the verse, or removes it if it's already kept. Returns whether it
    /// is bookmarked afterwards.
    @discardableResult
    func toggle(book: String, chapter: Int, verse: Int, verseText: String) -> Bool {
        let key = Self.key(book: book, chapter: chapter, verse: verse)
        if let index = entries.firstIndex(where: { $0.id == key }) {
            entries.remove(at: index)
            persist()
            return false
        }
        entries.insert(
            Entry(book: book, chapter: chapter, verse: verse, verseText: verseText, addedAt: now()),
            at: 0
        )
        persist()
        return true
    }

    func remove(id: String) {
        entries.removeAll { $0.id == id }
        persist()
    }

    private func persist() {
        do {
            defaults.set(try JSONEncoder().encode(entries), forKey: storageKey)
        } catch {
            Log.persistence.error("Failed to persist bookmarks: \(error, privacy: .public)")
        }
    }

    private static func load(from defaults: UserDefaults, key: String) -> [Entry] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([Entry].self, from: data)) ?? []
    }
}
