//
//  CompletionView.swift
//  Bible Crossword Challenge
//
//  Shown when a puzzle is solved: time, streak, the day's verse, any new
//  achievements, plus Share and Home actions.
//

import SwiftUI
import StoreKit
import Lottie

struct CompletionView: View {
    let puzzle: Puzzle
    let seconds: Int
    let streak: Int
    let newAchievements: [Achievement]
    var earnedFreeze: Bool = false
    var totalCompleted: Int = 0
    let onHome: () -> Void

    @State private var shareImage: Image?
    @State private var showPaywall = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale
    @Environment(\.gameCenter) private var gameCenter
    @Environment(\.requestReview) private var requestReview
    @Environment(\.puzzleProvider) private var puzzleProvider
    @Environment(\.readerRouter) private var readerRouter
    @Environment(\.analytics) private var analytics
    @Environment(StoreService.self) private var store
    /// Highest completion milestone we've already asked a review at, so each
    /// milestone prompts at most once across sessions.
    @AppStorage("reviewPromptMilestone") private var reviewPromptMilestone = 0

    private var shareCaption: String {
        var text = "I solved “\(puzzle.title)” in \(TimeFormat.clock(seconds)) — \(streak)-day streak 🔥"
        let grid = ShareGrid.emoji(for: puzzle)
        if !grid.isEmpty { text += "\n\n\(grid)" }
        if let url = ShareConfig.storeURL { text += "\n\n\(url.absoluteString)" }
        return text
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.l) {
                header

                verseCard

                if earnedFreeze {
                    freezeCard
                }

                if !newAchievements.isEmpty {
                    achievementsCard
                }

                if puzzle.isMini && !store.isPremium && pastMiniCount > 0 {
                    miniUpsellCard
                }

                nextPuzzleFooter
            }
            .padding(Theme.Spacing.l)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemGroupedBackground))
        .safeAreaInset(edge: .bottom) {
            actions
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.vertical, Theme.Spacing.s)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
                .background(.bar)
        }
        .onAppear {
            renderShareCard()
            maybeRequestReview()
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
    }

    // MARK: - Mini upsell

    /// Every mini in the bank except today's — the library Premium unlocks.
    private var pastMiniCount: Int { max(0, puzzleProvider.minis.count - 1) }

    /// The post-win ask: shown only to free users right after a Mini solve,
    /// when the appetite for "one more" is highest. A single quiet card — the
    /// celebration stays the hero.
    private var miniUpsellCard: some View {
        Button {
            analytics.log(.paywallOpened(source: "mini_completion"))
            showPaywall = true
        } label: {
            HStack(spacing: Theme.Spacing.m) {
                Image(systemName: "bolt.circle.fill")
                    .font(.title)
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Enjoyed that?")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("\(pastMiniCount) more Minis are waiting in Premium.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(Theme.Spacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.accent.opacity(0.10), in: .rect(cornerRadius: Theme.cornerRadius, style: .continuous))
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Enjoyed that? \(pastMiniCount) more Minis are waiting in Premium.")
        .accessibilityHint("Opens Premium upgrade options")
    }

    private var header: some View {
        VStack(spacing: Theme.Spacing.m) {
            celebration

            Text("Puzzle Completed!")
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)

            statLine
        }
        .padding(.top, Theme.Spacing.m)
    }

    /// Celebratory completion mark. Plays the branded Lottie burst once;
    /// falls back to the static seal when Reduce Motion is on.
    ///
    /// The badge fills only ~30% of the Lottie canvas (the rest is room for
    /// the confetti burst), so the animation renders in an oversized overlay
    /// while the layout box stays a fixed 120pt — confetti overflows
    /// decoratively without inflating the header.
    @ViewBuilder private var celebration: some View {
        if reduceMotion {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
                .frame(height: 120)
        } else {
            Color.clear
                .frame(width: 120, height: 120)
                .overlay {
                    LottieView(animation: .named("puzzle_complete"))
                        .configure { $0.contentMode = .scaleAspectFit }
                        .playing(loopMode: .playOnce)
                        .frame(width: 300, height: 300)
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    /// Time and streak inline under the title — two small numbers don't
    /// warrant cards of their own.
    private var statLine: some View {
        HStack(spacing: Theme.Spacing.s) {
            Label {
                Text(TimeFormat.clock(seconds)).monospacedDigit()
            } icon: {
                Image(systemName: "timer")
            }

            if streak > 0 {
                Text("·")
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)

                Label {
                    Text("\(streak)-day streak")
                } icon: {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(.orange)
                }
            }
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.secondary)
    }

    /// Snowflake mark for the streak-freeze card.
    @ViewBuilder private var freezeMark: some View {
        if reduceMotion {
            Image(systemName: "snowflake")
                .font(.title2)
                .foregroundStyle(.cyan)
        } else {
            LottieView(animation: .named("streak_freeze"))
                .configure { $0.contentMode = .scaleAspectFit }
                .playing(loopMode: .playOnce)
                .frame(width: 72, height: 72)
                .accessibilityHidden(true)
        }
    }

    /// Star-burst mark crowning the new-achievements card.
    @ViewBuilder private var achievementMark: some View {
        if reduceMotion {
            Image(systemName: "star.fill")
                .font(.system(size: 44))
                .foregroundStyle(.yellow)
        } else {
            LottieView(animation: .named("achievement_unlock"))
                .configure { $0.contentMode = .scaleAspectFit }
                .playing(loopMode: .playOnce)
                .frame(width: 112, height: 112)
                .accessibilityHidden(true)
        }
    }

    /// The verse is the emotional payoff of the solve — the one card that gets
    /// special treatment (accent wash) while everything else recedes.
    private var verseCard: some View {
        VStack(spacing: Theme.Spacing.s) {
            Text("Today's Verse")
                .kicker()
            Text("“\(puzzle.verse)”")
                .font(.title3)
                .italic()
                .multilineTextAlignment(.center)
            Text(puzzle.reference)
                .font(.headline)
                .foregroundStyle(Theme.accent)

            Button {
                readerRouter.open(reference: puzzle.reference)
                onHome()
            } label: {
                Label("Read the passage", systemImage: "book")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .tint(Theme.accent)
            .padding(.top, Theme.Spacing.xs)
            .accessibilityHint("Closes this screen and opens the passage in the reader")
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity)
        .background(Theme.accent.opacity(0.1), in: .rect(cornerRadius: Theme.cornerRadius, style: .continuous))
    }

    private var freezeCard: some View {
        HStack(spacing: Theme.Spacing.m) {
            freezeMark
            VStack(alignment: .leading, spacing: 2) {
                Text("Streak freeze earned!")
                    .font(.subheadline.weight(.semibold))
                Text("It'll cover you if you miss a day.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: Theme.cornerRadius))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Streak freeze earned. It'll cover you if you miss a day.")
    }

    private var achievementsCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            achievementMark
                .frame(maxWidth: .infinity)
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

    /// Tomorrow hook, demoted to a quiet footer line — the streak already
    /// carries the retention message up in the stat line.
    private var nextPuzzleFooter: some View {
        Text("Next puzzle in \(Text(timerInterval: Date()...nextMidnight, countsDown: true).monospacedDigit())")
            .font(.footnote.weight(.medium))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
    }

    private var nextMidnight: Date {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        return calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? startOfToday
    }

    /// Ask for a rating at completion milestones — the happiest moment in the
    /// loop. Each milestone asks at most once; the system further rate-limits.
    private static let reviewMilestones = [3, 10, 30]

    private func maybeRequestReview() {
        guard let milestone = Self.reviewMilestones.last(where: { totalCompleted >= $0 }),
              milestone > reviewPromptMilestone
        else { return }
        reviewPromptMilestone = milestone
        Task {
            // Let the celebration land before the system sheet appears.
            try? await Task.sleep(for: .seconds(2))
            requestReview()
        }
    }

    private var actions: some View {
        VStack(spacing: Theme.Spacing.m) {
            Group {
                if let shareImage {
                    ShareLink(
                        item: shareImage,
                        message: Text(shareCaption),
                        preview: SharePreview("Bible Crossword", image: shareImage)
                    ) { shareLabel }
                } else {
                    // Fallback if image rendering failed.
                    ShareLink(item: shareCaption) { shareLabel }
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            // Minis race the clock against everyone — surface this week's
            // standings while the solve is fresh. Hidden when the player
            // isn't signed in to Game Center.
            if puzzle.isMini && gameCenter.isAuthenticated {
                Button {
                    gameCenter.showWeeklyMiniLeaderboard()
                } label: {
                    Label("Weekly Leaderboard", systemImage: "trophy")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }

            Button {
                onHome()
            } label: {
                Text("Home")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderless)
            .controlSize(.large)
        }
    }

    private var shareLabel: some View {
        Label("Share", systemImage: "square.and.arrow.up")
            .frame(maxWidth: .infinity)
    }

    /// Rasterise the spoiler-free result card so it can be shared as an image.
    /// `ImageRenderer.uiImage` is synchronous, so the image is ready before the
    /// user can reach the Share button.
    private func renderShareCard() {
        let renderer = ImageRenderer(
            content: ShareCardView(
                title: puzzle.title,
                seconds: seconds,
                streak: streak,
                verse: puzzle.verse,
                reference: puzzle.reference
            )
        )
        renderer.scale = displayScale
        if let ui = renderer.uiImage {
            shareImage = Image(uiImage: ui)
        }
    }
}
