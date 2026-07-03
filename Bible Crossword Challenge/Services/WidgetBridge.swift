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
    }

    /// Mirrors the profile into shared defaults and asks WidgetKit to redraw.
    /// Call after any change to streak/completion state has been saved.
    static func publish(_ profile: PlayerProfile, calendar: Calendar = .current) {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return }
        defaults.set(profile.currentStreak, forKey: Key.currentStreak)
        defaults.set(profile.bestStreak, forKey: Key.bestStreak)
        defaults.set(profile.streakFreezes, forKey: Key.streakFreezes)
        let lastDay = profile.lastCompletedDate.map {
            calendar.startOfDay(for: $0).timeIntervalSinceReferenceDate
        } ?? 0
        defaults.set(lastDay, forKey: Key.lastCompletedDay)
        defaults.set(profile.totalPuzzlesCompleted, forKey: Key.totalCompleted)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
