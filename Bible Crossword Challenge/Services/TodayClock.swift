//
//  TodayClock.swift
//  Bible Crossword Challenge
//
//  The calendar day the app is showing, as one environment value.
//
//  A view that reads `Date()` in its body has no dependency on the date, so
//  nothing redraws it at midnight: Today kept showing yesterday's puzzle as
//  Solved to a player who left the app open overnight. Reading `\.today`
//  instead makes the day an input. RootView provides it, refreshed on the
//  system's day change and on every return to the foreground; an unchanged
//  day is an equal value and redraws nothing.
//

import SwiftUI

extension EnvironmentValues {
    /// Start of the current calendar day. Kept fresh by `tracksToday()`.
    @Entry var today: Date = Calendar.current.startOfDay(for: .now)
}

extension View {
    /// Provides `\.today` to this hierarchy and keeps it current.
    func tracksToday() -> some View {
        modifier(TodayTracker())
    }
}

private struct TodayTracker: ViewModifier {
    @State private var day = Calendar.current.startOfDay(for: .now)
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .environment(\.today, day)
            .task {
                for await _ in NotificationCenter.default.notifications(named: .NSCalendarDayChanged) {
                    refresh()
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { refresh() }
            }
    }

    private func refresh() {
        day = Calendar.current.startOfDay(for: .now)
    }
}
