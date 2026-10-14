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
    /// The solve, rendered for sharing. Built in `CrosswordGameView` where the
    /// finished grid is in scope — this screen has no other use for cell state.
    let resultGrid: ShareGrid.Render
    /// Hints the player actually asked for. The starter gift is free by design
    /// and never lands here, which is what lets the stat line say "no hints"
    /// honestly for a player who was handed a foothold.
    let hintsUsed: Int
    var earnedFreeze: Bool = false
    /// True when this solve restarted a streak that had broken. Only changes how
    /// the streak reads — a comeback deserves naming, not a second celebration
    /// competing with achievements and pack completions.
    var isComeback: Bool = false
    var totalCompleted: Int = 0
    let onHome: () -> Void

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
    /// The completion offer is shown once per device, ever — see `completionOffer`.
    @AppStorage("completionOfferShown") private var completionOfferShown = false
    /// Latched on appear so the row stays put for this screen once the
    /// once-only flag above has been spent.
    @State private var showsCompletionOffer = false
    /// The row is on screen (scrolled into view, not under a sheet) — the
    /// impression is logged only then, so the tap rate isn't diluted by
    /// views nobody saw.
    @State private var completionOfferVisible = false
    @State private var didLogCompletionOffer = false
    @State private var showReturnDaySheet = false
    /// The review prompt and the return-day sheet wait for the celebration to
    /// land. Cancelled if the screen closes first, so an ask the player never
    /// saw isn't logged as shown or spent.
    @State private var delayedAsks: [Task<Void, Never>] = []
    /// Decided once on appear so spending an impression can't hide the card
    /// mid-view.
    @State private var showReminderAsk = false

    private var kindLabel: String {
        switch puzzle.kind ?? .daily {
        case .mini: return "Mini"
        case .sunday: return "Sunday Special"
        case .daily: return "Daily"
        }
    }

    /// Time, help taken, streak — the three things two players can compare.
    private var statLine: String {
        let help = hintsUsed == 0
            ? "no hints"
            : "\(hintsUsed) hint\(hintsUsed == 1 ? "" : "s")"
        return "\(TimeFormat.clock(seconds)) · \(help) · 🔥 \(streak)"
    }

    /// Plain text on purpose: the whole mechanic is that this can be pasted
    /// into any thread. Nothing here is a link preview or an attachment.
    private var shareCaption: String {
        var text = "Bible Crossword · \(kindLabel) · “\(puzzle.title)”"
        if !resultGrid.isEmpty { text += "\n\n\(resultGrid.text)" }
        text += "\n\n\(statLine)"
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
    /// Whether the bars are a side rail. The bar's primary actions keep
    /// their words on a phone, which takes a custom view — a bottom bar
    /// reduces a Label to its glyph — and a rail can't carry a custom view,
    /// so they become Labels there. See `barLabel`.
    @State private var barsVertical = false

    var body: some View {
        // A navigation stack for its bars alone. The close button and the
        // action bar are toolbar items, so the system owns where they go —
        // top and bottom on a phone, the side rail on iPhone Duo — along
        // with the scroll edges under them.
        NavigationStack {
            content
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
                .observeVerticalBars($barsVertical)
        }
    }

    private var content: some View {
        // Short content (the common case now: header, scorecard, verse)
        // centres between the top and the bottom bar instead of leaving
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

                    if showsCompletionOffer {
                        completionOffer
                            .onScrollVisibilityChange(threshold: 0.6) { visible in
                                completionOfferVisible = visible
                                logCompletionOfferIfSeen()
                            }
                            // Already in view under the day-2 sheet: counts
                            // once the sheet goes.
                            .onChange(of: showReturnDaySheet) { logCompletionOfferIfSeen() }
                    }

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

                }
                .padding(Theme.Spacing.l)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
                .frame(minHeight: viewport.size.height)
            }
        }
        .background(Theme.background)
        // One presenter for every Share entry in the bar — the pill, the icon,
        // and the menu item — so none of them has to own the sheet.
        .sheet(item: $cardShare) { share in
            ShareSheet(items: share.items) { completed in
                analytics.log(.shareCompleted(kind: "share_card", completed: completed))
            }
        }
        .onAppear {
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
            maybeShowCompletionOffer()
        }
        .onDisappear {
            delayedAsks.forEach { $0.cancel() }
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
        let recordsByID = records.byPuzzleID
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
        let recordsByID = records.byPuzzleID
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
                        // The count, not just the wall: "3 more puzzles in
                        // this pack" is the reason to keep going, said at the
                        // moment the pack has proved itself.
                        Text(locked ? lockedPackLine(ctx) : "Next: \(next.title)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.forward")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
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

    private func lockedPackLine(_ ctx: PackContext) -> String {
        let left = max(ctx.progress.total - ctx.progress.solved, 0)
        let noun = left == 1 ? "puzzle" : "puzzles"
        return "\(left) more \(noun) in this pack · keep going with Premium"
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
    /// The second ask: one row under the verse, once, on a free player's
    /// first completion after this shipped. The onboarding paywall lands 30
    /// seconds into the app and 92% leave it; the in-app buyers bought ~20
    /// hours in, after playing. This is the first moment they have.
    ///
    /// Below the verse, never above it (the verse is this screen's reward),
    /// and a row the player taps rather than a sheet — the auto-paywall on
    /// completion was removed 2026-09-02. It sells what retained players use
    /// (packs, Journeys, memory verses) rather than puzzle counts; the old
    /// `mini_completion` card that sold "more puzzles" here got 0 taps of 15.
    private var completionOffer: some View {
        Button {
            paywallEntry = PaywallEntry(source: .completionOffer)
        } label: {
            HStack(spacing: Theme.Spacing.m) {
                RowIcon(symbol: "brain", tint: FeatureTint.memory)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Every pack, every Journey")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(completionOfferSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(Theme.Spacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .elevatedCard()
            .contentShape(.rect)
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityHint("Opens Premium options")
    }

    private var completionOfferSubtitle: String {
        if let yearly = store.yearly, let offer = store.introOffer(for: yearly) {
            return "Free for \(offer.duration) · unlimited verses"
        }
        return "Unlimited verses with Premium"
    }

    private func maybeShowCompletionOffer() {
        guard !store.isPremium, !completionOfferShown else { return }
        completionOfferShown = true
        showsCompletionOffer = true
    }

    private func logCompletionOfferIfSeen() {
        guard completionOfferVisible, !didLogCompletionOffer,
              !showReturnDaySheet, paywallEntry == nil else { return }
        didLogCompletionOffer = true
        analytics.log(.upsellShown(source: PaywallSource.completionOffer.rawValue))
    }

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
        // Claimed now so the other asks on this screen yield to it; spent
        // only once the prompt is actually requested.
        didRequestReview = true
        delayedAsks.append(Task {
            // Let the celebration land before the system sheet appears. A
            // screen closed in the meantime cancels the sleep: nothing spent.
            guard (try? await Task.sleep(for: .seconds(2))) != nil else { return }
            switch trigger {
            case .milestone(let milestone): reviewPromptMilestone = milestone
            case .streak: streakReviewPromptShown = true
            case .version: break
            }
            // Any ask spends this version's re-arm — the version trigger can't
            // stack a second prompt onto a version that already asked.
            reviewPromptVersion = Self.marketingVersion
            reviewPromptLastAsk = Date().timeIntervalSinceReferenceDate
            analytics.log(.reviewPromptRequested(
                trigger: trigger.analyticsValue, totalCompleted: totalCompleted))
            requestReview()
        })
    }

    private static let marketingVersion =
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""

    // No auto-presented paywall here any more. The first-solve and 3-day-streak
    // sheets (`first_completion`, `streak_3`) were shown to 88 free players in
    // the 30 days to 2026-09-02 and produced one CTA tap and zero purchases,
    // while covering the celebration and pre-empting the reminder ask. The
    // paywall is still reachable from this screen through the locked-pack
    // row — an ask the player chooses to tap. The mini upsell card went on
    // 2026-10-03: 15 players opened it in 30 days and none tapped through.

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
        // the system dialog. The completion ask has three impressions ever,
        // aimed at the permission grant that gates every retention loop.
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
    /// Long enough for the celebration to land. UI tests stretch it with
    /// `-uiAskDelay <seconds>` so closing the screen inside it is
    /// deterministic rather than a race with the simulator's speed.
    private static var returnDaySheetDelay: Duration {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let flag = args.firstIndex(of: "-uiAskDelay"), flag + 1 < args.count,
           let seconds = Double(args[flag + 1]) {
            return .seconds(seconds)
        }
        #endif
        return .seconds(1.5)
    }

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

        // The budget is taken now so the inline card decided next yields to
        // the sheet, and handed back if the screen closes before it slides up.
        let previousDay = reminderAskLastDay
        let previousAsked = ReminderAskSession.asked
        reminderAskLastDay = Calendar.current.startOfDay(for: Date()).timeIntervalSinceReferenceDate
        ReminderAskSession.asked = true
        delayedAsks.append(Task {
            guard (try? await Task.sleep(for: Self.returnDaySheetDelay)) != nil else {
                reminderAskLastDay = previousDay
                ReminderAskSession.asked = previousAsked
                return
            }
            analytics.log(.reminderAskShown(source: ReminderAsk.Surface.returnDaySheet.rawValue))
            showReturnDaySheet = true
        })
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

    /// The bar: one primary action, Share beside it when it isn't the
    /// primary, and everything else social in the system overflow menu.
    /// Separate items rather than one HStack, because the system can only
    /// carry an item it can name — an icon on a side rail, icon and title in
    /// the overflow — and never a custom view.
    ///
    /// The exit is trailing, matching every other ✕ in the app and the
    /// platform: a lone ✕ leading reads as Cancel or Back, which is what the
    /// top-left corner means in a two-button sheet. This does cost something —
    /// the game's own back button sits at the leading spot this cover opens
    /// over, so the exit no longer lands under a hand that just used it.
    /// Consistency won: the player meets this screen far more often from the
    /// Today card than mid-game.
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                onHome()
            } label: {
                Label("Close", systemImage: "xmark")
            }
        }
        if let chainTarget {
            ToolbarItem(placement: .bottomBar) {
                Button {
                    analytics.log(.completionChainTapped(
                        fromPuzzleID: puzzle.id, toPuzzleID: chainTarget.id
                    ))
                    if let url = URL(string: "biblecrossword://puzzle?id=\(chainTarget.id)") {
                        openURL(url)
                        onHome()
                    }
                } label: {
                    barLabel("Play Today's Full Puzzle", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .accessibilityHint("Closes this screen and opens today's full-size puzzle")
            }
        } else if challenge == nil {
            ToolbarItem(placement: .bottomBar) {
                challengeButton
            }
            ToolbarItem(placement: .bottomBar) {
                shareButton(prominent: false)
            }
        } else {
            // A challenge arrived for this puzzle: the result card already
            // offers "Send Result Back", so Share leads and nothing doubles.
            ToolbarItem(placement: .bottomBar) {
                shareButton(prominent: true)
            }
        }
        if hasOverflowActions {
            if #available(iOS 27.0, *) {
                ToolbarOverflowMenu {
                    overflowActions
                }
            } else {
                ToolbarItem(placement: .bottomBar) {
                    Menu {
                        overflowActions
                    } label: {
                        Label("More", systemImage: "ellipsis")
                    }
                }
            }
        }
    }

    /// The invite, in the bar. Same action and name prompt as the menu item had.
    private var challengeButton: some View {
        Button {
            sendChallenge(rematch: lastOpponent != nil)
        } label: {
            barLabel(challengeTitle, systemImage: "flag.checkered")
        }
        .buttonStyle(.borderedProminent)
        .accessibilityHint("Shares this puzzle and your time with a friend")
    }

    /// A bar primary's label: icon and words on a phone, where a bottom bar
    /// would reduce a Label to its glyph; a Label on a side rail, which draws
    /// the icon and can't take a custom view at all.
    @ViewBuilder
    private func barLabel(_ title: String, systemImage: String) -> some View {
        if barsVertical {
            Label(title, systemImage: systemImage)
        } else {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                Text(title)
            }
            .font(.body.weight(.semibold))
        }
    }

    /// Whether the overflow menu has anything in it — an empty ellipsis is
    /// a button that does nothing.
    private var hasOverflowActions: Bool {
        chainTarget != nil
            || (challenge == nil && chainTarget != nil)
            || board == nil
            || (puzzle.isMini && gameCenter.isAuthenticated)
    }

    /// Everything social that isn't the primary: same actions, same name
    /// prompt and share sheets, same events, one tap further away.
    @ViewBuilder
    private var overflowActions: some View {
        // When the chain owns the primary slot, Share and the challenge
        // step in here; otherwise both are in the bar already. A challenge
        // that arrived for this puzzle offers "Send Result Back" in the
        // result card — don't double up.
        if chainTarget != nil {
            Button {
                openShareCard()
            } label: {
                shareLabel
            }
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
    }

    /// Share in the bar: prominent when it leads the row, plain beside the
    /// challenge.
    @ViewBuilder
    private func shareButton(prominent: Bool) -> some View {
        if prominent {
            Button {
                openShareCard()
            } label: {
                barLabel("Share", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.borderedProminent)
        } else {
            Button {
                openShareCard()
            } label: {
                shareLabel
            }
        }
    }

    /// Builds the result block and hands it to the sheet on `content`.
    private func openShareCard() {
        analytics.log(.resultShareOpened(
            puzzleID: puzzle.id,
            puzzleKind: (puzzle.kind ?? .daily).rawValue,
            hintsUsed: hintsUsed,
            seconds: seconds,
            gridCells: resultGrid.cells
        ))
        // Text only. An image alongside it makes Messages render a photo
        // attachment and bury the block underneath — and the block, pasteable
        // into any thread, is the thing worth sending.
        cardShare = CardShare(items: [shareCaption])
    }

    private var shareLabel: some View {
        Label("Share", systemImage: "square.and.arrow.up")
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
