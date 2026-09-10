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

    /// The rasterised scorecard, ready before the Share button can be reached.
    @State private var shareUIImage: UIImage?
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
    /// reminder ask stands down rather than stacking asks.
    @State private var didRequestReview = false
    /// A challenge-earned freeze this appearance — receiving side granted in
    /// `processIncomingChallenge`, sending side in the share-sheet callback.
    /// Separate from `earnedFreeze` (the caller's streak-milestone grant) so
    /// either can light the card.
    @State private var bonusFreezeEarned = false
    /// A friend's challenge for this puzzle, captured on appear so consuming it
    /// doesn't make the result card vanish mid-view. Nil = a plain solve.
    @State private var challenge: ChallengeService.Challenge?
    @State private var didProcessChallenge = false
    /// Set to present the system share sheet for an outgoing challenge link.
    @State private var challengeShare: ChallengeShare?
    /// The solved puzzle's pack, if any, with progress and the next unsolved
    /// puzzle — computed once on appear so the card doesn't shift mid-view.
    @State private var packContext: PackContext?
    @State private var questContext: QuestContext?
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
    @Environment(\.memoryVerses) private var memoryVerses
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
    /// Start-of-day stamp of the last challenge-send freeze, capping the
    /// sender's reward at one per day — see `grantSenderFreezeIfDue`.
    @AppStorage("challengeFreezeLastDay") private var challengeFreezeLastDay = 0.0
    /// Reminder-ask bookkeeping shared with Home's streak card and the day-2
    /// sheet — the rules live in `ReminderAsk.decide`.
    @Environment(\.notifications) private var notifications
    @AppStorage("remindersEnabled") private var remindersEnabled = false
    @AppStorage("completionReminderAsksShown") private var completionReminderAsksShown = 0
    @AppStorage("streakReminderAskShown") private var streakReminderAskShown = false
    @AppStorage("reminderAskLastDay") private var reminderAskLastDay = 0.0
    /// The return-day sheet is once ever; this is the spent flag. Same key
    /// the launch-time sheet used, so players who already met it there are
    /// not asked twice across the move.
    @AppStorage("didAskReminderAgain") private var didAskReminderAgain = false
    @State private var showReturnDaySheet = false
    /// Decided once on appear so spending an impression can't hide the card
    /// mid-view.
    @State private var showReminderAsk = false

    private var shareCaption: String {
        var text = "I solved “\(puzzle.title)” in \(TimeFormat.clock(seconds)) — \(streak)-day streak 🔥"
        let grid = ShareGrid.emoji(for: puzzle)
        if !grid.isEmpty { text += "\n\n\(grid)" }
        if let url = ShareConfig.storeURL(kind: "share_card") { text += "\n\n\(url.absoluteString)" }
        return text
    }

    /// The scorecard share, wrapped so `.sheet(item:)` presents it; a fresh id
    /// per tap re-presents after a cancel.
    private struct CardShare: Identifiable {
        let id = UUID()
        let items: [Any]
    }
    @State private var cardShare: CardShare?

    var body: some View {
        // Short content (the common case now: header, scorecard, verse)
        // centres between the top and the pinned bar instead of leaving
        // the bottom third empty; taller content scrolls as before.
        GeometryReader { viewport in
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

                    if let questContext {
                        questCard(questContext)
                    }

                    if earnedFreeze || bonusFreezeEarned {
                        freezeCard
                    }

                    if !newAchievements.isEmpty {
                        achievementsCard
                    }

                    // The completion reminder ask lives in the scorecard now, not
                    // here: this slot sat two to four screens below the fold, and
                    // of 79 players whose screen included the card (2.2–2.6, 45
                    // days to 2026-09-02) 76 never touched it. See `scorecard`.

                    if puzzle.isMini && !store.isPremium && pastMiniCount > 0 && !showReminderAsk {
                        miniUpsellCard
                    }

                }
                .padding(Theme.Spacing.l)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
                .frame(minHeight: viewport.size.height)
            }
        }
        .background(Theme.background)
        .softTopScrollEdge()
        // HIG: a pinned bottom bar carries one primary action; the rest sits
        // behind the "more" menu beside it (see `pinnedActions`).
        // The exit is a close button where a full-screen cover keeps it, not
        // a second line under the primary pill.
        .overlay(alignment: .topLeading) {
            Button {
                onHome()
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .background(Theme.surface, in: .circle)
                    // Floats over scrolled content, so it needs the lift a
                    // resting card doesn't.
                    .shadow(color: .black.opacity(0.10), radius: 8, y: 2)
            }
            .buttonStyle(.plain)
            .padding(.leading, Theme.Spacing.m)
            .padding(.top, Theme.Spacing.xs)
            .accessibilityLabel("Close")
            // An overlay sits after the scroll content in the tree; VoiceOver
            // should reach the exit first, as it would on a system sheet.
            .accessibilitySortPriority(1)
        }
        // Content fades under the bar rather than being cut by a rule.
        .safeAreaInset(edge: .bottom) {
            pinnedActions
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.vertical, Theme.Spacing.s)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
                .background {
                    Theme.background
                        .overlay(alignment: .top) {
                            LinearGradient(
                                colors: [Theme.background.opacity(0), Theme.background],
                                startPoint: .top, endPoint: .bottom
                            )
                            .frame(height: Theme.Spacing.l)
                            .offset(y: -Theme.Spacing.l)
                        }
                        .ignoresSafeArea()
                }
        }
        .onAppear {
            renderShareCard()
            maybeRequestReview()
            processIncomingChallenge()
            loadLastOpponent()
            loadFamilyBoard()
            loadWeek()
            loadPackContext()
            loadQuestContext()
            loadChainTarget()
            loadWeeklyRank()
            // Sheet first: it spends the day's ask budget, and the inline
            // card below yields to it through `ReminderAsk.decide`.
            maybeShowReturnDaySheet()
            maybeShowReminderAsk()
        }
        .sheet(isPresented: $showReturnDaySheet, onDismiss: {
            // Marked on the way out, whichever way it closed — a swipe-down
            // counts as an answer; the single sheet this player gets is spent.
            didAskReminderAgain = true
        }) {
            DailyReminderPrompt(profile: profile) {
                showReturnDaySheet = false
            }
        }
        .sheet(item: $paywallEntry) { entry in
            PaywallView(source: entry.source)
        }
        .sheet(item: $challengeShare) { share in
            // History and analytics record the send, not the intent: a share
            // sheet the player backs out of never happened, and a list (or a
            // `challenge_sent` count) claiming otherwise is the one thing a
            // brag sheet can't afford. The cancel is logged too — 22 "sent" to
            // 0 opened was undiagnosable while the split was invisible.
            ShareSheet(items: [share.caption, share.url]) { completed in
                guard !share.isBoard else { return }
                guard completed else {
                    analytics.log(.challengeShareCancelled(puzzleID: puzzle.id))
                    return
                }
                analytics.log(share.isRematch
                    ? .challengeRematchSent(puzzleID: puzzle.id)
                    : .challengeSent(puzzleID: puzzle.id))
                recordOutgoing(rematch: share.isRematch)
                grantSenderFreezeIfDue()
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
        // Taking a friend's challenge earns a freeze — the receiving half of
        // the incentive (the sending half is the share-sheet callback). Tied
        // to the pending challenge just consumed, so a replay can't re-earn.
        if profile.streakFreezes < PlayerProfile.maxStreakFreezes {
            profile.streakFreezes += 1
            context.saveLogged("challenge freeze")
            bonusFreezeEarned = true
        }
    }

    /// The opponent this screen offers a rematch against — only when no
    /// challenge came in with this solve, since that case already has the result
    /// card and its own "Send Result Back". Read after `processIncomingChallenge`
    /// so the row it just wrote can't be mistaken for a past matchup.
    private func loadLastOpponent() {
        guard challenge == nil else { return }
        lastOpponent = challengeHistory.lastOpponent(for: puzzle.id)
    }

    /// The sending half of the challenge incentive: the first completed share
    /// of the day earns a freeze. Once daily, because the sheet callback only
    /// proves the share finished — with no backend, a friend actually
    /// receiving it can't be verified, and unlimited grants would turn the
    /// share button into a freeze faucet.
    private func grantSenderFreezeIfDue() {
        let today = Calendar.current.startOfDay(for: Date()).timeIntervalSinceReferenceDate
        guard challengeFreezeLastDay != today,
              profile.streakFreezes < PlayerProfile.maxStreakFreezes else { return }
        challengeFreezeLastDay = today
        profile.streakFreezes += 1
        context.saveLogged("challenge freeze")
        withAnimation { bonusFreezeEarned = true }
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
        let caption = "Can you beat me? I solved \"\(puzzle.title)\" in \(TimeFormat.clock(seconds)) — Bible Crossword. Solve it and you'll earn a streak freeze 🧊"
        challengeShare = ChallengeShare(url: url, caption: caption, isRematch: rematch)
        // Sent/cancelled is logged by the share sheet's callback — presenting
        // the sheet proves intent, not a send.
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

    // MARK: - Quest continuation

    /// The solved puzzle's place in its Journey. Unlike the pack card there is
    /// deliberately no "next puzzle" button: the quest's whole frame is one
    /// step a day, so the card banks today's step and points at tomorrow.
    private struct QuestContext {
        let quest: QuestLine
        let progress: QuestProgress
    }

    private func loadQuestContext() {
        guard let quest = puzzleProvider.quests(containing: puzzle.id).first else { return }
        let records = (try? context.fetch(FetchDescriptor<PuzzleRecord>())) ?? []
        let recordsByID = Dictionary(records.map { ($0.puzzleID, $0) }, uniquingKeysWith: { a, _ in a })
        questContext = QuestContext(
            quest: quest,
            progress: QuestProgress(quest: quest, recordsByID: recordsByID)
        )
    }

    @ViewBuilder
    private func questCard(_ ctx: QuestContext) -> some View {
        HStack(spacing: Theme.Spacing.m) {
            Image(systemName: ctx.progress.isComplete ? "checkmark.seal.fill" : ctx.quest.coverSymbol)
                .font(.title)
                .foregroundStyle(ctx.quest.accent)
            VStack(alignment: .leading, spacing: 2) {
                if ctx.progress.isComplete {
                    Text("\(ctx.quest.title) — Journey complete!")
                        .font(.subheadline.weight(.semibold))
                    Text("Every step of the path is walked.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(ctx.quest.title) · step \(ctx.progress.solved) of \(ctx.progress.total)")
                        .font(.subheadline.weight(.semibold))
                    Text("The next step will be waiting tomorrow.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ctx.quest.accent.opacity(0.12), in: .rect(cornerRadius: Theme.cornerRadius, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ctx.progress.isComplete
            ? "\(ctx.quest.title) Journey complete."
            : "\(ctx.quest.title), step \(ctx.progress.solved) of \(ctx.progress.total) done. The next step will be waiting tomorrow.")
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
                    paywallEntry = PaywallEntry(source: .packCompletion)
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
            paywallEntry = PaywallEntry(source: .miniCompletion)
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

    /// The badge and the two facts of the solve: the time as the title, the
    /// puzzle's name under it. The time used to be a stat tile below a generic
    /// "Puzzle Completed!" — the headline is the result now. The mark is the
    /// grid the player just filled, not a checkmark (see `CelebrationBadge`).
    private var header: some View {
        VStack(spacing: Theme.Spacing.m) {
            CelebrationBadge(grid: puzzle.grid, confetti: "puzzle_complete", size: 88, showsRim: false)

            VStack(spacing: Theme.Spacing.xs) {
                Text("Solved in \(TimeFormat.clock(seconds))")
                    .font(.title.bold())
                    .monospacedDigit()
                Text(puzzle.title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            // One stop: "Solved in 4:12, The New Jerusalem".
            .accessibilityElement(children: .combine)
        }
        .padding(.top, Theme.Spacing.s)
    }

    /// The solve's own numbers, given the weight a results screen owes them.
    ///
    /// These used to be one grey `.subheadline` line under the title — smaller
    /// than the upsell card's body text, on the one screen whose whole job is to
    /// report them. Tiles put the numbers first and the labels under, and the
    /// week row underneath turns a bare streak count into a visible run: this is
    /// the moment today's dot fills, so it's the moment worth showing it.
    /// Time, streak, the week row — and, when it's due, the reminder ask in
    /// one compact row under the week. The week row is already a picture of
    /// tomorrow, and this card is the one thing on the screen every player
    /// sees: the ask used to be its own card far below the fold, where 76 of
    /// 79 players never reached it. Grouped so VoiceOver reads the stats as
    /// one element and still lands on the ask's buttons.
    private var scorecard: some View {
        VStack(spacing: Theme.Spacing.m) {
            scorecardStats
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(scorecardLabel)

            if showReminderAsk {
                Rectangle()
                    .fill(Color.primary.opacity(0.08))
                    .frame(height: 1)

                ReminderAskRow(
                    profile: profile,
                    surface: .completion,
                    onFinish: { withAnimation { showReminderAsk = false } }
                )
                .transition(.opacity)
            }
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity)
        .elevatedCard()
    }

    /// One line for the streak and a row of dots for the week. The old
    /// icon–number–label tiles and lettered 42pt circles were the loudest
    /// things on the screen for two facts.
    private var scorecardStats: some View {
        VStack(spacing: Theme.Spacing.s) {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: "flame.fill")
                    .foregroundStyle(.orange)
                Text(streakLine)
            }
            .font(.headline)

            WeekRow(completedWeekdays: completedWeekdays, style: .dots)
        }
        .frame(maxWidth: .infinity)
    }

    /// "1-day streak" is a true but bleak thing to show someone who just lost
    /// a long one. Naming it a new streak says the same number and frames it
    /// as a start.
    private var streakLine: String {
        guard streak > 0 else { return "Solved today" }
        return isComeback ? "New streak · day \(streak)" : "\(streak)-day streak"
    }

    private var scorecardLabel: String {
        var parts: [String] = []
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
    /// The verse is content, not chrome: set straight on the paper, with the
    /// reference and a text link under it. It used to be a tinted card, the
    /// third container style on one screen.
    private var verseCard: some View {
        VStack(spacing: Theme.Spacing.s) {
            Text("Today's Verse")
                .kicker()
            Text("“\(puzzle.verse)”")
                .font(.scripture(.title3))
                .lineSpacing(4)
                .multilineTextAlignment(.center)
            Text(puzzle.reference)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            memorizeButton

            Button {
                analytics.log(.scriptureOpened(reference: puzzle.reference, source: "puzzle_completion"))
                readerRouter.open(reference: puzzle.reference, source: "puzzle_completion")
                onHome()
            } label: {
                Label("Read the passage", systemImage: "book")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderless)
            .tint(Theme.accent)
            .padding(.top, Theme.Spacing.xs)
            .accessibilityHint("Closes this screen and opens the passage in the reader")
        }
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, Theme.Spacing.s)
        .frame(maxWidth: .infinity)
    }

    /// "Try it from memory": the verse they just filled in, as the level-1
    /// cloze grid, one tap away. A pill, not a link — this screen has already
    /// run that comparison: the chain pill is tapped by 111 of 203 solvers a
    /// month, the "Read the passage" link under this verse by 2. Absent when
    /// the free shelf is full rather than shown to bounce off the paywall
    /// (38 opens, 0 buys in the 30 days to 2026-09-10). A verse already on
    /// the shelf offers practice instead of a second add.
    @ViewBuilder
    private var memorizeButton: some View {
        if MemoryCloze.isEligible(verseText: puzzle.verse) {
            let key = MemoryCloze.referenceKey(puzzle.reference)
            let held = memoryVerses.entry(for: key) != nil
            if held || memoryVerses.canStartNewVerse(isPremium: store.isPremium) {
                Button {
                    if !held {
                        memoryVerses.start(reference: puzzle.reference, verseText: puzzle.verse)
                        analytics.log(.memoryVerseAdded(reference: puzzle.reference, source: "completion"))
                    }
                    // The same route as the chain pill: a link, so the push
                    // lands a turn after this cover and the grid are gone.
                    var link = URLComponents()
                    link.scheme = "biblecrossword"
                    link.host = "memory"
                    link.queryItems = [
                        URLQueryItem(name: "ref", value: key),
                        URLQueryItem(name: "src", value: "completion"),
                    ]
                    if let url = link.url {
                        openURL(url)
                        onHome()
                    }
                } label: {
                    Label(held ? "Practice it from memory" : "Try it from memory", systemImage: "brain")
                }
                .buttonStyle(.pillTonal)
                .padding(.top, Theme.Spacing.xs)
                .accessibilityHint("Closes this screen and opens the verse as a memory grid")
            }
        }
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

    /// Ask for a rating at the happiest moments in the loop — the triggers and
    /// their spacing live in `ReviewAsk.decide`; this just spends the flag the
    /// verdict names and calls the system prompt, which Apple further
    /// rate-limits. No sentiment card in front of it any more: in 2.5–2.6 the
    /// card sat below the fold and 15 of 15 players who were shown it never
    /// answered, so the ladder produced zero prompts while the direct call in
    /// 2.3–2.4 produced 28 in the same span — and the store rating it was
    /// meant to protect stood at 4.86.
    private func maybeRequestReview() {
        let state = ReviewAsk.State(
            totalCompleted: totalCompleted,
            currentStreak: streak,
            milestoneAsked: reviewPromptMilestone,
            streakAsked: streakReviewPromptShown,
            versionAsked: reviewPromptVersion,
            currentVersion: Self.marketingVersion,
            lastAsk: reviewPromptLastAsk == 0
                ? nil : Date(timeIntervalSinceReferenceDate: reviewPromptLastAsk),
            installedAt: profile.createdAt
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

    // No auto-presented paywall here any more. The first-solve and 3-day-streak
    // sheets (`first_completion`, `streak_3`) were shown to 88 free players in
    // the 30 days to 2026-09-02 and produced one CTA tap and zero purchases,
    // while covering the celebration and pre-empting the reminder ask. The
    // paywall is still reachable from this screen through the mini upsell
    // card and the locked-pack row — asks the player chooses to tap.

    /// Offer the daily reminder at the moment the product just proved its
    /// value — but only when this screen carries no other ask: a challenge
    /// result or a review sheet outrank it, and `ReminderAsk.decide` enforces
    /// the cross-surface caps (one ask per day anywhere, one per session,
    /// first three solves only).
    private var reminderAskEligible: Bool {
        guard challenge == nil, !didRequestReview else { return false }
        // No mini-upsell suppression here any more. It used to stand this ask
        // down on every Mini solve past the first — and for a free player
        // almost every completion is a Mini, so of 78 onboarding decliners in
        // the 30 days to 2026-08-23, only 8 ever met a re-ask and 1 reached
        // the system dialog. The upsell card can show on any other solve; the
        // completion ask has three impressions ever, aimed at the permission
        // grant that gates every retention loop. When this ask fires, the
        // upsell yields for that one screen — see `miniUpsellCard`'s gate.
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
            askedThisSession: ReminderAskSession.asked,
            returnDaySheetShown: didAskReminderAgain,
            isInstallDay: Calendar.current.isDateInToday(profile.createdAt)
        )
    }

    /// The once-ever full ask, over the completion screen of a solve on a
    /// later day than the install. It used to open at app launch on that day
    /// and 29 of 34 players tapped it away to get to the puzzle; here the
    /// puzzle is done and the habit is a fact. Yields to a challenge result
    /// and the review sheet like every other ask, and takes the day's budget
    /// so the inline card stands down. Slides up after the celebration lands.
    private func maybeShowReturnDaySheet() {
        guard challenge == nil, !didRequestReview else { return }
        #if DEBUG
        // Reaching the eligible state takes a real second day; the flag makes
        // the sheet inspectable. Gating is unit-tested (ReminderAskTests).
        let forced = ProcessInfo.processInfo.arguments.contains("-uiForceReminderPrompt")
        #else
        let forced = false
        #endif
        guard forced || ReminderAsk.decide(.returnDaySheet, reminderAskState) else { return }

        reminderAskLastDay = Calendar.current.startOfDay(for: Date()).timeIntervalSinceReferenceDate
        ReminderAskSession.asked = true
        analytics.log(.reminderAskShown(source: ReminderAsk.Surface.returnDaySheet.rawValue))
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            showReturnDaySheet = true
        }
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
        guard reminderAskEligible else { return }

        showReminderAsk = true
        completionReminderAsksShown += 1
        reminderAskLastDay = today
        ReminderAskSession.asked = true
        analytics.log(.reminderAskShown(source: ReminderAsk.Surface.completion.rawValue))
    }

    /// The pinned bar: one primary action, a share icon, and a "more" menu.
    ///
    /// A Mini solved with today's daily still open makes the chain the primary
    /// (the next solve is worth more than anything social). Otherwise the
    /// challenge leads with Share beside it as an icon: the invite opens the
    /// exact puzzle for the friend, carries a streak-freeze reward, and is the
    /// one action on this screen that brings a new player in. Family board
    /// and leaderboard stay in the menu.
    ///
    /// The challenge lived in that menu until 2026-09-07. Before that it was a
    /// card, a pill and a button in the scroll — 60 days to 2026-09-02: 8
    /// senders, everyone else scrolled past — and it was demoted on that read.
    /// But every link sent in that window was also dropped on arrival by a
    /// scheme guard in `RootView.handleDeepLink`, so the read measured a loop
    /// with no receiving end. With the link fixed and a clipboard handoff for
    /// fresh installs, the send earns the primary slot. Readout: senders per
    /// completer against the old 3.6%, and `challenge_opened` finally above 0.
    private var pinnedActions: some View {
        HStack(spacing: Theme.Spacing.s) {
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
            } else if challenge == nil {
                challengeButton
                shareIconButton
            } else {
                // A challenge arrived for this puzzle: the result card already
                // offers "Send Result Back", so Share leads and nothing doubles.
                shareButton(prominent: true)
            }

            moreMenu
        }
        // One presenter for every Share entry in the bar — the pill, the icon,
        // and the menu item — so none of them has to own the sheet.
        .sheet(item: $cardShare) { share in
            ShareSheet(items: share.items) { completed in
                analytics.log(.shareCompleted(kind: "share_card", completed: completed))
            }
        }
    }

    /// The invite, pinned. Same action and name prompt as the menu item had.
    private var challengeButton: some View {
        Button {
            sendChallenge(rematch: lastOpponent != nil)
        } label: {
            Label(challengeTitle, systemImage: "flag.checkered")
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.pillProminent)
        .accessibilityHint("Shares this puzzle and your time with a friend")
    }

    /// Share as a 52pt circle, for the row where the challenge holds the pill.
    private var shareIconButton: some View {
        Button {
            openShareCard()
        } label: {
            Image(systemName: "square.and.arrow.up")
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 52, height: 52)
                .background(Color.primary.opacity(0.08), in: .circle)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Share")
    }

    /// Everything social that isn't the primary: same actions, same name
    /// prompt and share sheets, same events, one tap further away.
    private var moreMenu: some View {
        Menu {
            // When the chain owns the primary slot, Share and the challenge
            // step in here; otherwise both are in the bar already. A challenge
            // that arrived for this puzzle offers "Send Result Back" in the
            // result card — don't double up.
            if chainTarget != nil {
                shareButton(prominent: false)
            }
            if challenge == nil && chainTarget != nil {
                Button {
                    sendChallenge(rematch: lastOpponent != nil)
                } label: {
                    Label(challengeTitle, systemImage: "flag.checkered")
                }
            }
            if board == nil {
                Button {
                    startBoard()
                } label: {
                    Label("Start a Family Board", systemImage: "person.3")
                }
            }
            if puzzle.isMini && gameCenter.isAuthenticated {
                Button {
                    gameCenter.showWeeklyMiniLeaderboard()
                } label: {
                    Label(weeklyRankTitle, systemImage: "trophy")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 52, height: 52)
                .background(Color.primary.opacity(0.08), in: .circle)
                .contentShape(.circle)
        }
        // A Menu label takes the accent tint; the glyph should read as ink.
        .buttonStyle(.plain)
        .accessibilityLabel("More")
        .accessibilityHint("Challenge a friend, start a family board, or see the leaderboard")
    }

    /// `ShareSheet` rather than `ShareLink`: the sheet reports whether the
    /// share went through, and until 2.9 the scorecard — the app's most
    /// shared surface — had no event at all, so its reach was a guess.
    private func shareButton(prominent: Bool) -> some View {
        Button {
            openShareCard()
        } label: {
            shareLabel
        }
        .buttonStyle(PillButtonStyle(emphasis: prominent ? .primary : .tonal))
    }

    /// Builds the scorecard share and hands it to the sheet on `pinnedActions`.
    private func openShareCard() {
        analytics.log(.shareOpened(kind: "share_card"))
        var items: [Any] = []
        if let shareUIImage { items.append(shareUIImage) }
        items.append(shareCaption)
        cardShare = CardShare(items: items)
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
        shareUIImage = renderer.uiImage
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
    let source: PaywallSource
    var id: String { source.rawValue }
}
