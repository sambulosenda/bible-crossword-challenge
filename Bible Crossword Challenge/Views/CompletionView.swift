//
//  CompletionView.swift
//  Bible Crossword Challenge
//
//  Shown when a puzzle is solved: time, streak, the day's verse, any new
//  achievements, plus Share and Home actions.
//

import SwiftUI
import SwiftData
import StoreKit

struct CompletionView: View {
    let puzzle: Puzzle
    let profile: PlayerProfile
    let seconds: Int
    let streak: Int
    let newAchievements: [Achievement]
    var earnedFreeze: Bool = false
    /// True when this solve restarted a streak that had broken. Only changes how
    /// the streak reads — a comeback deserves naming, not a second celebration
    /// competing with achievements and pack completions.
    var isComeback: Bool = false
    var totalCompleted: Int = 0
    let onHome: () -> Void

    @State private var shareImage: Image?
    @State private var showPaywall = false
    /// Which entry point opened the paywall — set right before `showPaywall`
    /// so `paywall_opened` / `premium_purchased` attribute correctly.
    @State private var paywallSource = "completion"
    /// True once this appearance scheduled the system review prompt — the
    /// auto paywall stands down rather than stacking sheets.
    @State private var didRequestReview = false
    /// A friend's challenge for this puzzle, captured on appear so consuming it
    /// doesn't make the result card vanish mid-view. Nil = a plain solve.
    @State private var challenge: ChallengeService.Challenge?
    @State private var didProcessChallenge = false
    /// Set to present the system share sheet for an outgoing challenge link.
    @State private var challengeShare: ChallengeShare?
    /// The solved puzzle's pack, if any, with progress and the next unsolved
    /// puzzle — computed once on appear so the card doesn't shift mid-view.
    @State private var packContext: PackContext?
    /// First outgoing challenge needs a display name — collected inline. The
    /// intent (fresh challenge vs. rematch) is stashed across the prompt.
    @State private var showNamePrompt = false
    @State private var draftName = ""
    @State private var pendingRematchIntent = false
    @Environment(\.displayScale) private var displayScale
    @Environment(\.openURL) private var openURL
    @Environment(\.gameCenter) private var gameCenter
    @Environment(\.requestReview) private var requestReview
    @Environment(\.puzzleProvider) private var puzzleProvider
    @Environment(\.readerRouter) private var readerRouter
    @Environment(\.analytics) private var analytics
    @Environment(\.challengeService) private var challengeService
    @Environment(\.modelContext) private var context
    @Environment(StoreService.self) private var store
    /// Highest completion milestone we've already asked a review at, so each
    /// milestone prompts at most once across sessions.
    @AppStorage("reviewPromptMilestone") private var reviewPromptMilestone = 0
    /// One-shot flags for the auto-shown paywall moments (first-ever solve,
    /// 3-day streak) plus a daily cap so at most one auto paywall fires per day.
    @AppStorage("firstCompletionPaywallShown") private var firstCompletionPaywallShown = false
    @AppStorage("streakPaywallShown") private var streakPaywallShown = false
    @AppStorage("autoPaywallLastDay") private var autoPaywallLastDay = 0.0

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

                if let challenge {
                    resultCard(challenge)
                }

                verseCard

                if let packContext {
                    packCard(packContext)
                }

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
        .background(Theme.background)
        .softTopScrollEdge()
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
            processIncomingChallenge()
            loadPackContext()
            maybeAutoShowPaywall()
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(source: paywallSource)
        }
        .sheet(item: $challengeShare) { share in
            ShareSheet(items: [share.caption, share.url])
        }
        .alert("What should we call you?", isPresented: $showNamePrompt) {
            TextField("Your name", text: $draftName)
            Button("Save") { saveNameAndSend() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("We'll show this name to friends you challenge.")
        }
    }

    // MARK: - Friend challenge

    /// Capture any incoming challenge once, record the head-to-head, and clear it
    /// from the pending store so a replay won't re-show the comparison.
    private func processIncomingChallenge() {
        guard !didProcessChallenge else { return }
        didProcessChallenge = true
        guard let incoming = challengeService.pending(for: puzzle.id) else { return }
        challenge = incoming
        analytics.log(.challengeCompleted(
            puzzleID: puzzle.id,
            won: seconds < incoming.seconds,
            deltaSeconds: incoming.seconds - seconds
        ))
        challengeService.consume(puzzleID: puzzle.id)
    }

    /// The head-to-head against a friend's time, crowning the screen above the
    /// verse. Its primary action is the rematch — send *your* time back.
    private func resultCard(_ challenge: ChallengeService.Challenge) -> some View {
        let won = seconds < challenge.seconds
        let tied = seconds == challenge.seconds
        let title = tied ? "Dead heat with \(challenge.challengerName)!"
            : won ? "You beat \(challenge.challengerName)!"
            : "\(challenge.challengerName) still leads"

        return VStack(spacing: Theme.Spacing.m) {
            Image(systemName: won ? "crown.fill" : tied ? "equal.circle.fill" : "flag.checkered")
                .font(.system(size: 40))
                .foregroundStyle(won ? .yellow : Theme.accent)

            Text(title)
                .font(.title3.weight(.bold))
                .multilineTextAlignment(.center)

            HStack(spacing: Theme.Spacing.l) {
                comparisonStat(label: "You", value: seconds, highlight: won || tied)
                comparisonStat(label: challenge.challengerName, value: challenge.seconds, highlight: !won && !tied)
            }

            Button {
                sendChallenge(rematch: true)
            } label: {
                Label("Send Result Back", systemImage: "arrow.uturn.left")
            }
            .buttonStyle(.pillProminent)
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity)
        .background(Theme.accent.opacity(0.1), in: .rect(cornerRadius: Theme.cornerRadius, style: .continuous))
    }

    private func comparisonStat(label: String, value: Int, highlight: Bool) -> some View {
        VStack(spacing: 2) {
            Text(TimeFormat.clock(value))
                .font(.title2.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(highlight ? Theme.accent : .primary)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    /// True once the player has set a display name (the default counts as unset).
    private var hasChosenName: Bool {
        let name = profile.username.trimmingCharacters(in: .whitespacesAndNewlines)
        return !name.isEmpty && name != ChallengeService.placeholderName
    }

    /// Share a challenge carrying this solve's time. Prompts for a name first if
    /// the player hasn't set one — this is the highest-motivation moment to ask.
    private func sendChallenge(rematch: Bool) {
        guard hasChosenName else {
            pendingRematchIntent = rematch
            draftName = ""
            showNamePrompt = true
            return
        }
        // The https universal link is tappable everywhere: it opens the app for
        // installed friends and the web landing page (→ App Store) for the rest.
        guard let url = challengeService.challengeWebURL(
            puzzleID: puzzle.id, seconds: seconds, name: profile.username
        ) else { return }
        let caption = "Can you beat me? I solved \"\(puzzle.title)\" in \(TimeFormat.clock(seconds)) — Bible Crossword"
        challengeShare = ChallengeShare(url: url, caption: caption)
        analytics.log(rematch ? .challengeRematchSent(puzzleID: puzzle.id)
                              : .challengeSent(puzzleID: puzzle.id))
    }

    private func saveNameAndSend() {
        let name = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        profile.username = String(name.prefix(20))
        context.saveLogged("challenge name")
        sendChallenge(rematch: pendingRematchIntent)
    }

    // MARK: - Pack continuation

    /// The solved puzzle's place in its pack: overall progress plus the next
    /// unsolved puzzle in authored order (nil once the pack is finished).
    private struct PackContext {
        let pack: PuzzlePack
        let progress: PackProgress
        let next: Puzzle?
    }

    private func loadPackContext() {
        guard let pack = puzzleProvider.pack(forPuzzle: puzzle.id) else { return }
        let records = (try? context.fetch(FetchDescriptor<PuzzleRecord>())) ?? []
        let recordsByID = Dictionary(records.map { ($0.puzzleID, $0) }, uniquingKeysWith: { a, _ in a })
        let next = puzzleProvider.puzzles(in: pack).first {
            $0.id != puzzle.id && recordsByID[$0.id]?.isCompleted != true
        }
        packContext = PackContext(
            pack: pack,
            progress: PackProgress(pack: pack, recordsByID: recordsByID),
            next: next
        )
    }

    /// Where this solve sits in its pack. Finished → a celebratory seal; more
    /// to go → one tap into the next puzzle (or the paywall when the pack is
    /// premium and the player isn't — a natural discovery moment for overlay
    /// puzzles reached via the daily feed).
    @ViewBuilder
    private func packCard(_ ctx: PackContext) -> some View {
        if ctx.progress.isComplete {
            HStack(spacing: Theme.Spacing.m) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.title)
                    .foregroundStyle(ctx.pack.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(ctx.pack.title) complete!")
                        .font(.subheadline.weight(.semibold))
                    Text("Every puzzle in the pack is solved.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(Theme.Spacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ctx.pack.accent.opacity(0.12), in: .rect(cornerRadius: Theme.cornerRadius, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(ctx.pack.title) complete. Every puzzle in the pack is solved.")
        } else if let next = ctx.next {
            let locked = ctx.pack.isPremium && !store.isPremium
            Button {
                if locked {
                    paywallSource = "pack_completion"
                    showPaywall = true
                } else if let url = URL(string: "biblecrossword://puzzle?id=\(next.id)") {
                    openURL(url)
                    onHome()
                }
            } label: {
                HStack(spacing: Theme.Spacing.m) {
                    Image(systemName: locked ? "crown.fill" : ctx.pack.coverSymbol)
                        .font(.title)
                        .foregroundStyle(locked ? .yellow : ctx.pack.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(ctx.pack.title) · \(ctx.progress.solved) of \(ctx.progress.total)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(locked ? "Unlock Premium to keep going" : "Next: \(next.title)")
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
                .background(ctx.pack.accent.opacity(0.12), in: .rect(cornerRadius: Theme.cornerRadius, style: .continuous))
            }
            .buttonStyle(PressableCardStyle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(ctx.pack.title), \(ctx.progress.solved) of \(ctx.progress.total) solved.")
            .accessibilityHint(locked ? "Opens Premium upgrade options" : "Plays the next puzzle, \(next.title)")
        }
    }

    // MARK: - Mini upsell

    /// The minis actually behind the wall: everything except the ones a free
    /// player can already open this week (see `PuzzleAccess`). This used to
    /// subtract only today's, which overstated the offer the moment the archive
    /// gate softened — and a count the reader can disprove by opening Library
    /// costs more than it wins.
    private var pastMiniCount: Int {
        max(0, puzzleProvider.minis.count - PuzzleAccess.windowLength)
    }

    /// The post-win ask: shown only to free users right after a Mini solve,
    /// when the appetite for "one more" is highest. A single quiet card — the
    /// celebration stays the hero.
    private var miniUpsellCard: some View {
        Button {
            paywallSource = "mini_completion"
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

    /// Celebratory completion mark. The disc is drawn natively so it tracks the
    /// accent and survives Reduce Motion intact; the Lottie adds only confetti.
    private var celebration: some View {
        CelebrationBadge(systemImage: "checkmark", confetti: "puzzle_complete")
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
                    // "1-day streak" is a true but bleak thing to show someone
                    // who just lost a long one. Naming it a new streak says the
                    // same number and frames it as a start.
                    Text(isComeback ? "New streak — day \(streak)" : "\(streak)-day streak")
                } icon: {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(.orange)
                }
            }
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.secondary)
    }

    /// Snowflake mark for the streak-freeze card. Cyan carries the meaning; the
    /// gold rim keeps it in the same family as the solve and achievement badges.
    private var freezeMark: some View {
        CelebrationBadge(systemImage: "snowflake",
                         confetti: "streak_freeze",
                         tint: .cyan,
                         size: 72)
    }

    /// Star mark crowning the new-achievements card.
    private var achievementMark: some View {
        CelebrationBadge(systemImage: "star.fill",
                         confetti: "achievement_unlock",
                         size: 112)
    }

    /// The verse is the emotional payoff of the solve — the one card that gets
    /// special treatment (accent wash) while everything else recedes.
    private var verseCard: some View {
        VStack(spacing: Theme.Spacing.s) {
            Text("Today's Verse")
                .kicker()
            Text("“\(puzzle.verse)”")
                .font(.scripture(.title3))
                .lineSpacing(4)
                .multilineTextAlignment(.center)
            Text(puzzle.reference)
                .font(.headline)
                .foregroundStyle(Theme.accent)

            Button {
                analytics.log(.scriptureOpened(reference: puzzle.reference, source: "puzzle_completion"))
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
        didRequestReview = true
        Task {
            // Let the celebration land before the system sheet appears.
            try? await Task.sleep(for: .seconds(2))
            requestReview()
        }
    }

    /// Auto-present the paywall at the two highest-intent free-user moments:
    /// the first-ever solve ("first_completion") and reaching a 3-day streak
    /// ("streak_3"). Each fires once ever, at most one auto paywall per day,
    /// and never over a challenge result, the mini upsell card, or a review
    /// prompt — the celebration stays the hero, the ask follows it.
    private func maybeAutoShowPaywall() {
        guard !store.isPremium, challenge == nil, !didRequestReview else { return }
        // The mini upsell card already makes this screen's ask — don't stack.
        if puzzle.isMini && pastMiniCount > 0 { return }

        let today = Calendar.current.startOfDay(for: Date()).timeIntervalSinceReferenceDate
        guard autoPaywallLastDay != today else { return }

        let source: String
        if totalCompleted == 1 && !firstCompletionPaywallShown {
            source = "first_completion"
            firstCompletionPaywallShown = true
        } else if streak >= 3 && !streakPaywallShown {
            source = "streak_3"
            streakPaywallShown = true
        } else {
            return
        }

        autoPaywallLastDay = today
        Task {
            // Let the completion celebration land before the sheet slides up.
            try? await Task.sleep(for: .seconds(1.5))
            paywallSource = source
            showPaywall = true
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
            .buttonStyle(.pillProminent)

            // A challenge that arrived for this puzzle already offers "Send
            // Result Back" in the result card — don't double up the CTA.
            if challenge == nil {
                Button {
                    sendChallenge(rematch: false)
                } label: {
                    Label("Challenge a Friend", systemImage: "flag.checkered")
                }
                .buttonStyle(.pillTonal)
            }

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

    /// An outgoing challenge to hand to the share sheet. Identifiable so it can
    /// drive `.sheet(item:)`; a fresh id each time forces re-presentation.
    private struct ChallengeShare: Identifiable {
        let id = UUID()
        let url: URL
        let caption: String
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

/// A thin `UIActivityViewController` wrapper for imperative sharing — used for
/// the challenge link, which is built after an optional name prompt and so can't
/// be a declarative `ShareLink`.
private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

// MARK: - Scroll edge

private extension View {
    /// This screen is full-bleed with no navigation bar, so scrolled content
    /// runs straight into the clock and Dynamic Island. iOS 26's scroll edge
    /// effect needs a bar to blur into and there isn't one here, so cap the
    /// status area with the same `.bar` material the actions row already uses.
    ///
    /// The cap is a zero-height view pinned to the top of the safe area; letting
    /// it ignore the top edge stretches it up over exactly the inset, whatever
    /// the device.
    func softTopScrollEdge() -> some View {
        overlay(alignment: .top) {
            Color.clear
                .frame(height: 0)
                .background {
                    Rectangle()
                        .fill(.bar)
                        .ignoresSafeArea(edges: .top)
                }
                .allowsHitTesting(false)
        }
    }
}
