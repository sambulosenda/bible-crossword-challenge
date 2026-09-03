//
//  ScriptureProvider.swift
//  Bible Crossword Challenge
//
//  Loads the bundled Berean Standard Bible. The ~4.6 MB JSON is decoded lazily
//  on first access (when the Read tab first opens) so it stays off the launch
//  path. Mirrors `PuzzleProvider` and keeps the app fully offline.
//

import Foundation

final class ScriptureProvider {
    static let shared = ScriptureProvider()

    private let bundle: Bundle
    private var cached: Bible?
    /// Case-insensitive book lookup, built once alongside the decode.
    private var byName: [String: BibleBook] = [:]

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    /// Decoded on first use, then cached for the process lifetime.
    var bible: Bible {
        if let cached { return cached }
        let loaded = Self.load(bundle: bundle)
        install(loaded)
        return loaded
    }

    /// Decodes off the main thread when nothing has needed the Bible yet, so
    /// the first screen that shows it (the Read tab) doesn't pay the decode
    /// as a hitch. `bible` still decodes synchronously for a caller that
    /// can't wait; a caller that can should `await` this first. Safe to call
    /// repeatedly: a decode that lands after another already did is dropped.
    func preload() async {
        guard cached == nil else { return }
        let bundle = self.bundle
        let loaded = await Task.detached(priority: .userInitiated) {
            Self.load(bundle: bundle)
        }.value
        guard cached == nil else { return }
        install(loaded)
    }

    private func install(_ loaded: Bible) {
        cached = loaded
        byName = Dictionary(
            loaded.books.map { ($0.name.lowercased(), $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    var books: [BibleBook] { bible.books }

    func book(named name: String) -> BibleBook? {
        _ = bible // ensure `byName` is populated
        return byName[name.lowercased()]
    }

    func chapter(_ ref: ScriptureRef) -> (book: BibleBook, chapter: BibleChapter)? {
        guard let book = book(named: ref.book),
              let chapter = book.chapters.first(where: { $0.number == ref.chapter })
        else { return nil }
        return (book, chapter)
    }

    private nonisolated static func load(bundle: Bundle) -> Bible {
        guard let url = bundle.url(forResource: "bsb", withExtension: "json") else {
            assertionFailure("bsb.json missing from bundle")
            return Bible(translation: "", abbreviation: "", books: [])
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(Bible.self, from: data)
        } catch {
            assertionFailure("Failed to decode bsb.json: \(error)")
            return Bible(translation: "", abbreviation: "", books: [])
        }
    }
}
