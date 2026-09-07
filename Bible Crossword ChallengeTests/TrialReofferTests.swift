//
//  TrialReofferTests.swift
//  Bible Crossword ChallengeTests
//
//  The re-offer rule: once per abandoned sheet, never in the same sitting,
//  only while the intent is still warm, and never to someone who has bought.
//

import Testing
import Foundation
@testable import Bible_Crossword_Challenge

struct TrialReofferTests {

    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    /// Abandoned yesterday, process launched this morning: the canonical case.
    private func eligible() -> TrialReoffer.State {
        TrialReoffer.State(
            abandonedAt: now.addingTimeInterval(-24 * 60 * 60),
            isPremium: false,
            reofferShown: false,
            launchedAt: now.addingTimeInterval(-60),
            now: now,
            calendar: utc
        )
    }

    @Test func offersOnALaterLaunch() {
        #expect(TrialReoffer.decide(eligible()))
    }

    @Test func neverInTheSameSitting() {
        // Abandoned five minutes ago, in this process, on this day.
        var s = eligible()
        s.abandonedAt = now.addingTimeInterval(-5 * 60)
        s.launchedAt = now.addingTimeInterval(-60 * 60)
        #expect(!TrialReoffer.decide(s))
    }

    @Test func aLaterDayCountsEvenWithoutARelaunch() {
        // Process has been alive since before the abandon; it is now tomorrow.
        var s = eligible()
        s.launchedAt = now.addingTimeInterval(-3 * 24 * 60 * 60)
        s.abandonedAt = utc.date(byAdding: .day, value: -1, to: now)
        #expect(TrialReoffer.decide(s))
    }

    @Test func aLaterLaunchCountsEvenOnTheSameDay() {
        var s = eligible()
        s.abandonedAt = now.addingTimeInterval(-2 * 60 * 60)
        s.launchedAt = now.addingTimeInterval(-60)
        #expect(utc.isDate(s.abandonedAt!, inSameDayAs: now))
        #expect(TrialReoffer.decide(s))
    }

    @Test func silentOnceShown() {
        var s = eligible(); s.reofferShown = true
        #expect(!TrialReoffer.decide(s))
    }

    @Test func silentOnceBought() {
        var s = eligible(); s.isPremium = true
        #expect(!TrialReoffer.decide(s))
    }

    @Test func silentWithNoAbandon() {
        var s = eligible(); s.abandonedAt = nil
        #expect(!TrialReoffer.decide(s))
    }

    @Test func expiresAfterTheWindow() {
        var s = eligible()
        s.abandonedAt = now.addingTimeInterval(-TrialReoffer.window - 1)
        #expect(!TrialReoffer.decide(s))
        s.abandonedAt = now.addingTimeInterval(-TrialReoffer.window + 60)
        #expect(TrialReoffer.decide(s))
    }
}
