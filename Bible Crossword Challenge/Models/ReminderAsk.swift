//
//  ReminderAsk.swift
//  Bible Crossword Challenge
//
//  Whether a reminder opt-in ask may be shown on a given surface, as a pure
//  decision over plain values — same pattern as `DailyPresentation`. The views
//  own persistence (@AppStorage) and side effects; this owns the rules, so the
//  cross-surface guarantees (one ask per day, one per session, silence once
//  answered) are testable without SwiftUI.
//
//  Only players iOS has never asked are eligible: `.notDetermined` is the one
//  state where a tap can still reach the real system dialog. Players who
//  reached it and said no recover through the Profile toggle's Settings
//  deep-link, not another prompt.
//

import Foundation

enum ReminderAsk {
    /// Where an ask can appear. Raw values are the analytics `source`.
    enum Surface: String {
        /// Completion screen, first few solves — asked at the moment the
        /// product just proved its value.
        case completion
        /// Home streak card once there is a streak worth protecting.
        case streakCard = "streak_card"
    }

    /// The completion ask retries across the first few solves until answered;
    /// beyond this it stops competing with a screen that has other work to do.
    static let maxCompletionAsks = 3

    struct State {
        var remindersEnabled: Bool
        /// `UNAuthorizationStatus == .notDetermined`, passed as a plain Bool so
        /// the model (and its tests) never import UserNotifications.
        var permissionUndetermined: Bool
        var totalCompleted: Int
        var currentStreak: Int
        /// Impressions already spent per surface.
        var completionAsksShown: Int
        var streakAskShown: Bool
        /// Start-of-day stamp of the last ask on ANY surface, including the
        /// day-2 sheet. Encoded like `autoPaywallLastDay`.
        var lastAskDay: Date?
        /// True once any surface asked since process launch — two asks in one
        /// sitting reads as nagging even when the daily cap would allow it.
        var askedThisSession: Bool
        var now: Date = Date()
        var calendar: Calendar = .current
    }

    static func decide(_ surface: Surface, _ s: State) -> Bool {
        guard !s.remindersEnabled,
              s.permissionUndetermined,
              !s.askedThisSession
        else { return false }
        if let last = s.lastAskDay, s.calendar.isDate(last, inSameDayAs: s.now) {
            return false
        }
        switch surface {
        case .completion:
            return s.totalCompleted >= 1 && s.completionAsksShown < Self.maxCompletionAsks
        case .streakCard:
            return s.currentStreak >= 2 && !s.streakAskShown
        }
    }
}

/// Process-lifetime flag behind `State.askedThisSession`. A type rather than a
/// stored default deliberately: "this session" should reset on relaunch.
/// Main-actor isolated — every reader/writer is view code, and an unisolated
/// mutable static is a data race under strict concurrency.
enum ReminderAskSession {
    @MainActor static var asked = false
}
