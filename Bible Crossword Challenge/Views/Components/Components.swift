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

                // Only a record worth chasing earns a second number — while
                // best == current the trailing stat just mirrors the big one.
                if best > current {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("\(best)")
                            .font(.headline)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        Text("best")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
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

    // The tint stays on the symbol only: a cyan caption fails contrast on the
    // card, and a full-width tinted line reads as a button this isn't.
    private func footnote(_ text: LocalizedStringKey, symbol: String, tint: Color) -> some View {
        Label {
            Text(text).foregroundStyle(.secondary)
        } icon: {
            Image(systemName: symbol).foregroundStyle(tint)
        }
        .font(.caption.weight(.medium))
        .frame(maxWidth: .infinity)
        .padding(.top, Theme.Spacing.xs)
    }
}

// MARK: - Comeback

/// Shown on Today in place of `StreakCard` when a streak has just broken.
///
/// A zero on the flame card states the loss and offers nothing — the moment a
/// long run ends is exactly when a player decides whether to keep the app, and
/// "0 day streak" is a scoreboard for a game they just lost. This says the same
/// fact and hands them the next move.
///
/// Deliberately quiet: the outline flame rather than the lit one, no celebration
/// treatment, and a tonal CTA so it can't outshout the daily card's own pill —
/// Today allows one loud action, and it isn't this one. No guilt, no offer to
/// sell the streak back; the ticket's product rules rule both out.
struct ComebackCard: View {
    /// The run that ended, for naming what was lost rather than glossing it.
    let previousStreak: Int
    /// What the primary action opens — the mini when there is one, else the
    /// daily. Passed in so the button can name the thing it actually plays.
    let playLabel: String
    var onPlay: () -> Void
    var onDismiss: () -> Void

    @ScaledMetric(relativeTo: .largeTitle) private var iconSize = 48

    var body: some View {
        VStack(spacing: Theme.Spacing.m) {
            HStack(spacing: Theme.Spacing.m) {
                // Outline, and grey rather than fire-orange: the streak is out.
                // A lit flame beside "paused" would contradict itself.
                Image(systemName: "flame")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .frame(width: iconSize, height: iconSize)
                    .background(Color.primary.opacity(0.06), in: .circle)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Streak paused")
                        .font(.headline)
                    Text("Your \(previousStreak)-day run ended. One puzzle starts the next.")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            // One stop for the fact, so VoiceOver reaches the two actions next
            // rather than reading the icon and two labels on the way.
            .accessibilityElement(children: .combine)

            Button(playLabel) { onPlay() }
                .buttonStyle(.pillTonal)

            Button("Not now") { onDismiss() }
                .font(.subheadline.weight(.semibold))
                .tint(.secondary)
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity)
        .elevatedCard()
    }
}

/// The seven-day row: a filled accent check for completed days, an outlined ring
/// for today, and muted letter chips for the rest.
///
/// Shared by `StreakCard` on Today and the completion scorecard — the dot that
/// fills is the same dot in both places, which is the point of showing it at the
/// moment it fills.
struct WeekRow: View {
    let completedWeekdays: Set<Int>

    @Environment(\.calendar) private var calendar

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            ForEach(orderedWeekdays, id: \.self) { day in
                dayCircle(day)
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
        // Seven circles divide the width they're given rather than each taking a
        // Dynamic-Type-scaled size: at accessibility sizes a fixed metric grew
        // the row past the screen and dragged every card on Today out with it.
        // The glyph still scales, and shrinks to fit once the circle can't.
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .lineLimit(1)
        .minimumScaleFactor(0.5)
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
