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

    var body: some View {
        HStack(spacing: Theme.Spacing.l) {
            metric(value: current, label: "Current", symbol: "flame.fill", tint: .orange)
            Divider().frame(height: 44)
            metric(value: best, label: "Best", symbol: "trophy.fill", tint: .yellow)
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.Spacing.l)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: Theme.cornerRadius))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Current streak \(current) days, best streak \(best) days")
    }

    private func metric(value: Int, label: String, symbol: String, tint: Color) -> some View {
        VStack(spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: symbol).foregroundStyle(tint)
                Text("\(value)")
                    .font(.title.bold())
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            Text(label)
                .font(.caption)
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
