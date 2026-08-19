//
//  ReviewAskTests.swift
//  Bible Crossword ChallengeTests
//
//  The review-prompt rules: milestone ladder, the streak-7 trigger, the
//  per-version re-arm for loyal players, and the spacing gap that keeps a
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
            versionAsked: "",
            currentVersion: "2.2",
            lastAsk: nil
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
        // The caller stamps the version on every ask, so the version trigger
        // can't chain a second prompt right behind the milestone one.
        s.milestoneAsked = 75; s.versionAsked = s.currentVersion
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

    @Test func versionRearmNeedsLoyaltyFloor() {
        var s = fresh(); s.totalCompleted = 29
        s.milestoneAsked = 10; s.versionAsked = "2.1"
        #expect(ReviewAsk.decide(s) == nil)
    }

    @Test func newVersionRearmsForLoyalPlayer() {
        var s = fresh(); s.totalCompleted = 40
        s.milestoneAsked = 30; s.versionAsked = "2.1"
        #expect(ReviewAsk.decide(s) == .version)
        s.versionAsked = s.currentVersion
        #expect(ReviewAsk.decide(s) == nil)
    }

    @Test func unknownVersionNeverRearms() {
        var s = fresh(); s.totalCompleted = 40
        s.milestoneAsked = 30; s.currentVersion = ""
        #expect(ReviewAsk.decide(s) == nil)
    }

    @Test func spacingGapSilencesEveryTrigger() {
        var s = fresh(); s.totalCompleted = 10; s.currentStreak = 7
        s.milestoneAsked = 3; s.versionAsked = "2.1"
        s.lastAsk = s.now.addingTimeInterval(-ReviewAsk.minimumGap + 3_600)
        #expect(ReviewAsk.decide(s) == nil)
    }

    @Test func blockedTriggerRetriesAfterGap() {
        var s = fresh(); s.totalCompleted = 10; s.milestoneAsked = 3
        s.lastAsk = s.now.addingTimeInterval(-ReviewAsk.minimumGap - 3_600)
        #expect(ReviewAsk.decide(s) == .milestone(10))
    }
}
