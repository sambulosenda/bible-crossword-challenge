//
//  NotificationService.swift
//  Bible Crossword Challenge
//
//  Schedules the daily reminder and streak-risk nudge as local notifications —
//  no server, no APNs.
//  Because a local notification can't recompute state at fire time, we instead
//  reschedule the next two weeks whenever the app's state changes (launch,
//  foreground, puzzle completion, settings change). The next reminder is the one
//  that matters most, so it carries streak-aware copy; later days fall back to
//  rotating generic prompts.
//
//  The whole app runs with default MainActor isolation, so this type is
//  main-actor isolated and its @Observable status property is safe to read from
//  SwiftUI without extra annotation.
//

import Foundation
import Observation
import UserNotifications

@Observable
final class NotificationService {
    static let shared = NotificationService()

    /// Mirrors the system permission state; refreshed on launch/foreground and
    /// after a request. Views read this to decide what settings UI to show.
    private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private let center = UNUserNotificationCenter.current()

    /// How many days ahead we keep scheduled. Well under iOS's 64-pending cap.
    private let horizonDays = 14

    /// When the streak-risk nudge fires (9:00 PM) — late enough to be a last
    /// call, early enough to leave time to solve.
    private let streakRiskMinutes = 21 * 60

    private init() {}

    // MARK: - Authorization

    func refreshStatus() async {
        authorizationStatus = await center.notificationSettings().authorizationStatus
    }

    /// Prompts for alert + sound permission. Returns whether it was granted.
    @discardableResult
    func requestAuthorization() async -> Bool {
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        await refreshStatus()
        return granted
    }

    // MARK: - Scheduling

    /// Convenience that derives streak context from the profile.
    func reschedule(for profile: PlayerProfile, enabled: Bool, minutes: Int) async {
        let completedToday = Calendar.current.isDate(
            profile.lastCompletedDate ?? .distantPast, inSameDayAs: Date()
        )
        await reschedule(
            enabled: enabled,
            minutes: minutes,
            streak: profile.currentStreak,
            completedToday: completedToday,
            freezes: profile.streakFreezes
        )
    }

    /// Clears our pending reminders and, when enabled + authorized, schedules one
    /// per day for the next `horizonDays` at the chosen time. Today is skipped if
    /// already solved or the time has passed; the next reminder uses streak-saver
    /// copy when a streak is on the line.
    func reschedule(
        enabled: Bool, minutes: Int, streak: Int, completedToday: Bool, freezes: Int = 0
    ) async {
        center.removeAllPendingNotificationRequests()
        guard enabled else { return }
        await refreshStatus()
        guard authorizationStatus == .authorized else { return }

        let calendar = Calendar.current
        let now = Date()
        let hour = minutes / 60
        let minute = minutes % 60
        let startOfToday = calendar.startOfDay(for: now)

        for dayOffset in 0..<horizonDays {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: startOfToday),
                  let fireDate = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day),
                  fireDate > now
            else { continue }
            if dayOffset == 0 && completedToday { continue }

            let content = UNMutableNotificationContent()
            if dayOffset == 0 && streak > 0 && !completedToday {
                content.title = "Keep your streak alive 🔥"
                content.body = "You're on a \(streak)-day streak. Solve today's Bible puzzle to keep it going."
            } else {
                content.title = "Today's puzzle is ready"
                content.body = Self.prompts[dayOffset % Self.prompts.count]
            }
            content.sound = .default

            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(identifier: "daily-\(dayOffset)", content: content, trigger: trigger)
            try? await center.add(request)
        }

        await scheduleStreakRiskNudge(
            minutes: minutes, streak: streak, completedToday: completedToday,
            freezes: freezes, calendar: calendar, now: now
        )
    }

    /// A second, last-call reminder for the evening a streak would break.
    /// Targets tonight when today is still unsolved, or tomorrow night right
    /// after a solve — every reschedule clears and recomputes it, so it only
    /// fires if the day genuinely ends with the streak on the line. Skipped
    /// when there's no streak or the regular reminder already fires at 9 PM
    /// or later.
    private func scheduleStreakRiskNudge(
        minutes: Int, streak: Int, completedToday: Bool, freezes: Int,
        calendar: Calendar, now: Date
    ) async {
        guard streak > 0, minutes < streakRiskMinutes else { return }
        guard let day = calendar.date(
            byAdding: .day, value: completedToday ? 1 : 0, to: calendar.startOfDay(for: now)
        ), let fireDate = calendar.date(
            bySettingHour: streakRiskMinutes / 60, minute: streakRiskMinutes % 60,
            second: 0, of: day
        ), fireDate > now else { return }

        let content = UNMutableNotificationContent()
        content.title = "Your \(streak)-day streak ends at midnight ⏰"
        // Name the freeze when there is one. Withholding it to keep the threat
        // sharp would be a lie by omission about a thing the player earned, and
        // the app tells them about it everywhere else — the last message before
        // a streak dies is the wrong place to start being cagey.
        content.body = freezes > 0
            ? "Solve today's Bible puzzle to keep it alive — or a freeze will cover you tonight."
            : "Solve today's Bible puzzle before the day is over to keep it alive."
        content.sound = .default

        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: "streak-risk", content: content, trigger: trigger)
        try? await center.add(request)
    }

    func cancelAll() {
        center.removeAllPendingNotificationRequests()
    }

    private static let prompts = [
        "A fresh Bible crossword is waiting for you.",
        "Take a few minutes for today's verse and puzzle.",
        "Your daily Bible crossword is here — can you solve it?",
        "Sharpen your Scripture knowledge with today's puzzle.",
    ]
}

// MARK: - Reminder time <-> minutes-from-midnight

/// Bridges the stored `reminderMinutes` (Int) and the `Date` a DatePicker wants.
enum ReminderTime {
    static let defaultMinutes = 19 * 60 // 7:00 PM

    static func date(fromMinutes minutes: Int) -> Date {
        Calendar.current.date(
            bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()
        ) ?? Date()
    }

    static func minutes(from date: Date) -> Int {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 19) * 60 + (parts.minute ?? 0)
    }
}
