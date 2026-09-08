//
//  PremiumAsk.swift
//  Bible Crossword Challenge
//
//  Whether to offer Premium to a player who has stuck around and never asked
//  for it — the app's one proactive ask outside onboarding. A pure decision
//  over plain values, same pattern as `ReminderAsk` and `TrialReoffer`: Home
//  owns the presentation and the persistence, this owns the rule, so it is
//  testable without SwiftUI or StoreKit.
//
//  Why this exists: in the 30 days to 2026-09-08, 75% of every paywall opened
//  on builds 2.7–2.9 was onboarding's own page — shown after a single tutorial
//  clue, to a player with no relationship to the library yet. It converts
//  because it is the only ask, not because it is the right one. Every other
//  surface went passive when the automatic paywalls came out on 2026-09-02, so
//  a player who skipped onboarding's offer and then solved a puzzle a day for a
//  fortnight was never spoken to again.
//
//  The rule is deliberately narrow. It waits for a habit rather than a wall:
//  five solves is past the learning window (three) with room to spare, and the
//  install day is excluded outright so this can never be a first-sitting
//  interruption stacked on top of onboarding's.
//
//  This is *not* the sheet-on-completion paywall removed on 2026-09-02. That
//  one fired on a payoff screen, unprompted, up to four times a player. This is
//  once ever, on Today, in the same one-ask-per-sitting budget as the reminder
//  prompts and the trial re-offer — and it ships behind `FeatureFlag.premiumAsk`
//  so its effect on purchases *and* on retention is measured rather than
//  assumed.
//

import Foundation

enum PremiumAsk {
    /// The paywall `source` for the ask, so its open → tap → purchase funnel is
    /// read on its own.
    static let source = PaywallSource.premiumAsk

    /// Solves before the app brings Premium up by itself.
    ///
    /// Five, not three: three is `PlayerProfile.isStillLearning`, the window
    /// where hints are free and the app is deliberately not selling anything.
    /// Asking the moment that lifts would read as the meter starting — which is
    /// the impression the learning window was introduced to avoid.
    static let minCompletions = 5

    struct State {
        var isPremium: Bool
        /// Whether `isPremium` is an answer yet — see
        /// `StoreService.entitlementsResolved`. An unproven `false` is not a
        /// free player, and this is the one ask that speaks first.
        var entitlementsKnown: Bool
        var totalCompleted: Int
        /// This player has already been assigned an arm — the ask is once ever,
        /// in both arms. See `isEligible`.
        var assigned: Bool
        /// True once any surface asked this player for anything since launch:
        /// reminders, the trial re-offer, or this. Two asks in one sitting reads
        /// as nagging however well-earned each one is.
        var anyAskThisSession: Bool
        /// Today is the day the profile was created. A first sitting is not a
        /// habit, and onboarding has already made this offer once today.
        var isInstallDay: Bool
    }

    /// Whether this player should enter the experiment now.
    ///
    /// Eligibility, not presentation — the two are separate on purpose. This
    /// answers "is this the moment the app would speak up?", and *both* arms
    /// are assigned at that moment: treatment sees the sheet, control sees
    /// nothing but is stamped as having reached the same point. Without that,
    /// control would be every un-flagged player in the app — including everyone
    /// who never got near five solves — and the comparison would measure
    /// engagement rather than the ask.
    ///
    /// `FeatureFlag.premiumAsk` is read *after* this returns true, so the
    /// exposure event fires for the eligible population only.
    static func isEligible(_ s: State) -> Bool {
        guard s.entitlementsKnown, !s.isPremium else { return false }
        guard !s.assigned else { return false }
        guard !s.anyAskThisSession else { return false }
        guard !s.isInstallDay else { return false }
        return s.totalCompleted >= minCompletions
    }
}

#if DEBUG
/// Once per process for the `-uiForcePremiumAsk` launch argument, so the forced
/// sheet doesn't return on every pop back to Today. Mirrors
/// `TrialReofferSession`.
enum PremiumAskSession {
    @MainActor static var forced = false
}
#endif
