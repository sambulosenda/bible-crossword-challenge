//
//  PremiumRowPlacement.swift
//  Bible Crossword Challenge
//
//  Where Today's Premium row sits for a free player: last on the page, as it
//  has since 2026-10-24, or at the top of the column under the day's
//  puzzles, for players past their first few days. A pure decision over
//  plain values, same pattern as `TrialReoffer`: HomeView reads the flag
//  and owns the layout; this owns the rule.
//
//  Why this exists: the row is the best-converting ask inside the app
//  (30 days to 2026-11-09: 17 players opened it, 8 tapped the trial button,
//  4 bought), but it closes the page, and until this change it had no
//  impression event, so its reach was unknown. The generic proactive offer
//  after 5 solves (`premium-ask`, removed 2026-10-03) got no taps from about
//  85 players. That one was a full-screen pitch nobody asked for; this one
//  is the same quiet row, only easier to find.
//
//  When the old Premium *card* sat at the top (30 days to 2026-10-02) it was
//  opened by 22 players and sold 3, so placement alone is not proven. The
//  flag is the test: `premium_row` treatment against control, read with the
//  row's `upsell_shown` → `paywall_opened` → `premium_purchased` series, and
//  checked against day-7 retention so a better-placed ask doesn't cost the
//  habit it's selling to.
//

import Foundation

enum PremiumRowPlacement {
    /// Off until it's turned on in PostHog. Unknown (offline, never fetched,
    /// flag not created yet) keeps the shipped layout.
    static let flag = FeatureFlag(rawValue: "premium-row-up", defaultValue: false)

    /// The super property every event carries once a device has an answer
    /// from the flag — see `FeatureFlags.registerVariant`.
    static let variantName = "premium_row_variant"

    /// Calendar days since install before the row can move: the install day
    /// is day 0, so 2 is the player's third day. The first days belong to
    /// the beginner path and the first solves.
    static let minimumDay = 2

    /// Past the learning window (`PlayerProfile.isStillLearning`), so the
    /// row never competes with the first three puzzles.
    static let minimumCompleted = 3

    struct State {
        var isPremium: Bool
        var totalCompleted: Int
        /// When the profile was created, which is install for nearly every
        /// player (a CloudKit restore carries the original date over).
        var createdAt: Date
        /// The day Today is showing — `\.today`, never `Date()`.
        var today: Date
        var calendar: Calendar = .current
    }

    /// True when this player is one the flag applies to. Read before the flag,
    /// so only eligible players are enrolled in the experiment: a flag read
    /// is an exposure, and counting players the change can't reach would
    /// dilute the readout.
    static func isEligible(_ s: State) -> Bool {
        guard !s.isPremium, s.totalCompleted >= minimumCompleted else { return false }
        let installed = s.calendar.startOfDay(for: s.createdAt)
        let today = s.calendar.startOfDay(for: s.today)
        let days = s.calendar.dateComponents([.day], from: installed, to: today).day ?? 0
        return days >= minimumDay
    }
}

#if DEBUG
extension PremiumRowPlacement {
    /// `-uiForcePremiumRowUp`: the promoted layout without a live flag, a
    /// three-day-old profile and three solves.
    static var isForced: Bool {
        ProcessInfo.processInfo.arguments.contains("-uiForcePremiumRowUp")
    }
}
#endif
