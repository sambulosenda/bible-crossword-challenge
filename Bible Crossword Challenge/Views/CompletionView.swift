//
//  CompletionView.swift
//  Bible Crossword Challenge
//
//  Shown when a puzzle is solved: time, streak, the day's verse, any new
//  achievements, plus Share and Home actions.
//

import SwiftUI

struct CompletionView: View {
    let puzzle: Puzzle
    let seconds: Int
    let streak: Int
    let newAchievements: [Achievement]
    let onHome: () -> Void

    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shareText: String {
        """
        I just completed “\(puzzle.title)” in Bible Crossword Challenge! \
        🔥 \(streak)-day streak.

        “\(puzzle.verse)” — \(puzzle.reference)
        """
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.l) {
                header

                statRow

                verseCard

                if !newAchievements.isEmpty {
                    achievementsCard
                }

                actions
            }
            .padding(Theme.Spacing.l)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemGroupedBackground))
        .onAppear {
            if reduceMotion {
                appeared = true
            } else {
                withAnimation(.spring(duration: 0.5)) { appeared = true }
            }
        }
    }

    private var header: some View {
        VStack(spacing: Theme.Spacing.m) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 72))
                .foregroundStyle(.green)
                .symbolEffect(.bounce, value: reduceMotion ? false : appeared)
                .scaleEffect(reduceMotion ? 1 : (appeared ? 1 : 0.5))

            Text("Puzzle Completed!")
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
        }
        .padding(.top, Theme.Spacing.xl)
    }

    private var statRow: some View {
        HStack(spacing: Theme.Spacing.m) {
            stat(title: "Time", value: TimeFormat.clock(seconds), symbol: "timer")
            stat(title: "Streak", value: "\(streak)", symbol: "flame.fill")
        }
    }

    private func stat(title: String, value: String, symbol: String) -> some View {
        VStack(spacing: Theme.Spacing.xs) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(Theme.accent)
            Text(value)
                .font(.title2.bold())
                .monospacedDigit()
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.Spacing.m)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: Theme.cornerRadius))
    }

    private var verseCard: some View {
        VStack(spacing: Theme.Spacing.s) {
            Text("Today's Verse")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("“\(puzzle.verse)”")
                .font(.title3)
                .italic()
                .multilineTextAlignment(.center)
            Text(puzzle.reference)
                .font(.headline)
                .foregroundStyle(Theme.accent)
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: Theme.cornerRadius))
    }

    private var achievementsCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text("New Achievement\(newAchievements.count > 1 ? "s" : "")!")
                .font(.headline)
            ForEach(newAchievements) { achievement in
                Label {
                    VStack(alignment: .leading) {
                        Text(achievement.title).font(.subheadline.weight(.semibold))
                        Text(achievement.detail).font(.caption).foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: achievement.symbol)
                        .foregroundStyle(.yellow)
                }
            }
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: Theme.cornerRadius))
    }

    private var actions: some View {
        VStack(spacing: Theme.Spacing.m) {
            ShareLink(item: shareText) {
                Label("Share", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button {
                onHome()
            } label: {
                Text("Home")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
        .padding(.top, Theme.Spacing.s)
    }
}
