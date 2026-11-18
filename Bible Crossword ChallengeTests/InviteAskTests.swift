//
//  InviteAskTests.swift
//  Bible Crossword ChallengeTests
//
//  When the completion screen's invite row may show: only on a solve worth
//  sending, never beside another ask, at most once a week, and resting for a
//  month once two rows in a row went unanswered.
//

import Testing
import Foundation
@testable import Bible_Crossword_Challenge

struct InviteAskTests {

    /// A full puzzle, solved for the first time with no hints, nothing else
    /// on screen and no ask before it.
    private func eligible() -> InviteAsk.State {
        InviteAsk.State(
            isFirstSolve: true,
            isMini: false,
            hintsUsed: 0,
            isNewBest: false,
            streak: 2,
            streakAdvanced: true,
            isComeback: false,
            totalCompleted: 5,
            otherAskOnScreen: false,
            lastShown: nil,
            unanswered: 0
        )
    }

    @Test func noHintFullSolveAsks() {
        #expect(InviteAsk.decide(eligible()) == .noHints)
    }

    @Test func ordinarySolveStaysQuiet() {
        var s = eligible(); s.hintsUsed = 2
        #expect(InviteAsk.decide(s) == nil)
    }

    @Test func bestTimeOutranksNoHints() {
        var s = eligible(); s.isNewBest = true
        #expect(InviteAsk.decide(s) == .bestTime)
        s.hintsUsed = 3
        #expect(InviteAsk.decide(s) == .bestTime)
    }

    @Test func streakMomentOutranksTheRest() {
        var s = eligible(); s.isNewBest = true
        for days in InviteAsk.streakMoments {
            s.streak = days
            #expect(InviteAsk.decide(s) == .streak(days))
        }
    }

    @Test func streakMomentNeedsTheStreakToHaveMovedOnThisSolve() {
        // A second puzzle on day 7 is not day 7 again.
        var s = eligible(); s.streak = 7; s.hintsUsed = 1; s.streakAdvanced = false
        #expect(InviteAsk.decide(s) == nil)
    }

    @Test func comebackIsNotAStreakMoment() {
        var s = eligible(); s.streak = 3; s.hintsUsed = 1; s.isComeback = true
        #expect(InviteAsk.decide(s) == nil)
    }

    @Test func miniAsksOnlyOnAStreakMoment() {
        var s = eligible(); s.isMini = true; s.isNewBest = true
        #expect(InviteAsk.decide(s) == nil)
        s.streak = 14
        #expect(InviteAsk.decide(s) == .streak(14))
    }

    @Test func replayNeverAsks() {
        var s = eligible(); s.isFirstSolve = false; s.streak = 7; s.isNewBest = true
        #expect(InviteAsk.decide(s) == nil)
    }

    @Test func firstEverSolveNeverAsks() {
        var s = eligible(); s.totalCompleted = 1
        #expect(InviteAsk.decide(s) == nil)
    }

    @Test func yieldsToAnotherAskOnTheScreen() {
        var s = eligible(); s.streak = 7; s.otherAskOnScreen = true
        #expect(InviteAsk.decide(s) == nil)
    }

    @Test func atMostOnceAWeek() {
        var s = eligible()
        s.lastShown = s.now.addingTimeInterval(-InviteAsk.gap + 60)
        #expect(InviteAsk.decide(s) == nil)
        s.lastShown = s.now.addingTimeInterval(-InviteAsk.gap)
        #expect(InviteAsk.decide(s) == .noHints)
    }

    @Test func restsAMonthAfterTwoUnansweredRows() {
        var s = eligible()
        s.unanswered = InviteAsk.unansweredBeforeRest
        s.lastShown = s.now.addingTimeInterval(-InviteAsk.gap - 60)
        #expect(InviteAsk.decide(s) == nil)
        s.lastShown = s.now.addingTimeInterval(-InviteAsk.restGap)
        #expect(InviteAsk.decide(s) == .noHints)
    }

    @Test func oneUnansweredRowKeepsTheWeeklyPace() {
        var s = eligible()
        s.unanswered = InviteAsk.unansweredBeforeRest - 1
        s.lastShown = s.now.addingTimeInterval(-InviteAsk.gap)
        #expect(InviteAsk.decide(s) == .noHints)
    }

    @Test func analyticsValuesAreStable() {
        #expect(InviteAsk.Moment.streak(7).analyticsValue == "streak_7")
        #expect(InviteAsk.Moment.bestTime.analyticsValue == "best_time")
        #expect(InviteAsk.Moment.noHints.analyticsValue == "no_hints")
    }
}
