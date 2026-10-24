//
//  BibleCanon+Abbreviation.swift
//  Bible Crossword Challenge
//
//  Short book names for the serif marks on pack covers ("Ps", "1 Sa", "Lk").
//  The common study-Bible forms, kept short enough to set large in a cover's
//  corner: two to four letters, with the number kept for numbered books.
//

import Foundation

extension BibleCanon.Book {
    /// The book's short mark — "Ps" for Psalms, "1 Sa" for 1 Samuel. Falls
    /// back to the first three letters for a name the table doesn't cover, so
    /// a cover always has something to show.
    var abbreviation: String {
        Self.abbreviations[name] ?? String(name.prefix(3))
    }

    private static let abbreviations: [String: String] = [
        "Genesis": "Gen", "Exodus": "Ex", "Leviticus": "Lev", "Numbers": "Num",
        "Deuteronomy": "Deut", "Joshua": "Josh", "Judges": "Judg", "Ruth": "Ru",
        "1 Samuel": "1 Sa", "2 Samuel": "2 Sa", "1 Kings": "1 Ki", "2 Kings": "2 Ki",
        "1 Chronicles": "1 Ch", "2 Chronicles": "2 Ch", "Ezra": "Ezra",
        "Nehemiah": "Neh", "Esther": "Est", "Job": "Job", "Psalm": "Ps",
        "Proverbs": "Prov", "Ecclesiastes": "Eccl", "Song of Solomon": "Song",
        "Isaiah": "Isa", "Jeremiah": "Jer", "Lamentations": "Lam", "Ezekiel": "Ezek",
        "Daniel": "Dan", "Hosea": "Hos", "Joel": "Joel", "Amos": "Amos",
        "Obadiah": "Obad", "Jonah": "Jon", "Micah": "Mic", "Nahum": "Nah",
        "Habakkuk": "Hab", "Zephaniah": "Zeph", "Haggai": "Hag", "Zechariah": "Zech",
        "Malachi": "Mal",
        "Matthew": "Mt", "Mark": "Mk", "Luke": "Lk", "John": "Jn", "Acts": "Ac",
        "Romans": "Rom", "1 Corinthians": "1 Co", "2 Corinthians": "2 Co",
        "Galatians": "Gal", "Ephesians": "Eph", "Philippians": "Phil",
        "Colossians": "Col", "1 Thessalonians": "1 Th", "2 Thessalonians": "2 Th",
        "1 Timothy": "1 Ti", "2 Timothy": "2 Ti", "Titus": "Titus", "Philemon": "Phlm",
        "Hebrews": "Heb", "James": "Jas", "1 Peter": "1 Pe", "2 Peter": "2 Pe",
        "1 John": "1 Jn", "2 John": "2 Jn", "3 John": "3 Jn", "Jude": "Jude",
        "Revelation": "Rev",
    ]
}
