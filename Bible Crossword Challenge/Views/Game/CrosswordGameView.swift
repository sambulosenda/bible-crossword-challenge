//
//  CrosswordGameView.swift
//  Bible Crossword Challenge
//
//  Hosts the grid, clue bar and keyboard, and wires the engine to persistence,
//  hints, streaks, achievements, analytics and the completion screen.
//

import SwiftUI
import SwiftData
import os

struct CrosswordGameView: View {
    let puzzle: Puzzle
    let profile: PlayerProfile
    /// Which surface's navigation pushed this screen (`home` / `library` /
    /// `pack`) — carried on `daily_puzzle_started` so quick closes can be
    /// attributed to an entry point.
    let entrySource: String

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.analytics) private var analytics
    @Environment(\.puzzleProvider) private var puzzleProvider
    @Environment(\.notifications) private var notifications
    @Environment(\.gameCenter) private var gameCenter
    @Environment(\.challengeService) private var challengeService
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(StoreService.self) private var store

    @AppStorage("remindersEnabled") private var remindersEnabled = false
    @AppStorage("reminderMinutes") private var reminderMinutes = ReminderTime.defaultMinutes
    @AppStorage("packNewsEnabled") private var packNewsEnabled = false
    /// Marks wrong letters as they're typed. Seeded per player on first entry
    /// (see `GameViewModel.seedAutoCheckIfNeeded`), toggleable from the hint
    /// menu and Profile → Gameplay.
    @AppStorage("autoCheckErrors") private var autoCheckErrors = false
    /// Zen mode, inverted (Profile → Gameplay): off hides the clock's digits
    /// while the timer keeps recording — see `timerView` for why the
    /// TimelineView must stay mounted either way.
    @AppStorage("showSolveTimer") private var showSolveTimer = true

    @State private var vm: GameViewModel
    @State private var showClues = false
    /// A passage opened from the standing clue panel. Held here, not in the
    /// panel, so folding iPhone Duo (which removes the panel) leaves it open.
    @State private var clueReaderTarget: ReaderRouter.Target?
    /// The window the game actually has, read off the view itself. Size classes
    /// alone misjudge the foldable: iPhone Duo unfolded in landscape reports
    /// regular/regular — an iPad's classes — in 678×466pt, about half an iPad's
    /// height, so the layout decisions below check the size too.
    @State private var containerSize: CGSize = .zero
    /// Whether the system has put this screen's bars on a side rail (iPhone
    /// Duo closed, or open in landscape). A custom toolbar view is never
    /// presented vertically — it would hold a second, horizontal bar open
    /// above the rail — so the clock and streak leave the toolbar for the
    /// solve surface when this is set, and the Hints menu becomes a Label
    /// the rail can draw as an icon.
    @State private var barsVertical = false
    @State private var showCompletion = false
    @State private var showPaywall = false
    /// The hint wall, inline. Tapping a paid hint with no quota left used to
    /// open the full paywall as a sheet over the grid: 317 opens by 82 free
    /// players in the 30 days to 2026-09-02, median 2 seconds on screen, four
    /// purchases — an interstitial people learned to swipe away, ~4 times
    /// each. Now the wall is a one-line notice that names what's still free
    /// (the verse and the checks) and carries the upgrade as a tap.
    @State private var showHintLimitNote = false
    /// The rung the player was refused, so the note can say why rather than
    /// assuming the pool is empty — see `hintLimitHeadline`.
    @State private var hintLimitType: HintType?
    /// Bumped on every wall hit so the auto-dismiss timer restarts from the
    /// latest tap — `.task(id:)` cancels and re-runs on change, where a plain
    /// `.task` would keep the first hit's clock while the note is already up.
    @State private var hintLimitHits = 0
    /// The offer card for a refused hint — raised once per puzzle, on the
    /// first refusal; later ones fall back to the chip. See `HintUpgradeSheet`.
    @State private var hintUpgrade: HintUpgrade?
    @State private var didOfferHintUpgrade = false
    /// What the card ended with, acted on once it has fully dismissed, so a
    /// reveal or the verse sheet never races the card's own dismissal.
    @State private var hintUpgradeOutcome: (HintType, HintUpgradeSheet.Outcome)?
    @State private var newlyUnlocked: [Achievement] = []
    /// Whether this solve crossed a streak milestone that granted a freeze.
    @State private var earnedFreeze = false
    /// True when this solve is the one that restarted a broken streak, so the
    /// completion screen can name it rather than reporting a bare "1-day streak"
    /// to someone who just lost forty.
    @State private var isComeback = false

    /// The break the comeback card was offering to end, and where the attempt
    /// came from. Both are cleared by the solve that ends it — see
    /// `HomeView.startComeback`.
    @AppStorage("pendingStreakBreak") private var pendingStreakBreak = 0
    @AppStorage("comebackSource") private var comebackSource = ""
    /// The "first word's on us" line shown after the gift, auto-dismissed.
    @State private var showStarterGiftNote = false
    /// Wall-clock mark of when this screen appeared, for `puzzle_abandoned`'s
    /// `wall_seconds` — the active clock ticks at ~1s cadence, so a fast
    /// bounce can round to 0 and read the same as a prewarm-and-detach.
    @State private var openedAt = Date()
    /// Grid is full but at least one letter is wrong — nudge instead of leaving
    /// the player stranded wondering why the completion screen didn't appear.
    @State private var showFullMissAlert = false
    /// Reveal Puzzle is the give-up button — never fired from a stray menu tap.
    @State private var showRevealPuzzleConfirm = false
    /// A friend's "beat my time" for this puzzle, captured on entry so the
    /// target chip and result comparison stay stable even after it's consumed.
    @State private var incomingChallenge: ChallengeService.Challenge?
    /// When entering a challenge for an already-solved puzzle, the time to show
    /// on the (immediate) completion screen — the prior solve, not a fresh 0.
    @State private var challengeReplaySeconds: Int?
    /// Abandonment fires once per visit to this screen, but every departure
    /// path (window detach, onDisappear) can fire more than once for one exit.
    @State private var didLogAbandon = false
    /// The passage a verse hint opened, presented as a local sheet (see the
    /// `.sheet(item:)` note below for why not `ReaderRouter`).
    @State private var verseHintTarget: ReaderRouter.Target?
    /// The daily hint pool this player is playing under — the shipped three, or
    /// the tightened one under `FeatureFlag.hintQuotaOne`.
    ///
    /// Resolved once per puzzle rather than read at each use: every read emits
    /// `$feature_flag_called`, and the quota is consulted on every menu open
    /// and every hint tap. Opening a puzzle is the moment the pool takes
    /// effect, which is where the exposure belongs.
    @State private var freeHintLimit = PlayerProfile.freeHintLimit
    /// Treatment arm of `verse-hint-limit`: verse hints past the daily
    /// allowance cost from the pool. See `VerseHintAllowance`.
    @State private var verseHintsMetered = false
    /// Verse hints taken in this puzzle, for the cost and the menu label.
    @State private var verseHintsUsed = 0
    /// Keeps the screen focused so a hardware keyboard can type into the grid.
    @FocusState private var gridFocused: Bool

    init(puzzle: Puzzle, profile: PlayerProfile, entrySource: String) {
        self.puzzle = puzzle
        self.profile = profile
        self.entrySource = entrySource
        // Learning-window players get the shorter stall thresholds — see
        // `GameViewModel.isLearning`. The holdout is read here, at the moment
        // the model that owns the nudge is created, so the exposure lands on
        // players who actually start a puzzle.
        _vm = State(initialValue: GameViewModel(
            puzzle: puzzle,
            learning: profile.isStillLearning,
            stallNudgeEnabled: FeatureFlags.isEnabled(.stallNudge)
        ))
    }

    var body: some View {
        session(layout)
    }

    /// The arrangement for the current window — and only that. Every case
    /// is its own view identity, so a rotation, an iPad resize or iPhone Duo
    /// folding swaps one for another. Anything that must outlive that swap
    /// (the lifecycle, the clock probe, every sheet) lives in `session`,
    /// above the switch: hung off the surface it tore down with it, logging
    /// an abandon and a second start and closing whatever sheet was up.
    private var layout: some View {
        Group {
            switch solveLayout {
            case .sideBySide:
                // A short, wide window: a phone in landscape, or the Duo
                // unfolded and turned. Height is the scarce dimension here —
                // about 400pt, most of it spent on the top bar, clue bar and
                // keypad — so `solveSurface` lays itself out side by side and
                // gives the grid the full height. Decided before the clue
                // panel on purpose: a large phone in landscape is regular
                // width, and grid + keypad + a standing clue list is three
                // columns in 950pt, which leaves the grid narrower than the
                // keyboard. The clue list stays a toolbar sheet here.
                solveSurface()
            case .withCluePanel:
                // iPad: the clue list stops being a sheet and becomes a
                // standing side panel — grid and keyboard on the left, every
                // clue in view on the right, the way a paper crossword sits
                // next to its clues.
                if #available(iOS 27.1, *) {
                    // The system's split owns the seam here too, so the
                    // panel is sized by the arrangement rather than beside
                    // it. The surface inside stays one column: left to its
                    // own arrangement it could split again and put three
                    // columns in the window.
                    ArrangementView {
                        solveSurface(stacked: true)
                    } secondary: {
                        ClueListView(vm: vm, embedded: true, standingReaderTarget: $clueReaderTarget)
                            .splitArrangementLayoutSize(
                                minWidth: Self.cluePanelWidth,
                                idealWidth: Self.cluePanelWidth
                            )
                    }
                    .arrangementViewStyle(.split.axes(.horizontal))
                } else {
                    HStack(spacing: 0) {
                        solveSurface()
                        Divider().ignoresSafeArea(edges: .bottom)
                        ClueListView(vm: vm, embedded: true, standingReaderTarget: $clueReaderTarget)
                            .frame(width: Self.cluePanelWidth)
                    }
                }
            case .stacked, .cluesInColumn:
                solveSurface()
            }
        }
        .background(Theme.background)
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { size in
            containerSize = size
        }
        .observeVerticalBars($barsVertical)
        // The clue list opened as a sheet on a phone-sized window is a second
        // copy of the panel once the window grows enough to stand it.
        .onChange(of: cluesStanding) { _, standing in
            if standing { showClues = false }
        }
    }

    private enum SolveLayout {
        /// Notes, grid, clue bar and keypad in one column. Phones in portrait.
        case stacked
        /// Grid beside a column of clue bar and keypad. Short, wide windows.
        case sideBySide
        /// `stacked` beside a standing clue list. Windows wide enough for both.
        case withCluePanel
        /// `sideBySide` with the clue list standing in the keypad's column,
        /// above the clue bar. A regular window that is wide but short —
        /// iPhone Duo open in landscape, 951×669pt — has no height to stack
        /// a column beside a panel, and plenty beside the grid.
        case cluesInColumn
    }

    /// Whether the clue list is on screen as a panel rather than a sheet.
    private var cluesStanding: Bool {
        solveLayout == .withCluePanel || solveLayout == .cluesInColumn
    }

    /// Width of the standing clue list in `withCluePanel`.
    private static let cluePanelWidth: CGFloat = 340

    /// Under this height a wide window goes side by side even when its size
    /// classes say otherwise: a column of grid, clue bar and keypad cannot
    /// fit, so the grid takes the height and the rest a column beside it.
    private static let shortHeight: CGFloat = 520

    /// Under this height a wide regular window keeps the clue list standing
    /// but moves it into the keypad's column. The Duo open in landscape is
    /// 669pt tall; the shortest iPad in landscape is 744pt and keeps its
    /// full-height panel.
    private static let shortRegularHeight: CGFloat = 720

    /// Which arrangement the window gets. Size classes first, then the
    /// measured size where the classes alone would pick wrong. iPhone Duo
    /// open reports regular/regular like an iPad, in 951×669pt landscape and
    /// 669×951pt portrait: landscape is too short to stack a column beside
    /// the clue panel, so the clues join the keypad's column; portrait is
    /// too narrow to seat a legible keypad beside a panel, so the clue list
    /// stays a sheet. Before the first measurement the classes decide.
    private var solveLayout: SolveLayout {
        let size = containerSize
        let measured = size != .zero
        let wide = measured && size.width > size.height
        if verticalSizeClass == .compact || (wide && size.height < Self.shortHeight) {
            return .sideBySide
        }
        if horizontalSizeClass == .regular {
            if wide && size.height < Self.shortRegularHeight {
                return .cluesInColumn
            }
            if !measured || size.width - Self.cluePanelWidth >= Self.landscapeKeypadWidth {
                return .withCluePanel
            }
        }
        return .stacked
    }

    /// How much width the clue bar and keypad take when they move beside the
    /// grid. Ten key columns plus their gutters: under this the keys are
    /// narrower than a fingertip, and much over it the grid starts paying for
    /// keys that were already big enough.
    private static let landscapeKeypadWidth: CGFloat = 400

    /// The solving surface: notes, grid, clue bar and keyboard. Stacked in
    /// portrait and on iPad (where it is the left column beside the clue
    /// panel); side by side in landscape on a phone. `stacked` keeps it one
    /// column whatever the window, for when it is itself a pane.
    private func solveSurface(stacked: Bool = false) -> some View {
        Group {
            if stacked {
                VStack(spacing: 0) {
                    railStatusRow
                    solveNotes
                    gridArea
                    clueBar
                    keypad
                }
            } else if #available(iOS 27.1, *) {
                // The system's own two-pane container. It picks the axis
                // from the window's size and size classes — its rule, not
                // the branches below — and on iPhone Duo it moves the seam
                // off the fold, which a hand-rolled stack can't.
                ArrangementView {
                    gridArea
                } secondary: {
                    VStack(spacing: 0) {
                        railStatusRow
                        solveNotes
                        // The clue list stands in the column's slack when it
                        // has one; otherwise the clue bar and keypad sink to
                        // the foot of their pane, where the thumbs are. That
                        // matters beside the grid, and on iPhone Duo folded
                        // like a laptop, where the pane below the hinge is
                        // taller than the keypad. Under the grid on a phone
                        // the pane is sized to its content, so the spacer
                        // costs nothing there.
                        if solveLayout == .cluesInColumn {
                            columnClueList
                        } else {
                            Spacer(minLength: 0)
                        }
                        clueBar
                        keypad
                    }
                    // Left to itself the split sizes this pane by ratio;
                    // hold it to the same keypad width the fallback
                    // column gets.
                    .splitArrangementLayoutSize(
                        minWidth: Self.landscapeKeypadWidth,
                        idealWidth: Self.landscapeKeypadWidth
                    )
                }
                .arrangementViewStyle(.split)
            } else if solveLayout == .sideBySide || solveLayout == .cluesInColumn {
                HStack(spacing: 0) {
                    gridArea
                    Divider()
                    VStack(spacing: 0) {
                        railStatusRow
                        // The notes ride at the top of this column rather than
                        // over the grid: in landscape a banner above the board
                        // is height the board cannot spare, and a stall nudge
                        // that resizes every cell arrives exactly when the
                        // player is already stuck.
                        solveNotes
                        if solveLayout == .cluesInColumn {
                            columnClueList
                        } else {
                            Spacer(minLength: 0)
                        }
                        clueBar
                        keypad
                    }
                    .frame(width: Self.landscapeKeypadWidth)
                }
            } else {
                VStack(spacing: 0) {
                    railStatusRow
                    solveNotes
                    gridArea
                    clueBar
                    keypad
                }
            }
        }
        .background(Theme.background)
    }

    /// The puzzle session around whichever layout is showing: the clock's
    /// window probe, keyboard entry, the bars, every sheet and the
    /// lifecycle. Applied once, in `body`, so a layout change can't reset it.
    private func session(_ content: some View) -> some View {
        content
        .background(
            // Ground truth for the solve clock. SwiftUI's lifecycle events are
            // unreliable here: hidden tab content can stay alive (and keep
            // rendering TimelineView ticks) without onDisappear, and
            // navigation destinations can be prewarmed offscreen with a
            // spurious onAppear. A UIView's window attachment can't lie.
            WindowAttachmentProbe { attached in
                vm.isAttachedToWindow = attached
                if !attached {
                    vm.pauseTimer()
                    saveProgress()
                    logAbandonIfNeeded()
                }
            }
        )
        // Hardware keyboard entry (iPad / Bluetooth): the screen itself takes
        // focus and routes letters and backspace into the engine.
        .focusable()
        .focusEffectDisabled()
        .focused($gridFocused)
        .onKeyPress(characters: .letters, phases: .down) { press in
            guard let letter = press.characters.first else { return .ignored }
            vm.enter(letter)
            return .handled
        }
        .onKeyPress(.delete, phases: .down) { _ in
            vm.delete()
            return .handled
        }
        // Arrow keys walk the grid (skipping blocks) and the space bar flips
        // between across and down — the vocabulary every desktop crossword
        // shares, for anyone solving with an iPad keyboard.
        .onKeyPress(.upArrow, phases: .down) { _ in
            vm.moveSelection(rowDelta: -1, colDelta: 0)
            return .handled
        }
        .onKeyPress(.downArrow, phases: .down) { _ in
            vm.moveSelection(rowDelta: 1, colDelta: 0)
            return .handled
        }
        .onKeyPress(.leftArrow, phases: .down) { _ in
            vm.moveSelection(rowDelta: 0, colDelta: -1)
            return .handled
        }
        .onKeyPress(.rightArrow, phases: .down) { _ in
            vm.moveSelection(rowDelta: 0, colDelta: 1)
            return .handled
        }
        .onKeyPress(.space, phases: .down) { _ in
            vm.toggleDirection()
            return .handled
        }
        // With the bars on a side rail the title is the only thing left in
        // the top bar, and it holds a 44pt strip open across the whole width
        // for it. The title moves to the status row instead and the bar
        // gets nothing, so the board starts at the top.
        .navigationTitle(barsVertical ? "" : puzzle.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar { toolbarContent }
        .sheet(isPresented: $showClues) {
            ClueListView(vm: vm)
        }
        // Reading must not detach the grid, so a sheet rather than a cover —
        // see `ClueListView.embedded`.
        .sheet(item: $clueReaderTarget) { target in
            ReaderModal(target: target)
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(source: .hintLimit)
        }
        .sheet(item: $hintUpgrade, onDismiss: resolveHintUpgrade) { upgrade in
            HintUpgradeSheet(
                upgrade: upgrade,
                // Never offered as the way out of a refused verse hint.
                canUseVerse: upgrade.type != .verse && vm.activeSlot?.reference != nil
            ) { outcome in
                hintUpgradeOutcome = (upgrade.type, outcome)
                hintUpgrade = nil
            }
        }
        // Presented locally like the clue list's reader — the ReaderRouter
        // cover hangs off the tab bar and would detach this view from its
        // window, firing the abandonment log for what is just a hint. A sheet
        // keeps the grid attached (and its TimelineView ticking), so the clock
        // is gated by `isTimerSuppressed` instead: reading must cost no time.
        .sheet(item: $verseHintTarget, onDismiss: {
            vm.isTimerSuppressed = false
        }) { target in
            // Verse-first, not the chapter: the player is mid-grid looking
            // for an answer (1,490 of 1,630 reader opens in the 30 days to
            // 2026-09-03 came from here). The chapter is one tap away.
            VerseHintSheet(target: target)
        }
        .fullScreenCover(isPresented: $showCompletion) {
            CompletionView(
                puzzle: puzzle,
                profile: profile,
                seconds: challengeReplaySeconds ?? vm.completionSeconds,
                streak: profile.currentStreak,
                newAchievements: newlyUnlocked,
                resultGrid: ShareGrid.result(for: vm.grid),
                hintsUsed: vm.hintsUsed,
                earnedFreeze: earnedFreeze,
                isComeback: isComeback,
                totalCompleted: profile.totalPuzzlesCompleted,
                onHome: {
                    showCompletion = false
                    dismiss()
                }
            )
            // Tie the results screen's identity to the puzzle it reports.
            //
            // A deep link can replace the Today stack while this cover is up —
            // tap a friend's board link from the screen that just told you to
            // send one and that is exactly what happens. SwiftUI then reuses
            // this view for the new puzzle: the `let` properties re-render, but
            // every `@State` the screen captured on appear (the challenge, the
            // family board, the pack context, the week row) stays behind,
            // leaving one puzzle's verse above another's board.
            .id(puzzle.id)
        }
        .sensoryFeedback(.success, trigger: vm.isComplete)
        .sensoryFeedback(.warning, trigger: vm.gridFullWithErrorsTick)
        .onChange(of: vm.gridFullWithErrorsTick) { _, _ in
            showFullMissAlert = true
        }
        .onChange(of: vm.stallNudgeTick) { _, _ in
            analytics.log(.stallNudgeShown(
                puzzleID: puzzle.id,
                fillPercent: fillPercent,
                idleSeconds: vm.secondsSinceLastInput,
                kind: vm.stallNudgeKind.rawValue
            ))
        }
        .alert("Almost There", isPresented: $showFullMissAlert) {
            Button("Check Answers") { runCheck(.puzzle) }
            Button("Keep Trying", role: .cancel) {}
        } message: {
            Text("Every square is filled, but at least one letter isn't right.")
        }
        .confirmationDialog(
            "Reveal the whole puzzle?",
            isPresented: $showRevealPuzzleConfirm,
            titleVisibility: .visible
        ) {
            Button("Reveal Puzzle", role: .destructive) { useHint(.puzzle) }
            Button("Keep Solving", role: .cancel) {}
        } message: {
            Text("Every remaining square is filled in for you. This uses a hint and the solve won't count as unaided.")
        }
        .task {
            gridFocused = true
            resolveHintQuota()
            resolveVerseHintLimit()
            GameViewModel.seedAutoCheckIfNeeded(totalCompleted: profile.totalPuzzlesCompleted)
            // Straight from defaults, not the property wrapper: @AppStorage may
            // not observe a write made earlier in this same runloop turn.
            vm.autoCheck = UserDefaults.standard.bool(forKey: "autoCheckErrors")
            vm.onComplete = { seconds in handleCompletion(seconds: seconds) }
            let rec = loadOrCreateRecord()
            incomingChallenge = challengeService.pending(for: puzzle.id)
            let isResume = !rec.isCompleted
                && (!rec.entries.isEmpty || !rec.pencil.isEmpty || rec.elapsedSeconds > 0)
            if rec.isCompleted, incomingChallenge != nil {
                // Already solved this puzzle — jump straight to the comparison
                // rather than replaying (a replay knows the answers and would
                // post a bogus winning time).
                challengeReplaySeconds = rec.elapsedSeconds
                showCompletion = true
            } else if !rec.isCompleted {
                // Seed accumulated time before restoring, since restoring a
                // fully-filled grid can trigger completion.
                vm.seedElapsed(rec.elapsedSeconds)
                if !rec.entries.isEmpty || !rec.pencil.isEmpty {
                    vm.restore(rec.entries, pencil: rec.pencil)
                }
            }
            // A new player's puzzle opens with the starter word already solved
            // — new players were abandoning at the empty grid (287 of 675
            // abandons under 10% fill in the 30 days to 2026-08-27). Every
            // fresh open until the third completion, not once per install: the
            // one-shot version spent the whole on-ramp on a single puzzle.
            // Free: no hint spent, `usedHint` untouched, so an unaided solve
            // still counts. Never on a resume or replay.
            //
            // Paced, not instant: the letters land one at a time so the player
            // watches a letter arrive in a square. A word that is simply there
            // when the screen opens taught nothing — see
            // `GameViewModel.giftStarterWordPaced`. The banner follows the
            // reveal rather than racing it, so the demonstration lands first
            // and the caption only names what was just shown.
            if profile.isStillLearning,
               !rec.isCompleted, !isResume,
               let gifted = await vm.giftStarterWordPaced(
                   letterInterval: reduceMotion ? .zero : .milliseconds(170)
               ) {
                withAnimation(.snappy) { showStarterGiftNote = true }
                analytics.log(.starterWordGifted(
                    puzzleID: puzzle.id,
                    answerLength: gifted.answer.count
                ))
            }
            openedAt = Date()
            analytics.log(.dailyPuzzleStarted(
                puzzleID: puzzle.id,
                isResume: isResume,
                source: entrySource
            ))
            #if DEBUG
            // Screenshot helpers, triggered by launch arguments — no visible UI.
            let args = ProcessInfo.processInfo.arguments
            // Put a believable clock on the shot. A puzzle auto-solved at launch
            // finishes in about three seconds, which is the one detail that
            // gives a staged screenshot away — the completion screen leads with
            // the time. Seeded before the fill helpers, since solving reads it.
            if let flag = args.firstIndex(of: "-uiElapsed"), flag + 1 < args.count,
               let seconds = Int(args[flag + 1]) {
                vm.seedElapsed(seconds)
            }
            if args.contains("-uiFillSolved") {
                vm.fillSolvedNoComplete()
            } else if args.contains("-uiAutoSolve") {
                vm.autoSolve()
            } else if args.contains("-uiFillPartial") {
                // Optional fraction: `-uiFillPartial 0.55`. Defaults to half.
                let fraction = args.firstIndex(of: "-uiFillPartial")
                    .flatMap { $0 + 1 < args.count ? Double(args[$0 + 1]) : nil } ?? 0.5
                vm.fillPartial(fraction: fraction)
            }
            #endif
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                break
            case .inactive, .background:
                // Leaving the foreground is the last reliable moment before the
                // app may be suspended/killed — freeze the clock and persist.
                vm.pauseTimer()
                saveProgress()
            @unknown default:
                break
            }
        }
        .onChange(of: autoCheckErrors) { _, enabled in
            vm.autoCheck = enabled
        }
        .onDisappear {
            vm.pauseTimer()
            saveProgress()
            logAbandonIfNeeded()
        }
    }

    // MARK: - The surface's pieces, arranged by `solveSurface`

    /// The title and the clock while the bars are a side rail. The clock is
    /// a custom toolbar view, which the rail cannot take, so it sits in a
    /// slim row above the board instead of holding a horizontal bar open.
    /// The clock view drives the solve timer's ticks, so it must render in
    /// exactly one place: here when the rail has it, the toolbar otherwise.
    @ViewBuilder
    private var railStatusRow: some View {
        if barsVertical {
            HStack {
                // The title, evicted from the top bar (see `.navigationTitle`).
                Text(puzzle.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                timerSlot
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.top, Theme.Spacing.xs)
        }
    }

    /// Transient banners: the challenge target, the hint-limit note, the
    /// starter-word gift. Each retires itself on a timer.
    @ViewBuilder
    private var solveNotes: some View {
        if let challenge = incomingChallenge {
            ChallengeTargetChip(name: challenge.challengerName, seconds: challenge.seconds)
                .padding(.top, Theme.Spacing.xs)
        }

        if showHintLimitNote {
            hintLimitNote
                .padding(.top, Theme.Spacing.xs)
                .transition(.move(edge: .top).combined(with: .opacity))
                .task(id: hintLimitHits) {
                    try? await Task.sleep(for: .seconds(10))
                    withAnimation(.snappy) { showHintLimitNote = false }
                }
        }

        if showStarterGiftNote {
            Label("Your first word is filled in — you take it from here!", systemImage: "gift.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, Theme.Spacing.m)
                .padding(.vertical, Theme.Spacing.xs)
                .background(Theme.accent.opacity(0.12), in: .capsule)
                .padding(.top, Theme.Spacing.xs)
                .transition(.move(edge: .top).combined(with: .opacity))
                .task {
                    try? await Task.sleep(for: .seconds(8))
                    withAnimation(.snappy) { showStarterGiftNote = false }
                }
        }
    }

    /// The clue list standing in the keypad's column. Its last row scrolls
    /// to rest a breath above the clue bar rather than flush against it.
    private var columnClueList: some View {
        ClueListView(vm: vm, embedded: true, standingReaderTarget: $clueReaderTarget)
            .contentMargins(.bottom, Theme.Spacing.m, for: .scrollContent)
    }

    /// Takes every point the arrangement can spare in both directions; the grid
    /// decides for itself whether that is enough to show the whole board.
    private var gridArea: some View {
        CrosswordGridView(vm: vm)
            .padding(Theme.Spacing.m)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var clueBar: some View {
        ClueBarView(vm: vm, onStallTap: runStallAction, onVerseTap: { useVerseHint() })
    }

    private var keypad: some View {
        LetterKeyboardView(
            isPencilMode: vm.isPencilMode,
            onLetter: { vm.enter($0) },
            onDelete: { vm.delete() },
            onTogglePencil: { vm.isPencilMode.toggle() }
        )
        .background(Color(.systemBackground))
    }

    // MARK: - Toolbar

    /// Every hint and check, behind one button.
    private var hintsMenu: some View {
        Menu {
            Section("Hints left: \(hintsRemainingText)") {
                // The hint ladder, gentlest rung first. Two Texts in a
                // Button label render as title + cost subtitle in a Menu.
                // Absent (not disabled) when the clue has no reference —
                // a dimmed row would advertise a hint most clues can't
                // offer yet. See ClueListView for the same discipline.
                if vm.activeSlot?.reference != nil {
                    Button {
                        useVerseHint()
                    } label: {
                        Text(HintType.verse.title)
                        Text(costLabel(.verse))
                        Image(systemName: "book")
                    }
                }
                Button {
                    useHint(.letter)
                } label: {
                    Text(HintType.letter.title)
                    Text(costLabel(.letter))
                    Image(systemName: "a.square")
                }
                Button {
                    useHint(.word)
                } label: {
                    Text(HintType.word.title)
                    Text(costLabel(.word))
                    Image(systemName: canAfford(.word) ? "text.word.spacing" : "lock.fill")
                }
                Button(role: .destructive) {
                    // Straight to the wall when it can't be paid for.
                    // Confirming a spend the next line refuses is the one
                    // order these two steps must never run in.
                    if canAfford(.puzzle) {
                        showRevealPuzzleConfirm = true
                    } else {
                        useHint(.puzzle)
                    }
                } label: {
                    Text(HintType.puzzle.title)
                    Text(costLabel(.puzzle))
                    Image(systemName: canAfford(.puzzle) ? "square.grid.3x3.fill" : "lock.fill")
                }
            }
            // Checks are free: they judge what's on the grid without giving
            // anything away, which is a different economy from hints.
            Section("Check") {
                Button {
                    runCheck(.letter)
                } label: {
                    Label("Check Letter", systemImage: "checkmark.square")
                }
                Button {
                    runCheck(.word)
                } label: {
                    Label("Check Word", systemImage: "checkmark.rectangle")
                }
                Button {
                    runCheck(.puzzle)
                } label: {
                    Label("Check Puzzle", systemImage: "checkmark.circle")
                }
            }
            Section {
                // Persistent as-you-type marking; the one-shot checks above
                // stay for players who keep it off.
                Toggle(isOn: $autoCheckErrors) {
                    Label("Auto-Check", systemImage: "checkmark.seal")
                }
                // Wanting the clock gone is a mid-solve feeling, so the
                // switch belongs beside the clock rather than three taps
                // away in Settings — the same `@AppStorage` as that row, so
                // the two never disagree. Left out during a challenge,
                // where `clockVisible` keeps the clock on regardless and
                // the switch would do nothing.
                if incomingChallenge == nil {
                    Toggle(isOn: $showSolveTimer) {
                        Label("Show Timer", systemImage: "timer")
                    }
                }
            }
        } label: {
            if barsVertical {
                // A side rail draws an item's icon and keeps its title for
                // the overflow menu, and only a Label can go vertical at all.
                Label("Hints", systemImage: "lightbulb")
            } else {
                // Titled, not a bare glyph: every hint and check lives behind
                // this one button, and the unlabeled lightbulb was invisible
                // to exactly the stuck new player it exists for. An HStack,
                // not a Label — the toolbar restyles a Label back to its icon.
                HStack(spacing: 3) {
                    Image(systemName: "lightbulb")
                    Text("Hints")
                }
                .font(.subheadline.weight(.medium))
            }
        }
        .accessibilityLabel("Hints and check answers")
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // A custom view, so a side rail can't take it; `railStatusRow`
        // shows it on the board instead.
        //
        // No streak here. It sat at the same weight as Back and Hints, and
        // mid-solve it has nothing to act on — for a new player it is a grey
        // "0" beside a flame. The streak is shown on Today and at completion,
        // where it is the point.
        if !barsVertical {
            ToolbarItem(placement: .principal) {
                timerSlot
            }
        }
        // Kept in the bar longest when the rail runs out of room: it is
        // the one control a stuck player needs.
        if #available(iOS 27.0, *) {
            ToolbarItem(placement: .topBarTrailing) {
                hintsMenu
            }
            .visibilityPriority(.high)
        } else {
            ToolbarItem(placement: .topBarTrailing) {
                hintsMenu
            }
        }
        // With the clue list standing as a side panel, a button that opens it
        // as a sheet would be a second copy of what's on screen.
        if !cluesStanding {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showClues = true
                } label: {
                    Label("Clue list", systemImage: "list.bullet")
                }
            }
        }
    }

    /// Whether the clock's digits are on screen. Zen hides them — except when
    /// racing a friend's time, where a hidden clock makes the race unplayable.
    private var clockVisible: Bool {
        showSolveTimer || incomingChallenge != nil
    }

    /// The clock, tappable to put it away — and the leaf tappable to bring it
    /// back. Wanting the timer gone is a mid-solve feeling, and a tap on the
    /// thing itself is the shortest route to acting on it. The Hints menu
    /// keeps its labelled "Show Timer" row all the same: a bare tap target
    /// announces itself to nobody, and the menu is where someone looks when
    /// they wonder whether the option exists at all.
    ///
    /// No button while racing a friend. `clockVisible` keeps the clock on for
    /// a challenge whatever this setting says, so a tap that appeared to do
    /// nothing would read as a broken control — better to have nothing to tap.
    ///
    /// The label is left to the content underneath, so VoiceOver still reads
    /// the elapsed time rather than a verb about hiding it; the hint carries
    /// what the tap does.
    @ViewBuilder
    private var timerSlot: some View {
        if incomingChallenge == nil {
            Button {
                showSolveTimer.toggle()
            } label: {
                timerView
                    // Animated here rather than at the tap, so the swap looks
                    // the same however the setting was changed — this button,
                    // the Hints menu, or Profile.
                    .animation(.snappy(duration: 0.22), value: clockVisible)
                    // Grows a 16pt leaf into something a thumb can actually
                    // hit. Nothing moves: the principal slot is centred, the
                    // content is fixed-size, and the toolbar row is already
                    // this tall — only the target grows to the 44pt floor.
                    .padding(.horizontal, Theme.Spacing.s)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(showSolveTimer ? "Hides the timer" : "Shows the timer")
        } else {
            timerView
        }
    }

    @ViewBuilder
    private var timerView: some View {
        // No leading icon and fixedSize: the principal slot gets squeezed
        // between the streak flame and the trailing buttons, and a Label
        // truncates the time there ("2:14…").
        if vm.isComplete {
            if clockVisible {
                Text(TimeFormat.clock(vm.completionSeconds))
                    .foregroundStyle(.green)
                    .monospacedDigit()
                    .fixedSize()
                    .transition(zenSwap)
            } else {
                zenMark
            }
        } else {
            // The TimelineView stays mounted in zen too: `vm.tick(now:)` is
            // driven only by its rendered ticks, so an empty slot here would
            // silently stop the clock — and challenges, best times and the
            // leaderboard all need honest seconds from zen players. The leaf
            // is real content, guaranteeing the render keeps happening.
            TimelineView(.periodic(from: vm.startDate, by: 1)) { context in
                Group {
                    if clockVisible {
                        Text(TimeFormat.clock(vm.elapsed()))
                            .monospacedDigit()
                            .fixedSize()
                            .transition(zenSwap)
                    } else {
                        zenMark
                    }
                }
                // Drives the clock: ticks stop whenever this timer isn't
                // actually rendering, so hidden time never accrues.
                .onChange(of: context.date) { _, now in vm.tick(now: now) }
            }
        }
    }

    /// What the timer slot shows in zen: a quiet leaf instead of an empty gap,
    /// so the missing clock reads as a mode, not a bug.
    private var zenMark: some View {
        Image(systemName: "leaf.fill")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .transition(zenSwap)
            .accessibilityLabel("Zen mode, timer hidden")
    }

    /// How the clock and the leaf trade places. Swapping with no transition
    /// reads as a glitch rather than a change of mode. This is the idea behind
    /// the SF Symbols Replace animation but not its API: `.symbolEffect(
    /// .replace)` goes symbol to symbol, and here text gives way to a symbol.
    /// Reduce Motion keeps the cross-fade and drops the scale.
    private var zenSwap: AnyTransition {
        reduceMotion ? .opacity : .scale(scale: 0.7).combined(with: .opacity)
    }

    /// "No hints left today" plus the two rungs that still cost nothing, and
    /// the upgrade as a link rather than a wall. A verse rung only exists when
    /// the active clue has a reference, so the line names it only then.
    private var hintLimitNote: some View {
        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: "lightbulb.slash")
                .font(.caption.weight(.semibold))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(hintLimitHeadline)
                    .font(.caption.weight(.semibold))
                Text(vm.activeSlot?.reference != nil
                     ? "The verse and checks are still free."
                     : "Checks are still free.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            // One VoiceOver stop for the two lines; the button stays its own.
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            Button {
                withAnimation(.snappy) { showHintLimitNote = false }
                showPaywall = true
            } label: {
                // Explicit: the container's accent foreground otherwise
                // cascades into the label and paints it accent-on-accent.
                Text("Get Premium")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.mini)
            .tint(Theme.accent)
            .accessibilityLabel("Get Premium")
            .accessibilityHint("Opens Premium upgrade options")
        }
        .foregroundStyle(Theme.accent)
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, Theme.Spacing.xs)
        .background(Theme.accent.opacity(0.12), in: .capsule)
    }

    /// What the wall actually is for the rung that was tapped.
    ///
    /// It said "No hints left today" for every refusal, which is wrong in two
    /// of the three cases: a player holding one hint who taps Reveal Word has
    /// hints left, and under a reduced pool "today" is not the problem at all.
    private var hintLimitHeadline: String {
        let left = profile.hintsRemaining(isPremium: store.isPremium, limit: freeHintLimit)
        guard let type = hintLimitType else {
            return left == 0 ? "That's your hints for today" : "Not enough hints for that"
        }
        // Naming the rung beats "that one": the player tapped a specific thing
        // and the wall should answer about that thing.
        if isBeyondPool(type) { return "\(type.title) is a Premium hint" }
        if left == 0 { return "That's your hints for today" }
        return "\(type.title) costs \(type.cost) hints"
    }

    private var hintsRemainingText: String {
        if store.isPremium { return "Unlimited" }
        if profile.isStillLearning { return "Free while you learn" }
        return "\(profile.hintsRemaining(isPremium: false, limit: freeHintLimit))"
    }

    /// Whether this player's pool covers the rung. Premium and the learning
    /// window hold `Int.max`, so both are always true for them.
    private var canAffordVerse: Bool {
        profile.hintsRemaining(isPremium: store.isPremium, limit: freeHintLimit) >= verseHintCost
    }

    private func canAfford(_ type: HintType) -> Bool {
        profile.hintsRemaining(isPremium: store.isPremium, limit: freeHintLimit) >= type.cost
    }

    /// Whether the rung costs more than a full day's pool — unreachable by
    /// waiting, not merely unaffordable right now.
    ///
    /// Never true at the shipped pool of three, where Reveal Puzzle costs
    /// exactly a full day and tomorrow really does fix it. Under
    /// `FeatureFlag.hintQuotaOne` it is true of Reveal Word (2) and Reveal
    /// Puzzle (3) permanently, which is the distinction the copy has to make.
    private func isBeyondPool(_ type: HintType) -> Bool {
        !store.isPremium && !profile.isStillLearning && type.cost > freeHintLimit
    }

    /// The rung's price — or, when it can't be paid, what's missing.
    ///
    /// A row reading "2 hints" to a player holding one is a row that lies: the
    /// tap can only wall them, and they did the arithmetic before tapping. The
    /// shipped three-a-day pool already produced that state near the end of a
    /// day; `FeatureFlag.hintQuotaOne` makes it permanent, since a pool of one
    /// can never reach Reveal Word (2) or Reveal Puzzle (3).
    ///
    /// The row stays visible rather than being hidden — unlike the verse rung,
    /// which is absent on clues that have no reference. That rung is absent
    /// because it doesn't exist for the clue; this one exists and is simply out
    /// of reach, and saying so is what makes the wall — and the upgrade behind
    /// it — legible instead of surprising.
    private func costLabel(_ type: HintType) -> String {
        // The learning window meters nothing, so the rungs must not claim a
        // price the tap won't charge.
        if !store.isPremium, profile.isStillLearning { return "Free" }
        if type == .verse, verseHintsMetered, !store.isPremium {
            let left = VerseHintAllowance.freeAllowance(verseClueCount: verseClueCount) - verseHintsUsed
            if left > 0 { return "Free · \(left) left in this puzzle" }
            return canAffordVerse ? "1 hint" : "Back tomorrow"
        }
        if type.cost > 0, !canAfford(type) {
            // Out of reach for good, not just today. A pool this size can never
            // cover the rung however long the player waits, so a countdown
            // would be true and its implied remedy false — it would read as
            // "not yet" when it means "not without Premium". Named as a thing
            // Premium *has* rather than a thing the player lacks: the row is
            // the only place most players ever learn the rung exists.
            if isBeyondPool(type) { return "Premium hint" }
            // The remedy, not the arithmetic. "0 left — needs 2" made the
            // reader do the subtraction and still didn't answer the question
            // they actually have, which is when it comes back — and the section
            // header above already states the count once.
            return "Back tomorrow"
        }
        switch type.cost {
        case 0: return "Free"
        case 1: return "1 hint"
        default: return "\(type.cost) hints"
        }
    }

    // MARK: - Actions

    /// Free one-shot check. Marks wrong cells (until edited), flashes correct
    /// ones, and deliberately never touches `usedHint` — checking is play,
    /// not aid, and must not cost anyone the Unaided/Purist achievements.
    private func runCheck(_ scope: CheckScope) {
        guard let wrong = vm.check(scope) else { return }
        analytics.log(.checkUsed(scope: scope.rawValue, wrongCount: wrong))
    }

    /// Picks this player's daily pool and buckets them, once per puzzle.
    ///
    /// Only free players past the learning window are assigned: nobody else can
    /// feel the change, and enrolling them would dilute the arms with players
    /// whose experience is identical either way. `value(of:)` rather than
    /// `isEnabled` so a device PostHog hasn't answered for keeps the shipped
    /// three rather than being counted as control — see `FeatureFlags`.
    private func resolveHintQuota() {
        guard !store.isPremium, !profile.isStillLearning else { return }
        #if DEBUG
        // Same family as -uiForceTrialReoffer. The real treatment arm needs a
        // PostHog assignment, and the locked rungs it produces are otherwise
        // only reachable by spending a real pool down on a real device.
        if ProcessInfo.processInfo.arguments.contains("-uiForceHintQuotaOne") {
            freeHintLimit = PlayerProfile.reducedHintLimit
            return
        }
        #endif
        guard let isTreatment = FeatureFlags.value(of: .hintQuotaOne) else { return }
        FeatureFlags.registerVariant("hint_quota_variant", isTreatment: isTreatment)
        freeHintLimit = isTreatment ? PlayerProfile.reducedHintLimit : PlayerProfile.freeHintLimit
    }

    private func resolveVerseHintLimit() {
        verseHintsUsed = VerseHintAllowance.used(puzzleID: puzzle.id)
        #if DEBUG
        // Treatment for any free player past the learning window, whatever
        // the profile's age — a seeded profile predates the cohort.
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-uiForceVerseHintLimit") {
            verseHintsMetered = !store.isPremium && !profile.isStillLearning
            // `-uiVerseHintsUsed 10`: start past the allowance for screenshots.
            if let i = args.firstIndex(of: "-uiVerseHintsUsed"), i + 1 < args.count,
               let used = Int(args[i + 1]) {
                verseHintsUsed = used
            }
            return
        }
        #endif
        guard VerseHintAllowance.isEligible(
            isPremium: store.isPremium,
            isStillLearning: profile.isStillLearning,
            profileCreatedAt: profile.createdAt
        ) else { return }
        guard let isTreatment = FeatureFlags.value(of: .verseHintLimit) else { return }
        FeatureFlags.registerVariant("verse_hint_variant", isTreatment: isTreatment)
        verseHintsMetered = isTreatment
    }

    /// The pool cost of the next verse hint for this player: always 0 outside
    /// the experiment's treatment arm, and for premium.
    private var verseHintCost: Int {
        guard verseHintsMetered, !store.isPremium else { return 0 }
        return VerseHintAllowance.cost(used: verseHintsUsed, verseClueCount: verseClueCount)
    }

    private var verseClueCount: Int {
        vm.allSlots.count(where: { $0.reference != nil })
    }

    /// A hint the pool can't cover: the offer card the first time in a
    /// puzzle, the inline chip after that.
    private func refuseHint(_ type: HintType) {
        analytics.log(.hintLimitReached(type: type.rawValue))
        hintLimitType = type
        if !didOfferHintUpgrade {
            didOfferHintUpgrade = true
            hintUpgrade = HintUpgrade(type: type, word: activeHintWord)
            return
        }
        hintLimitHits += 1
        withAnimation(.snappy) { showHintLimitNote = true }
    }

    private func useHint(_ type: HintType) {
        // `>= cost`, never subtraction: premium's remaining is Int.max.
        // A word (cost 2) with 1 left paywalls with no partial spend.
        guard profile.hintsRemaining(isPremium: store.isPremium, limit: freeHintLimit) >= type.cost else {
            refuseHint(type)
            return
        }
        // Mark the puzzle as hinted *before* revealing: a reveal can complete the
        // puzzle and fire handleCompletion synchronously, which reads usedHint.
        let rec = loadOrCreateRecord()
        let priorUsedHint = rec.usedHint
        rec.usedHint = true

        let didReveal: Bool
        switch type {
        case .letter: didReveal = vm.revealLetter()
        case .word: didReveal = vm.revealWord()
        case .puzzle: didReveal = vm.revealPuzzle()
        // Never routed here — the verse hint reveals nothing, so it has its
        // own path (`useVerseHint`).
        case .verse: didReveal = false
        }
        guard didReveal else {
            rec.usedHint = priorUsedHint
            return
        }
        if !store.isPremium { profile.consumeHint(cost: type.cost) }
        // `cost` is what the quota was actually charged: 0 inside the
        // learning window, list price otherwise (premium included — that
        // series predates the window and stays comparable).
        let charged = (!store.isPremium && profile.isStillLearning) ? 0 : type.cost
        analytics.log(.hintUsed(type: type.rawValue, cost: charged))
        saveProgress()
    }

    /// The word under the cursor as the hint card draws it.
    private var activeHintWord: HintUpgrade.Word? {
        guard let slot = vm.activeSlot else { return nil }
        let cells = slot.positions.map { vm.grid[$0.row][$0.col] }
        return HintUpgrade.Word(
            label: "\(slot.number) \(slot.direction.label)",
            solution: Array(slot.answer),
            entries: cells.map { $0.isPencil ? nil : $0.entry },
            focus: slot.positions.firstIndex(of: vm.selected)
        )
    }

    /// Acts on how the hint card ended, after it has gone: a purchase applies
    /// the hint they asked for, the verse button opens the free rung, and a
    /// plain dismissal leaves the board as it was.
    private func resolveHintUpgrade() {
        guard let (type, outcome) = hintUpgradeOutcome else { return }
        hintUpgradeOutcome = nil
        switch outcome {
        case .purchased:
            guard store.isPremium else { break }
            if type == .verse { useVerseHint() } else { useHint(type) }
        case .verse:
            useVerseHint()
        case .dismissed:
            break
        }
    }

    /// The ladder's free rung: open the passage the answer comes from and let
    /// the player find the word themselves. Costs nothing from the daily
    /// quota, but still counts as a hint for no-hint achievements.
    /// `metered: false` for the stall nudge's offer of the verse — the app
    /// suggested it, so it never spends the allowance or the pool.
    private func useVerseHint(metered: Bool = true) {
        guard let slot = vm.activeSlot,
              let reference = slot.reference,
              let target = ReaderRouter.Target(reference: reference, source: "hint") else { return }

        let charged = metered ? verseHintCost : 0
        if charged > 0 {
            guard profile.hintsRemaining(isPremium: store.isPremium, limit: freeHintLimit) >= charged else {
                refuseHint(.verse)
                return
            }
            profile.consumeHint(cost: charged)
        }
        if metered && verseHintsMetered && !store.isPremium {
            VerseHintAllowance.recordUse(puzzleID: puzzle.id)
            verseHintsUsed = VerseHintAllowance.used(puzzleID: puzzle.id)
        }

        let rec = loadOrCreateRecord()
        if !rec.usedHint {
            rec.usedHint = true
            saveProgress()
        }
        vm.noteVerseHint()
        analytics.log(.hintUsed(type: HintType.verse.rawValue, cost: charged))
        analytics.log(.scriptureOpened(reference: reference, source: "hint"))
        vm.isTimerSuppressed = true
        vm.pauseTimer()
        verseHintTarget = target
    }

    private func handleCompletion(seconds: Int) {
        let rec = loadOrCreateRecord()
        let firstCompletion = !rec.isCompleted

        let freezesBefore = profile.streakFreezes
        let advanced = Streaks.registerCompletion(profile, isReplay: !firstCompletion)
        earnedFreeze = profile.streakFreezes > freezesBefore
        analytics.log(.dailyPuzzleCompleted(puzzleID: puzzle.id, seconds: seconds))
        if advanced {
            analytics.log(.streakUpdated(streak: profile.currentStreak))
        }

        // The solve that answers a broken streak. Cleared here rather than when
        // the comeback card is tapped, so opening a puzzle and backing out
        // doesn't spend the offer — the card is owed until something is solved.
        //
        // Any solve counts, not just one launched from the card: a player who
        // ignores it and plays the daily has still come back, and `source`
        // records which of the two it was.
        if pendingStreakBreak > 0, profile.currentStreak > 0 {
            analytics.log(.streakComebackStarted(
                source: comebackSource.isEmpty ? "organic" : comebackSource
            ))
            isComeback = true
            pendingStreakBreak = 0
            comebackSource = ""
        }

        // Update achievement stats before evaluating unlocks. Best time updates on
        // every solve; the once-per-puzzle stats only on the first completion.
        // Minis count toward totals and the streak, but a 7×7 can't earn the
        // fast-solve or no-hint achievements meant for full puzzles.
        if !puzzle.isMini {
            profile.bestSolveSeconds = min(profile.bestSolveSeconds ?? .max, seconds)
        }
        if firstCompletion {
            if !rec.usedHint && !puzzle.isMini { profile.noHintSolves += 1 }
            if puzzle.difficulty == .hard { profile.hardCompleted += 1 }
            // This solve may have finished one or more packs — record them
            // before evaluating achievements so a pack unlock lands on this
            // completion screen, not the next one.
            for pack in recordPackCompletions() {
                analytics.log(.packCompleted(id: pack.id))
            }
            // Same contract for Journeys: step credit on every quest this
            // puzzle belongs to, and full-quest credit before achievements so
            // the badge lands on this completion screen.
            for quest in puzzleProvider.quests(containing: puzzle.id) {
                if let step = quest.puzzleIDs.firstIndex(of: puzzle.id) {
                    analytics.log(.questStepCompleted(
                        id: quest.id,
                        step: step + 1,
                        total: quest.puzzleIDs.count
                    ))
                }
            }
            for quest in recordQuestCompletions() {
                analytics.log(.questCompleted(id: quest.id))
            }
        }

        let unlocked = Achievements.newlyUnlocked(for: profile)
        for achievement in unlocked {
            profile.unlockedAchievementIDs.append(achievement.id)
            analytics.log(.achievementUnlocked(id: achievement.id))
        }
        newlyUnlocked = unlocked

        rec.isCompleted = true
        rec.completedDate = Date()
        rec.elapsedSeconds = seconds
        rec.entries = vm.snapshot()
        rec.pencil = [:] // a completed grid has no provisional letters left
        rec.updatedAt = Date()
        context.saveLogged("puzzle completion")
        WidgetBridge.publish(profile, context: context)

        // Post the Mini time to the weekly Game Center board. First completion
        // only: a replay knows the answers and would post an unbeatable time.
        // Unaided only: any hint — and above all Reveal Puzzle, which is one
        // tap — buys a time nobody solved for, and a board of bought times
        // isn't worth topping. rec.usedHint survives resume and device merges,
        // so a hint spent in an earlier sitting still disqualifies the post.
        if firstCompletion && puzzle.isMini && !rec.usedHint {
            gameCenter.submitWeeklyMiniTime(seconds: seconds)
        }

        // Today's puzzle is now solved — drop today's reminder and refresh copy.
        Task {
            await notifications.reschedule(
                for: profile, enabled: remindersEnabled,
                minutes: reminderMinutes, packNews: packNewsEnabled
            )
        }

        // Hold the cover long enough for the grid's celebration wave (a diagonal
        // sweep, 40ms per diagonal, ~550ms tail) to finish playing.
        let waveMillis = reduceMotion ? 0 : 2 * (puzzle.size - 1) * 40 + 550
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(waveMillis))
            showCompletion = true
        }
    }

    /// Packs this puzzle just finished. Runs before `rec.isCompleted` is
    /// written, so the current puzzle counts as solved explicitly.
    private func recordPackCompletions() -> [PuzzlePack] {
        let candidates = puzzleProvider.packs(containing: puzzle.id)
        guard !candidates.isEmpty else { return [] }
        let solvedIDs: Set<String>
        do {
            let records = try context.fetch(FetchDescriptor<PuzzleRecord>())
            solvedIDs = Set(records.filter(\.isCompleted).map(\.puzzleID))
        } catch {
            // Fetch failure just defers credit — launch reconciliation will
            // record the completed pack next time the store is readable.
            Log.persistence.error("Pack completion fetch failed: \(error, privacy: .public)")
            return []
        }
        return PackCompletion.record(packs: candidates, profile: profile) { id in
            id == puzzle.id || solvedIDs.contains(id)
        }
    }

    /// Journeys this puzzle just finished — the quest mirror of
    /// `recordPackCompletions`, with the same defer-on-fetch-failure contract.
    private func recordQuestCompletions() -> [QuestLine] {
        let candidates = puzzleProvider.quests(containing: puzzle.id)
        guard !candidates.isEmpty else { return [] }
        let solvedIDs: Set<String>
        do {
            let records = try context.fetch(FetchDescriptor<PuzzleRecord>())
            solvedIDs = Set(records.filter(\.isCompleted).map(\.puzzleID))
        } catch {
            Log.persistence.error("Quest completion fetch failed: \(error, privacy: .public)")
            return []
        }
        return QuestCompletion.record(quests: candidates, profile: profile) { id in
            id == puzzle.id || solvedIDs.contains(id)
        }
    }

    // MARK: - Persistence

    private func loadOrCreateRecord() -> PuzzleRecord {
        let id = puzzle.id
        let descriptor = FetchDescriptor<PuzzleRecord>(predicate: #Predicate { $0.puzzleID == id })
        // CloudKit sync may have delivered a duplicate for this puzzle from
        // another device — merge instead of blindly taking the first match.
        do {
            if let existing = SyncMerge.mergeRecords(try context.fetch(descriptor), context: context) {
                return existing
            }
        } catch {
            // A failed fetch means a fresh record may shadow an existing one
            // (SyncMerge collapses them later) — worth a trace if it happens.
            Log.persistence.error("PuzzleRecord fetch failed for \(id, privacy: .public): \(error, privacy: .public)")
        }
        let rec = PuzzleRecord(puzzleID: id)
        context.insert(rec)
        return rec
    }

    /// Records the mid-solve departure. Guards, in order: the completion cover
    /// detaching the grid from the window is not an abandon; a challenge replay
    /// jumps straight to the results with an untouched grid; and both departure
    /// paths can fire for one exit, so this only ever logs once per visit.
    private func logAbandonIfNeeded() {
        guard !vm.isComplete, challengeReplaySeconds == nil, !didLogAbandon else { return }
        didLogAbandon = true
        analytics.log(.puzzleAbandoned(
            puzzleID: puzzle.id,
            fillPercent: fillPercent,
            seconds: vm.elapsed(),
            wallSeconds: Int(Date().timeIntervalSince(openedAt).rounded()),
            hintsUsed: vm.hintsUsed,
            cellTaps: vm.cellTaps,
            keyPresses: vm.keyPresses
        ))
    }

    /// Whole-grid fill as a 0–100 int — the one convention `puzzle_abandoned`
    /// and the stall-nudge events share, so their histograms line up.
    private var fillPercent: Int {
        let total = vm.totalPlayableCount
        guard total > 0 else { return 0 }
        return Int((Double(vm.filledPlayableCount) / Double(total) * 100).rounded())
    }

    /// The stall nudge's tap: log it, then run the tier's action. The check
    /// tier runs the same whole-puzzle check the hint menu offers; the early
    /// tier reveals one letter free of the daily quota — a foothold for the
    /// player who has nothing worth checking yet. Both actions call back into
    /// the vm, which clears the nudge line.
    private func runStallAction() {
        analytics.log(.stallNudgeTapped(
            puzzleID: puzzle.id,
            fillPercent: fillPercent,
            idleSeconds: vm.secondsSinceLastInput,
            kind: vm.stallNudgeKind.rawValue
        ))
        switch vm.stallNudgeKind {
        case .checkAnswers:
            runCheck(.puzzle)
        case .readVerse:
            // The reader doesn't touch the grid, so the vm wouldn't otherwise
            // learn the nudge was taken; acknowledge first so the line drops
            // and the idle clock restarts behind the sheet.
            vm.acknowledgeStallNudge()
            useVerseHint(metered: false)
        case .freeLetter:
            // Free of quota, but still a reveal: `usedHint` and the session
            // hint counter stay honest so unaided achievements and the
            // weekly Mini leaderboard can't be bought with a stall.
            let rec = loadOrCreateRecord()
            let priorUsedHint = rec.usedHint
            rec.usedHint = true
            guard vm.revealLetter() else {
                rec.usedHint = priorUsedHint
                return
            }
            analytics.log(.hintUsed(type: HintType.letter.rawValue, cost: 0))
            saveProgress()
        }
    }

    private func saveProgress() {
        guard !vm.isComplete, vm.hasAnyEntries else { return }
        let rec = loadOrCreateRecord()
        guard !rec.isCompleted else { return }
        rec.entries = vm.snapshot()
        rec.pencil = vm.pencilSnapshot()
        rec.elapsedSeconds = vm.elapsed()
        rec.updatedAt = Date()
        context.saveLogged("puzzle progress")
    }
}

/// A friend's target time to beat, shown above the grid while playing a puzzle
/// opened from a challenge link.
private struct ChallengeTargetChip: View {
    let name: String
    let seconds: Int

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "flag.checkered")
            Text("Beat \(name): \(TimeFormat.clock(seconds))")
                .monospacedDigit()
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .foregroundStyle(Theme.accent)
        .background(Theme.accent.opacity(0.15), in: .capsule)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Challenge from \(name): beat \(TimeFormat.clock(seconds))")
    }
}

/// A zero-size UIKit view that reports whether it's attached to a window.
/// Used as the reliable "is this screen actually visible" signal — see the
/// comment at the use site in `CrosswordGameView`.
private struct WindowAttachmentProbe: UIViewRepresentable {
    let onChange: (Bool) -> Void

    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.onWindowChange = onChange
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        return view
    }

    func updateUIView(_ uiView: ProbeView, context: Context) {
        uiView.onWindowChange = onChange
    }

    final class ProbeView: UIView {
        var onWindowChange: ((Bool) -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            let attached = window != nil
            // didMoveToWindow can fire mid-layout; hop to the next runloop turn
            // before touching observable state that drives SwiftUI updates.
            DispatchQueue.main.async { [weak self] in
                guard let self, (self.window != nil) == attached else { return }
                self.onWindowChange?(attached)
            }
        }
    }
}
