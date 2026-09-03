//
//  AchievementsView.swift
//  Bible Crossword Challenge
//
//  The trophy list. A pushed screen since 2.8, reached from Profile's
//  achievements card and Today's next-achievement card; it held a tab of its
//  own before that, while the reader, memory verses and the journey map had
//  no front door at all (see `ReadView`).
//

import SwiftUI

struct AchievementsView: View {
    let profile: PlayerProfile
    /// Which surface pushed it — `profile` or `home_card`.
    var source: String = "profile"

    @Environment(\.analytics) private var analytics

    var body: some View {
        ScrollView {
            LazyVStack(spacing: Theme.Spacing.m) {
                ForEach(Achievements.all) { achievement in
                    row(achievement)
                }
            }
            .padding(Theme.Spacing.m)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background)
        .navigationTitle("Achievements")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { analytics.log(.achievementsOpened(source: source)) }
    }

    private func row(_ achievement: Achievement) -> some View {
        let unlocked = achievement.isUnlocked(by: profile)
        let progress = achievement.progress(for: profile)

        return HStack(spacing: Theme.Spacing.m) {
            Image(systemName: achievement.symbol)
                .font(.title)
                .frame(width: 52, height: 52)
                .background(unlocked ? Color.yellow.opacity(0.2) : Color(.tertiarySystemFill), in: .circle)
                .foregroundStyle(unlocked ? .yellow : .secondary)

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(achievement.title)
                    .font(.headline)
                Text(achievement.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if !unlocked {
                    ProgressView(value: progress)
                        .tint(Theme.accent)
                }
            }

            Spacer(minLength: 0)

            if unlocked {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                    .font(.title3)
            } else {
                Text(achievement.progressText(for: profile))
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .padding(Theme.Spacing.l)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: Theme.cornerRadius))
        .opacity(unlocked ? 1 : 0.9)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(achievement.title), \(achievement.detail), \(unlocked ? "unlocked" : "\(Int(progress * 100)) percent")")
    }
}
