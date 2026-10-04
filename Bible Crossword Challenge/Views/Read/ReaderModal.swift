//
//  ReaderModal.swift
//  Bible Crossword Challenge
//
//  Modal host for a deep-linked passage. Opens straight to the chapter reader
//  (browsing is reachable from the reader's own "Jump to"); a Close button
//  dismisses back to wherever the reference was tapped.
//
//  Two things present it. RootView presents the `ReaderRouter` target over the
//  tab bar, which is right for references tapped on a plain screen. The clue
//  list presents one itself, because a sheet cannot ask an ancestor to put up a
//  full-screen cover while the sheet is still on top — the request is simply
//  dropped. Presenting it locally also returns the player to the clue list on
//  Close, rather than tearing the list down to read one verse.
//

import SwiftUI

struct ReaderModal: View {
    let target: ReaderRouter.Target
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ChapterReaderView(
                startBook: target.book,
                startChapter: target.chapter,
                highlightVerse: target.verse,
                source: target.source,
                showsPuzzleLink: false
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // A symbol, not the word: a title-only item can't go on
                    // iPhone Duo's side rail, and would hold a horizontal bar
                    // open across the cover for itself.
                    Button { dismiss() } label: { Label("Close", systemImage: "xmark") }
                }
            }
        }
    }
}
