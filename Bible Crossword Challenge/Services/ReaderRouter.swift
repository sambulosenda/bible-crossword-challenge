//
//  ReaderRouter.swift
//  Bible Crossword Challenge
//
//  Drives the modal scripture reader — a puzzle's verse reference sets
//  `target` and RootView presents the reader over whatever tab is in front.
//  The Read tab (`ReadView`) hosts the same reader for browsing; this stays
//  the route for a reference tapped mid-puzzle.
//

import SwiftUI

@Observable
final class ReaderRouter {
    static let shared = ReaderRouter()

    /// A passage to open in the modal reader, addressed by content so identical
    /// references coalesce.
    struct Target: Identifiable, Hashable {
        let book: String
        let chapter: Int
        let verse: Int?

        var id: String { "\(book)-\(chapter)-\(verse ?? 0)" }

        /// Nil for a reference the bundled Bible can't address, so a citation
        /// that doesn't resolve shows nothing rather than opening an empty
        /// reader.
        init?(reference: String) {
            guard let ref = ScriptureRef(reference) else { return nil }
            self.init(book: ref.book, chapter: ref.chapter, verse: ref.verse)
        }

        init(book: String, chapter: Int, verse: Int?) {
            self.book = book
            self.chapter = chapter
            self.verse = verse
        }
    }

    /// The passage currently requested. Non-nil presents the reader; RootView
    /// binds this to a `fullScreenCover` and clears it on dismiss.
    var target: Target?

    /// Open a reference string like "Isaiah 11:6" in the modal reader.
    ///
    /// Only for references tapped on a screen that isn't itself inside a sheet:
    /// the cover this drives hangs off the tab bar, and UIKit drops the request
    /// if something is already presented over it. A sheet should present its own
    /// `ReaderModal` instead.
    func open(reference: String) {
        guard let target = Target(reference: reference) else { return }
        self.target = target
    }
}
