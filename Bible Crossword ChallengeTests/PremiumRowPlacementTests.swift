//
//  PremiumRowPlacementTests.swift
//  Bible Crossword ChallengeTests
//
//  Who the `premium-row-up` experiment can reach: free players past their
//  learning window, from their third calendar day. Everyone else keeps the
//  shipped layout and never reads the flag.
//

import Testing
import Foundation
@testable import Bible_Crossword_Challenge

struct PremiumRowPlacementTests {

    private let today = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    /// Installed two calendar days ago, three solves, free.
    private func eligible() -> PremiumRowPlacement.State {
        PremiumRowPlacement.State(
            isPremium: false,
            totalCompleted: 3,
            createdAt: utc.date(byAdding: .day, value: -2, to: today)!,
            today: today,
            calendar: utc
        )
    }

    @Test func thirdDayPastTheLearningWindowIsEligible() {
        #expect(PremiumRowPlacement.isEligible(eligible()))
    }

    @Test func neverForPremium() {
        var s = eligible()
        s.isPremium = true
        #expect(!PremiumRowPlacement.isEligible(s))
    }

    @Test func notWhileStillLearning() {
        var s = eligible()
        s.totalCompleted = 2
        #expect(!PremiumRowPlacement.isEligible(s))
    }

    @Test func notOnTheSecondDay() {
        var s = eligible()
        s.createdAt = utc.date(byAdding: .day, value: -1, to: today)!
        #expect(!PremiumRowPlacement.isEligible(s))
    }

    @Test func countsCalendarDaysNotHours() {
        // Installed at 23:59 two days back, opened at 00:01: about 24 hours,
        // but the third calendar day.
        let start = utc.startOfDay(for: today)
        var s = eligible()
        s.createdAt = start.addingTimeInterval(-24 * 60 * 60 - 60)
        s.today = start.addingTimeInterval(60)
        #expect(PremiumRowPlacement.isEligible(s))
    }

    @Test func learningWindowMatchesTheProfile() {
        // The row must not move while hints are still free.
        let profile = PlayerProfile()
        profile.totalPuzzlesCompleted = PremiumRowPlacement.minimumCompleted
        #expect(!profile.isStillLearning)
        profile.totalPuzzlesCompleted -= 1
        #expect(profile.isStillLearning)
    }

    @Test func shippedDefaultIsOff() {
        #expect(PremiumRowPlacement.flag.defaultValue == false)
        #expect(PremiumRowPlacement.flag.rawValue == "premium-row-up")
    }
}
