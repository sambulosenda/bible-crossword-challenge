//
//  HomeView.swift
//  Bible Crossword Challenge
//
//  The "Today" tab: greeting, streak summary, the daily puzzle card, and a
//  banner placeholder for free users.
//

import SwiftUI
import SwiftData

struct HomeView: View {
    let profile: PlayerProfile

    @Environment(\.puzzleProvider) private var puzzleProvider
    @Environment(\.ads) private var ads
    @Environment(StoreService.self) private var store
    @Query private var records: [PuzzleRecord]

    private var dailyPuzzle: Puzzle? { puzzleProvider.dailyPuzzle() }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.l) {
                    StreakCard(current: profile.currentStreak, best: profile.bestStreak)

                    if let puzzle = dailyPuzzle {
                        dailyCard(puzzle)
                    } else {
                        ContentUnavailableView(
                            "No puzzle available",
                            systemImage: "puzzlepiece",
                            description: Text("Check back soon for today's puzzle.")
                        )
                        .padding(.top, Theme.Spacing.xl)
                    }

                    if let verse = verseOfTheDay {
                        verseCard(verse)
                    }

                    nextAchievementCard

                    if !store.isPremium {
                        upgradeCard
                    }
                }
                .padding(Theme.Spacing.m)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(greeting)
            .navigationDestination(for: Puzzle.self) { puzzle in
                CrosswordGameView(puzzle: puzzle, profile: profile)
            }
            .safeAreaInset(edge: .bottom) {
                if !store.isPremium && ads.isLive {
                    BannerAdView()
                }
            }
        }
    }

    // MARK: - Daily card

    private func dailyCard(_ puzzle: Puzzle) -> some View {
        let record = records.first { $0.puzzleID == puzzle.id }
        let status = PuzzleStatus(record: record)

        return VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack {
                Label("Daily Puzzle", systemImage: "calendar")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                DifficultyBadge(difficulty: puzzle.difficulty)
            }

            Text(puzzle.title)
                .font(.title2.bold())

            HStack(spacing: Theme.Spacing.m) {
                Label("\(puzzle.clueCount) clues", systemImage: "list.bullet")
                Label("\(puzzle.size)×\(puzzle.size)", systemImage: "square.grid.3x3")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            if status == .completed {
                completedFooter(puzzle)
            }

            NavigationLink(value: puzzle) {
                Label(status.actionTitle, systemImage: status.actionSymbol)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.top, Theme.Spacing.xs)
        }
        .padding(Theme.Spacing.l)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: Theme.cornerRadius))
    }

    private func completedFooter(_ puzzle: Puzzle) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Label("Completed", systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.green)
            Text("“\(puzzle.verse)”")
                .font(.callout).italic()
            Text(puzzle.reference)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.accent)
        }
        .padding(Theme.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.green.opacity(0.1), in: .rect(cornerRadius: Theme.cornerRadius - 4))
    }

    private var upgradeCard: some View {
        NavigationLink {
            PaywallView()
        } label: {
            HStack(spacing: Theme.Spacing.m) {
                Image(systemName: "crown.fill")
                    .font(.title2)
                    .foregroundStyle(.yellow)
                VStack(alignment: .leading) {
                    Text("Go Premium")
                        .font(.headline)
                    Text("Remove ads · Unlimited hints · Puzzle archive")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
            .padding(Theme.Spacing.l)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: Theme.cornerRadius))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Verse of the day

    /// A daily inspirational verse, rotated deterministically and chosen from a
    /// puzzle other than today's so it never spoils the daily answer.
    private var verseOfTheDay: Puzzle? {
        let pool = puzzleProvider.puzzles.filter { $0.id != dailyPuzzle?.id }
        guard !pool.isEmpty else { return nil }
        let day = Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0
        return pool[((day % pool.count) + pool.count) % pool.count]
    }

    private func verseCard(_ puzzle: Puzzle) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Label("Verse of the Day", systemImage: "book.closed")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("“\(puzzle.verse)”")
                .font(.title3)
                .italic()
            Text(puzzle.reference)
                .font(.headline)
                .foregroundStyle(Theme.accent)
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: Theme.cornerRadius))
    }

    // MARK: - Next achievement

    @ViewBuilder
    private var nextAchievementCard: some View {
        if let next = Achievements.all.first(where: { !$0.isUnlocked(by: profile) }) {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                Label("Next Achievement", systemImage: "target")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                HStack(spacing: Theme.Spacing.m) {
                    Image(systemName: next.symbol)
                        .font(.title)
                        .frame(width: 48, height: 48)
                        .background(Color(.tertiarySystemFill), in: .circle)
                        .foregroundStyle(Theme.accent)
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text(next.title).font(.headline)
                        Text(next.detail).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Text(next.progressText(for: profile))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: next.progress(for: profile))
                    .tint(Theme.accent)
            }
            .padding(Theme.Spacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: Theme.cornerRadius))
        } else {
            Label("All achievements unlocked!", systemImage: "star.circle.fill")
                .font(.headline)
                .foregroundStyle(.yellow)
                .frame(maxWidth: .infinity)
                .padding(Theme.Spacing.l)
                .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: Theme.cornerRadius))
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good Morning"
        case 12..<17: return "Good Afternoon"
        default: return "Good Evening"
        }
    }
}
