//
//  ReminderAskTests.swift
//  Bible Crossword ChallengeTests
//
//  The cross-surface reminder-ask rules: one ask per day anywhere, one per
//  session, silence once answered, and each surface's own eligibility.
//

import Testing
import Foundation
@testable import Bible_Crossword_Challenge

struct ReminderAskTests {

    /// A state that passes every shared guard, eligible on both surfaces.
    private func eligible() -> ReminderAsk.State {
        ReminderAsk.State(
            remindersEnabled: false,
            permissionUndetermined: true,
            totalCompleted: 1,
            currentStreak: 2,
            completionAsksShown: 0,
            streakAskShown: false,
            lastAskDay: nil,
            askedThisSession: false
        )
    }

    @Test func eligibleStateAsksOnBothSurfaces() {
        #expect(ReminderAsk.decide(.completion, eligible()))
        #expect(ReminderAsk.decide(.streakCard, eligible()))
    }

    @Test func silentOnceRemindersEnabled() {
        var s = eligible(); s.remindersEnabled = true
        #expect(!ReminderAsk.decide(.completion, s))
        #expect(!ReminderAsk.decide(.streakCard, s))
    }

    @Test func silentOnceSystemPromptSpent() {
        // Granted or denied — either way iOS has been asked; the recovery
        // path for denied is the Profile toggle, not another prompt.
        var s = eligible(); s.permissionUndetermined = false
        #expect(!ReminderAsk.decide(.completion, s))
        #expect(!ReminderAsk.decide(.streakCard, s))
    }

    @Test func oneAskPerDayAcrossSurfaces() {
        var s = eligible()
        s.lastAskDay = s.calendar.startOfDay(for: s.now)
        #expect(!ReminderAsk.decide(.completion, s))
        #expect(!ReminderAsk.decide(.streakCard, s))

        // Yesterday's ask doesn't block today.
        s.lastAskDay = s.calendar.date(byAdding: .day, value: -1, to: s.now)
        #expect(ReminderAsk.decide(.completion, s))
    }

    @Test func oneAskPerSession() {
        var s = eligible(); s.askedThisSession = true
        #expect(!ReminderAsk.decide(.completion, s))
        #expect(!ReminderAsk.decide(.streakCard, s))
    }

    @Test func completionAsksStopAfterCap() {
        var s = eligible()
        s.completionAsksShown = ReminderAsk.maxCompletionAsks - 1
        #expect(ReminderAsk.decide(.completion, s))
        s.completionAsksShown = ReminderAsk.maxCompletionAsks
        #expect(!ReminderAsk.decide(.completion, s))
    }

    @Test func completionNeedsASolve() {
        var s = eligible(); s.totalCompleted = 0
        #expect(!ReminderAsk.decide(.completion, s))
    }

    @Test func streakAskNeedsAStreakWorthProtecting() {
        var s = eligible(); s.currentStreak = 1
        #expect(!ReminderAsk.decide(.streakCard, s))
        s.currentStreak = 2
        #expect(ReminderAsk.decide(.streakCard, s))
    }

    @Test func streakAskIsOnceEver() {
        var s = eligible(); s.streakAskShown = true
        #expect(!ReminderAsk.decide(.streakCard, s))
        // But the completion surface is unaffected by the streak flag.
        #expect(ReminderAsk.decide(.completion, s))
    }
}
