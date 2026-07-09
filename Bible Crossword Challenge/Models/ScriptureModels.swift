//
//  ScriptureModels.swift
//  Bible Crossword Challenge
//
//  Value types describing the bundled Bible (Berean Standard Bible, public
//  domain). Decoded from `bsb.json` and consumed by the Read tab. Fully offline,
//  mirroring how `puzzles.json` backs the game.
//

import Foundation

enum Testament: String, Codable, Hashable, CaseIterable {
    case old, new

    var label: String { self == .old ? "Old Testament" : "New Testament" }
}

struct Bible: Codable, Hashable {
    let translation: String
    let abbreviation: String
    let books: [BibleBook]
}

struct BibleBook: Codable, Hashable, Identifiable {
    let name: String
    let testament: Testament
    let chapters: [BibleChapter]

    var id: String { name }
    var chapterCount: Int { chapters.count }
}

struct BibleChapter: Codable, Hashable, Identifiable {
    let number: Int
    let verses: [BibleVerse]

    var id: Int { number }
}

struct BibleVerse: Codable, Hashable, Identifiable {
    let number: Int
    let text: String

    var id: Int { number }
}

// MARK: - Reference

/// A parsed scripture reference such as "Isaiah 11:6" or "1 Corinthians 13:4-7".
/// Used to deep-link a puzzle's verse into the reader.
struct ScriptureRef: Hashable {
    let book: String
    let chapter: Int
    /// The starting verse, or `nil` for a whole-chapter reference. Verse ranges
    /// ("13:4-7") keep only the start — enough to scroll to.
    let verse: Int?

    init(book: String, chapter: Int, verse: Int? = nil) {
        self.book = book
        self.chapter = chapter
        self.verse = verse
    }

    /// Parses "Book C:V", "Book C:V-W", or "Book C". The book name is everything
    /// before the last space, so multi-word books ("1 Corinthians", "Song of
    /// Solomon") parse correctly.
    init?(_ raw: String) {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let sp = s.range(of: " ", options: .backwards) else { return nil }
        let bookPart = String(s[..<sp.lowerBound]).trimmingCharacters(in: .whitespaces)
        let cvPart = String(s[sp.upperBound...]).trimmingCharacters(in: .whitespaces)
        guard !bookPart.isEmpty else { return nil }

        let cv = cvPart.split(separator: ":", maxSplits: 1)
        guard let first = cv.first, let chap = Int(first) else { return nil }
        self.book = bookPart
        self.chapter = chap

        if cv.count > 1 {
            // Verse may be a single number ("6") or a range ("4-7" / "4–7").
            let start = cv[1].split(whereSeparator: { $0 == "-" || $0 == "\u{2013}" }).first
            self.verse = start.flatMap { Int($0) }
        } else {
            self.verse = nil
        }
    }
}
