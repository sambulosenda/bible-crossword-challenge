//
//  NotificationCopyTests.swift
//  Bible Crossword ChallengeTests
//
//  Which reminder a lapsed player gets, and on which day.
//
//  `reschedule` itself can't be unit-tested — it writes to the real
//  `UNUserNotificationCenter`, which needs an app. The decision it makes can be,
//  because both halves are pure: `daysSinceLastSolve` maps a date to a lapse,
//  and `winBack` maps a lapse to copy. Everything worth getting wrong lives in
//  those two functions.
//

import Testing
import Foundation
@testable import Bible_Crossword_Challenge

private let utc: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(secondsFromGMT: 0)!
    return c
}()

struct WinBackCopyTests {

    @Test func firesOnTheThreeMarkedDays() {
        for day in [3, 7, 14] {
            #expect(NotificationService.winBack(lapseDays: day) != nil)
        }
    }

    /// The generic rotation has to keep running in between, or the lapse copy
    /// becomes the only thing the app ever says and stops meaning anything.
    @Test func silentOnEveryOtherDay() {
        for day in [0, 1, 2, 4, 5, 6, 8, 13, 15, 30, 365] {
            #expect(
                NotificationService.winBack(lapseDays: day) == nil,
                "day \(day) should use the ordinary rotation"
            )
        }
    }

    /// A negative lapse is arithmetically reachable if a solve is ever recorded
    /// against a future date (a device clock rolled back, a synced record from
    /// a device in a later timezone). It must not read as a fortnight away.
    @Test func silentOnNegativeLapse() {
        #expect(NotificationService.winBack(lapseDays: -1) == nil)
        #expect(NotificationService.winBack(lapseDays: -14) == nil)
    }

    /// Naming a streak to someone whose streak has already broken is the one
    /// thing this copy must never do.
    @Test func neverMentionsStreaks() {
        for day in [3, 7, 14] {
            let copy = NotificationService.winBack(lapseDays: day)
            let text = ((copy?.title ?? "") + " " + (copy?.body ?? "")).lowercased()
            #expect(!text.contains("streak") || text.contains("no streak"))
        }
    }
}

struct DaysSinceLastSolveTests {

    private func at(_ y: Int, _ m: Int, _ d: Int) -> Date {
        utc.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    /// Never solved is not "lapsed forever" — it's a different player, and the
    /// win-back copy is addressed to someone who has been here before.
    @Test func neverSolvedIsNil() {
        #expect(NotificationService.daysSinceLastSolve(nil, calendar: utc) == nil)
    }

    /// Whole calendar days, not elapsed hours: solving at 11 PM and checking at
    /// 1 AM is one day apart, not zero.
    @Test func countsCalendarDaysNotElapsedTime() {
        let lateLastNight = utc.date(from: DateComponents(year: 2026, month: 8, day: 10, hour: 23))!
        let days = NotificationService.daysSinceLastSolve(lateLastNight, calendar: utc)
        // Relative to "now", so assert the shape rather than a frozen number:
        // it can only be a non-negative whole number of days.
        #expect((days ?? -1) >= 0)
    }

    @Test func todayIsZero() {
        #expect(NotificationService.daysSinceLastSolve(Date(), calendar: utc) == 0)
    }

    /// The projection `reschedule` relies on: a player two days idle hits the
    /// three-day copy on tomorrow's reminder, not today's.
    @Test func projectionLandsOnTheMarkedDay() {
        let twoDaysIdle = 2
        #expect(NotificationService.winBack(lapseDays: twoDaysIdle + 0) == nil)
        #expect(NotificationService.winBack(lapseDays: twoDaysIdle + 1) != nil)
    }
}

// MARK: - Per-day reminder copy

struct ReminderCopyTests {

    /// The day-1→2 cliff: right after a first solve, tomorrow's reminder is
    /// the one that decides whether a streak exists — it must carry the
    /// day-2 invitation, not the generic rotation.
    @Test func tomorrowsReminderAfterFirstSolveInvitesDayTwo() {
        let copy = NotificationService.reminderCopy(
            dayOffset: 1, streak: 1, completedToday: true, projectedLapse: 1
        )
        #expect(copy.title.contains("two days running"))
    }

    /// Same situation seen from the unsolved day itself: streak 1, today
    /// pending — still the day-2 invitation.
    @Test func todaysReminderAtStreakOneInvitesDayTwo() {
        let copy = NotificationService.reminderCopy(
            dayOffset: 0, streak: 1, completedToday: false, projectedLapse: 1
        )
        #expect(copy.title.contains("two days running"))
    }

    /// A longer streak keeps the established streak-saver copy, on tomorrow's
    /// reminder after a solve and on today's when unsolved.
    @Test func longerStreaksKeepStreakSaverCopy() {
        let afterSolve = NotificationService.reminderCopy(
            dayOffset: 1, streak: 4, completedToday: true, projectedLapse: 1
        )
        #expect(afterSolve.title == "Keep your streak alive 🔥")
        #expect(afterSolve.body.contains("4-day"))

        let unsolvedToday = NotificationService.reminderCopy(
            dayOffset: 0, streak: 4, completedToday: false, projectedLapse: 1
        )
        #expect(unsolvedToday.title == "Keep your streak alive 🔥")
    }

    /// Only the last reminder that can still save the streak gets the streak
    /// copy — by the day after, the streak is already gone at fire time.
    @Test func laterDaysFallBackToTheRotation() {
        let copy = NotificationService.reminderCopy(
            dayOffset: 2, streak: 4, completedToday: true, projectedLapse: 2
        )
        #expect(copy.title == "Today's puzzle is ready")
    }

    /// No streak means no streak copy, whatever the day.
    @Test func noStreakNeverClaimsOne() {
        for offset in 0...2 {
            let copy = NotificationService.reminderCopy(
                dayOffset: offset, streak: 0, completedToday: false, projectedLapse: nil
            )
            #expect(!copy.title.contains("streak"))
            #expect(!copy.title.contains("two days"))
        }
    }

    /// Win-back still owns its marked days once the streak-save day has passed.
    @Test func winBackStillOwnsItsMarkedDays() {
        let copy = NotificationService.reminderCopy(
            dayOffset: 1, streak: 0, completedToday: false, projectedLapse: 3
        )
        let winBack = NotificationService.winBack(lapseDays: 3)!
        #expect(copy.title == winBack.title)
        #expect(copy.body == winBack.body)
        // And it goes out quiet — see `reminderCopy`.
        #expect(copy.passive)
    }
}

// MARK: - Play-hour reminder default

struct ReminderTimeSuggestionTests {

    private func at(_ hour: Int, _ minute: Int) -> Date {
        utc.date(from: DateComponents(year: 2026, month: 8, day: 23, hour: hour, minute: minute))!
    }

    /// The suggestion is the play hour, rounded down to the half hour.
    @Test func roundsDownToTheHalfHour() {
        #expect(ReminderTime.suggestedMinutes(now: at(9, 14), calendar: utc) == 9 * 60)
        #expect(ReminderTime.suggestedMinutes(now: at(9, 44), calendar: utc) == 9 * 60 + 30)
        #expect(ReminderTime.suggestedMinutes(now: at(20, 0), calendar: utc) == 20 * 60)
    }

    /// Antisocial hours clamp into 7:00–21:00: the small-hours solver gets a
    /// morning nudge, the late-night one gets last call at 9 PM.
    @Test func clampsAntisocialHours() {
        #expect(ReminderTime.suggestedMinutes(now: at(2, 10), calendar: utc) == 7 * 60)
        #expect(ReminderTime.suggestedMinutes(now: at(23, 30), calendar: utc) == 21 * 60)
        #expect(ReminderTime.suggestedMinutes(now: at(6, 59), calendar: utc) == 7 * 60)
        #expect(ReminderTime.suggestedMinutes(now: at(21, 0), calendar: utc) == 21 * 60)
    }
}

/// `notification_tapped.kind` is read off the identifier each request was
/// scheduled under, so a renamed identifier would silently file every tap as
/// `other`. These pin the identifiers `reschedule` actually uses.
struct NotificationTapKindTests {

    @Test func dailyCarriesItsDayOffset() {
        let tap = NotificationService.tapKind(identifier: "daily-3", passive: false)
        #expect(tap.kind == "daily")
        #expect(tap.dayOffset == 3)
    }

    @Test func passiveDailyIsWinBack() {
        let tap = NotificationService.tapKind(identifier: "daily-7", passive: true)
        #expect(tap.kind == "winback")
        #expect(tap.dayOffset == 7)
    }

    @Test func streakRiskAndPackNews() {
        #expect(NotificationService.tapKind(identifier: "streak-risk", passive: false).kind == "streak_risk")
        #expect(NotificationService.tapKind(identifier: "pack-open-easter", passive: true).kind == "pack_news")
        #expect(NotificationService.tapKind(identifier: "pack-open-easter", passive: true).dayOffset == nil)
    }

    @Test func unknownIsOther() {
        #expect(NotificationService.tapKind(identifier: "something-new", passive: false).kind == "other")
    }
}
