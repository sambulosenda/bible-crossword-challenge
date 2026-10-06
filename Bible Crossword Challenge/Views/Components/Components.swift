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
                // Fire-orange, and the week row below is too: the card is one
                // colour story about one thing. The square is the shape of
                // every other icon on Today.
                CollectionCover(
                    symbol: "flame.fill",
                    accent: FeatureTint.streak,
                    isLocked: false,
                    side: iconSize,
                    font: .title2,
                    cornerRadius: 13
                )
                .accessibilityHidden(true)

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

            // At streak 0 there is nothing to protect, and "freeze" is a word
            // the new player hasn't met: say what to do today instead. When a
            // freeze is mentioned, say what it does — this line is its first
            // appearance for most players.
            if savedRecently {
                footnote("A freeze saved your streak", symbol: "snowflake", tint: .cyan)
            } else if current == 0 {
                footnote("Solve today to start your streak", symbol: "flame", tint: .orange)
            } else if freezes > 0 {
                footnote("^[\(freezes) freeze](inflect: true) ready to cover a missed day",
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
        } else if current == 0 {
            label += ". Solve today to start your streak"
        } else if freezes > 0 {
            label += ". \(freezes) streak \(freezes == 1 ? "freeze" : "freezes") available, each covers a missed day"
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
        // Leading, like the count and the label above it — centred, it was
        // the one line on the card hanging off a different edge.
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, Theme.Spacing.xs)
    }
}

// MARK: - Row icon

/// The icon at the head of a list row: the soft-tinted rounded square the pack
/// covers already use, so every icon on Today is the same kind of object.
/// Today used to mix three — filled SF circles on the puzzle rows, tinted
/// discs on Keep going, squares on the packs shelf.
///
/// Each feature has its own tint, the way Settings and Fitness colour theirs:
/// with every glyph in the accent, blue stopped meaning "you can tap this"
/// and the screen read as one colour. Blue now belongs to actions and the
/// daily puzzle.
struct RowIcon: View {
    let symbol: String
    let tint: Color

    var body: some View {
        CollectionCover(
            symbol: symbol,
            accent: tint,
            isLocked: false,
            side: 44,
            font: .title3,
            cornerRadius: 12
        )
        // The square is a fixed 44pt, so the glyph stops growing where the
        // square does instead of spilling out of it.
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .accessibilityHidden(true)
    }
}

/// Feature tints for `RowIcon`. One place, so a feature is the same colour
/// wherever it's listed.
enum FeatureTint {
    static let daily = Theme.accent
    static let mini = Color.teal
    static let sunday = Color.orange
    static let journey = Color.green
    // Indigo, not purple: the iOS 26 system purple renders near-magenta
    // and shouted beside the muted pack covers on the shelf below.
    static let memory = Color.indigo
    static let badge = Theme.badgeRim
    /// The flame, and the week row that fills under it.
    static let streak = Color.orange
    static let readingPlan = Color.brown
    /// Done, as everywhere in the app.
    static let solved = Color.green
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
                // A lit flame beside "paused" would contradict itself. The
                // cover's locked treatment is exactly that grey square.
                CollectionCover(
                    symbol: "flame",
                    accent: FeatureTint.streak,
                    isLocked: true,
                    side: iconSize,
                    font: .title2,
                    cornerRadius: 13
                )
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

/// The seven-day row: a filled orange check for completed days, an outlined ring
/// for today, a muted circle for the rest, and every day's letter underneath.
/// Orange, the streak's colour, since 2026-10-04 — in the accent it was the
/// largest block of blue on Today, and blue is kept for actions.
///
/// Shared by `StreakCard` on Today and the completion scorecard — the dot that
/// fills is the same dot in both places, which is the point of showing it at the
/// moment it fills.
struct WeekRow: View {
    /// `.circles` is the lettered row for Home; `.dots` is the quiet 10pt
    /// version for a card that has a headline of its own above it.
    enum Style { case circles, dots }

    let completedWeekdays: Set<Int>
    var style: Style = .circles

    @Environment(\.calendar) private var calendar

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            ForEach(orderedWeekdays, id: \.self) { day in
                switch style {
                case .circles: dayCircle(day)
                case .dots: dot(day)
                }
            }
        }
        // Decorative recap — the card's combined label already summarises it.
        .accessibilityHidden(true)
    }

    private func dot(_ day: Int) -> some View {
        let done = completedWeekdays.contains(day)
        let isToday = day == today
        return Circle()
            .fill(done ? FeatureTint.streak : Color.primary.opacity(0.1))
            .overlay {
                if isToday && !done {
                    Circle().strokeBorder(FeatureTint.streak, lineWidth: 1.5)
                }
            }
            .frame(width: 10, height: 10)
    }

    private var orderedWeekdays: [Int] {
        let first = calendar.firstWeekday
        return (0..<7).map { ((first - 1 + $0) % 7) + 1 }
    }

    private var today: Int { calendar.component(.weekday, from: Date()) }

    @ViewBuilder
    private func dayCircle(_ day: Int) -> some View {
        let done = completedWeekdays.contains(day)
        let isToday = day == today

        VStack(spacing: Theme.Spacing.xs + 2) {
            ZStack {
                if done {
                    Circle().fill(FeatureTint.streak)
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        // The circle stops at 32pt, so the check does too.
                        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                        .foregroundStyle(.white)
                } else {
                    Circle().fill(Color.primary.opacity(0.06))
                    if isToday {
                        Circle().strokeBorder(FeatureTint.streak, lineWidth: 1.5)
                    }
                }
            }
            // 32pt, fixed. A seventh of the card was ~50pt a circle, and the
            // row of seven outweighed the streak count it sits under. Not
            // scaled with Dynamic Type — a scaled metric once grew the row
            // past the screen at accessibility sizes and dragged every card
            // on Today with it; seven of these and their gaps come to 272pt,
            // inside the narrowest card (375pt phone). Not a flexible frame
            // either: with an aspect ratio, today's column resolved taller
            // than the rest and its letter sat low.
            .frame(width: 32, height: 32)

            // The letter sits under the circle, not in it, so a finished day
            // keeps its name — with the check inside, a week of checks was a
            // row of identical dots and only the unfinished days were labelled.
            Text(letter(for: day))
                .font(.caption.weight(isToday ? .bold : .medium))
                .foregroundStyle(isToday ? .primary : .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
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
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Text(difficulty.label)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, Theme.Spacing.s)
            .padding(.vertical, 4)
            // The capsule firms up under increased contrast too. A tint at 0.18
            // is a whisper of a shape, and the setting is asking for the shape.
            .background(difficulty.tint.opacity(contrast == .increased ? 0.28 : 0.18), in: .capsule)
            .foregroundStyle(textColor)
    }

    /// The bright system tints fail WCAG contrast on the faint tinted capsule in
    /// light mode, so use a darker same-hue shade there.
    ///
    /// Dark mode reads fine on the system tint, and that tint already carries
    /// its own increased-contrast variant, so dark needs nothing here. Light is
    /// hand-mixed and therefore has to mix its own darker step as well.
    private var textColor: Color {
        guard scheme == .light else { return difficulty.tint }
        let high = contrast == .increased
        switch difficulty {
        case .easy:   return high ? Color(red: 0.04, green: 0.31, blue: 0.11)
                                  : Color(red: 0.10, green: 0.42, blue: 0.18)
        case .medium: return high ? Color(red: 0.42, green: 0.22, blue: 0.0)
                                  : Color(red: 0.55, green: 0.31, blue: 0.0)
        case .hard:   return high ? Color(red: 0.33, green: 0.10, blue: 0.52)
                                  : Color(red: 0.45, green: 0.18, blue: 0.66)
        }
    }
}

// MARK: - Title revealed on scroll

/// For a detail screen whose header card already names it: the bar shows the
/// title only once that header has scrolled up under it — the App Store's
/// detail-page pattern — rather than saying the name twice on arrival.
/// `navigationTitle` stays set underneath, so the back button on any screen
/// pushed from here still reads the name.
private struct RevealedTitle: ViewModifier {
    let title: String
    let isRevealed: Bool

    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItem(placement: .principal) {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                    .opacity(isRevealed ? 1 : 0)
                    .animation(.easeOut(duration: 0.15), value: isRevealed)
                    .accessibilityHidden(!isRevealed)
            }
        }
    }
}

extension View {
    func revealedTitle(_ title: String, when isRevealed: Bool) -> some View {
        modifier(RevealedTitle(title: title, isRevealed: isRevealed))
    }

    /// Reports whether this view has (nearly) scrolled up under the navigation
    /// bar. The bar ends a little under 120pt in window space on current
    /// iPhones; 150 trips once only the header's last strip is left, by which
    /// point the name it carries is long gone — at 120 a short page could
    /// never scroll far enough to hand the name to the bar.
    func onScrolledUnderBar(_ action: @escaping (Bool) -> Void) -> some View {
        onGeometryChange(for: Bool.self) { proxy in
            proxy.frame(in: .global).maxY < 150
        } action: { action($0) }
    }
}
