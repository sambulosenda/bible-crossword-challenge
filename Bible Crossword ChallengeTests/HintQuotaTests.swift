//
//  HintQuotaTests.swift
//  Bible Crossword ChallengeTests
//
//  The daily hint pool, at both sizes it can take.
//
//  The tightened pool is a real product change, not a tuning tweak: at one
//  hint a day, `HintType.word` (2) and `HintType.puzzle` (3) can never be
//  afforded, so the ladder for a free player past the learning window becomes
//  the free verse rung, one letter, and the paywall. These pin that, so nobody
//  later "fixes" the arithmetic that makes it true.
//

import Testing
import Foundation
@testable import Bible_Crossword_Challenge

@MainActor
struct HintQuotaTests {

    /// A player past the learning window with a clean day.
    private func player(usedToday: Int = 0, completed: Int = 10) -> PlayerProfile {
        let p = PlayerProfile()
        p.totalPuzzlesCompleted = completed
        p.hintsUsedToday = usedToday
        p.hintsDate = usedToday > 0 ? Date() : nil
        return p
    }

    @Test("the shipped pool is one")
    func poolSize() {
        #expect(PlayerProfile.freeHintLimit == 1)
    }

    @Test("defaults to the shipped pool when no limit is passed")
    func defaultsToShipped() {
        #expect(player().hintsRemaining(isPremium: false) == 1)
    }

    @Test("the tightened pool gives one hint a day")
    func tightenedPool() {
        let limit = PlayerProfile.freeHintLimit
        #expect(player().hintsRemaining(isPremium: false, limit: limit) == 1)
        #expect(player(usedToday: 1).hintsRemaining(isPremium: false, limit: limit) == 0)
    }

    /// The mechanism, stated as a test. A one-hint pool can never afford the
    /// two rungs above a letter, so every tap on them is a paywall.
    @Test("at one a day, Reveal Word and Reveal Puzzle are unaffordable")
    func wordAndPuzzleBecomeUnreachable() {
        let remaining = player().hintsRemaining(isPremium: false, limit: PlayerProfile.freeHintLimit)
        #expect(remaining >= HintType.letter.cost)
        #expect(remaining < HintType.word.cost)
        #expect(remaining < HintType.puzzle.cost)
        // The free rung is unaffected — it costs nothing and never touches the
        // quota, which is what keeps the ladder from collapsing to the paywall.
        #expect(HintType.verse.cost == 0)
    }

    @Test("premium and the learning window ignore the pool entirely")
    func exemptionsIgnoreTheLimit() {
        let limit = PlayerProfile.freeHintLimit
        #expect(player().hintsRemaining(isPremium: true, limit: limit) == .max)
        // Still learning: fewer than three completions.
        #expect(player(completed: 2).hintsRemaining(isPremium: false, limit: limit) == .max)
    }

    @Test("yesterday's spend doesn't carry into today, at either size")
    func poolResetsDaily() {
        let p = player(usedToday: 3)
        p.hintsDate = Calendar.current.date(byAdding: .day, value: -1, to: Date())
        #expect(p.hintsRemaining(isPremium: false, limit: 3) == 3)
        #expect(p.hintsRemaining(isPremium: false) == 1)
    }
}
