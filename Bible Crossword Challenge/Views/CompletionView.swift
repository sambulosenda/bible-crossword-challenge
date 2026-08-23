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
    /// Which entry point opened the paywall, carried *as* the sheet's item.
    ///
    /// This used to be a `Bool` plus a separate `paywallSource` string, set one
    /// line apart. `.sheet(isPresented:)` builds its content from the body pass
    /// that flipped the flag, which still held the previous source — so every
    /// paywall opened from this screen logged `paywall_opened` with the initial
    /// `"completion"`, whatever had actually triggered it. SwiftUI then
    /// re-evaluated with the real value, so `paywall_cta_tapped` from the *same*
    /// sheet carried the correct source: `first_completion` taps existed against
    /// zero `first_completion` opens, and `streak_3`, `pack_completion` and
    /// `mini_completion` read as dead triggers for three weeks.
    ///
    /// With `.sheet(item:)` the value that presents the sheet is the value the
    /// sheet is built from, so the two can't drift apart again.
    @State private var paywallEntry: PaywallEntry?
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
    /// Weekdays solved this week, driving the scorecard's week row. Captured on
    /// appear so the row can't shift mid-view.
    @State private var completedWeekdays: Set<Int> = []
    /// First outgoing challenge needs a display name — collected inline. The
    /// intent (fresh challenge vs. rematch) is stashed across the prompt.
    @State private var showNamePrompt = false
    @State private var draftName = ""
    @State private var pendingRematchIntent = false
    /// True when the name prompt was raised by a board action rather than a
    /// one-to-one challenge, so saving the name resumes the right one.
    @State private var pendingBoardIntent = false
    /// The last friend we have a recorded head-to-head against on *this* puzzle,
    /// captured on appear. Only read when no challenge arrived with this solve —
    /// otherwise the result card is already naming an opponent.
    @State private var lastOpponent: ChallengeHistory.Entry?
    /// This puzzle's family board once this solve has been folded in, or nil
    /// when the player isn't part of one. Captured on appear so the card can't
    /// appear or re-rank mid-view.
    @State private var board: FamilyBoardService.Board?
    /// Today's full daily, when this solve was a Mini and the daily is still
    /// unsolved — the highest-value next step this screen can offer, so it
    /// takes the primary slot. Captured on appear.
    @State private var chainTarget: Puzzle?
    /// This week's Game Center standing, fetched after a Mini solve so the
    /// leaderboard button can say where the player sits instead of just that
    /// a board exists. Nil until it loads (or when it can't).
    @State private var weeklyRank: (rank: Int, total: Int)?
    @Environment(\.displayScale) private var displayScale
    @Environment(\.openURL) private var openURL
    @Environment(\.gameCenter) private var gameCenter
    @Environment(\.requestReview) private var requestReview
    @Environment(\.puzzleProvider) private var puzzleProvider
    @Environment(\.readerRouter) private var readerRouter
    @Environment(\.analytics) private var analytics
    @Environment(\.challengeService) private var challengeService
    @Environment(\.challengeHistory) private var challengeHistory
    @Environment(\.familyBoard) private var familyBoard
    @Environment(\.modelContext) private var context
    @Environment(StoreService.self) private var store
    /// Review-ask bookkeeping — the rules live in `ReviewAsk.decide`.
    @AppStorage("reviewPromptMilestone") private var reviewPromptMilestone = 0
    @AppStorage("streakReviewPromptShown") private var streakReviewPromptShown = false
    @AppStorage("reviewPromptVersion") private var reviewPromptVersion = ""
    @AppStorage("reviewPromptLastAsk") private var reviewPromptLastAsk = 0.0
    /// One-shot flags for the auto-shown paywall moments (first-ever solve,
    /// 3-day streak) plus a daily cap so at most one auto paywall fires per day.
    @AppStorage("firstCompletionPaywallShown") private var firstCompletionPaywallShown = false
    @AppStorage("streakPaywallShown") private var streakPaywallShown = false
    @AppStorage("autoPaywallLastDay") private var autoPaywallLastDay = 0.0
    /// Reminder-ask bookkeeping shared with Home's streak card and the day-2
    /// sheet — the rules live in `ReminderAsk.decide`.
    @Environment(\.notifications) private var notifications
    @AppStorage("remindersEnabled") private var remindersEnabled = false
    @AppStorage("completionReminderAsksShown") private var completionReminderAsksShown = 0
    @AppStorage("streakReminderAskShown") private var streakReminderAskShown = false
    @AppStorage("reminderAskLastDay") private var reminderAskLastDay = 0.0
    /// Decided once on appear so spending an impression can't hide the card
    /// mid-view.
    @State private var showReminderAsk = false

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

                scorecard

                if let challenge {
                    resultCard(challenge)
                }

                // A board the player is already part of is why they're on this
                // screen, so it sits above the verse with the other payoffs.
                if let board {
                    familyBoardCard(board)
                }

                verseCard

                if let packContext {
                    packCard(packContext)
                }

                // The invitation, by contrast, is an ask — it belongs down here
                // with the other quiet cards, not competing with the verse.
                if board == nil {
                    startBoardCard
                }

                if earnedFreeze {
                    freezeCard
                }

                if !newAchievements.isEmpty {
                    achievementsCard
                }

                // Below the payoffs with the other asks. Present only when the
                // screen has no other ask this launch — see maybeShowReminderAsk.
                if showReminderAsk {
                    ReminderAskCard(
                        profile: profile,
                        surface: .completion,
                        kicker: "Make it a habit",
                        headline: "Same time tomorrow?",
                        onFinish: { withAnimation { showReminderAsk = false } }
                    )
                }

                if puzzle.isMini && !store.isPremium && pastMiniCount > 0 {
                    miniUpsellCard
                }

                secondaryActions

                nextPuzzleFooter
            }
            .padding(Theme.Spacing.l)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background)
        .softTopScrollEdge()
        // HIG: a pinned bottom bar carries one primary action, not a menu.
        // Everything else scrolls with the content (see `secondaryActions`).
        .safeAreaInset(edge: .bottom) {
            pinnedActions
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.vertical, Theme.Spacing.s)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
                .background(.bar)
                .overlay(alignment: .top) { Divider() }
        }
        .onAppear {
            renderShareCard()
            maybeRequestReview()
            processIncomingChallenge()
            loadLastOpponent()
            loadFamilyBoard()
            loadWeek()
            loadPackContext()
            loadChainTarget()
            loadWeeklyRank()
            maybeAutoShowPaywall()
            // After the paywall decision on purpose: the reminder ask stands
            // down any day an auto paywall fired (including just now).
            maybeShowReminderAsk()
        }
        .sheet(item: $paywallEntry) { entry in
            PaywallView(source: entry.source)
        }
        .sheet(item: $challengeShare) { share in
            // History records the send, not the intent: a share sheet the
            // player backs out of never happened, and a list claiming
            // otherwise is the one thing a brag sheet can't afford.
            ShareSheet(items: [share.caption, share.url]) { completed in
                guard completed, !share.isBoard else { return }
                recordOutgoing(rematch: share.isRematch)
            }
        }
        .alert("What should we call you?", isPresented: $showNamePrompt) {
            TextField("Your name", text: $draftName)
            // Alert buttons always dismiss, and a Save on an empty field would
            // silently drop the pending challenge/board intent — so it can't
            // be tapped until there's a name to save.
            Button("Save") { saveNameAndSend() }
                .disabled(draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
        challengeHistory.recordPlayed(
            puzzleID: puzzle.id,
            puzzleTitle: puzzle.title,
            opponentName: incoming.challengerName,
            opponentSeconds: incoming.seconds,
            mySeconds: seconds
        )
        challengeService.consume(puzzleID: puzzle.id)
    }

    /// The opponent this screen offers a rematch against — only when no
    /// challenge came in with this solve, since that case already has the result
    /// card and its own "Send Result Back". Read after `processIncomingChallenge`
    /// so the row it just wrote can't be mistaken for a past matchup.
    private func loadLastOpponent() {
        guard challenge == nil else { return }
        lastOpponent = challengeHistory.lastOpponent(for: puzzle.id)
    }

    /// Write an outgoing challenge to history once the share has gone through.
    /// A rematch marks the row it answers rather than opening a second one.
    private func recordOutgoing(rematch: Bool) {
        if rematch {
            challengeHistory.markRematchSent(
                puzzleID: puzzle.id, puzzleTitle: puzzle.title, mySeconds: seconds
            )
        } else {
            challengeHistory.recordSent(
                puzzleID: puzzle.id, puzzleTitle: puzzle.title, mySeconds: seconds
            )
        }
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

    /// The secondary CTA's title. Naming the last opponent turns a generic
    /// "Challenge a Friend" into a specific person to beat, which is the whole
    /// reason the rematch loop exists.
    private var challengeTitle: String {
        guard let name = lastOpponent?.opponentName else { return "Challenge a Friend" }
        return "Challenge \(name) Again"
    }

    /// One quiet line under the CTA: how this puzzle's last matchup stands, or —
    /// for someone who has never sent one — what tapping actually does.
    private var challengeHint: String? {
        if let last = lastOpponent, let name = last.opponentName, let theirs = last.opponentSeconds {
            let mine = TimeFormat.clock(last.mySeconds)
            let hers = TimeFormat.clock(theirs)
            switch last.outcome {
            case .won: return "You won that one — \(mine) to \(hers)."
            case .lost: return "\(name) won that one — \(hers) to \(mine)."
            case .tied, .none: return "You and \(name) tied at \(mine)."
            }
        }
        guard challengeHistory.entries.isEmpty else { return nil }
        return "They'll get a link to this exact puzzle. Fastest time wins."
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
        challengeShare = ChallengeShare(url: url, caption: caption, isRematch: rematch)
        analytics.log(rematch ? .challengeRematchSent(puzzleID: puzzle.id)
                              : .challengeSent(puzzleID: puzzle.id))
    }

    private func saveNameAndSend() {
        let name = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let previous = boardName
        profile.username = String(name.prefix(20))
        context.saveLogged("challenge name")

        guard pendingBoardIntent else {
            sendChallenge(rematch: pendingRematchIntent)
            return
        }
        pendingBoardIntent = false
        // A board joined before the name was chosen carries the placeholder;
        // relabel that row rather than letting a second one appear beside it.
        familyBoard.rename(puzzleID: puzzle.id, from: previous, to: profile.username)
        if board == nil {
            startBoard()
        } else if let refreshed = familyBoard.board(for: puzzle.id) {
            board = refreshed
            shareBoard(refreshed)
        }
    }

    // MARK: - Family board

    /// Fold this solve into the puzzle's board, if the player is on one.
    ///
    /// Only an existing board is joined here — starting one is a deliberate tap,
    /// because a board is a thing you send to people and creating them silently
    /// on every solve would fill the list with boards of one.
    private func loadFamilyBoard() {
        guard familyBoard.board(for: puzzle.id) != nil else { return }
        board = familyBoard.record(
            puzzleID: puzzle.id,
            puzzleTitle: puzzle.title,
            name: boardName,
            seconds: seconds
        )
    }

    /// What this device is called on a board. Falls back to the placeholder
    /// rather than blocking on a prompt: the board is local until it's shared,
    /// and `shareBoard` collects a real name before it leaves the device.
    private var boardName: String {
        hasChosenName ? profile.username : ChallengeService.placeholderName
    }

    /// The ranked board, with this player's row marked. The whole feature is
    /// this list — everything else is plumbing to get names onto it.
    private func familyBoardCard(_ board: FamilyBoardService.Board) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack(spacing: Theme.Spacing.s) {
                Image(systemName: "person.3.fill")
                    .foregroundStyle(Theme.accent)
                Text("Family board")
                    .kicker()
                Spacer(minLength: 0)
                Text("\(board.standings.count) playing")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: Theme.Spacing.s) {
                ForEach(Array(board.standings.enumerated()), id: \.element.id) { index, standing in
                    standingRow(index: index, standing: standing, isMe: standing.name == boardName)
                }
            }

            Button {
                shareBoard(board)
            } label: {
                Label("Share the Board", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.pillTonal)
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity)
        .background(Theme.accent.opacity(0.1), in: .rect(cornerRadius: Theme.cornerRadius, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    private func standingRow(index: Int, standing: FamilyBoardService.Standing, isMe: Bool) -> some View {
        HStack(spacing: Theme.Spacing.m) {
            Text("\(index + 1)")
                .font(.caption.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 18, alignment: .trailing)
            Text(standing.name)
                .font(.subheadline.weight(isMe ? .bold : .regular))
                .lineLimit(1)
            Spacer(minLength: Theme.Spacing.s)
            Text(TimeFormat.clock(standing.seconds))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(index + 1). \(standing.name)\(isMe ? ", you" : ""), \(TimeFormat.clock(standing.seconds))")
    }

    /// The invitation, for a puzzle with no board yet.
    private var startBoardCard: some View {
        Button {
            startBoard()
        } label: {
            HStack(spacing: Theme.Spacing.m) {
                Image(systemName: "person.3.fill")
                    .font(.title)
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Start a family board")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("Everyone plays this puzzle; the times stack up in one list.")
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
            .elevatedCard()
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Start a family board. Everyone plays this puzzle; the times stack up in one list.")
        .accessibilityHint("Creates a board with your time and opens the share sheet")
    }

    /// Create the board with this solve on it and hand it straight to the share
    /// sheet — a board of one has no reason to exist until it's sent.
    private func startBoard() {
        guard hasChosenName else {
            pendingBoardIntent = true
            draftName = ""
            showNamePrompt = true
            return
        }
        let created = familyBoard.record(
            puzzleID: puzzle.id,
            puzzleTitle: puzzle.title,
            name: profile.username,
            seconds: seconds
        )
        board = created
        analytics.log(.familyBoardStarted(puzzleID: puzzle.id))
        shareBoard(created)
    }

    private func shareBoard(_ board: FamilyBoardService.Board) {
        guard hasChosenName else {
            pendingBoardIntent = true
            draftName = ""
            showNamePrompt = true
            return
        }
        guard let url = familyBoard.boardURL(board) else { return }
        challengeShare = ChallengeShare(
            url: url,
            caption: board.shareText + "\n\nBeat us:",
            isRematch: false,
            isBoard: true
        )
        analytics.log(.familyBoardShared(puzzleID: board.puzzleID, size: board.standings.count))
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
                    paywallEntry = PaywallEntry(source: "pack_completion")
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
            paywallEntry = PaywallEntry(source: "mini_completion")
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
            // A plain card, not an accent wash: the verse is this screen's hero
            // and the wash is what marks it. Dressing the upsell in the same
            // tint made the two read as siblings, with the ask borrowing the
            // weight the payoff had earned.
            .elevatedCard()
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
        }
        .padding(.top, Theme.Spacing.m)
    }

    /// Celebratory completion mark: the grid the player just filled, not a
    /// checkmark. A tick is what iOS shows for "operation succeeded" — it marks
    /// that something finished without saying what, and every results screen in
    /// the category that reaches for one looks like every other. The grid is the
    /// puzzle itself, a different shape every day, and the same mark the app
    /// icon, the daily card and the share caption already use.
    ///
    /// The disc is drawn natively so it tracks the accent and survives Reduce
    /// Motion intact; the Lottie adds only confetti.
    private var celebration: some View {
        CelebrationBadge(grid: puzzle.grid, confetti: "puzzle_complete")
    }

    /// The solve's own numbers, given the weight a results screen owes them.
    ///
    /// These used to be one grey `.subheadline` line under the title — smaller
    /// than the upsell card's body text, on the one screen whose whole job is to
    /// report them. Tiles put the numbers first and the labels under, and the
    /// week row underneath turns a bare streak count into a visible run: this is
    /// the moment today's dot fills, so it's the moment worth showing it.
    private var scorecard: some View {
        VStack(spacing: Theme.Spacing.m) {
            HStack(spacing: Theme.Spacing.m) {
                statTile(value: TimeFormat.clock(seconds),
                         label: "Time",
                         symbol: "timer",
                         tint: .secondary)

                if streak > 0 {
                    // "1-day streak" is a true but bleak thing to show someone
                    // who just lost a long one. Naming it a new streak says the
                    // same number and frames it as a start.
                    statTile(value: "\(streak)",
                             label: isComeback ? "New streak" : "Day streak",
                             symbol: "flame.fill",
                             tint: .orange)
                }
            }

            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 1)

            WeekRow(completedWeekdays: completedWeekdays)
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity)
        .elevatedCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(scorecardLabel)
    }

    private func statTile(value: String, label: String, symbol: String, tint: Color) -> some View {
        VStack(spacing: 2) {
            Image(systemName: symbol)
                .font(.subheadline)
                .foregroundStyle(tint)
            Text(value)
                .font(.title.weight(.bold))
                .monospacedDigit()
            Text(label)
                .kicker()
        }
        .frame(maxWidth: .infinity)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }

    private var scorecardLabel: String {
        var parts = ["Solved in \(TimeFormat.clock(seconds))"]
        if streak > 0 {
            parts.append(isComeback ? "New streak, day \(streak)" : "\(streak) day streak")
        }
        let days = completedWeekdays.count
        parts.append("\(days) \(days == 1 ? "day" : "days") completed this week")
        return parts.joined(separator: ". ")
    }

    /// The mini→daily chain target: today's full puzzle, offered only when this
    /// solve was a Mini and the daily hasn't been solved yet. Day-one puzzle
    /// completion is the strongest D1 signal we have; this is the moment the
    /// appetite for "one more" exists, so the next solve is one tap away.
    private func loadChainTarget() {
        guard puzzle.isMini,
              let daily = puzzleProvider.dailyPuzzle(),
              daily.id != puzzle.id
        else { return }
        let records = (try? context.fetch(FetchDescriptor<PuzzleRecord>())) ?? []
        guard !records.contains(where: { $0.puzzleID == daily.id && $0.isCompleted }) else { return }
        chainTarget = daily
    }

    /// Fetch this week's standing for the leaderboard button. The solve's score
    /// was submitted moments ago, so give Game Center a beat to fold it in;
    /// if the fetch loses that race the button just keeps its generic title.
    private func loadWeeklyRank() {
        guard puzzle.isMini, gameCenter.isAuthenticated else { return }
        Task {
            try? await Task.sleep(for: .seconds(1))
            weeklyRank = await gameCenter.weeklyMiniRank()
        }
    }

    /// The leaderboard button's title: the player's own standing once it loads.
    private var weeklyRankTitle: String {
        guard let weeklyRank else { return "Weekly Leaderboard" }
        return "#\(weeklyRank.rank) of \(weeklyRank.total) this week"
    }

    /// Weekdays with a completed puzzle in the current week, for the week row.
    /// Read once on appear — this solve's record is already written and saved by
    /// the time the cover presents, so today's dot is lit.
    private func loadWeek() {
        let calendar = Calendar.current
        guard let week = calendar.dateInterval(of: .weekOfYear, for: Date()) else { return }
        let records = (try? context.fetch(FetchDescriptor<PuzzleRecord>())) ?? []
        completedWeekdays = Set(records.compactMap { record in
            guard record.isCompleted, let date = record.completedDate, week.contains(date) else { return nil }
            return calendar.component(.weekday, from: date)
        })
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
        .elevatedCard()
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
        .elevatedCard()
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

    /// Ask for a rating at the happiest moments in the loop — the triggers and
    /// their spacing live in `ReviewAsk.decide`; this just spends the flag the
    /// verdict names. The system further rate-limits what actually shows.
    private func maybeRequestReview() {
        let state = ReviewAsk.State(
            totalCompleted: totalCompleted,
            currentStreak: streak,
            milestoneAsked: reviewPromptMilestone,
            streakAsked: streakReviewPromptShown,
            versionAsked: reviewPromptVersion,
            currentVersion: Self.marketingVersion,
            lastAsk: reviewPromptLastAsk == 0
                ? nil : Date(timeIntervalSinceReferenceDate: reviewPromptLastAsk)
        )
        guard let trigger = ReviewAsk.decide(state) else { return }
        switch trigger {
        case .milestone(let milestone): reviewPromptMilestone = milestone
        case .streak: streakReviewPromptShown = true
        case .version: break
        }
        // Any ask spends this version's re-arm — the version trigger can't
        // stack a second prompt onto a version that already asked.
        reviewPromptVersion = Self.marketingVersion
        reviewPromptLastAsk = Date().timeIntervalSinceReferenceDate
        didRequestReview = true
        analytics.log(.reviewPromptRequested(
            trigger: trigger.analyticsValue, totalCompleted: totalCompleted))
        Task {
            // Let the celebration land before the system sheet appears.
            try? await Task.sleep(for: .seconds(2))
            requestReview()
        }
    }

    private static let marketingVersion =
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""

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
        // `<= 3`, not `== 1`: the "first completion" moment can be given away —
        // to the reminder ask below, or to the mini upsell when the first solve
        // is a Mini — and an exact match would lose this paywall forever when
        // that happens. A small window keeps "first" honest while letting a
        // deferred ask land on solve #2 or #3. (Also why the flag, not the
        // count, is what marks it spent.)
        if totalCompleted >= 1 && totalCompleted <= 3 && !firstCompletionPaywallShown {
            // The first solve is also the reminder ask's best moment, and the
            // two can't share the screen (`maybeShowReminderAsk` yields to
            // today's auto paywall). The notification grant compounds every
            // retention loop this paywall later benefits from — 67% of players
            // who reach the dialog say yes — so when the ask is eligible it
            // wins solve #1 outright and this paywall takes the next one.
            if totalCompleted == 1 && reminderAskEligible { return }
            // The mini→daily chain outranks this paywall too: completing a
            // real puzzle on day one is the strongest retention signal we
            // have (D7 34.8% vs 7%, measured 2026-08-23), and a sheet sliding
            // over the chain button spends that moment on an ask the player
            // already declined during onboarding minutes earlier. The `<= 3`
            // window means the paywall lands on the next solve instead —
            // usually the chained daily, an even better-proven moment.
            if chainTarget != nil { return }
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
            paywallEntry = PaywallEntry(source: source)
        }
    }

    /// Offer the daily reminder at the moment the product just proved its
    /// value — but only when this screen carries no other ask: a challenge
    /// result, a review sheet, today's auto paywall, or the mini upsell all
    /// outrank it, and `ReminderAsk.decide` enforces the cross-surface caps
    /// (one ask per day anywhere, one per session, first three solves only).
    /// Whether the completion reminder ask would fire if no auto paywall
    /// claimed today — the first-solve precedence check in
    /// `maybeAutoShowPaywall`. Mirrors `maybeShowReminderAsk`'s guards exactly,
    /// minus the `autoPaywallLastDay` gate this decision feeds.
    private var reminderAskEligible: Bool {
        guard challenge == nil, !didRequestReview else { return false }
        if puzzle.isMini && !store.isPremium && pastMiniCount > 0 { return false }
        return ReminderAsk.decide(.completion, reminderAskState)
    }

    private var reminderAskState: ReminderAsk.State {
        ReminderAsk.State(
            remindersEnabled: remindersEnabled,
            permissionUndetermined: notifications.authorizationStatus == .notDetermined,
            totalCompleted: totalCompleted,
            currentStreak: streak,
            completionAsksShown: completionReminderAsksShown,
            streakAskShown: streakReminderAskShown,
            lastAskDay: reminderAskLastDay == 0 ? nil : Date(timeIntervalSinceReferenceDate: reminderAskLastDay),
            askedThisSession: ReminderAskSession.asked
        )
    }

    private func maybeShowReminderAsk() {
        #if DEBUG
        // Same family as -uiForceReminderPrompt: the eligible state needs a
        // prior day's paywall and an unanswered onboarding, which takes two
        // real days to reach. Gating itself is unit-tested (ReminderAskTests).
        if ProcessInfo.processInfo.arguments.contains("-uiForceReminderAsk") {
            showReminderAsk = true
            analytics.log(.reminderAskShown(source: ReminderAsk.Surface.completion.rawValue))
            return
        }
        #endif
        let today = Calendar.current.startOfDay(for: Date()).timeIntervalSinceReferenceDate
        guard autoPaywallLastDay != today else { return }
        guard reminderAskEligible else { return }

        showReminderAsk = true
        completionReminderAsksShown += 1
        reminderAskLastDay = today
        ReminderAskSession.asked = true
        analytics.log(.reminderAskShown(source: ReminderAsk.Surface.completion.rawValue))
    }

    /// The pinned bottom bar: one primary action plus the quiet exit. A Mini
    /// solved with today's full puzzle still open makes the chain the primary
    /// (the next solve is worth more than the share); otherwise Share leads.
    private var pinnedActions: some View {
        VStack(spacing: Theme.Spacing.xs) {
            if let chainTarget {
                Button {
                    analytics.log(.completionChainTapped(
                        fromPuzzleID: puzzle.id, toPuzzleID: chainTarget.id
                    ))
                    if let url = URL(string: "biblecrossword://puzzle?id=\(chainTarget.id)") {
                        openURL(url)
                        onHome()
                    }
                } label: {
                    Label("Play Today's Full Puzzle", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.pillProminent)
                .accessibilityHint("Closes this screen and opens today's full-size puzzle")
            } else {
                shareButton(prominent: true)
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

    /// The rest of the actions, scrolling with the content they relate to —
    /// pinning all of them made the bar taller than the visible content on
    /// smaller phones, burying the verse under a wall of buttons.
    private var secondaryActions: some View {
        VStack(spacing: Theme.Spacing.m) {
            // When the chain owns the pinned bar, Share steps down into here.
            if chainTarget != nil {
                shareButton(prominent: false)
            }

            // A challenge that arrived for this puzzle already offers "Send
            // Result Back" in the result card — don't double up the CTA.
            if challenge == nil {
                VStack(spacing: Theme.Spacing.xs) {
                    Button {
                        sendChallenge(rematch: lastOpponent != nil)
                    } label: {
                        Label(challengeTitle, systemImage: "flag.checkered")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.pillTonal)

                    if let hint = challengeHint {
                        Text(hint)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
            }

            // Minis race the clock against everyone — surface this week's
            // standings while the solve is fresh, with the player's own rank
            // once Game Center reports it. Hidden when not signed in.
            if puzzle.isMini && gameCenter.isAuthenticated {
                Button {
                    gameCenter.showWeeklyMiniLeaderboard()
                } label: {
                    Label(weeklyRankTitle, systemImage: "trophy")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .accessibilityHint("Opens the weekly Mini leaderboard")
            }
        }
    }

    private func shareButton(prominent: Bool) -> some View {
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
        .buttonStyle(PillButtonStyle(emphasis: prominent ? .primary : .tonal))
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
        /// Carried through the sheet so the completion handler knows whether to
        /// open a history row or mark the one this answers.
        let isRematch: Bool
        /// A board share is not a one-to-one challenge and must not land in the
        /// head-to-head history — there's no single opponent to record.
        var isBoard = false
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
                reference: puzzle.reference,
                grid: puzzle.grid
            )
        )
        renderer.scale = displayScale
        if let ui = renderer.uiImage {
            shareImage = Image(uiImage: ui)
        }
    }
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

/// The paywall's entry point, as a sheet item.
///
/// A one-field wrapper exists only so the source can drive `.sheet(item:)`
/// rather than ride alongside a separate `isPresented` flag — see the comment
/// on `CompletionView.paywallEntry` for the mis-attribution that cost.
struct PaywallEntry: Identifiable {
    let source: String
    var id: String { source }
}
