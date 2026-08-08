//
//  BibleJourney.swift
//  Bible Crossword Challenge
//
//  Which books of Scripture a player's solves have taken them through.
//
//  Achievements are discrete — five puzzles, a streak, a fast solve. The journey
//  is continuous: "I've been through twelve books". It's derived, never stored,
//  so it needs no new synced field and no CloudKit schema deploy — the records
//  that back it are already on the device and already sync.
//
//  Every puzzle is anchored to one book, read from its verse reference. Clue
//  references would have been the richer source but only ~2% of clues carry one,
//  where every puzzle carries a verse; when clue coverage grows, `books(for:)`
//  is the single place that has to widen.
//

import Foundation

/// The 66-book Protestant canon, in reading order.
///
/// Deliberately a small static table rather than a read of `bsb.json`: that file
/// is 4.6 MB and is decoded lazily so it stays off the launch path (see
/// `ScriptureProvider`). Deriving the journey from it would drag the whole Bible
/// into memory the moment someone opened Profile, to learn 66 names that have
/// not changed in centuries. `BibleJourneyTests` pins this list against the
/// bundled Bible so the two cannot drift.
enum BibleCanon {
    struct Book: Identifiable, Hashable {
        let name: String
        let testament: Testament
        var id: String { name }

        init(_ name: String, _ testament: Testament) {
            self.name = name
            self.testament = testament
        }
    }

    static let books: [Book] = [
        Book("Genesis", .old), Book("Exodus", .old), Book("Leviticus", .old),
        Book("Numbers", .old), Book("Deuteronomy", .old), Book("Joshua", .old),
        Book("Judges", .old), Book("Ruth", .old), Book("1 Samuel", .old),
        Book("2 Samuel", .old), Book("1 Kings", .old), Book("2 Kings", .old),
        Book("1 Chronicles", .old), Book("2 Chronicles", .old), Book("Ezra", .old),
        Book("Nehemiah", .old), Book("Esther", .old), Book("Job", .old),
        Book("Psalm", .old), Book("Proverbs", .old), Book("Ecclesiastes", .old),
        Book("Song of Solomon", .old), Book("Isaiah", .old), Book("Jeremiah", .old),
        Book("Lamentations", .old), Book("Ezekiel", .old), Book("Daniel", .old),
        Book("Hosea", .old), Book("Joel", .old), Book("Amos", .old),
        Book("Obadiah", .old), Book("Jonah", .old), Book("Micah", .old),
        Book("Nahum", .old), Book("Habakkuk", .old), Book("Zephaniah", .old),
        Book("Haggai", .old), Book("Zechariah", .old), Book("Malachi", .old),
        Book("Matthew", .new), Book("Mark", .new), Book("Luke", .new),
        Book("John", .new), Book("Acts", .new), Book("Romans", .new),
        Book("1 Corinthians", .new), Book("2 Corinthians", .new), Book("Galatians", .new),
        Book("Ephesians", .new), Book("Philippians", .new), Book("Colossians", .new),
        Book("1 Thessalonians", .new), Book("2 Thessalonians", .new), Book("1 Timothy", .new),
        Book("2 Timothy", .new), Book("Titus", .new), Book("Philemon", .new),
        Book("Hebrews", .new), Book("James", .new), Book("1 Peter", .new),
        Book("2 Peter", .new), Book("1 John", .new), Book("2 John", .new),
        Book("3 John", .new), Book("Jude", .new), Book("Revelation", .new),
    ]

    /// Case-insensitive lookup, so a reference's capitalisation can't lose a book.
    private static let byName: [String: Book] = Dictionary(
        books.map { ($0.name.lowercased(), $0) },
        uniquingKeysWith: { first, _ in first }
    )

    static func book(named name: String) -> Book? {
        byName[name.trimmingCharacters(in: .whitespaces).lowercased()]
    }

    private static let order: [String: Int] = Dictionary(
        books.enumerated().map { ($0.element.name, $0.offset) },
        uniquingKeysWith: { first, _ in first }
    )

    /// Position in reading order, so a subset of books can be sorted back into
    /// canon sequence. Unknown names sort last rather than first — an
    /// unrecognised book belongs at the end of a list, not ahead of Genesis.
    static func position(of name: String) -> Int {
        order[name] ?? books.count
    }

    static func books(in testament: Testament) -> [Book] {
        books.filter { $0.testament == testament }
    }
}

enum BibleJourney {
    /// Puzzles in one book before it counts as more than passed through.
    static let deepThreshold = 3

    /// Where one book stands. `available` is what the bundle can offer, which is
    /// what stops the map reading as a scolding: two thirds of the canon has no
    /// puzzle written for it yet, and that is the content's doing, not the
    /// player's.
    struct BookProgress: Identifiable, Hashable {
        let book: BibleCanon.Book
        let solved: Int
        let available: Int

        var id: String { book.name }
        var name: String { book.name }
        var testament: Testament { book.testament }

        enum State {
            /// No puzzle in the bundle touches this book yet.
            case empty
            case untouched
            case touched
            case deep
        }

        /// Fourteen books carry only one or two puzzles, so a flat "three or
        /// more" top state would be unreachable in them: solve everything Ruth
        /// has and it would still read as less explored than Genesis at three of
        /// twenty. Exhausting a book counts as knowing it.
        var state: State {
            if available == 0 { return .empty }
            if solved == 0 { return .untouched }
            if solved >= available { return .deep }
            return solved >= BibleJourney.deepThreshold ? .deep : .touched
        }

        /// True when there is nothing left to solve here.
        var isComplete: Bool { available > 0 && solved >= available }
    }

    /// The whole journey, in canonical order.
    ///
    /// Takes its inputs rather than reaching for the providers so the arithmetic
    /// can be tested without a bundle.
    static func progress(
        completedPuzzleIDs: Set<String>,
        puzzles: [Puzzle]
    ) -> [BookProgress] {
        var solved: [String: Int] = [:]
        var available: [String: Int] = [:]

        for puzzle in puzzles {
            guard let book = book(for: puzzle) else { continue }
            available[book.name, default: 0] += 1
            if completedPuzzleIDs.contains(puzzle.id) {
                solved[book.name, default: 0] += 1
            }
        }

        return BibleCanon.books.map { book in
            BookProgress(
                book: book,
                solved: solved[book.name] ?? 0,
                available: available[book.name] ?? 0
            )
        }
    }

    /// The books a set of completed puzzles has touched.
    static func booksTouched(completedPuzzleIDs: Set<String>, puzzles: [Puzzle]) -> Set<String> {
        var touched: Set<String> = []
        for puzzle in puzzles where completedPuzzleIDs.contains(puzzle.id) {
            if let book = book(for: puzzle) { touched.insert(book.name) }
        }
        return touched
    }

    /// The book a puzzle is anchored to, or nil when its reference names one this
    /// canon doesn't carry. An unrecognised reference costs that puzzle its place
    /// on the map and nothing else — no crash, no zeroed progress.
    static func book(for puzzle: Puzzle) -> BibleCanon.Book? {
        guard let ref = ScriptureRef(puzzle.reference) else { return nil }
        return BibleCanon.book(named: ref.book)
    }
}
