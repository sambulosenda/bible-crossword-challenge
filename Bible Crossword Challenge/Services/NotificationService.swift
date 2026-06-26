//
//  NotificationService.swift
//  Bible Crossword Challenge
//
//  Schedules the daily reminder as local notifications — no server, no APNs.
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
            completedToday: completedToday
        )
    }

    /// Clears our pending reminders and, when enabled + authorized, schedules one
    /// per day for the next `horizonDays` at the chosen time. Today is skipped if
    /// already solved or the time has passed; the next reminder uses streak-saver
    /// copy when a streak is on the line.
    func reschedule(enabled: Bool, minutes: Int, streak: Int, completedToday: Bool) async {
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
