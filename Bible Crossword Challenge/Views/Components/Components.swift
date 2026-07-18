//
//  Components.swift
//  Bible Crossword Challenge
//
//  Small reusable views shared across screens.
//

import SwiftUI

// MARK: - Streak summary

/// YouVersion-style streak: flame + big day count, a week row of check-filled
/// circles, and the best streak kept quiet on the trailing edge.
struct StreakCard: View {
    let current: Int
    let best: Int
    var freezes: Int = 0
    /// True when a freeze was spent today, to surface a one-time reassurance.
    var savedRecently: Bool = false
    /// `Calendar` weekday numbers (1 = Sunday) with a completed puzzle this
    /// week, driving the week row.
    var completedWeekdays: Set<Int> = []

    @ScaledMetric(relativeTo: .largeTitle) private var iconSize = 48
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: Theme.Spacing.m) {
            HStack(spacing: Theme.Spacing.m) {
                // The flame stays fire-orange (a blue flame reads as off), while
                // the week row below carries the accent.
                Image(systemName: "flame.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)
                    .frame(width: iconSize, height: iconSize)
                    .background(.orange.opacity(0.12), in: .circle)

                VStack(alignment: .leading, spacing: 0) {
                    Text("\(current)")
                        .font(.largeTitle.weight(.bold))
                        .monospacedDigit()
                        .contentTransition(reduceMotion ? .identity : .numericText())
                    Text("day streak")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(best)")
                        .font(.title3.weight(.bold))
                        .monospacedDigit()
                    Text("best")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }

            WeekRow(completedWeekdays: completedWeekdays)

            if savedRecently {
                footnote("A freeze saved your streak", symbol: "snowflake", tint: .cyan)
            } else if freezes > 0 {
                footnote("^[\(freezes) freeze](inflect: true) ready to protect your streak",
                         symbol: "snowflake", tint: .cyan)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.Spacing.l)
        .elevatedCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        var label = "Current streak \(current) days, best streak \(best) days"
        if !completedWeekdays.isEmpty {
            label += ". \(completedWeekdays.count) \(completedWeekdays.count == 1 ? "day" : "days") completed this week"
        }
        if savedRecently {
            label += ". A freeze saved your streak"
        } else if freezes > 0 {
            label += ". \(freezes) streak \(freezes == 1 ? "freeze" : "freezes") available"
        }
        return label
    }

    private func footnote(_ text: LocalizedStringKey, symbol: String, tint: Color) -> some View {
        Label(text, systemImage: symbol)
            .font(.caption.weight(.medium))
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .padding(.top, Theme.Spacing.xs)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color.primary.opacity(0.08))
                    .frame(height: 1)
            }
    }
}

/// The seven-day row inside `StreakCard`: a filled scarlet check for completed
/// days, an outlined ring for today, and muted letter chips for the rest.
private struct WeekRow: View {
    let completedWeekdays: Set<Int>

    @Environment(\.calendar) private var calendar
    @ScaledMetric(relativeTo: .body) private var daySize = 34

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            ForEach(orderedWeekdays, id: \.self) { day in
                dayCircle(day)
                    .frame(maxWidth: .infinity)
            }
        }
        // Decorative recap — the card's combined label already summarises it.
        .accessibilityHidden(true)
    }

    /// The week's weekdays in the user's calendar order (respects firstWeekday).
    private var orderedWeekdays: [Int] {
        let first = calendar.firstWeekday
        return (0..<7).map { ((first - 1 + $0) % 7) + 1 }
    }

    private var today: Int { calendar.component(.weekday, from: Date()) }

    @ViewBuilder
    private func dayCircle(_ day: Int) -> some View {
        let done = completedWeekdays.contains(day)
        let isToday = day == today

        ZStack {
            if done {
                Circle().fill(Theme.accent)
                Image(systemName: "checkmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
            } else {
                Circle().fill(Color.primary.opacity(0.06))
                if isToday {
                    Circle().strokeBorder(Theme.accent, lineWidth: 1.5)
                }
                Text(letter(for: day))
                    .font(.caption.weight(isToday ? .bold : .medium))
                    .foregroundStyle(isToday ? .primary : .secondary)
            }
        }
        .frame(width: daySize, height: daySize)
    }

    private func letter(for day: Int) -> String {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        return symbols.indices.contains(day - 1) ? symbols[day - 1] : ""
    }
}

// MARK: - Difficulty pill

struct DifficultyBadge: View {
    let difficulty: PuzzleDifficulty

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Text(difficulty.label)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, Theme.Spacing.s)
            .padding(.vertical, 4)
            .background(difficulty.tint.opacity(0.18), in: .capsule)
            .foregroundStyle(textColor)
    }

    /// The bright system tints fail WCAG contrast on the faint tinted capsule in
    /// light mode, so use a darker same-hue shade there. Dark mode reads fine.
    private var textColor: Color {
        guard scheme == .light else { return difficulty.tint }
        switch difficulty {
        case .easy:   return Color(red: 0.10, green: 0.42, blue: 0.18)
        case .medium: return Color(red: 0.55, green: 0.31, blue: 0.0)
        case .hard:   return Color(red: 0.70, green: 0.12, blue: 0.12)
        }
    }
}

// MARK: - Banner ad placeholder

/// Placeholder banner shown to free users. Swap for a real `GADBannerView`
/// wrapper once AdMob is configured.
struct BannerAdView: View {
    var body: some View {
        Text("Advertisement")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(Color(.secondarySystemBackground))
            .overlay(alignment: .topLeading) {
                Text("Ad")
                    .font(.system(size: 9, weight: .bold))
                    .padding(2)
                    .background(.yellow.opacity(0.7), in: .rect(cornerRadius: 3))
                    .padding(4)
            }
            .accessibilityHidden(true)
    }
}
