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

    @ScaledMetric(relativeTo: .title) private var iconSize = 40
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            metric(value: current, label: "Current Streak", symbol: "flame.fill", tint: .orange)
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(width: 1, height: 48)
            metric(value: best, label: "Best Streak", symbol: "trophy.fill", tint: .yellow)
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.Spacing.l)
        .elevatedCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Current streak \(current) days, best streak \(best) days")
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

    var body: some View {
        Text(difficulty.label)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, Theme.Spacing.s)
            .padding(.vertical, 4)
            .background(difficulty.tint.opacity(0.18), in: .capsule)
            .foregroundStyle(difficulty.tint)
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
