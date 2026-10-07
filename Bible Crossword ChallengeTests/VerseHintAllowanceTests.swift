//
//  VerseHintAllowanceTests.swift
//  Bible Crossword ChallengeTests
//
//  The verse-hint-limit rule: new free profiles past the learning window
//  only; free on half a puzzle's verse clues, then one from the pool; the
//  count is per puzzle and survives leaving and resuming.
//

import Testing
import Foundation
@testable import Bible_Crossword_Challenge

struct VerseHintAllowanceTests {

    private func freshDefaults() -> UserDefaults {
        let name = "VerseHintAllowanceTests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    @Test func eligibilityNeedsANewFreeProfileOutsideTheLearningWindow() {
        let after = VerseHintAllowance.cohortStart.addingTimeInterval(60)
        let before = VerseHintAllowance.cohortStart.addingTimeInterval(-60)
        #expect(VerseHintAllowance.isEligible(isPremium: false, isStillLearning: false, profileCreatedAt: after))
        #expect(!VerseHintAllowance.isEligible(isPremium: false, isStillLearning: false, profileCreatedAt: before))
        #expect(!VerseHintAllowance.isEligible(isPremium: true, isStillLearning: false, profileCreatedAt: after))
        #expect(!VerseHintAllowance.isEligible(isPremium: false, isStillLearning: true, profileCreatedAt: after))
    }

    @Test func allowanceIsHalfTheVerseCluesRoundedUp() {
        #expect(VerseHintAllowance.freeAllowance(verseClueCount: 18) == 9)
        #expect(VerseHintAllowance.freeAllowance(verseClueCount: 5) == 3)
        #expect(VerseHintAllowance.freeAllowance(verseClueCount: 1) == 1)
        #expect(VerseHintAllowance.freeAllowance(verseClueCount: 0) == 1)
    }

    @Test func freeUntilTheAllowanceThenOneHint() {
        #expect(VerseHintAllowance.cost(used: 0, verseClueCount: 10) == 0)
        #expect(VerseHintAllowance.cost(used: 4, verseClueCount: 10) == 0)
        #expect(VerseHintAllowance.cost(used: 5, verseClueCount: 10) == 1)
        #expect(VerseHintAllowance.cost(used: 30, verseClueCount: 10) == 1)
    }

    @Test func countIsPerPuzzle() {
        let defaults = freshDefaults()
        for _ in 0..<3 { VerseHintAllowance.recordUse(puzzleID: "daily-001", defaults: defaults) }
        #expect(VerseHintAllowance.used(puzzleID: "daily-001", defaults: defaults) == 3)
        #expect(VerseHintAllowance.used(puzzleID: "daily-002", defaults: defaults) == 0)
    }
}
