//
//  ReviewAsk.swift
//  Bible Crossword Challenge
//
//  Whether the completion screen may call the system review prompt, as a pure
//  decision over plain values — same pattern as `ReminderAsk`. The view owns
//  persistence (@AppStorage) and the actual `requestReview` call; this owns
//  the rules, so the triggers and their interplay are testable without SwiftUI.
//
//  Three triggers, in priority order: solve-count milestones, the first 7-day
//  streak, and — for players well past the ladder's start — once per app
//  version, so loyal players who exhausted the ladder are still reachable on
//  a new release. Apple shows at most 3 prompts per 365 days and decides
//  whether a call displays at all; the spacing gap below keeps a cluster of
//  triggers (e.g. solve #10 landing days after streak 7) from spending those
//  three displays in one burst.
//

import Foundation

enum ReviewAsk {
    /// Which trigger fired, so the caller can spend the matching flag.
    enum Trigger: Equatable {
        case milestone(Int)
        case streak
        case version

        /// The analytics `trigger` value for `review_prompt_requested`.
        var analyticsValue: String {
            switch self {
            case .milestone(let rung): return "milestone_\(rung)"
            case .streak: return "streak"
            case .version: return "version"
            }
        }
    }

    /// Solve counts worth celebrating with an ask. Early rungs catch players
    /// while the honeymoon lasts; the tail keeps long-haul players askable.
    static let milestones = [3, 10, 30, 75, 150, 300]

    /// A first week-long streak is a happier moment than any mid-ladder rung.
    static let streakFloor = 7

    /// Solves needed before a new app version re-arms the prompt: version
    /// re-asks are for proven loyalists, not everyone who updates.
    static let versionFloor = 30

    /// Minimum spacing between asks on any trigger.
    static let minimumGap: TimeInterval = 14 * 86_400

    struct State {
        var totalCompleted: Int
        var currentStreak: Int
        /// Highest milestone already asked at.
        var milestoneAsked: Int
        var streakAsked: Bool
        /// Marketing version at the time of the last ask on ANY trigger —
        /// spending one also spends that version's re-arm.
        var versionAsked: String
        var currentVersion: String
        /// When the last ask fired, `nil` if never.
        var lastAsk: Date?
        var now: Date = Date()
    }

    static func decide(_ s: State) -> Trigger? {
        if let last = s.lastAsk, s.now.timeIntervalSince(last) < Self.minimumGap {
            // Blocked triggers stay armed — nothing is spent, so the same
            // trigger retries on a later solve once the gap has passed.
            return nil
        }
        if let milestone = milestones.last(where: { s.totalCompleted >= $0 }),
           milestone > s.milestoneAsked {
            return .milestone(milestone)
        }
        if s.currentStreak >= Self.streakFloor && !s.streakAsked {
            return .streak
        }
        if s.totalCompleted >= Self.versionFloor,
           !s.currentVersion.isEmpty,
           s.currentVersion != s.versionAsked {
            return .version
        }
        return nil
    }
}
