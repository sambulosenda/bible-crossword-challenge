//
//  BibleCrosswordWidget.swift
//  BibleCrosswordWidget
//
//  Home and Lock Screen widgets showing the streak flame and whether today's
//  puzzle is still waiting. Reads the snapshot the app writes into the shared
//  app-group defaults (see WidgetBridge in the app target) — it never opens
//  the SwiftData store. Timeline entries land at each midnight so the
//  "solved" state resets without the app launching.
//

import WidgetKit
import SwiftUI

// MARK: - Shared snapshot (keys mirror WidgetBridge in the app)

struct StreakSnapshot {
    static let appGroupID = "group.com.sambulosendas1.Bible-Crossword-Challenge"

    var currentStreak: Int = 0
    var bestStreak: Int = 0
    var streakFreezes: Int = 0
    var lastCompletedDay: Date?
    var totalCompleted: Int = 0

    static func load() -> StreakSnapshot {
        guard let d = UserDefaults(suiteName: appGroupID) else { return StreakSnapshot() }
        var s = StreakSnapshot()
        s.currentStreak = d.integer(forKey: "widget.currentStreak")
        s.bestStreak = d.integer(forKey: "widget.bestStreak")
        s.streakFreezes = d.integer(forKey: "widget.streakFreezes")
        let interval = d.double(forKey: "widget.lastCompletedDay")
        s.lastCompletedDay = interval > 0 ? Date(timeIntervalSinceReferenceDate: interval) : nil
        s.totalCompleted = d.integer(forKey: "widget.totalCompleted")
        return s
    }
}

// MARK: - Entry

struct StreakEntry: TimelineEntry {
    enum State {
        /// Today's puzzle is done — flame is lit.
        case solvedToday
        /// Streak is alive (solved yesterday, or one missed day covered by a
        /// freeze) but today's puzzle is still waiting.
        case streakAtStake
        /// No live streak — fresh start.
        case fresh
    }

    let date: Date
    let streak: Int
    let state: State

    /// Mirrors the app's Streaks rules: solved today keeps the flame lit;
    /// solved yesterday means the streak is alive but at stake; exactly one
    /// missed day with a freeze in hand still counts as alive.
    static func make(from snapshot: StreakSnapshot, at date: Date, calendar: Calendar = .current) -> StreakEntry {
        let today = calendar.startOfDay(for: date)
        guard let lastDay = snapshot.lastCompletedDay.map({ calendar.startOfDay(for: $0) }),
              snapshot.currentStreak > 0 else {
            return StreakEntry(date: date, streak: 0, state: .fresh)
        }
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        let dayBefore = calendar.date(byAdding: .day, value: -2, to: today) ?? today
        if lastDay >= today {
            return StreakEntry(date: date, streak: snapshot.currentStreak, state: .solvedToday)
        }
        if lastDay == yesterday {
            return StreakEntry(date: date, streak: snapshot.currentStreak, state: .streakAtStake)
        }
        if lastDay == dayBefore, snapshot.streakFreezes > 0 {
            return StreakEntry(date: date, streak: snapshot.currentStreak, state: .streakAtStake)
        }
        return StreakEntry(date: date, streak: 0, state: .fresh)
    }
}

// MARK: - Provider

struct StreakProvider: TimelineProvider {
    func placeholder(in context: Context) -> StreakEntry {
        StreakEntry(date: Date(), streak: 7, state: .streakAtStake)
    }

    func getSnapshot(in context: Context, completion: @escaping (StreakEntry) -> Void) {
        if context.isPreview {
            completion(StreakEntry(date: Date(), streak: 7, state: .streakAtStake))
        } else {
            completion(StreakEntry.make(from: StreakSnapshot.load(), at: Date()))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StreakEntry>) -> Void) {
        let snapshot = StreakSnapshot.load()
        let calendar = Calendar.current
        let now = Date()
        // One entry now, then one at each of the next two midnights so the
        // solved/waiting state flips even if the app isn't opened.
        var entries = [StreakEntry.make(from: snapshot, at: now)]
        var day = calendar.startOfDay(for: now)
        for _ in 0..<2 {
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
            entries.append(StreakEntry.make(from: snapshot, at: next))
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

// MARK: - Shared bits

extension StreakEntry {
    var flameColor: Color {
        switch state {
        case .solvedToday: .orange
        case .streakAtStake: .orange.opacity(0.75)
        case .fresh: .secondary.opacity(0.5)
        }
    }

    var headline: String {
        switch state {
        case .solvedToday: "Solved for today"
        case .streakAtStake: streak == 1 ? "Keep your streak" : "Keep your \(streak)-day streak"
        case .fresh: "Today's puzzle is ready"
        }
    }

    var subline: String {
        switch state {
        case .solvedToday: "Come back tomorrow"
        case .streakAtStake: "Solve today's puzzle"
        case .fresh: "Start a new streak"
        }
    }

    /// Tap target. When there's a puzzle to play, jump straight into it;
    /// once solved, just open the app. Handled by RootView's `onOpenURL`.
    var deepLinkURL: URL {
        switch state {
        case .solvedToday: URL(string: "biblecrossword://today")!
        case .streakAtStake, .fresh: URL(string: "biblecrossword://play-daily")!
        }
    }
}

// MARK: - Home Screen views

struct SmallStreakView: View {
    let entry: StreakEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "flame.fill")
                    .font(.title2)
                    .foregroundStyle(entry.flameColor)
                Text("\(entry.streak)")
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .contentTransition(.numericText())
                Spacer(minLength: 0)
            }
            Text("day streak")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text(entry.headline)
                .font(.footnote.weight(.semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            if entry.state != .solvedToday {
                Text(entry.subline)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Label("Done", systemImage: "checkmark.circle.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.green)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct MediumStreakView: View {
    let entry: StreakEntry

    var body: some View {
        HStack(spacing: 16) {
            VStack(spacing: 2) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(entry.flameColor)
                Text("\(entry.streak)")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .contentTransition(.numericText())
                Text(entry.streak == 1 ? "day" : "days")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 64)

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.headline)
                    .font(.headline)
                    .lineLimit(2)
                Text(entry.subline)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if entry.state == .solvedToday {
                    Label("Completed", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                } else {
                    Text("Play now")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.tint, in: .capsule)
                        .foregroundStyle(.white)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: .infinity)
    }
}

// MARK: - Lock Screen views

struct CircularStreakView: View {
    let entry: StreakEntry

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: entry.state == .solvedToday ? "flame.fill" : "flame")
                    .font(.headline)
                Text("\(entry.streak)")
                    .font(.system(.body, design: .rounded, weight: .bold))
            }
        }
    }
}

struct RectangularStreakView: View {
    let entry: StreakEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Label("\(entry.streak) day streak", systemImage: "flame.fill")
                .font(.headline)
            Text(entry.state == .solvedToday ? "Solved for today" : "Puzzle waiting")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct InlineStreakView: View {
    let entry: StreakEntry

    var body: some View {
        if entry.state == .solvedToday {
            Label("\(entry.streak) days · Solved", systemImage: "flame.fill")
        } else {
            Label("\(entry.streak) days · Puzzle ready", systemImage: "flame")
        }
    }
}

// MARK: - Widget

struct StreakWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: StreakEntry

    var body: some View {
        switch family {
        case .accessoryCircular: CircularStreakView(entry: entry)
        case .accessoryRectangular: RectangularStreakView(entry: entry)
        case .accessoryInline: InlineStreakView(entry: entry)
        case .systemMedium: MediumStreakView(entry: entry)
        default: SmallStreakView(entry: entry)
        }
    }
}

struct BibleCrosswordStreakWidget: Widget {
    let kind = "BibleCrosswordStreakWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StreakProvider()) { entry in
            StreakWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(entry.deepLinkURL)
        }
        .configurationDisplayName("Daily Streak")
        .description("Your streak flame and today's puzzle at a glance.")
        .supportedFamilies([
            .systemSmall, .systemMedium,
            .accessoryCircular, .accessoryRectangular, .accessoryInline,
        ])
    }
}

@main
struct BibleCrosswordWidgetBundle: WidgetBundle {
    var body: some Widget {
        BibleCrosswordStreakWidget()
    }
}

// MARK: - Previews

#Preview("Small · at stake", as: .systemSmall) {
    BibleCrosswordStreakWidget()
} timeline: {
    StreakEntry(date: .now, streak: 7, state: .streakAtStake)
    StreakEntry(date: .now, streak: 8, state: .solvedToday)
    StreakEntry(date: .now, streak: 0, state: .fresh)
}

#Preview("Medium", as: .systemMedium) {
    BibleCrosswordStreakWidget()
} timeline: {
    StreakEntry(date: .now, streak: 12, state: .streakAtStake)
    StreakEntry(date: .now, streak: 13, state: .solvedToday)
}
