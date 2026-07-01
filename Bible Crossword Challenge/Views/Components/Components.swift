//
//  Components.swift
//  Bible Crossword Challenge
//
//  Small reusable views shared across screens.
//

import SwiftUI

// MARK: - Streak summary

struct StreakCard: View {
    let current: Int
    let best: Int
    var freezes: Int = 0
    /// True when a freeze was spent today, to surface a one-time reassurance.
    var savedRecently: Bool = false

    @ScaledMetric(relativeTo: .title) private var iconSize = 40
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme

    /// System yellow washes out against the faint tinted circle in light mode,
    /// so use a deeper gold there. Dark mode reads fine.
    private var trophyTint: Color {
        scheme == .light ? Color(red: 0.72, green: 0.52, blue: 0.0) : .yellow
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.m) {
            HStack(spacing: 0) {
                metric(value: current, label: "Current Streak", symbol: "flame.fill", tint: .orange)
                Rectangle()
                    .fill(Color.primary.opacity(0.08))
                    .frame(width: 1, height: 48)
                metric(value: best, label: "Best Streak", symbol: "trophy.fill", tint: trophyTint)
            }

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

    private func metric(value: Int, label: String, symbol: String, tint: Color) -> some View {
        VStack(spacing: Theme.Spacing.s) {
            Image(systemName: symbol)
                .font(.headline)
                .foregroundStyle(tint)
                .frame(width: iconSize, height: iconSize)
                .background(tint.opacity(0.15), in: .circle)
            Text("\(value)")
                .font(.title.weight(.bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(reduceMotion ? .identity : .numericText())
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
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
