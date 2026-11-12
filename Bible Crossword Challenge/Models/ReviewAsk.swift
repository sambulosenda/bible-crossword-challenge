//
//  ReviewAsk.swift
//  Bible Crossword Challenge
//
//  Whether the completion screen may call the system review prompt, as a pure
//  decision over plain values — same pattern as `ReminderAsk`. The view owns
//  persistence (@AppStorage) and the actual `requestReview` call; this owns
//  the rules, so the triggers and their interplay are testable without SwiftUI.
//
//  Four triggers, in priority order: solve-count milestones, finishing a pack
//  or Journey, the first 7-day streak, and — for players well past the
//  ladder's start — a periodic re-ask every 120 days, so loyal players who
//  exhausted the ladder are still reachable. Apple shows at most 3 prompts per 365 days and decides
//  whether a call displays at all; the spacing gap below keeps a cluster of
//  triggers (e.g. solve #10 landing days after streak 7) from spending those
//  three displays in one burst.
//

import Foundation

enum ReviewAsk {
    /// Which trigger fired, so the caller can spend the matching flag.
    enum Trigger: Equatable {
        case milestone(Int)
        /// This solve finished a pack or Journey for the first time.
        case collection
        case streak
        /// A loyal player's re-ask, `periodicGap` after the last ask.
        case periodic

        /// The analytics `trigger` value for `review_prompt_requested`.
        var analyticsValue: String {
            switch self {
            case .milestone(let rung): return "milestone_\(rung)"
            case .collection: return "collection_complete"
            case .streak: return "streak"
            case .periodic: return "periodic"
            }
        }
    }

    /// Solve counts worth celebrating with an ask. Early rungs catch players
    /// while the honeymoon lasts; the tail keeps long-haul players askable.
    static let milestones = [3, 10, 30, 75, 150, 300]

    /// A first week-long streak is a happier moment than any mid-ladder rung.
    static let streakFloor = 7

    /// Solves needed before the periodic re-ask: it's for proven loyalists.
    static let loyaltyFloor = 30

    /// How long after any ask a loyal player is asked again. 120 days, about
    /// three a year — Apple's display cap. It was once per app version until
    /// 2026-11-03: shipping every week or two, that fired about twice per
    /// loyal player in 60 days (64 asks to 28 players), and each call could
    /// spend one of the year's three displays before a better moment.
    static let periodicGap: TimeInterval = 120 * 86_400

    /// Minimum spacing between asks on any trigger.
    static let minimumGap: TimeInterval = 14 * 86_400

    /// No ask before the install is this old, on any trigger. Solve counts
    /// include Minis, so the first rung is reachable in one sitting: of 20
    /// first-rung prompts to 2026-09-02, 7 fired on install day. A day-0
    /// rating is a novelty rating, and it spends one of the three yearly
    /// displays on the player least likely to still be here.
    ///
    /// One day, not the three it was until 2026-11-12: over 90 days, 143 of
    /// 344 players with three or more daily solves were never asked, most
    /// likely because they solved inside the floor and left before it
    /// lifted. Coming back on a second day is the signal the floor wanted.
    static let minimumInstallAge: TimeInterval = 1 * 86_400

    struct State {
        var totalCompleted: Int
        var currentStreak: Int
        /// Highest milestone already asked at.
        var milestoneAsked: Int
        var streakAsked: Bool
        /// This solve finished a pack or Journey for the first time — the
        /// biggest high in the loop after a streak, and earned.
        var finishedCollection: Bool = false
        /// When the last ask fired, `nil` if never.
        var lastAsk: Date?
        /// When the profile was created. `nil` (unknown) is treated as old
        /// enough — a missing date must not silence a long-time player.
        var installedAt: Date?
        var now: Date = Date()
    }

    static func decide(_ s: State) -> Trigger? {
        // Both floors block without spending: the trigger stays armed and
        // retries on a later solve once the time has passed.
        if let installed = s.installedAt,
           s.now.timeIntervalSince(installed) < Self.minimumInstallAge {
            return nil
        }
        if let last = s.lastAsk, s.now.timeIntervalSince(last) < Self.minimumGap {
            return nil
        }
        if let milestone = milestones.last(where: { s.totalCompleted >= $0 }),
           milestone > s.milestoneAsked {
            return .milestone(milestone)
        }
        if s.finishedCollection {
            return .collection
        }
        if s.currentStreak >= Self.streakFloor && !s.streakAsked {
            return .streak
        }
        // Never asked counts as long enough: a loyal player the ladder missed
        // (say, every rung landed inside the install floor) is still reached.
        if s.totalCompleted >= Self.loyaltyFloor,
           s.lastAsk.map({ s.now.timeIntervalSince($0) >= Self.periodicGap }) ?? true {
            return .periodic
        }
        return nil
    }
}
