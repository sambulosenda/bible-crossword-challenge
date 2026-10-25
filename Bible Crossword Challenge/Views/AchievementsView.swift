//
//  AchievementsView.swift
//  Bible Crossword Challenge
//
//  The badges. A pushed screen since 2.8, reached from Profile's Badges row
//  and Today's next-badge row; it held a tab of its own before that, while
//  the reader, memory verses and the journey map had no front door at all
//  (see `ReadView`).
//
//  Three groups since 2026-10-24 (design canvas): what you've earned, as gold
//  medallions; the one badge the next puzzles count toward; and the rest,
//  quietly. It was fourteen identical cards, earned and locked alike, each
//  with a bar — on day one fourteen empty bars, read as homework.
//

import SwiftUI

struct AchievementsView: View {
    let profile: PlayerProfile
    /// Which surface pushed it — `profile` or `home_card`.
    var source: String = "profile"

    @Environment(\.analytics) private var analytics

    private var earned: [Achievement] {
        Achievements.all.filter { $0.isUnlocked(by: profile) }
    }

    /// The badge Today's row names when one is within reach, so the two
    /// agree; otherwise the first not yet earned, in the list's own order.
    private var next: Achievement? {
        Achievements.next(for: profile)
    }

    private var stillToEarn: [Achievement] {
        Achievements.all.filter { !$0.isUnlocked(by: profile) && $0.id != next?.id }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if !earned.isEmpty {
                    earnedSection
                }
                if let next {
                    nextSection(next)
                }
                if !stillToEarn.isEmpty {
                    lockedSection
                }
            }
            .padding(.horizontal, Theme.Spacing.m + Theme.Spacing.xs)
            .padding(.top, Theme.Spacing.s + Theme.Spacing.xs)
            .padding(.bottom, Theme.Spacing.xl)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background)
        .navigationTitle("Badges")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { analytics.log(.achievementsOpened(source: source)) }
    }

    // MARK: - Earned

    private var earnedSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Earned").sectionHeader()
                Spacer(minLength: Theme.Spacing.s)
                Text("\(earned.count) of \(Achievements.all.count)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.s), count: 3),
                spacing: 18
            ) {
                ForEach(earned) { badge in
                    medallion(badge)
                }
            }
        }
    }

    /// An earned badge: its symbol in gold on a gold-rimmed disc, the name
    /// under it. No date — the profile records which badges are earned, not
    /// when.
    private func medallion(_ badge: Achievement) -> some View {
        VStack(spacing: Theme.Spacing.s) {
            Image(systemName: badge.symbol)
                .font(.title2)
                .foregroundStyle(Theme.badgeInk)
                .frame(width: 72, height: 72)
                .background(Theme.premiumWash, in: .circle)
                .overlay(Circle().strokeBorder(Theme.badgeRim, lineWidth: 2.5))
                .shadow(color: Theme.badgeRim.opacity(0.22), radius: 6, y: 4)
            Text(badge.title)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(badge.title), earned. \(badge.detail)")
    }

    // MARK: - Next up

    private func nextSection(_ badge: Achievement) -> some View {
        let fraction = badge.progress(for: profile)
        return VStack(alignment: .leading, spacing: Theme.Spacing.s + 2) {
            Text("Next up").sectionHeader()
            HStack(spacing: Theme.Spacing.m) {
                Image(systemName: badge.symbol)
                    .font(.title3)
                    .foregroundStyle(Theme.badgeInk)
                    .frame(width: 52, height: 52)
                    .background(Theme.premiumWash.opacity(0.6), in: .circle)
                    .overlay(Circle().strokeBorder(Theme.badgeRim.opacity(0.55), lineWidth: 1.5))
                VStack(alignment: .leading, spacing: 2) {
                    Text(badge.title)
                        .font(.headline)
                    Text(badge.detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    // A bar only once there's something on it, and never for a
                    // time goal, which is met or not.
                    if fraction > 0, badge.remaining(for: profile) != nil {
                        ProgressView(value: fraction)
                            .tint(Theme.progressBar)
                            .padding(.top, Theme.Spacing.s + 2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let left = nextTrailing(badge) {
                    Text(left)
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.badgeInk)
                }
            }
            .padding(Theme.Spacing.m + Theme.Spacing.xs)
            .background(Theme.surface, in: .rect(cornerRadius: Theme.cornerRadius, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Next up: \(badge.title). \(badge.detail). \(nextTrailing(badge) ?? "")")
        }
    }

    /// "7 to go", or for a time goal the player's best: a time goal has no
    /// count to close.
    private func nextTrailing(_ badge: Achievement) -> String? {
        if let left = badge.remaining(for: profile) { return "\(left) to go" }
        guard let best = profile.bestSolveSeconds else { return nil }
        return "Best \(TimeFormat.clock(best))"
    }

    // MARK: - Still to earn

    private var lockedSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s + 2) {
            Text("Still to earn").sectionHeader()
            VStack(spacing: 0) {
                ForEach(Array(stillToEarn.enumerated()), id: \.element.id) { index, badge in
                    if index > 0 {
                        Divider().padding(.leading, 70)
                    }
                    lockedRow(badge)
                }
            }
            .background(Theme.surface, in: .rect(cornerRadius: Theme.cornerRadius, style: .continuous))
        }
    }

    /// No bar and no count: the goal is all a badge this far off needs to say.
    private func lockedRow(_ badge: Achievement) -> some View {
        HStack(spacing: 14) {
            Image(systemName: badge.symbol)
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .frame(width: 36, height: 36)
                .background(Color.primary.opacity(0.06), in: .circle)
            VStack(alignment: .leading, spacing: 1) {
                Text(badge.title)
                    .font(.body)
                Text(badge.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, Theme.Spacing.m + Theme.Spacing.xs)
        .padding(.vertical, Theme.Spacing.s + 2)
        .frame(minHeight: 60)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(badge.title), not earned yet. \(badge.detail)")
    }
}
