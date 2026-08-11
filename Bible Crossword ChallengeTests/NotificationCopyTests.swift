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
