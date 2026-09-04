//
//  ScriptureSearch.swift
//  Bible Crossword Challenge
//
//  The Read tab's search box. A query is either a reference ("John 3:16",
//  "jn 3 16", "1cor13", "ps 23"), a book on its own ("Ruth"), or words to
//  find in the text ("still small voice"). Pure functions over the decoded
//  Bible so the rules are testable without a view.
//

import Foundation

enum ScriptureSearch {
    struct VerseHit: Hashable, Identifiable {
        let book: String
        let chapter: Int
        let verse: Int
        let text: String
        var id: String { "\(book)|\(chapter)|\(verse)" }
        var reference: String { "\(book) \(chapter):\(verse)" }
    }

    struct Results: Equatable {
        /// A book the query named without a chapter ("Ruth", "1 cor").
        var book: BibleBook?
        /// A chapter (and maybe verse) the query named.
        var reference: ScriptureRef?
        /// Verses whose text contains the query, when it named nothing.
        var verses: [VerseHit] = []

        var isEmpty: Bool { book == nil && reference == nil && verses.isEmpty }

        /// For `read_search`: reference / book / word / none.
        var kind: String {
            if reference != nil { return "reference" }
            if book != nil { return "book" }
            return verses.isEmpty ? "none" : "word"
        }
        var count: Int { (reference == nil ? 0 : 1) + (book == nil ? 0 : 1) + verses.count }
    }

    /// Enough verses to scroll; a word that hits more wants a longer query.
    static let maxHits = 50
    /// Shorter than this matches half the Bible.
    static let minWordLength = 3

    /// Names the reader's canon doesn't spell the way people type them.
    private static let aliases: [String: String] = [
        "psalms": "psalm", "ps": "psalm", "pss": "psalm",
        "song of songs": "song of solomon", "songs": "song of solomon", "sos": "song of solomon",
        "canticles": "song of solomon",
        "revelations": "revelation", "rev": "revelation",
        "mt": "matthew", "mk": "mark", "lk": "luke", "jn": "john",
        "1 jn": "1 john", "2 jn": "2 john", "3 jn": "3 john",
        "jas": "james", "phlm": "philemon", "phm": "philemon",
        "dt": "deuteronomy", "deut": "deuteronomy", "jdg": "judges", "jgs": "judges",
        "1 kgs": "1 kings", "2 kgs": "2 kings", "1 sm": "1 samuel", "2 sm": "2 samuel",
        "eccl": "ecclesiastes", "qoh": "ecclesiastes",
    ]

    // MARK: - Reference parsing

    struct Parsed: Equatable {
        let book: BibleBook
        let chapter: Int?
        let verse: Int?
    }

    /// "Book", "Book C", "Book C:V", "Book C V", "Book C.V"; ordinal prefixes
    /// as "1", "i", "1st" or "first"; the space after the ordinal optional.
    static func parseReference(_ query: String, books: [BibleBook]) -> Parsed? {
        var q = query.lowercased()
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return nil }
        q = q.replacingOccurrences(of: #"^(first|1st)\s*"#, with: "1 ", options: .regularExpression)
        q = q.replacingOccurrences(of: #"^(second|2nd)\s*"#, with: "2 ", options: .regularExpression)
        q = q.replacingOccurrences(of: #"^(third|3rd)\s*"#, with: "3 ", options: .regularExpression)
        q = q.replacingOccurrences(of: #"^iii\s*"#, with: "3 ", options: .regularExpression)
        q = q.replacingOccurrences(of: #"^ii\s*"#, with: "2 ", options: .regularExpression)
        q = q.replacingOccurrences(of: #"^i\s+"#, with: "1 ", options: .regularExpression)
        q = q.replacingOccurrences(of: #"^([1-3])\s*(?=[a-z])"#, with: "$1 ", options: .regularExpression)
        q = q.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)

        let pattern = #"^([1-3] )?([a-z][a-z .']*?)\s*(\d+)?(?:[:. ]\s*(\d+))?\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let m = regex.firstMatch(in: q, range: NSRange(q.startIndex..., in: q))
        else { return nil }
        func group(_ i: Int) -> String? {
            guard let r = Range(m.range(at: i), in: q) else { return nil }
            return String(q[r])
        }
        let name = ((group(1) ?? "") + (group(2) ?? "")).trimmingCharacters(in: .whitespaces)
        guard let book = matchBook(name, in: books) else { return nil }
        let chapter = group(3).flatMap(Int.init)
        let verse = group(4).flatMap(Int.init)
        if let chapter, !(1...book.chapterCount).contains(chapter) {
            // A chapter the book doesn't have: offer the book, not a dead page.
            return Parsed(book: book, chapter: nil, verse: nil)
        }
        return Parsed(book: book, chapter: chapter, verse: verse)
    }

    /// Exact name, then alias, then the first book in canon order whose name
    /// starts with what was typed (spaces ignored, so "1cor" finds
    /// 1 Corinthians). Two letters minimum: "j" would always be Joshua.
    static func matchBook(_ raw: String, in books: [BibleBook]) -> BibleBook? {
        let name = raw.trimmingCharacters(in: .whitespaces)
        guard name.count >= 2 else { return nil }
        if let exact = books.first(where: { $0.name.lowercased() == name }) { return exact }
        if let alias = aliases[name], let book = books.first(where: { $0.name.lowercased() == alias }) {
            return book
        }
        let squashed = name.replacingOccurrences(of: " ", with: "")
        return books.first { $0.name.lowercased().replacingOccurrences(of: " ", with: "").hasPrefix(squashed) }
    }

    // MARK: - Search

    static func search(_ query: String, in books: [BibleBook]) -> Results {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return Results() }
        if let parsed = parseReference(trimmed, books: books) {
            if let chapter = parsed.chapter {
                return Results(reference: ScriptureRef(book: parsed.book.name, chapter: chapter, verse: parsed.verse))
            }
            return Results(book: parsed.book)
        }
        guard trimmed.count >= minWordLength else { return Results() }
        var hits: [VerseHit] = []
        for book in books {
            for chapter in book.chapters {
                for verse in chapter.verses
                where verse.text.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive]) != nil {
                    hits.append(VerseHit(book: book.name, chapter: chapter.number, verse: verse.number, text: verse.text))
                    if hits.count == maxHits { return Results(verses: hits) }
                }
            }
        }
        return Results(verses: hits)
    }
}
