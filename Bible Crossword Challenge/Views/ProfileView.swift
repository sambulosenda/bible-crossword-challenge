//
//  ProfileView.swift
//  Bible Crossword Challenge
//
//  The player: who they are, how they're doing, what they've earned. No
//  authentication in v1 — everything is on device (and in their iCloud).
//
//  Built as a ScrollView of cards rather than a Form: every other tab (Today,
//  Packs, Library) already speaks that language.
//
//  Settings live behind the gear in the toolbar (`SettingsView`), not at the
//  foot of this screen. Until 2026-10 they did: more than a screen down, under
//  the stats and an upsell card, with nothing on screen saying they were
//  there. This tab is visited for the numbers and settings rarely, and making
//  the one longer for the other served neither.
//

import SwiftUI
import SwiftData

struct ProfileView: View {
    @Bindable var profile: PlayerProfile
    /// Presents Settings. RootView owns the sheet so ⌘, can open it from any
    /// tab, not only this one.
    let openSettings: () -> Void

    @Environment(StoreService.self) private var store
    @Environment(\.gameCenter) private var gameCenter
    @Environment(\.challengeHistory) private var challengeHistory
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showRename = false
    @State private var draftName = ""
    @State private var showChallengeHistory = false

    private var unlockedCount: Int {
        Achievements.all.filter { $0.isUnlocked(by: profile) }.count
    }

    var body: some View {
        NavigationStack {
            // Who they are and how they're doing on the left of a wide window;
            // what they've earned and who they've played on the right.
            CardColumns {
                identityCard
                ProfileStatsCard(
                    streak: profile.currentStreak,
                    solved: profile.totalPuzzlesCompleted,
                    bestStreak: profile.bestStreak,
                    bestSolveSeconds: profile.bestSolveSeconds,
                    freezes: profile.streakFreezes
                )
            } more: {
                AchievementsCard(
                    profile: profile,
                    unlocked: unlockedCount,
                    total: Achievements.all.count
                )
                leaderboardCard
                challengesSection
            }
            .background(Theme.background)
            .navigationTitle("Profile")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings", systemImage: "gearshape", action: openSettings)
                }
            }
            .navigationDestination(isPresented: $showChallengeHistory) {
                ChallengeHistoryView(profile: profile)
            }
            .alert(chosenName == nil ? "Add your name" : "Your name", isPresented: $showRename) {
                TextField("Your name", text: $draftName)
                    .textInputAutocapitalization(.words)
                Button("Cancel", role: .cancel) {}
                Button("Save") { commitRename() }
            } message: {
                // Not "only stored on your device": the profile syncs through
                // iCloud, and the name rides in every challenge link.
                Text("Friends see it on the challenges you send.")
            }
        }
    }

    // MARK: - Identity

    /// Avatar, name, and one quiet line of context, in a row — the whole card
    /// is the edit affordance. It was a centred hero with an "Edit name" pill
    /// under it: a quarter of the first screen spent on a name most players
    /// never set, shown back to them as "Friend" with an "F" in the disc.
    private var identityCard: some View {
        Button {
            // Starts empty for a player who never chose one, so they type a
            // name rather than delete the placeholder first.
            draftName = chosenName ?? ""
            showRename = true
        } label: {
            HStack(spacing: Theme.Spacing.m) {
                // Decorative, and at accessibility sizes its width is the
                // width the name needs.
                if !dynamicTypeSize.isAccessibilitySize {
                    Avatar(name: chosenName ?? "")
                }
                VStack(alignment: .leading, spacing: 2) {
                    // Serif, as the app sets every hero title and scripture line.
                    Text(chosenName ?? "Add your name")
                        .font(.scripture(.title2, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(membershipLine)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "pencil")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(Theme.Spacing.m)
            .elevatedCard()
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(chosenName.map { "\($0). \(membershipLine)" } ?? "Add your name")
        .accessibilityHint(chosenName == nil ? "Friends see it on the challenges you send" : "Edits your name")
        .accessibilityAddTraits(.isButton)
    }

    /// The name the player chose, or nil while it is still the placeholder
    /// onboarding and the challenge prompt fall back to.
    private var chosenName: String? {
        let trimmed = profile.username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != ChallengeService.placeholderName else { return nil }
        return trimmed
    }

    /// Premium status when there is some, otherwise how long they've been here.
    /// Both come from data already on the profile — no new persistence.
    private var membershipLine: String {
        if store.isPremium { return "Premium member" }
        return "Playing since \(profile.createdAt.formatted(.dateTime.month(.wide).year()))"
    }

    private func commitRename() {
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // The challenge prompt's cap: the name rides in challenge links and on
        // family boards, and only this door let a longer one through.
        profile.username = String(trimmed.prefix(20))
    }

    // MARK: - Leaderboard

    /// The standing way back to this week's Mini leaderboard — the only other
    /// entry point is the post-solve completion screen. A card beside
    /// Achievements, since a leaderboard is about how the player is doing.
    ///
    /// Hidden when the player isn't signed in to Game Center.
    @ViewBuilder
    private var leaderboardCard: some View {
        if gameCenter.isAuthenticated {
            Button {
                gameCenter.showWeeklyMiniLeaderboard()
            } label: {
                ProfileLinkLabel(
                    symbol: "list.number",
                    title: "Weekly leaderboard",
                    subtitle: "This week's fastest Mini times"
                )
            }
            .buttonStyle(PressableCardStyle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Weekly leaderboard. This week's fastest Mini times")
            .accessibilityHint("Opens Game Center")
            .accessibilityAddTraits(.isButton)
        }
    }

    // MARK: - Challenges

    /// The friend-challenge ledger, previewed. Hidden until there is something
    /// to show: a "Recent challenges" heading over an empty card advertises a
    /// feature by its absence, and the completion screen is where the invitation
    /// to send one actually belongs.
    @ViewBuilder
    private var challengesSection: some View {
        let recent = Array(challengeHistory.entries.prefix(3))
        if !recent.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Text("Recent challenges").kicker()
                    .padding(.horizontal, Theme.Spacing.xs)

                // Every row leads to the same place — the full list is where
                // replay and rematch live.
                ChallengeHistoryList(entries: recent) { _ in
                    showChallengeHistory = true
                }

                Button {
                    showChallengeHistory = true
                } label: {
                    Text(challengeHistory.entries.count > recent.count
                         ? "See all \(challengeHistory.entries.count)"
                         : "See all")
                        .font(.caption.weight(.semibold))
                        // Bare caption text alone is a ~16pt target; the frame
                        // brings the hit region to the 44pt HIG minimum.
                        .frame(minHeight: 44, alignment: .leading)
                        .contentShape(.rect)
                }
                .padding(.horizontal, Theme.Spacing.xs)
            }
        }
    }
}

// MARK: - Stats

/// One card, two rows. The three headline numbers lead at title size; the two
/// supporting ones sit below a divider at a smaller scale. Previously three were
/// hero stats and the other two were buried as list rows in a separate section,
/// which split one idea across two places. A third supporting stat, badges,
/// went in 2026-10: the Achievements card right below already says it.
///
/// Its own type, taking plain values, rather than a computed property on
/// `ProfileView` — the tiles are the densest thing on the screen, and as a
/// computed property they shared the parent's invalidation boundary and rebuilt
/// every time an unrelated bit of profile state changed (opening a sheet,
/// typing in the rename alert). With only value inputs and no property wrappers
/// SwiftUI can compare the whole view and skip its body outright. `HomeView`'s
/// cards are built the same way and say so.
private struct ProfileStatsCard: View {
    let streak: Int
    let solved: Int
    let bestStreak: Int
    let bestSolveSeconds: Int?
    let freezes: Int

    var body: some View {
        // Three across until a label can't hold its line, then one per line.
        // Columns that merely wrap broke "3:34" over three lines and "Solved"
        // mid-word at the largest text size. `ViewThatFits` measures rather
        // than switching on the type size, so a wide window keeps the columns
        // for as long as they truly fit — and the card stays free of property
        // wrappers (see above).
        ViewThatFits(in: .horizontal) {
            columns
            stacked
        }
        .padding(Theme.Spacing.l)
        .elevatedCard()
    }

    private var columns: some View {
        VStack(spacing: Theme.Spacing.m) {
            HStack(spacing: 0) {
                heroStat(value: "\(streak)", label: "Day Streak", symbol: "flame.fill", tint: .orange)
                heroStat(value: "\(solved)", label: "Solved", symbol: "checkmark.circle.fill", tint: .green)
                heroStat(value: "\(bestStreak)", label: "Best Streak", symbol: "trophy.fill", tint: .yellow)
            }

            Divider()

            HStack(spacing: 0) {
                minorStat(value: bestTimeValue, label: "Best Time", symbol: "stopwatch.fill", tint: Theme.accent)
                minorStat(value: "\(freezes)", label: "Freezes", symbol: "snowflake", tint: .cyan)
            }
        }
    }

    private var stacked: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            stackedStat(value: "\(streak)", label: "Day Streak", symbol: "flame.fill", tint: .orange)
            stackedStat(value: "\(solved)", label: "Solved", symbol: "checkmark.circle.fill", tint: .green)
            stackedStat(value: "\(bestStreak)", label: "Best Streak", symbol: "trophy.fill", tint: .yellow)
            stackedStat(value: bestTimeValue, label: "Best Time", symbol: "stopwatch.fill", tint: Theme.accent)
            stackedStat(value: "\(freezes)", label: "Freezes", symbol: "snowflake", tint: .cyan)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// An em dash until the first solve — "0:00" would read as a real record.
    private var bestTimeValue: String {
        guard let bestSolveSeconds else { return "—" }
        return TimeFormat.clock(bestSolveSeconds)
    }

    private func heroStat(value: String, label: String, symbol: String, tint: Color) -> some View {
        VStack(spacing: Theme.Spacing.xs) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(tint)
            Text(value)
                .font(.title.weight(.bold))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }

    private func minorStat(value: String, label: String, symbol: String, tint: Color) -> some View {
        VStack(spacing: Theme.Spacing.xs) {
            Label {
                Text(value)
                    .font(.subheadline.weight(.bold))
                    .monospacedDigit()
            } icon: {
                Image(systemName: symbol)
                    .font(.caption)
                    .foregroundStyle(tint)
            }
            .labelStyle(.titleAndIcon)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }

    private func stackedStat(value: String, label: String, symbol: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label {
                Text(value)
                    .font(.title2.weight(.bold))
                    .monospacedDigit()
            } icon: {
                Image(systemName: symbol)
                    .foregroundStyle(tint)
            }
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }
}

// MARK: - Achievements

/// The way into the trophy list, in the row the journey card held until 2.8
/// (the map moved to the Read tab). Plain values only, for the same
/// invalidation reason as `ProfileStatsCard`.
private struct AchievementsCard: View {
    let profile: PlayerProfile
    let unlocked: Int
    let total: Int

    var body: some View {
        NavigationLink {
            AchievementsView(profile: profile, source: "profile")
        } label: {
            ProfileLinkLabel(symbol: "trophy.fill", title: "Achievements", subtitle: summary)
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Achievements. \(summary)")
        .accessibilityHint("Opens every badge and its progress")
    }

    private var summary: String {
        guard unlocked > 0 else { return "Solve puzzles to earn your first badge" }
        return "\(unlocked) of \(total) badges earned"
    }
}

/// The face of a card that goes somewhere: glyph, title, one line of
/// context, chevron. Achievements and the leaderboard share it so the two
/// doors read as a pair.
private struct ProfileLinkLabel: View {
    let symbol: String
    let title: LocalizedStringKey
    let subtitle: String

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            // Decorative, and at accessibility sizes the width it takes is the
            // width the title needs — "Achievements" hyphenated at the largest.
            if !dynamicTypeSize.isAccessibilitySize {
                Image(systemName: symbol)
                    .font(.title)
                    .foregroundStyle(Theme.accent)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.forward")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .elevatedCard()
    }
}

// MARK: - Avatar

/// The player's initial on an accent disc. A generic SF person glyph said
/// nothing about whose profile this is; the initial makes it theirs, and falls
/// back to the glyph only when there's no name to draw from.
private struct Avatar: View {
    let name: String

    @ScaledMetric(relativeTo: .title) private var size: CGFloat = 56

    private var initial: String? {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .first
            .map { String($0).uppercased() }
    }

    var body: some View {
        ZStack {
            Circle().fill(Theme.accent.opacity(0.14))
            if let initial {
                Text(initial)
                    .font(.scripture(.title, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            } else {
                Image(systemName: "person.fill")
                    .font(.title2)
                    .foregroundStyle(Theme.accent)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
