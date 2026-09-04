//
//  RecentChapters.swift
//  Bible Crossword Challenge
//
//  The last few chapters opened in the reader, newest first, for the Read
//  tab's "Recent" row. One string in UserDefaults ("Book|chapter;…") so both
//  the reader (writer) and the tab (reader) can hold it as `@AppStorage`.
//

import Foundation

enum RecentChapters {
    static let key = "read.recent"
    static let limit = 5

    struct Entry: Hashable, Identifiable {
        let book: String
        let chapter: Int
        var id: String { "\(book)|\(chapter)" }
        var reference: String { "\(book) \(chapter)" }
    }

    static func entries(from raw: String) -> [Entry] {
        raw.split(separator: ";").compactMap { item in
            let parts = item.split(separator: "|", maxSplits: 1)
            guard parts.count == 2, let chapter = Int(parts[1]) else { return nil }
            return Entry(book: String(parts[0]), chapter: chapter)
        }
    }

    /// `raw` with `book chapter` moved to the front, trimmed to `limit`.
    static func recording(book: String, chapter: Int, in raw: String) -> String {
        let entry = Entry(book: book, chapter: chapter)
        let rest = entries(from: raw).filter { $0 != entry }
        return ([entry] + rest).prefix(limit).map(\.id).joined(separator: ";")
    }
}
