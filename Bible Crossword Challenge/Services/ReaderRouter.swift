//
//  ReaderRouter.swift
//  Bible Crossword Challenge
//
//  Drives the scripture reader, which exists only as a deep-link target — a
//  puzzle's verse reference sets `target` and RootView presents the reader
//  modally over whatever tab is in front. There is no standalone Read tab.
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
    }

    /// The passage currently requested. Non-nil presents the reader; RootView
    /// binds this to a `fullScreenCover` and clears it on dismiss.
    var target: Target?

    /// Open a reference string like "Isaiah 11:6" in the modal reader.
    func open(reference: String) {
        guard let ref = ScriptureRef(reference) else { return }
        target = Target(book: ref.book, chapter: ref.chapter, verse: ref.verse)
    }
}
