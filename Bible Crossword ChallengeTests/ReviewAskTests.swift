//
//  ReviewAskTests.swift
//  Bible Crossword ChallengeTests
//
//  The review-prompt rules: milestone ladder, a finished pack or Journey, the
//  streak-7 trigger, the 120-day re-ask for loyal players, and the spacing gap that keeps a
//  cluster of triggers from spending Apple's three yearly displays at once.
//

import Testing
import Foundation
@testable import Bible_Crossword_Challenge

struct ReviewAskTests {

    /// A quiet baseline: nothing asked yet, no trigger currently met.
    private func fresh() -> ReviewAsk.State {
        ReviewAsk.State(
            totalCompleted: 0,
            currentStreak: 0,
            milestoneAsked: 0,
            streakAsked: false,
            lastAsk: nil,
            installedAt: Date().addingTimeInterval(-30 * 86_400)
        )
    }

    @Test func silentBeforeFirstMilestone() {
        var s = fresh(); s.totalCompleted = 2
        #expect(ReviewAsk.decide(s) == nil)
    }

    @Test func milestoneLadderFiresEachRungOnce() {
        var s = fresh()
        for milestone in ReviewAsk.milestones {
            s.totalCompleted = milestone
            #expect(ReviewAsk.decide(s) == .milestone(milestone))
            s.milestoneAsked = milestone
            #expect(ReviewAsk.decide(s) != .milestone(milestone))
        }
    }

    @Test func ladderExtendsPastThirtyForExistingPlayers() {
        // A pre-2.3 player whose stored high-water mark is the old ladder's
        // top rung is asked again at 75, not silenced forever.
        var s = fresh(); s.totalCompleted = 75; s.milestoneAsked = 30
        #expect(ReviewAsk.decide(s) == .milestone(75))
    }

    @Test func bingeCrossingSeveralRungsAsksOnce() {
        var s = fresh(); s.totalCompleted = 80
        #expect(ReviewAsk.decide(s) == .milestone(75))
        // The caller stamps the ask's time, so nothing chains a second prompt
        // right behind the milestone one.
        s.milestoneAsked = 75; s.lastAsk = s.now
        #expect(ReviewAsk.decide(s) == nil)
    }

    @Test func streakSevenFiresOnceEver() {
        var s = fresh(); s.totalCompleted = 5; s.currentStreak = 7
        s.milestoneAsked = 3
        #expect(ReviewAsk.decide(s) == .streak)
        s.streakAsked = true
        #expect(ReviewAsk.decide(s) == nil)
    }

    @Test func milestoneOutranksStreak() {
        var s = fresh(); s.totalCompleted = 10; s.currentStreak = 7
        #expect(ReviewAsk.decide(s) == .milestone(10))
    }

    @Test func periodicReaskNeedsLoyaltyFloor() {
        var s = fresh(); s.totalCompleted = 29; s.milestoneAsked = 10
        s.lastAsk = s.now.addingTimeInterval(-ReviewAsk.periodicGap - 86_400)
        #expect(ReviewAsk.decide(s) == nil)
    }

    @Test func loyalPlayerIsReaskedAfterPeriodicGap() {
        var s = fresh(); s.totalCompleted = 40; s.milestoneAsked = 30
        s.lastAsk = s.now.addingTimeInterval(-ReviewAsk.periodicGap + 86_400)
        #expect(ReviewAsk.decide(s) == nil)
        s.lastAsk = s.now.addingTimeInterval(-ReviewAsk.periodicGap - 86_400)
        #expect(ReviewAsk.decide(s) == .periodic)
    }

    @Test func loyalPlayerNeverAskedIsReached() {
        var s = fresh(); s.totalCompleted = 40; s.milestoneAsked = 30
        #expect(ReviewAsk.decide(s) == .periodic)
    }

    @Test func finishedCollectionAsks() {
        var s = fresh(); s.totalCompleted = 5; s.milestoneAsked = 3
        s.finishedCollection = true
        #expect(ReviewAsk.decide(s) == .collection)
    }

    @Test func milestoneOutranksCollectionAndCollectionOutranksStreak() {
        var s = fresh(); s.totalCompleted = 10; s.currentStreak = 7; s.finishedCollection = true
        #expect(ReviewAsk.decide(s) == .milestone(10))
        s.milestoneAsked = 10
        #expect(ReviewAsk.decide(s) == .collection)
    }

    @Test func collectionRespectsGapAndInstallFloor() {
        var s = fresh(); s.totalCompleted = 5; s.milestoneAsked = 3; s.finishedCollection = true
        s.lastAsk = s.now.addingTimeInterval(-ReviewAsk.minimumGap + 3_600)
        #expect(ReviewAsk.decide(s) == nil)
        s.lastAsk = nil
        s.installedAt = s.now.addingTimeInterval(-ReviewAsk.minimumInstallAge + 3_600)
        #expect(ReviewAsk.decide(s) == nil)
    }

    @Test func spacingGapSilencesEveryTrigger() {
        var s = fresh(); s.totalCompleted = 10; s.currentStreak = 7
        s.milestoneAsked = 3; s.finishedCollection = true
        s.lastAsk = s.now.addingTimeInterval(-ReviewAsk.minimumGap + 3_600)
        #expect(ReviewAsk.decide(s) == nil)
    }

    @Test func blockedTriggerRetriesAfterGap() {
        var s = fresh(); s.totalCompleted = 10; s.milestoneAsked = 3
        s.lastAsk = s.now.addingTimeInterval(-ReviewAsk.minimumGap - 3_600)
        #expect(ReviewAsk.decide(s) == .milestone(10))
    }

    @Test func freshInstallSilencesEveryTrigger() {
        // Three Minis in one sitting reach the first rung on install day;
        // a 7-streak can't, but the floor is on every trigger regardless.
        var s = fresh(); s.totalCompleted = 3; s.currentStreak = 7
        s.installedAt = s.now.addingTimeInterval(-ReviewAsk.minimumInstallAge + 3_600)
        #expect(ReviewAsk.decide(s) == nil)
        s.installedAt = s.now.addingTimeInterval(-ReviewAsk.minimumInstallAge - 3_600)
        #expect(ReviewAsk.decide(s) == .milestone(3))
    }

    @Test func unknownInstallDateDoesNotBlock() {
        var s = fresh(); s.totalCompleted = 3; s.installedAt = nil
        #expect(ReviewAsk.decide(s) == .milestone(3))
    }
}
