//
//  NotificationService.swift
//  Bible Crossword Challenge
//
//  Schedules the daily reminder, streak-risk nudge and season openings as local
//  notifications — no server, no APNs.
//  Two consents, not one: the reminder asks cover the daily nudge and the
//  streak nudge, and season openings are promotional, so they ride on their own
//  switch in Settings and are off until asked for (see `scheduleSeasonOpenings`).
//  Each is scheduled on its own say-so — turning the daily reminder off leaves
//  pack news alone.
//  Nothing here claims Time Sensitive — win-back copy goes out Passive and
//  silent, everything else Active.
//  A lapse of three days, a week, or a fortnight rewrites that day's reminder
//  rather than adding one (see `winBack`), so the number of notifications a
//  player gets never depends on how long they have been away.
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
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()

    /// Mirrors the system permission state; refreshed on launch/foreground and
    /// after a request. Views read this to decide what settings UI to show.
    private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    /// Whether the system will deliver what we schedule. Provisional and
    /// ephemeral authorization both do — quietly, but they deliver — so every
    /// caller asks this rather than comparing against `.authorized` itself.
    /// Three places used to make that comparison independently and disagree:
    /// `RootView` finished an interrupted opt-in on provisional, while
    /// `reschedule` refused to schedule anything for it, which would have left
    /// a player switched on with an empty schedule and nothing to explain it.
    var canDeliver: Bool {
        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        default: return false
        }
    }

    /// The deep link from a tapped notification, waiting to be routed.
    /// `RootView` observes it, opens it through the same handler as an external
    /// URL, and clears it — so a notification target and a widget target can
    /// never drift into two different definitions of the same destination.
    var pendingURL: URL?

    private let center = UNUserNotificationCenter.current()

    /// How many days ahead we keep scheduled. Well under iOS's 64-pending cap.
    private let horizonDays = 14

    /// When the streak-risk nudge fires (9:00 PM) — late enough to be a last
    /// call, early enough to leave time to solve. Not private: Settings states
    /// the hour in words, and a settings screen describing a time the scheduler
    /// doesn't use is worse than one that says nothing.
    static let streakRiskMinutes = 21 * 60

    /// When a season-opening notice fires (10:00 AM). Deliberately not the
    /// player's reminder time: this is news, not a nudge, and sharing a minute
    /// with the daily reminder would put two notifications on the lock screen
    /// at once on the one day a seasonal pack has to make an impression.
    private let seasonOpeningMinutes = 10 * 60

    /// Notification Center groups by thread. The daily nudge and seasonal pack
    /// news are different conversations, and someone who lets one pile up
    /// shouldn't have to read past it to find the other.
    private static let reminderThread = "daily-reminder"
    nonisolated private static let packNewsThread = "pack-news"

    private override init() {
        super.init()
        center.delegate = self
    }

    // MARK: - Tap routing

    /// A tapped notification. Nothing is decided here beyond handing the URL to
    /// the app's one deep-link handler — the tap needs to land on the pack the
    /// notice was about, and `RootView` already knows how to get there.
    ///
    /// `nonisolated`: UserNotifications calls its delegate on its own queue,
    /// not the main thread, and `pendingURL` is observed state RootView reads.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let url = (response.notification.request.content.userInfo["url"] as? String)
            .flatMap(URL.init(string:))
        completionHandler()
        guard let url else { return }
        Task { @MainActor in pendingURL = url }
    }

    /// A notification arriving while the app is open.
    ///
    /// Reminders are suppressed: every one of them exists to get the player
    /// back into the app, and they are already here — showing the banner would
    /// interrupt the very solve it was asking for. (This was also the previous
    /// behaviour, by omission. iOS suppresses foreground notifications when a
    /// delegate declines to answer, so the rule was real but unwritten.)
    ///
    /// Pack news is the exception. A season opens once, the notice is the only
    /// announcement it gets, and dropping it because the player happened to be
    /// mid-puzzle at 10 AM means they never hear about it at all.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler:
            @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let isPackNews = notification.request.content.threadIdentifier == Self.packNewsThread
        completionHandler(isPackNews ? [.banner, .list] : [])
    }

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
    func reschedule(
        for profile: PlayerProfile, enabled: Bool, minutes: Int, packNews: Bool
    ) async {
        let calendar = Calendar.current
        let completedToday = calendar.isDate(
            profile.lastCompletedDate ?? .distantPast, inSameDayAs: Date()
        )
        await reschedule(
            enabled: enabled,
            minutes: minutes,
            packNews: packNews,
            streak: profile.currentStreak,
            completedToday: completedToday,
            freezes: profile.streakFreezes,
            daysSinceLastSolve: Self.daysSinceLastSolve(profile.lastCompletedDate, calendar: calendar)
        )
    }

    /// Whole days between the last solve and today, or `nil` for a player who
    /// has never finished a puzzle.
    ///
    /// `nil` rather than a large number on purpose: someone who has never solved
    /// anything has nothing to come back *to*, and the win-back copy below reads
    /// as nonsense addressed to them. They get the ordinary rotation.
    static func daysSinceLastSolve(_ lastCompleted: Date?, calendar: Calendar = .current) -> Int? {
        guard let lastCompleted else { return nil }
        return calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: lastCompleted),
            to: calendar.startOfDay(for: Date())
        ).day
    }

    /// Clears our pending reminders and, when enabled + authorized, schedules one
    /// per day for the next `horizonDays` at the chosen time. Today is skipped if
    /// already solved or the time has passed; the next reminder uses streak-saver
    /// copy when a streak is on the line.
    /// Pack news is scheduled on its own consent, whether or not the daily
    /// reminder is on.
    /// `packs` defaults to the bundled set; `nil` rather than a default
    /// expression because a default argument is evaluated outside the actor and
    /// `PuzzleProvider.shared` is main-actor isolated. Tests pass their own.
    func reschedule(
        enabled: Bool, minutes: Int, packNews: Bool = false, streak: Int,
        completedToday: Bool, freezes: Int = 0, daysSinceLastSolve: Int? = nil,
        packs: [PuzzlePack]? = nil
    ) async {
        let packs = packs ?? PuzzleProvider.shared.packs
        center.removeAllPendingNotificationRequests()
        guard enabled || packNews else { return }
        await refreshStatus()
        guard canDeliver else { return }

        let calendar = Calendar.current
        let now = Date()
        // Only for players who asked for it, and off until they do — see
        // `scheduleSeasonOpenings`. Ahead of the daily reminder's guard, not
        // behind it: until 2026-10 it sat at the end of this function, so
        // switching the reminder off quietly took the pack notices with it.
        if packNews {
            await scheduleSeasonOpenings(packs: packs, calendar: calendar, now: now)
        }
        guard enabled else { return }

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
            // How long the lapse will have run by the day this one fires. The
            // premise is that they don't solve in between — and if they do,
            // `reschedule` runs again and recomputes the whole horizon, so the
            // projection can never outlive the thing it assumed.
            let projectedLapse = daysSinceLastSolve.map { $0 + dayOffset }
            let copy = Self.reminderCopy(
                dayOffset: dayOffset, streak: streak,
                completedToday: completedToday, projectedLapse: projectedLapse
            )
            content.title = copy.title
            content.body = copy.body
            // Win-back copy goes out quiet. Someone who has ignored the app for
            // a week is the last person whose screen should light up, and the
            // day they finally hear from us is the day they are likeliest to
            // turn the reminder off rather than open it.
            content.interruptionLevel = copy.passive ? .passive : .active
            content.sound = copy.passive ? nil : .default
            content.threadIdentifier = Self.reminderThread

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

    /// One notice per seasonal pack that opens inside the scheduling horizon.
    ///
    /// "Once, when the pack opens" needs no flag to remember it was sent: every
    /// reschedule clears and recomputes from the calendar, and a window that has
    /// already opened is no longer an upcoming opening — so the notice can only
    /// ever be scheduled for a day the season actually begins, and only once.
    ///
    /// Sent only to players who turned on pack news in Settings. An opening
    /// notice announces content and leads to a paywall, which makes it
    /// promotional however useful it is — and the HIG is explicit that
    /// promotional notifications need their own permission and their own
    /// in-app switch. Every reminder ask in this app collects consent for one
    /// thing, a daily nudge about today's puzzle, so pack news cannot ride
    /// along on it.
    ///
    /// Premium packs are announced to opted-in free players too. Browsing a
    /// pack is free, and the season is the honest reason to look now.
    private func scheduleSeasonOpenings(
        packs: [PuzzlePack], calendar: Calendar, now: Date
    ) async {
        let openings = PuzzlePack.openings(
            in: packs, from: now, within: horizonDays, calendar: calendar
        )
        for opening in openings {
            guard let fireDate = calendar.date(
                bySettingHour: seasonOpeningMinutes / 60,
                minute: seasonOpeningMinutes % 60,
                second: 0, of: opening.opensOn
            ), fireDate > now else { continue }

            let pack = opening.pack
            let content = UNMutableNotificationContent()
            content.title = "\(pack.title) is open ✨"
            content.body = "\(pack.puzzleIDs.count) puzzles for the season. "
                + "They're here until it's over."
            // Passive and silent. This is news on a morning the calendar chose,
            // not a response to anything the player did, so it can wait in
            // Notification Center until they look.
            content.interruptionLevel = .passive
            content.threadIdentifier = Self.packNewsThread
            // Lands on the pack itself rather than the app's front door, so the
            // tap arrives where the notification was about — and `pack_opened`
            // can attribute the visit to the notification that caused it.
            content.userInfo = ["url": "biblecrossword://pack?id=\(pack.id)"]

            let components = calendar.dateComponents(
                [.year, .month, .day, .hour, .minute], from: fireDate
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(
                identifier: "pack-open-\(pack.id)", content: content, trigger: trigger
            )
            try? await center.add(request)
        }
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
        guard streak > 0, minutes < Self.streakRiskMinutes else { return }
        guard let day = calendar.date(
            byAdding: .day, value: completedToday ? 1 : 0, to: calendar.startOfDay(for: now)
        ), let fireDate = calendar.date(
            bySettingHour: Self.streakRiskMinutes / 60,
            minute: Self.streakRiskMinutes % 60,
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
        // Active, not Time Sensitive: a streak is a thing the app invented, and
        // breaking through a Focus for it would be exactly the overstatement
        // that teaches people to turn an app's notifications off.
        content.interruptionLevel = .active
        content.threadIdentifier = Self.reminderThread

        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: "streak-risk", content: content, trigger: trigger)
        try? await center.add(request)
    }

    private static let prompts = [
        "A fresh Bible crossword is waiting for you.",
        "Take a few minutes for today's verse and puzzle.",
        "Your daily Bible crossword is here — can you solve it?",
        "Sharpen your Scripture knowledge with today's puzzle.",
    ]

    /// Copy for the reminder scheduled `dayOffset` days out — extracted from
    /// the scheduling loop so the day-by-day decision is testable.
    ///
    /// The streak copy goes on the *last reminder that can still save the
    /// streak*: today's when today is unsolved, and tomorrow's right after a
    /// solve. The second case is new — before it, the reminder after a first
    /// solve carried the generic rotation, so the one notification aimed at
    /// the day-1→2 cliff (54% of players never pass a 1-day streak, measured
    /// 2026-08-23) never mentioned the streak at all. Streak 1 gets its own
    /// wording, borrowed from the day-2 sheet: "a 1-day streak" is a claim,
    /// "make it two days running" is an invitation.
    ///
    /// Copy is written for how things stand at *fire time*, assuming no solve
    /// in between — any solve triggers a full reschedule, so the assumption
    /// can't outlive itself.
    /// `passive` asks for the Passive interruption level and no sound: true
    /// for win-back copy, which is addressed to someone who has already been
    /// ignoring us.
    static func reminderCopy(
        dayOffset: Int, streak: Int, completedToday: Bool, projectedLapse: Int?
    ) -> (title: String, body: String, passive: Bool) {
        let streakSaveOffset = completedToday ? 1 : 0
        if streak > 0 && dayOffset == streakSaveOffset {
            if streak == 1 {
                return (
                    "Make it two days running 🔥",
                    "You solved yesterday's Bible puzzle. Solve today's and it's a streak.",
                    passive: false
                )
            }
            return (
                "Keep your streak alive 🔥",
                "You're on a \(streak)-day streak. Solve today's Bible puzzle to keep it going.",
                passive: false
            )
        }
        if let projectedLapse, let winBack = winBack(lapseDays: projectedLapse) {
            return (winBack.title, winBack.body, passive: true)
        }
        return ("Today's puzzle is ready", prompts[dayOffset % prompts.count], passive: false)
    }

    /// Copy for the day a lapse reaches three days, a week, or a fortnight —
    /// `nil` on every other day, which is most of them.
    ///
    /// This *replaces* the day's reminder rather than adding a second one. The
    /// daily reminder already fires every day of the horizon, so a lapsed player
    /// is being spoken to regardless; the problem was never reach, it was that
    /// after a week of ignoring "Today's puzzle is ready" the sentence has
    /// stopped carrying information. Stacking a win-back notification on top
    /// would put two lock-screen entries on the day someone is already least
    /// pleased to hear from us, which is how a reminder becomes an uninstall.
    ///
    /// Marked days only, not "3 or more": the generic rotation still runs in
    /// between, so the lapse copy stays occasional and keeps its weight.
    ///
    /// No streak numbers anywhere in here. By day three the streak is already
    /// gone, and opening with what they lost is an odd way to ask someone back.
    /// Each line names how little it costs to return instead — and by day
    /// fourteen says outright that there is nothing to catch up on, because
    /// believing otherwise is the actual reason people don't reopen a daily app.
    static func winBack(lapseDays: Int) -> (title: String, body: String)? {
        switch lapseDays {
        case 3:
            return (
                "Your puzzle is still here",
                "It's been a few days. Today's Bible crossword takes about five minutes."
            )
        case 7:
            return (
                "A week of verses waiting",
                "Come back to Scripture one clue at a time — today's puzzle is ready when you are."
            )
        case 14:
            return (
                "Still here whenever you are",
                "No streak to rebuild and nothing to catch up on. Just today's verse and a fresh crossword."
            )
        default:
            return nil
        }
    }
}

// MARK: - Reminder time <-> minutes-from-midnight

/// Bridges the stored `reminderMinutes` (Int) and the `Date` a DatePicker wants.
enum ReminderTime {
    static let defaultMinutes = 19 * 60 // 7:00 PM

    /// The reminder default for a player who never picked a time: their own
    /// play hour, since every ask surface appears while they are playing. A
    /// reminder at the hour a habit already happens beats a one-size 7 PM —
    /// the day-1→2 streak cliff (54% of players never pass a 1-day streak,
    /// measured 2026-08-23) is exactly the population the fixed default was
    /// missing. Rounded down to the half hour so the picker reads as a chosen
    /// time rather than a timestamp, and clamped to 7:00–21:00: a 2 AM solver
    /// gets a morning nudge, a midnight one gets last call at 9 PM — which
    /// also keeps the 9 PM streak-risk nudge from being made redundant.
    static func suggestedMinutes(now: Date = Date(), calendar: Calendar = .current) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: now)
        let rounded = ((parts.hour ?? 19) * 60 + (parts.minute ?? 0)) / 30 * 30
        return min(max(rounded, 7 * 60), 21 * 60)
    }

    /// Writes the play-hour suggestion into the shared default, once, and only
    /// for a player who has never set a time. Every reminder-ask surface calls
    /// this as it appears, so whichever ask the player meets first fixes the
    /// suggestion — and a time they picked themselves is never overwritten.
    static func seedSuggestionIfUnset(now: Date = Date()) {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: "reminderMinutes") == nil else { return }
        defaults.set(suggestedMinutes(now: now), forKey: "reminderMinutes")
    }

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
