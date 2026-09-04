//
//  PuzzleLaunch.swift
//  Bible Crossword Challenge
//
//  A request to play a puzzle from somewhere that can't push it itself — the
//  reader, which may be a full-screen cover over any tab. RootView watches
//  `pendingID`, drops the cover, switches to Today and pushes the grid with
//  entry source "read". The mirror of `ReaderRouter`.
//
//  Not for links and challenges: those go through RootView's own `openPuzzle`,
//  which bypasses the archive gate on purpose. A chip has already been gated
//  by the time it asks.
//

import SwiftUI

@Observable
final class PuzzleLaunch {
    static let shared = PuzzleLaunch()

    /// Set to ask; RootView clears it once the grid is pushed.
    var pendingID: String?

    func play(id: String) {
        pendingID = id
    }
}
