//
//  WidgetBridge.swift
//  Bible Crossword Challenge
//
//  Publishes a tiny snapshot of streak state into the shared app-group
//  defaults so the widget extension can render without touching the
//  SwiftData/CloudKit store. Keys are read by BibleCrosswordWidget — keep the
//  two sides in sync if they ever change.
//

import Foundation
import SwiftData
import WidgetKit

enum WidgetBridge {
    static let appGroupID = "group.com.sambulosendas1.Bible-Crossword-Challenge"

    enum Key {
        static let currentStreak = "widget.currentStreak"
        static let bestStreak = "widget.bestStreak"
        static let streakFreezes = "widget.streakFreezes"
        /// Start-of-day of the last completion, as timeIntervalSinceReferenceDate.
        /// 0 means never completed.
        static let lastCompletedDay = "widget.lastCompletedDay"
        static let totalCompleted = "widget.totalCompleted"
        /// Start-of-day the two per-pool flags below were computed for, as
        /// timeIntervalSinceReferenceDate. The widget trusts the flags only
        /// when this matches its entry's day, so a snapshot written yesterday
        /// can't claim today's puzzles are done after midnight.
        static let flagsDay = "widget.flagsDay"
        static let dailyCompletedToday = "widget.dailyCompletedToday"
        static let miniCompletedToday = "widget.miniCompletedToday"
        /// The verse of the day for today and the next few days, as
        /// `[["day": startOfDay interval, "text": …, "reference": …]]` — the
        /// same verse Today's header shows, so the widget and the app agree.
        /// Several days ahead because the widget's timeline runs past
        /// midnight without the app.
        static let verses = "widget.verses"
    }

    /// Days of verses published ahead: today plus the widget timeline's
    /// two midnights, and one spare.
    static let verseDays = 4

    /// Mirrors the profile into shared defaults and asks WidgetKit to redraw.
    /// Call after any change to streak/completion state has been saved. The
    /// context is used to read the two records that decide which puzzle the
    /// widget's tap should open — `lastCompletedDay` alone can't tell a
    /// mini-only day from a daily-only one.
    static func publish(
        _ profile: PlayerProfile,
        context: ModelContext,
        provider: PuzzleProvider = .shared,
        calendar: Calendar = .current
    ) {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return }
        defaults.set(profile.currentStreak, forKey: Key.currentStreak)
        defaults.set(profile.bestStreak, forKey: Key.bestStreak)
        defaults.set(profile.streakFreezes, forKey: Key.streakFreezes)
        let lastDay = profile.lastCompletedDate.map {
            calendar.startOfDay(for: $0).timeIntervalSinceReferenceDate
        } ?? 0
        defaults.set(lastDay, forKey: Key.lastCompletedDay)
        defaults.set(profile.totalPuzzlesCompleted, forKey: Key.totalCompleted)

        let today = calendar.startOfDay(for: Date())
        defaults.set(today.timeIntervalSinceReferenceDate, forKey: Key.flagsDay)
        defaults.set(
            completedToday(provider.dailyPuzzle()?.id, context: context, on: today, calendar: calendar),
            forKey: Key.dailyCompletedToday
        )
        defaults.set(
            completedToday(provider.dailyMini()?.id, context: context, on: today, calendar: calendar),
            forKey: Key.miniCompletedToday
        )
        defaults.set(verses(from: today, provider: provider, calendar: calendar), forKey: Key.verses)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private static func verses(from today: Date, provider: PuzzleProvider, calendar: Calendar) -> [[String: Any]] {
        (0..<verseDays).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let verse = provider.verseOfTheDay(
                      on: day, excluding: provider.dailyPuzzle(for: day, calendar: calendar)?.id, calendar: calendar
                  ),
                  !verse.verse.isEmpty
            else { return nil }
            return ["day": day.timeIntervalSinceReferenceDate, "text": verse.verse, "reference": verse.reference]
        }
    }

    /// Whether `puzzleID`'s record was completed on `day`. Completed on an
    /// earlier rotation pass doesn't count — the widget's job is today's
    /// habit, and the rotation serving a puzzle solved months ago is exactly
    /// the repeat `DailyPresentation` warns about.
    private static func completedToday(
        _ puzzleID: String?,
        context: ModelContext,
        on day: Date,
        calendar: Calendar
    ) -> Bool {
        guard let puzzleID else { return false }
        let descriptor = FetchDescriptor<PuzzleRecord>(
            predicate: #Predicate { $0.puzzleID == puzzleID }
        )
        guard let record = try? context.fetch(descriptor).first,
              record.isCompleted,
              let completed = record.completedDate
        else { return false }
        return calendar.isDate(completed, inSameDayAs: day)
    }
}
