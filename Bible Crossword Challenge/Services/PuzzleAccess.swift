//
//  PuzzleAccess.swift
//  Bible Crossword Challenge
//
//  Who may play what. One source of truth, so Library, packs and any future
//  entry point can't drift into disagreeing about the free tier.
//
//  The free tier is a soft gate, not a hard lock. Library used to show non-
//  premium players a preview and nothing else, which maximised paywall pressure
//  at the cost of "everything is locked" before anyone had seen enough of the
//  collection to want it.
//
//  Two rules, both deliberately stateless:
//
//    1. A rolling window of the puzzles currently in rotation — today's and the
//       six served before it, per pool.
//    2. Anything the player has already started stays theirs.
//
//  Rule 2 exists because rule 1 slides. Without it a puzzle begun on its last
//  day in the window would lock overnight with the player's own progress inside
//  it, which is a worse experience than never offering it — a soft gate that
//  takes something back is not softer than a hard one.
//
//  Neither rule needs new persisted state: the window is arithmetic on the
//  rotation, and "started" is the `PuzzleRecord` the game already writes. That
//  matters beyond tidiness — a new synced field on `PlayerProfile` would mean a
//  CloudKit schema deploy to Production before this could ship.
//

import Foundation

struct PuzzleAccess {
    /// How many puzzles per pool sit inside the rolling window.
    ///
    /// Seven, so the window is worth returning to weekly without handing over a
    /// meaningful share of an 82-puzzle archive. Premium is still the only way
    /// to reach the rest of the rotation, every mini, and the pack exclusives.
    static let windowLength = 7

    /// Ids currently inside the window, across every rotating pool.
    private let windowIDs: Set<String>

    init(
        provider: PuzzleProvider,
        date: Date = Date(),
        calendar: Calendar = .current,
        windowLength: Int = PuzzleAccess.windowLength
    ) {
        // Each pool rotates on its own index, so each gets its own window —
        // otherwise the smaller pool's window would be a slice of the larger
        // one's day count and drift out of step with what Home is serving.
        let dailies = provider.rotationWindow(
            provider.puzzles, for: date, calendar: calendar, length: windowLength
        )
        let minis = provider.rotationWindow(
            provider.minis, for: date, calendar: calendar, length: windowLength
        )
        self.windowIDs = Set(dailies.map(\.id)).union(minis.map(\.id))
    }

    /// True when `puzzle` is inside the current rolling window, regardless of
    /// entitlement or progress. Drives the "free this week" framing in Library.
    func isInWindow(_ puzzle: Puzzle) -> Bool {
        windowIDs.contains(puzzle.id)
    }

    /// Whether the player may open `puzzle`.
    ///
    /// `hasProgress` is "a `PuzzleRecord` exists", which the game writes on the
    /// first letter entered — not on merely opening a puzzle. So the grandfather
    /// clause covers work the player actually did, and browsing into a puzzle on
    /// its last windowed day without playing it doesn't bank it forever.
    func canPlay(_ puzzle: Puzzle, isPremium: Bool, hasProgress: Bool) -> Bool {
        if isPremium { return true }
        // Pack exclusives are sold with their pack and never enter a rotation,
        // so they have no window to fall into. Checked ahead of `hasProgress`
        // so a lapsed subscriber's pack history can't reopen them for free.
        if puzzle.id.hasPrefix(Self.packPrefix) { return false }
        if hasProgress { return true }
        return windowIDs.contains(puzzle.id)
    }

    /// Matches the filter `PuzzleProvider` uses to keep pack exclusives out of
    /// the daily pool — see its `init`.
    private static let packPrefix = "pack-"
}
