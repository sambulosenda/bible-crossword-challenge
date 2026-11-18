//
//  InviteAsk.swift
//  Bible Crossword Challenge
//
//  Whether the completion screen may put the invite in front of the player,
//  as a pure decision over plain values — same pattern as `ReminderAsk` and
//  `ReviewAsk`. The view owns persistence (@AppStorage) and the share sheet;
//  this owns the rules.
//
//  Why it exists (30 days to 2026-11-18): 3,732 completions, 31 taps on
//  Challenge a Friend, 18 sends — while 8 of those 18 were opened and 3
//  became installs. The link converts; the button is the leak. It read the
//  same on every solve, and after a Mini (1,910 of those completions) it sat
//  in the overflow menu behind "Play Today's Full Puzzle". So the invite is
//  named in the scorecard on the solves worth showing someone, and only then.
//

import Foundation

enum InviteAsk {
    /// What made this solve worth sending. Most notable first in `decide`.
    enum Moment: Equatable {
        case streak(Int)
        /// A full puzzle solved faster than any before it.
        case bestTime
        /// A full puzzle solved without asking for a hint.
        case noHints

        /// The analytics `moment` value for `invite_ask_shown`.
        var analyticsValue: String {
            switch self {
            case .streak(let days): return "streak_\(days)"
            case .bestTime: return "best_time"
            case .noHints: return "no_hints"
            }
        }
    }

    /// Runs worth stopping for. Three is the first one a new player reaches.
    static let streakMoments = [3, 7, 14, 30]

    /// At most one ask a week.
    static let gap: TimeInterval = 7 * 86_400

    /// Asks shown since the player last sent one. At this many the row rests.
    static let unansweredBeforeRest = 2

    /// How long the row stays away after `unansweredBeforeRest` asks went
    /// nowhere.
    static let restGap: TimeInterval = 30 * 86_400

    struct State {
        /// The first time this puzzle was finished: a replay beats the clock
        /// and skips the hints by memory.
        var isFirstSolve: Bool
        var isMini: Bool
        var hintsUsed: Int
        /// This solve set the profile's best time, and there was one to beat.
        var isNewBest: Bool
        var streak: Int
        /// The streak moved on this solve. A second puzzle on a milestone day
        /// is not the milestone again.
        var streakAdvanced: Bool
        var isComeback: Bool
        /// Solves including this one.
        var totalCompleted: Int
        /// The screen already carries an ask or a friend's result: the
        /// reminder row, the review prompt, the return-day sheet, a challenge
        /// that came in with this solve.
        var otherAskOnScreen: Bool
        var lastShown: Date?
        /// Asks shown since the last invite the player actually sent.
        var unanswered: Int
        var now: Date = Date()
    }

    static func decide(_ s: State) -> Moment? {
        // The first solve belongs to the celebration and the reminder ask.
        guard s.isFirstSolve, !s.otherAskOnScreen, s.totalCompleted >= 2 else { return nil }
        if let last = s.lastShown {
            let wait = s.unanswered >= unansweredBeforeRest ? restGap : gap
            guard s.now.timeIntervalSince(last) >= wait else { return nil }
        }
        if s.streakAdvanced, !s.isComeback, streakMoments.contains(s.streak) {
            return .streak(s.streak)
        }
        // A 7×7 has no best time and is rarely hinted, so neither says much
        // about a Mini — the same line the achievements draw.
        guard !s.isMini else { return nil }
        if s.isNewBest { return .bestTime }
        if s.hintsUsed == 0 { return .noHints }
        return nil
    }
}
