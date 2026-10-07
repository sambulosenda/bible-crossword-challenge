//
//  VerseHintAllowance.swift
//  Bible Crossword Challenge
//
//  The `verse-hint-limit` experiment: a daily allowance on the one hint that
//  has always been free and unlimited.
//
//  Why: in the 30 days to 2026-10-06 the verse hint was used 14,462 times by
//  210 players (~69 each), while only 56 players ever ran out of the metered
//  pool — 54 of whom finished puzzles anyway. Premium's "hints whenever you
//  need them" competes with a free hint nobody runs out of, so the hint offer
//  reaches almost no one. Treatment makes the verse free on half of a
//  puzzle's verse clues, then each costs one from the ordinary pool; an empty pool refuses it like any
//  other hint, which raises the hint offer card.
//
//  Risk: the verse hint is the most-used assist and props up day-0
//  completion. So the test is new profiles only (`cohortStart`), outside the
//  learning window, and D7 retention is the guardrail. A pure rule over plain
//  values, same pattern as `TrialReoffer`, so it is testable without UI.
//

import Foundation

enum VerseHintAllowance {
    /// What a verse hint costs from the pool once the puzzle's free ones are
    /// spent.
    static let costBeyondAllowance = 1
    /// Profiles created before this never join the test: changing the rules
    /// under an existing habit would measure annoyance, not the offer.
    static let cohortStart: Date = {
        var c = DateComponents()
        c.year = 2026; c.month = 10; c.day = 8
        c.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: c) ?? .distantFuture
    }()

    /// Whether this player could be in the experiment at all. Only an eligible
    /// player reads (and so registers for) the flag.
    static func isEligible(isPremium: Bool, isStillLearning: Bool, profileCreatedAt: Date) -> Bool {
        !isPremium && !isStillLearning && profileCreatedAt >= cohortStart
    }

    /// Free verse hints in a puzzle: half its verse clues, rounded up.
    ///
    /// Per puzzle and scaled, not per day: the median free player-day opens
    /// the verse 10 times (p75 22, p90 39; 30 days to 2026-10-07) — about half
    /// the clues of a daily. A daily cap cut off the most engaged players, the
    /// ones doing several puzzles, on their second puzzle; a fixed per-puzzle
    /// number is lavish on a mini and harsh on a Sunday 21×21. Half tracks the
    /// existing habit in every grid size, and says itself plainly.
    static func freeAllowance(verseClueCount: Int) -> Int {
        max(1, (verseClueCount + 1) / 2)
    }

    /// The pool cost of the next verse hint in this puzzle.
    static func cost(used: Int, verseClueCount: Int) -> Int {
        used < freeAllowance(verseClueCount: verseClueCount) ? 0 : costBeyondAllowance
    }

    // MARK: - Per-puzzle count

    /// Persisted so leaving and resuming a puzzle doesn't refill it.
    private static func key(_ puzzleID: String) -> String { "verseHints.puzzle.\(puzzleID)" }

    static func used(puzzleID: String, defaults: UserDefaults = .standard) -> Int {
        defaults.integer(forKey: key(puzzleID))
    }

    static func recordUse(puzzleID: String, defaults: UserDefaults = .standard) {
        defaults.set(used(puzzleID: puzzleID, defaults: defaults) + 1, forKey: key(puzzleID))
    }
}
