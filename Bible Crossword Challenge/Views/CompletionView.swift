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
import Lottie

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
    /// This solve finished a pack or Journey for the first time — a review
    /// moment (`ReviewAsk`).
    var finishedCollection: Bool = false
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
    /// The graduation row under Your First Seven's finished card — see
    /// `graduationRow`. Impression once, only when on screen.
    @State private var graduationRowVisible = false
    @State private var didLogGraduation = false
    /// The widget line, once ever, from the third solve — see `widgetOffer`.
    @AppStorage("widgetOfferShown") private var widgetOfferShown = false
    @State private var showsWidgetOffer = false
    @State private var didLogWidgetOffer = false
    @State private var showWidgetHow = false
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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The solve time is the hero's headline; it scales with Dynamic Type from
    /// a display size, and shrinks to fit rather than wrap.
    @ScaledMetric(relativeTo: .largeTitle) private var heroTimeSize: CGFloat = 64

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
        // The hero runs edge to edge from under the top bar; everything after
        // it sits in the readable column on the paper. Short content leaves
        // paper under the verse rather than centring — the hero is the top
        // of the page and has to stay there.
        GeometryReader { viewport in
            ScrollView {
                VStack(spacing: 0) {
                    hero

                    // 32 between groups (2026-11-03): hero, streak, verse,
                        // pack read as separate groups, as a results screen
                        // sets them, rather than one run of blocks.
                    VStack(spacing: Theme.Spacing.xl) {
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

                        if showsWidgetOffer {
                            widgetOffer
                                .onScrollVisibilityChange(threshold: 0.6) { visible in
                                    guard visible, !didLogWidgetOffer else { return }
                                    didLogWidgetOffer = true
                                    analytics.log(.widgetOfferShown)
                                }
                        }

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
                            if let next = graduationJourney(questContext) {
                                graduationRow(next)
                                    .onScrollVisibilityChange(threshold: 0.6) { visible in
                                        graduationRowVisible = visible
                                        logGraduationIfSeen()
                                    }
                                    .onChange(of: showReturnDaySheet) { logGraduationIfSeen() }
                            }
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
                    .padding(.horizontal, Theme.Spacing.m + Theme.Spacing.xs)
                    .padding(.vertical, Theme.Spacing.l)
                    .frame(maxWidth: 520)
                    .frame(maxWidth: .infinity)
                }
                .frame(minHeight: viewport.size.height, alignment: .top)
            }
        }
        .background(Theme.background)
        // A bar, not an inset, so the page fades under it as it does under
        // the system's bars. Only reachable where bars go vertical (27.1+).
        .modifier(RailPrimaryBar(isOn: barsVertical) { railPrimary })
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
            maybeShowWidgetOffer()
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
        .sheet(isPresented: $showWidgetHow) {
            WidgetHowToSheet()
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
                .textContentType(.nickname) // masked in session replay
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
        .background(Theme.surface, in: .rect(cornerRadius: Theme.cornerRadius, style: .continuous))
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
        .background(Theme.surface, in: .rect(cornerRadius: Theme.cornerRadius, style: .continuous))
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
        // A pack a Journey already covers is the Journey here, as on every
        // other screen (`notShadowedByQuests`). Both cards showed on a Life
        // of David daily (2026-11-04): the pack's said "play the next one
        // now" and drove Next Puzzle, the Journey's said "the next step will
        // be waiting tomorrow".
        guard let pack = puzzleProvider.pack(forPuzzle: puzzle.id),
              !PuzzlePack.notShadowedByQuests([pack], quests: puzzleProvider.quests).isEmpty
        else { return }
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
                .foregroundStyle(.secondary)
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
                    Text(ctx.quest.id == BeginnerPath.questID
                         ? "Try another mini now, or come back tomorrow."
                         : "The next step will be waiting tomorrow.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: .rect(cornerRadius: Theme.cornerRadius, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ctx.progress.isComplete
            ? "\(ctx.quest.title) Journey complete."
            : "\(ctx.quest.title), \(ctx.progress.solved) of \(ctx.progress.total) completed.")
    }

    /// The Premium Journey to offer when this solve finished Your First Seven,
    /// for a player without Premium. Nil otherwise.
    ///
    /// Graduation is the path's natural "what's next" (theme B, 2026-11): of
    /// the in-app paywall sources, the ones that showed specific content sold
    /// (Today's Premium row 4 of 13, a locked Journey 2 of 14) and the walls
    /// didn't (hint limit 1 of 46). The path itself never pitches, so this is
    /// the first Premium content a new player is shown after onboarding.
    private func graduationJourney(_ ctx: QuestContext) -> QuestLine? {
        guard ctx.quest.id == BeginnerPath.questID, ctx.progress.isComplete,
              !store.isPremium else { return nil }
        let records = (try? context.fetch(FetchDescriptor<PuzzleRecord>())) ?? []
        let byID = records.byPuzzleID
        return puzzleProvider.quests.first {
            $0.isPremium && !QuestProgress(quest: $0, recordsByID: byID).isComplete
        }
    }

    /// One quiet row under the finished path card, worn like the completion
    /// offer: the gold crown and the next Journey by name. A row the player
    /// taps, below the verse — never a sheet.
    private func graduationRow(_ quest: QuestLine) -> some View {
        Button {
            paywallEntry = PaywallEntry(source: .pathGraduation)
        } label: {
            Label {
                Text("Next: \(quest.title), a \(quest.puzzleIDs.count)-step Journey")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "crown.fill")
                    .foregroundStyle(Theme.badgeRim)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens Premium options")
        .accessibilityIdentifier("graduationOffer")
    }

    private func logGraduationIfSeen() {
        guard graduationRowVisible, !didLogGraduation,
              !showReturnDaySheet, paywallEntry == nil else { return }
        didLogGraduation = true
        analytics.log(.upsellShown(source: PaywallSource.pathGraduation.rawValue))
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
                    .foregroundStyle(.secondary)
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
            .background(Theme.surface, in: .rect(cornerRadius: Theme.cornerRadius, style: .continuous))
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
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(ctx.pack.title) · \(ctx.progress.solved) of \(ctx.progress.total)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        // The count, not just the wall: "3 more puzzles in
                        // this pack" is the reason to keep going, said at the
                        // moment the pack has proved itself. Open, how far
                        // along rather than "Next: …" (2026-11-03) — the bar's
                        // Next Puzzle already names the next step.
                        // No bar open (2026-11-04): the title counts it, and
                        // the bar was the heaviest mark under the verse.
                        if locked {
                            Text(lockedPackLine(ctx))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.forward")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(Theme.Spacing.l)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.surface, in: .rect(cornerRadius: Theme.cornerRadius, style: .continuous))
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

    /// The keepsake: the time as a display numeral on a full-bleed blue field,
    /// with the grid the player just filled set faintly behind it — a picture
    /// of what they did, different every day. It replaced an 88pt badge over
    /// "Solved in 4:12" (2026-10-24): the badge and the line said "done" twice,
    /// and the time — the one thing the player earned — was body-weight text.
    /// The confetti that used to burst behind the badge bursts over the hero.
    private var hero: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Label("Solved", systemImage: "checkmark")
                .font(.footnote.weight(.bold))
                .foregroundStyle(FeatureTint.solved)
                .padding(.vertical, 5)
                .padding(.horizontal, 12)
                .background(FeatureTint.solved.opacity(0.14), in: .capsule)
                .padding(.bottom, Theme.Spacing.s)

            Text(TimeFormat.clock(seconds))
                .font(.system(size: heroTimeSize, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)

            Text(heroSubtitle)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.primary)
        // One stop: "Solved, 4:12, The New Jerusalem · Daily · Friday, October 24".
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        // The cards' own column and inset, so the time and the cards share
        // one left edge. Padded inside the 520 the cards use, it sat 20pt
        // left of them once the window outgrew the column (iPhone Duo open).
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Spacing.m + Theme.Spacing.xs)
        .frame(maxWidth: 520)
        .padding(.top, 72)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity)
        .background {
            GeometryReader { geo in
                // About 20pt a square whatever the size, so a 7×7 Mini reads
                // as the same faint texture as a 15×15 rather than as big blocks.
                let full = min(300, CGFloat(puzzle.size) * 20)
                // Room beside the column: the grid sits low in that gutter,
                // as it always has. Without it (a phone, the folded Duo) it
                // went behind the subtitle, so it moves up beside the time,
                // which is short, and stays clear of the line under it.
                let gutter = (geo.size.width - 520) / 2
                let roomy = gutter >= 100
                let side = roomy ? min(full, gutter + 24) : min(full, geo.size.width * 0.35)
                // Half strength: on a 15×15 the stronger texture read as a
                // pattern behind the time rather than a texture.
                GridThumbnail(grid: puzzle.grid, tint: Color.primary.opacity(0.025), gap: 3, cropsToContent: true)
                    .frame(width: side, height: side)
                    .frame(maxWidth: .infinity, maxHeight: .infinity,
                           alignment: roomy ? .bottomTrailing : .topTrailing)
                    .offset(x: 24, y: roomy ? -20 : 56)
            }
        }
        .overlay {
            if !reduceMotion {
                LottieView(animation: .named("puzzle_complete"))
                    .configure { $0.contentMode = .scaleAspectFit }
                    .playing(loopMode: .playOnce)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        // On the page's own ground since 2026-11-03, as every hero in the
        // app is: the solid blue band was the last full-colour block left,
        // and blue is the action's colour — the bar's button below.
    }

    /// "The Shepherd King · Daily · Friday, October 24" — what was solved,
    /// which of the day's puzzles it was, and when. The kind is named only
    /// for the day's own puzzles; a pack's puzzle is its title alone.
    private var heroSubtitle: String {
        var parts = [puzzle.title]
        if puzzle.isMini {
            parts.append("Mini")
        } else if puzzle.isSunday {
            parts.append("Sunday Special")
        } else if puzzle.id == puzzleProvider.dailyPuzzle()?.id {
            parts.append("Daily")
        }
        parts.append(Date().formatted(.dateTime.weekday(.wide).month(.wide).day()))
        return parts.joined(separator: " · ")
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
        .padding(20)
        .frame(maxWidth: .infinity)
        .elevatedCard(cornerRadius: Theme.featureCornerRadius)
    }

    /// The streak on one line — flame, run, and on its right a note when the
    /// run is the longest yet — over the week, each day lettered and checked
    /// once solved, today ringed (design canvas, 2026-10-24). The bare row of
    /// unlabelled dots it replaced said a week had gone by without saying
    /// which days.
    private var scorecardStats: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
                Image(systemName: "flame.fill")
                    .foregroundStyle(FeatureTint.streak)
                Text(streakLine)
                    .font(.headline)
                Spacer(minLength: Theme.Spacing.s)
                if let streakNote {
                    Text(streakNote.text)
                        .font(streakNote.isMilestone ? .subheadline.weight(.semibold) : .subheadline)
                        .foregroundStyle(streakNote.isMilestone ? AnyShapeStyle(FeatureTint.streak) : AnyShapeStyle(.secondary))
                }
            }

            WeekRow(completedWeekdays: completedWeekdays, style: .circles)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The one thing about the run worth saying today, most notable first:
    /// a milestone, the week's goal just met, "Your longest yet", or how the
    /// week stands against its goal.
    ///
    /// The weekly goal (2026-10-25) is the forgiving half of the habit: five
    /// days in seven, resetting with the week, so a missed day costs the
    /// streak but not the week. Milestones mark the days a run is worth
    /// stopping for, in the streak's own orange.
    private var streakNote: (text: String, isMilestone: Bool)? {
        if !isComeback, let milestone = Self.milestoneLine(streak) {
            return (milestone, true)
        }
        let thisWeek = completedWeekdays.count
        if thisWeek == Self.weeklyGoal {
            return ("This week's goal met", true)
        }
        if streak > 1, !isComeback, streak >= profile.bestStreak {
            return ("Your longest yet", false)
        }
        guard thisWeek > 0 else { return nil }
        return thisWeek < Self.weeklyGoal
            ? ("\(thisWeek) of \(Self.weeklyGoal) this week", false)
            : ("\(thisWeek) days this week", false)
    }

    /// Days a week the habit asks for.
    static let weeklyGoal = 5

    /// The words for a streak milestone, or nil on an ordinary day.
    static func milestoneLine(_ streak: Int) -> String? {
        switch streak {
        case 7: "A full week"
        case 14: "Two weeks running"
        case 30: "A month in the Word"
        case 50, 100, 200, 300: "\(streak) days"
        case 365: "A whole year"
        default: nil
        }
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
        if let note = streakNote?.text, !note.hasSuffix("this week") {
            parts.append(note)
        }
        return parts.joined(separator: ". ")
    }

    /// The mini→daily chain target: today's full puzzle, offered only when this
    /// solve was a Mini and the daily hasn't been solved yet. Day-one puzzle
    /// completion is the strongest D1 signal we have; this is the moment the
    /// appetite for "one more" exists, so the next solve is one tap away.
    private func loadChainTarget() {
        // A pack's next puzzle, when this solve was in one and the next is
        // open to this player (2026-11-03): "play another" is the screen's
        // most valuable action, and it sat in the pack card below the verse.
        // Journeys stay out — their frame is one step a day.
        if let ctx = packContext, let next = ctx.next,
           !(ctx.pack.isPremium && !store.isPremium) {
            chainTarget = next
            return
        }
        if BeginnerPath.contains(puzzle, provider: puzzleProvider) {
            let records = (try? context.fetch(FetchDescriptor<PuzzleRecord>())) ?? []
            chainTarget = BeginnerPath.next(provider: puzzleProvider, recordsByID: records.byPuzzleID)
            return
        }
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
            // One quiet line since 2026-10-24 (design canvas): the gold crown
            // Premium wears everywhere, and the offer in secondary text. It
            // was a card with a chevron, the screen's second pitch for
            // attention after the bar.
            Label {
                Text(completionOfferLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "crown.fill")
                    .foregroundStyle(Theme.badgeRim)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens Premium options")
    }

    private var completionOfferLine: String {
        if let yearly = store.yearly, let offer = store.introOffer(for: yearly) {
            return "Every pack and Journey, free for \(offer.duration)"
        }
        return "Every pack and Journey with Premium"
    }

    private func maybeShowCompletionOffer() {
        // One ask under the scorecard at a time: the reminder ask, when it's
        // due, outranks the offer, which waits for a later solve unspent.
        guard !store.isPremium, !completionOfferShown, !showReminderAsk,
              !BeginnerPath.contains(puzzle, provider: puzzleProvider) else { return }
        completionOfferShown = true
        showsCompletionOffer = true
    }

    /// The Clue of the Day widget, offered once, from the third solve: by
    /// then the player has a habit for it to serve. Pointed at the
    /// interactive clue rather than the verse since 2026-11-10: a widget
    /// that can be played is a reason to look, and its solve shows the verse
    /// anyway. One quiet line like the
    /// offer's, and never on the same screen as the offer — one ask under the
    /// verse at a time.
    private var widgetOffer: some View {
        Button {
            analytics.log(.widgetOfferTapped)
            showWidgetHow = true
        } label: {
            Label {
                Text("Solve a clue a day from your Home Screen")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                // Grey (2026-11-03): beside the bar's blue button and the
                // verse's two blue links, a third blue item blurred which one
                // was the action.
                Image(systemName: "square.text.square")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows how to add the widget")
    }

    private func maybeShowWidgetOffer() {
        // Not beside the graduation row either: one ask under the verse.
        guard !widgetOfferShown, !showsCompletionOffer, !showReminderAsk,
              questContext.flatMap(graduationJourney) == nil,
              profile.totalPuzzlesCompleted >= 3 else { return }
        widgetOfferShown = true
        showsWidgetOffer = true
    }

    private func logCompletionOfferIfSeen() {
        guard completionOfferVisible, !didLogCompletionOffer,
              !showReturnDaySheet, paywallEntry == nil else { return }
        didLogCompletionOffer = true
        analytics.log(.upsellShown(source: PaywallSource.completionOffer.rawValue))
    }

    /// The verse on the paper, left-aligned as the rest of the app sets
    /// Scripture (design canvas, 2026-10-24): serif, the reference under it on
    /// the left and "Read the passage" on the right, then the memory door as
    /// one quiet link. It was centred under a "Today's Verse" label with the
    /// memory door as a full-width grey pill — the biggest control on the
    /// screen after the bar.
    private var verseCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            // A size down from title2 (2026-11-03): at title2 under a large
            // time and a full card the screen read as crowded.
            Text(puzzle.verse)
                .font(.scripture(.title3))
                .tracking(-0.2)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            Text(puzzle.reference)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            // The two doors on one line, falling back to two where they
            // don't fit (large text, a narrow fold).
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Theme.Spacing.l) { verseLinks }
                VStack(alignment: .leading, spacing: Theme.Spacing.s) { verseLinks }
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var verseLinks: some View {
                Button {
                    analytics.log(.scriptureOpened(reference: puzzle.reference, source: "puzzle_completion"))
                    readerRouter.open(reference: puzzle.reference, source: "puzzle_completion")
                    onHome()
                } label: {
                    Label("Read the passage", systemImage: "book")
                        .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.borderless)
                .tint(Theme.accent)
                .accessibilityHint("Closes this screen and opens the passage in the reader")
            memorizeButton
    }

    /// "Try it from memory": the verse they just filled in, as the level-1
    /// cloze grid, one tap away. A quiet link since 2026-10-24 (design
    /// canvas). It was a pill on the evidence that the chain pill is tapped by
    /// 111 of 203 solvers a month and the "Read the passage" link by 2 —
    /// watch `memory_verse_added` with source "completion" for the cost. Absent when
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
                        .font(.subheadline.weight(.medium))
                }
                // A link since 2026-10-24, beside the passage link it
                // belongs with, not a pill competing with the bar's action.
                .buttonStyle(.borderless)
                .tint(Theme.accent)
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

    /// The badge just earned, as Profile → Badges shows it (2026-11-03): its
    /// own medal, "Badge earned", its name and what earned it. It was a
    /// generic blue star in a gold ring over "New Achievement!" and a second,
    /// different icon per badge — clip art, and not the object the player
    /// then finds in Profile.
    private var achievementsCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            ForEach(Array(newAchievements.enumerated()), id: \.element.id) { index, achievement in
                HStack(spacing: Theme.Spacing.m) {
                    BadgeMedal(symbol: achievement.symbol, size: 56)
                        .overlay {
                            // The burst on the first medal only; Reduce Motion
                            // keeps the medal and drops the confetti.
                            if index == 0, !reduceMotion {
                                LottieView(animation: .named("achievement_unlock"))
                                    .configure { $0.contentMode = .scaleAspectFit }
                                    .playing(loopMode: .playOnce)
                                    .frame(width: 140, height: 140)
                                    .allowsHitTesting(false)
                                    .accessibilityHidden(true)
                            }
                        }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Badge earned")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(achievement.title)
                            .font(.headline)
                        Text(achievement.detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(Theme.Spacing.m + Theme.Spacing.xs)
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
            finishedCollection: finishedCollection,
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
            // Nothing to spend: each finished collection is its own moment,
            // and the gap and Apple's cap pace them.
            case .collection, .periodic: break
            }
            reviewPromptLastAsk = Date().timeIntervalSinceReferenceDate
            analytics.log(.reviewPromptRequested(
                trigger: trigger.analyticsValue, totalCompleted: totalCompleted))
            #if DEBUG
            // Screenshot helper: the system sheet would sit over the shot.
            if ProcessInfo.processInfo.arguments.contains("-uiNoReview") { return }
            #endif
            requestReview()
        })
    }

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
    /// The exit is leading since 2026-10-24, as the design draws it and as
    /// the Premium page sets its ✕: the cover opens over the game, whose back
    /// button sits at that spot, so the exit lands under the hand that just
    /// used it. "…" moved down to the action bar beside Share.
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                onHome()
            } label: {
                Label("Close", systemImage: "xmark")
            }
        }
        // On a side rail the primary leaves the bar for the foot of the page
        // (`railPrimary`): the rail draws an item as its glyph alone, and the
        // screen's one call to action read as an unlabeled ▶ (iPhone Duo,
        // 2026-11-05).
        if !barsVertical {
            ToolbarItem(placement: .bottomBar) {
                primaryAction
            }
        }
        if chainTarget == nil && challenge == nil {
            ToolbarItem(placement: .bottomBar) {
                shareButton(prominent: false)
            }
        }
        if hasOverflowActions {
            ToolbarItem(placement: .bottomBar) {
                Menu {
                    overflowActions
                } label: {
                    Label("More", systemImage: "ellipsis")
                }
            }
        }
    }

    /// The screen's one primary: the next puzzle when there is one, else
    /// the challenge, else (a challenge arrived for this puzzle, and the
    /// result card already offers "Send Result Back") Share.
    @ViewBuilder
    private var primaryAction: some View {
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
                barLabel(chainTitle, systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .accessibilityHint("Opens \(chainTarget.title)")
            .accessibilityIdentifier("completionNextPuzzle")
        } else if challenge == nil {
            challengeButton
        } else {
            shareButton(prominent: true)
        }
    }

    /// The primary as a full-width button pinned at the foot of the page,
    /// for when the bars are a side rail. Same column as the cards above.
    private var railPrimary: some View {
        primaryAction
            .controlSize(.large)
            .buttonBorderShape(.capsule)
            .padding(.horizontal, Theme.Spacing.m + Theme.Spacing.xs)
            .padding(.vertical, Theme.Spacing.s)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
    }

    /// The bar's "next" label: the pack's next puzzle, the beginner path's
    /// next Mini, or today's full puzzle after a Mini.
    private var chainTitle: String {
        if let next = packContext?.next, next.id == chainTarget?.id { return "Next Puzzle" }
        return BeginnerPath.contains(puzzle, provider: puzzleProvider) ? "Next Mini" : "Play Today's Full Puzzle"
    }

    /// The invite, in the bar. Same action and name prompt as the menu item had.
    private var challengeButton: some View {
        Button {
            sendChallenge(rematch: lastOpponent != nil)
        } label: {
            barLabel(challengeTitle, systemImage: "flag.checkered")
        }
        // Blue, the app's action colour, since the hero left blue (2026-11-03).
        .buttonStyle(.borderedProminent)
        .tint(Theme.accent)
        .accessibilityHint("Shares this puzzle and your time with a friend")
    }

    /// A bar primary's label: the words alone on a phone, where a bottom bar
    /// would reduce a Label to its glyph and the design sets the pill as text;
    /// icon and words across the column when the rail sends it to the page.
    @ViewBuilder
    private func barLabel(_ title: String, systemImage: String) -> some View {
        if barsVertical {
            Label(title, systemImage: systemImage)
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
        } else {
            Text(title)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, Theme.Spacing.s)
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
            .tint(Theme.accent)
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

/// How to add the Clue of the Day widget. iOS has no call that adds one for
/// the player, so the three steps are the whole of it.
private struct WidgetHowToSheet: View {
    @Environment(\.dismiss) private var dismiss

    private let steps = [
        "Touch and hold an empty spot on your Home Screen.",
        "Tap Edit, then Add Widget.",
        "Search for Bible Crossword and choose Clue of the Day.",
    ]

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                Text("One clue a day, solved by tapping letters right on your Home Screen. Get it and today's verse appears, with your streak beside it.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.m) {
                            Text("\(index + 1)")
                                .font(.headline)
                                .monospacedDigit()
                                .foregroundStyle(Theme.accent)
                            Text(step)
                                .font(.body)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(Theme.Spacing.m + Theme.Spacing.xs)
            .navigationTitle("Add the clue widget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

/// Pins the completion's primary at the foot of the page while the bars are
/// a side rail. `safeAreaBar` gives it the scroll edge the system bars get;
/// before iOS 26 the rail never appears, so there is nothing to pin.
private struct RailPrimaryBar<Bar: View>: ViewModifier {
    var isOn: Bool
    @ViewBuilder var bar: () -> Bar

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.safeAreaBar(edge: .bottom, spacing: 0) {
                if isOn { bar() }
            }
        } else {
            content
        }
    }
}
