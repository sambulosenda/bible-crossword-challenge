//
//  PremiumAskTests.swift
//  Bible Crossword ChallengeTests
//
//  The proactive premium ask: once ever, only after the habit, never on the
//  install day, and never stacked on another ask in the same sitting.
//
//  These pin the guarantees that keep this from becoming the sheet-on-
//  completion paywall that was removed on 2026-09-02 — which fired unprompted,
//  on a payoff screen, up to four times per player.
//

import Testing
@testable import Bible_Crossword_Challenge

struct PremiumAskTests {

    /// A player who has the habit, on a later day, with the sitting's ask
    /// budget unspent. Every test below is this minus one thing.
    private func eligible(
        isPremium: Bool = false,
        entitlementsKnown: Bool = true,
        totalCompleted: Int = PremiumAsk.minCompletions,
        assigned: Bool = false,
        anyAskThisSession: Bool = false,
        isInstallDay: Bool = false
    ) -> PremiumAsk.State {
        PremiumAsk.State(
            isPremium: isPremium,
            entitlementsKnown: entitlementsKnown,
            totalCompleted: totalCompleted,
            assigned: assigned,
            anyAskThisSession: anyAskThisSession,
            isInstallDay: isInstallDay
        )
    }

    @Test("asks a player with the habit on a later day")
    func asksTheHabitualPlayer() {
        #expect(PremiumAsk.isEligible(eligible()))
    }

    @Test("never asks someone who already pays")
    func neverAsksPremium() {
        #expect(!PremiumAsk.isEligible(eligible(isPremium: true)))
    }

    /// `isPremium` starts false on every launch and is filled in
    /// asynchronously. Speaking during that window opens a paywall in a
    /// subscriber's face and stamps them into an experiment they can't join.
    @Test("waits until the entitlement is actually known")
    func waitsForEntitlements() {
        #expect(!PremiumAsk.isEligible(eligible(entitlementsKnown: false)))
        #expect(!PremiumAsk.isEligible(eligible(entitlementsKnown: false, totalCompleted: 99)))
    }

    @Test("once ever, in both arms")
    func onceEver() {
        #expect(!PremiumAsk.isEligible(eligible(assigned: true)))
    }

    @Test("never stacks on another ask in the same sitting")
    func oneAskPerSitting() {
        #expect(!PremiumAsk.isEligible(eligible(anyAskThisSession: true)))
    }

    @Test("never on the install day, however many are solved")
    func neverOnInstallDay() {
        #expect(!PremiumAsk.isEligible(eligible(isInstallDay: true)))
        #expect(!PremiumAsk.isEligible(eligible(totalCompleted: 50, isInstallDay: true)))
    }

    @Test("waits for the habit, and for the learning window to be well past")
    func waitsForTheHabit() {
        for solved in 0..<PremiumAsk.minCompletions {
            #expect(
                !PremiumAsk.isEligible(eligible(totalCompleted: solved)),
                "asked after \(solved) solves"
            )
        }
        #expect(PremiumAsk.isEligible(eligible(totalCompleted: PremiumAsk.minCompletions)))
        #expect(PremiumAsk.isEligible(eligible(totalCompleted: 99)))
    }

    /// The learning window (`PlayerProfile.isStillLearning`) is three solves,
    /// and the ask must not land the moment it lifts — that would read as the
    /// meter starting, which is the impression the window exists to avoid.
    @Test("does not fire the moment the learning window lifts")
    func clearsTheLearningWindow() {
        #expect(PremiumAsk.minCompletions > 3)
        #expect(!PremiumAsk.isEligible(eligible(totalCompleted: 3)))
    }

    @Test("the ask keeps its own funnel label")
    func sourceIsItsOwn() {
        #expect(PremiumAsk.source == .premiumAsk)
        #expect(PremiumAsk.source.rawValue == "premium_ask")
    }
}
