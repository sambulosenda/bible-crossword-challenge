//
//  ProfileView.swift
//  Bible Crossword Challenge
//
//  The player: who they are, how they're doing, what they've earned. No
//  authentication in v1 — everything is on device (and in their iCloud).
//
//  A native inset-grouped List on the warm paper since 2026-10-13, like Packs:
//  the hand-built cards looked like iOS without behaving like it.
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
            List {
                Section {
                    identityRow
                    ProfileStatsRow(
                        solved: profile.totalPuzzlesCompleted,
                        streak: profile.currentStreak,
                        bestStreak: profile.bestStreak,
                        bestSolveSeconds: profile.bestSolveSeconds
                    )
                }

                Section {
                    NavigationLink {
                        AchievementsView(profile: profile, source: "profile")
                    } label: {
                        ProfileLinkLabel(symbol: "trophy", title: "Achievements", subtitle: achievementsSummary)
                    }
                    .accessibilityHint("Opens every badge and its progress")
                    leaderboardRow
                } header: {
                    Text("Progress")
                }
                .headerProminence(.increased)

                challengesSection
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
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

    /// Avatar, name and one quiet line, as the account row at the top of
    /// Settings. The name is body weight; with none set, "Add your name" is
    /// the accent — an action, not a headline in the scripture serif.
    private var identityRow: some View {
        Button {
            // Starts empty for a player who never chose one, so they type a
            // name rather than delete the placeholder first.
            draftName = chosenName ?? ""
            showRename = true
        } label: {
            HStack(spacing: Theme.Spacing.m) {
                if !dynamicTypeSize.isAccessibilitySize {
                    Avatar(name: chosenName ?? "")
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(chosenName ?? "Add your name")
                        .font(.headline)
                        .foregroundStyle(chosenName == nil ? Theme.accent : Color.primary)
                    Text(membershipLine)
                        .font(.subheadline)
                        // Concrete: in a list button `.secondary` takes the tint.
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, Theme.Spacing.xs)
            .contentShape(.rect)
        }
        // The list's own style, for the system tap highlight.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(chosenName.map { "\($0). \(membershipLine)" } ?? "Add your name")
        .accessibilityHint(chosenName == nil ? "Friends see it on the challenges you send" : "Edits your name")
        .accessibilityAddTraits(.isButton)
    }

    private var achievementsSummary: String {
        guard unlockedCount > 0 else { return "Solve puzzles to earn your first badge" }
        return "\(unlockedCount) of \(Achievements.all.count) badges earned"
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
    private var leaderboardRow: some View {
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
            .accessibilityHint("Opens Game Center")
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
            Section {
                // Every row leads to the same place — the full list is where
                // replay and rematch live.
                ForEach(recent) { entry in
                    Button {
                        showChallengeHistory = true
                    } label: {
                        ChallengeHistoryRow(entry: entry)
                    }
                    .buttonStyle(.plain)
                    // The row carries a card's 16pt padding of its own; the
                    // list already insets it, so it gives the margin back.
                    .listRowInsets(EdgeInsets(top: 0, leading: Theme.Spacing.xs, bottom: 0, trailing: Theme.Spacing.xs))
                }
                Button(challengeHistory.entries.count > recent.count
                       ? "See all \(challengeHistory.entries.count)"
                       : "See all") {
                    showChallengeHistory = true
                }
            } header: {
                Text("Challenges")
            }
            .headerProminence(.increased)
        }
    }
}

// MARK: - Stats

/// Four numbers of one size in one row — ink values, grey labels, no icons.
/// It was five stats in two sizes with five tints; the day streak also lives in
/// Today's bar and freezes in its streak sheet, so the row keeps the records.
/// Plain values only, so SwiftUI can skip it when unrelated state changes.
private struct ProfileStatsRow: View {
    let solved: Int
    let streak: Int
    let bestStreak: Int
    let bestSolveSeconds: Int?

    var body: some View {
        // Four across until a label can't hold its line, then two by two.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 0) { stats }
            Grid(alignment: .leading, horizontalSpacing: Theme.Spacing.m, verticalSpacing: Theme.Spacing.m) {
                GridRow {
                    stat("\(solved)", "Solved")
                    stat("\(streak)", "Streak")
                }
                GridRow {
                    stat("\(bestStreak)", "Best streak")
                    stat(bestTimeValue, "Best time")
                }
            }
        }
        .padding(.vertical, Theme.Spacing.s)
    }

    @ViewBuilder
    private var stats: some View {
        stat("\(solved)", "Solved")
        stat("\(streak)", "Streak")
        stat("\(bestStreak)", "Best streak")
        stat(bestTimeValue, "Best time")
    }

    /// An em dash until a real time — "0:00" would read as a record.
    private var bestTimeValue: String {
        guard let bestSolveSeconds, bestSolveSeconds > 0 else { return "—" }
        return TimeFormat.clock(bestSolveSeconds)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title2.weight(.semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }
}

/// A row that goes somewhere: grey glyph, title, one line of context. The
/// list draws the chevron for links; the leaderboard (a button) gets none.
private struct ProfileLinkLabel: View {
    let symbol: String
    let title: LocalizedStringKey
    let subtitle: String

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            if !dynamicTypeSize.isAccessibilitySize {
                Image(systemName: symbol)
                    .font(.body)
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
                    .frame(width: 28)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body).foregroundStyle(Color.primary)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
            }
            Spacer(minLength: 0)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Avatar

/// The player's initial on an accent disc. A generic SF person glyph said
/// nothing about whose profile this is; the initial makes it theirs, and falls
/// back to the glyph only when there's no name to draw from.
private struct Avatar: View {
    let name: String

    @ScaledMetric(relativeTo: .title) private var size: CGFloat = 52

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
