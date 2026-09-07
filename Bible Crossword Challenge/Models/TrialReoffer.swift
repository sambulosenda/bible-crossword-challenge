//
//  TrialReoffer.swift
//  Bible Crossword Challenge
//
//  Whether to offer the free trial again to a player who tapped "Start free
//  trial" and then backed out of Apple's purchase sheet. A pure decision over
//  plain values, same pattern as `ReminderAsk`: `StoreService` owns the
//  record (when, which plan, whether it has been re-offered) and Home owns
//  the presentation; this owns the rule, so it is testable without StoreKit.
//
//  Why this exists: in the 30 days to 2026-09-07, 33 players tapped the
//  onboarding CTA and 16 finished the sheet. The 17 who cancelled are the
//  warmest leads the app has — they read the price, chose a plan, and pressed
//  the button — and they were never spoken to again. Every later paywall
//  they might meet is generic, opens on a wall rather than on intent, and
//  converted nobody (78 openers, 0 taps in the same window).
//
//  The rule is deliberately narrow: once per abandon, never in the same
//  sitting, and only while the intent is still warm. A second "no" is final
//  until they show intent again somewhere else.
//

import Foundation

enum TrialReoffer {
    /// The paywall `source` for the re-offer, so its open → tap → purchase
    /// funnel is read on its own and never re-records an abandon of itself.
    static let source = "trial_abandon"

    /// How long a cancelled sheet stays worth revisiting. Two weeks: past
    /// that the player has either settled into the free daily or left, and
    /// "still waiting" would be a claim about a decision they don't remember.
    static let window: TimeInterval = 14 * 24 * 60 * 60

    struct State {
        /// When the player last backed out of the sheet on a plan that offered
        /// a trial. Nil when they never have, or have bought since.
        var abandonedAt: Date?
        var isPremium: Bool
        /// This abandon has already been re-offered once.
        var reofferShown: Bool
        /// When the current process launched.
        var launchedAt: Date
        var now: Date = Date()
        var calendar: Calendar = .current
    }

    /// True when the re-offer should be presented now.
    ///
    /// "A later sitting" is either a later process launch or a later calendar
    /// day — iOS keeps processes alive for days, so launch alone would miss
    /// someone who backed out in the morning and came back that evening;
    /// day alone would re-ask within minutes of a force-quit and reopen.
    /// Neither is the same sitting, which is the one thing this must never be.
    static func decide(_ s: State) -> Bool {
        guard !s.isPremium, !s.reofferShown, let at = s.abandonedAt else { return false }
        guard s.now.timeIntervalSince(at) <= window else { return false }
        let laterLaunch = at < s.launchedAt
        let laterDay = !s.calendar.isDate(at, inSameDayAs: s.now)
        return laterLaunch || laterDay
    }
}

#if DEBUG
/// Once per process for the `-uiForceTrialReoffer` launch argument, so the
/// forced sheet doesn't return on every pop back to Today.
enum TrialReofferSession {
    @MainActor static var forced = false
}
#endif
