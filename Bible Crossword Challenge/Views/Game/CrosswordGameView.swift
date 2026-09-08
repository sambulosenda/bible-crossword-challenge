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
    @Environment(StoreService.self) private var store

    @AppStorage("remindersEnabled") private var remindersEnabled = false
    @AppStorage("reminderMinutes") private var reminderMinutes = ReminderTime.defaultMinutes
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
        Group {
            if horizontalSizeClass == .regular {
                // iPad (and large-phone landscape): the clue list stops being a
                // sheet and becomes a standing side panel — grid and keyboard on
                // the left, every clue in view on the right, the way a paper
                // crossword sits next to its clues.
                HStack(spacing: 0) {
                    solveColumn
                    Divider().ignoresSafeArea(edges: .bottom)
                    ClueListView(vm: vm, embedded: true)
                        .frame(width: 340)
                }
            } else {
                solveColumn
            }
        }
        .background(Theme.background)
    }

    /// The solving surface: challenge chip, grid, clue bar and keyboard. The
    /// whole screen in compact width; the left column beside the clue panel in
    /// regular width.
    private var solveColumn: some View {
        VStack(spacing: 0) {
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

            CrosswordGridView(vm: vm)
                .padding(Theme.Spacing.m)
                .frame(maxHeight: .infinity)

            ClueBarView(vm: vm, onStallTap: runStallAction, onVerseTap: useVerseHint)

            LetterKeyboardView(
                isPencilMode: vm.isPencilMode,
                onLetter: { vm.enter($0) },
                onDelete: { vm.delete() },
                onTogglePencil: { vm.isPencilMode.toggle() }
            )
            .background(Color(.systemBackground))
        }
        .background(Theme.background)
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
        .navigationTitle(puzzle.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar { toolbarContent }
        .sheet(isPresented: $showClues) {
            ClueListView(vm: vm)
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(source: .hintLimit)
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
            if profile.isStillLearning,
               !rec.isCompleted, !isResume,
               let gifted = vm.giftStarterWord() {
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

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            StreakFlameView(streak: profile.currentStreak, pulseTick: vm.wordSolveTick)
        }
        ToolbarItem(placement: .principal) {
            timerView
        }
        ToolbarItem(placement: .topBarTrailing) {
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
                }
            } label: {
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
            .accessibilityLabel("Hints and check answers")
        }
        // In regular width the clue list is a standing side panel, so a button
        // that opens it as a sheet would be a second copy of what's on screen.
        if horizontalSizeClass != .regular {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showClues = true
                } label: {
                    Image(systemName: "list.bullet")
                }
                .accessibilityLabel("Clue list")
            }
        }
    }

    /// Whether the clock's digits are on screen. Zen hides them — except when
    /// racing a friend's time, where a hidden clock makes the race unplayable.
    private var clockVisible: Bool {
        showSolveTimer || incomingChallenge != nil
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
            .accessibilityLabel("Zen mode, timer hidden")
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
        // Same family as -uiForcePremiumAsk. The real treatment arm needs a
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

    private func useHint(_ type: HintType) {
        // `>= cost`, never subtraction: premium's remaining is Int.max.
        // A word (cost 2) with 1 left paywalls with no partial spend.
        guard profile.hintsRemaining(isPremium: store.isPremium, limit: freeHintLimit) >= type.cost else {
            analytics.log(.hintLimitReached(type: type.rawValue))
            hintLimitType = type
            hintLimitHits += 1
            withAnimation(.snappy) { showHintLimitNote = true }
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

    /// The ladder's free rung: open the passage the answer comes from and let
    /// the player find the word themselves. Costs nothing from the daily
    /// quota, but still counts as a hint for no-hint achievements.
    private func useVerseHint() {
        guard let slot = vm.activeSlot,
              let reference = slot.reference,
              let target = ReaderRouter.Target(reference: reference, source: "hint") else { return }

        let rec = loadOrCreateRecord()
        if !rec.usedHint {
            rec.usedHint = true
            saveProgress()
        }
        vm.noteVerseHint()
        analytics.log(.hintUsed(type: HintType.verse.rawValue, cost: HintType.verse.cost))
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
            await notifications.reschedule(for: profile, enabled: remindersEnabled, minutes: reminderMinutes)
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
            hintsUsed: vm.hintsUsed
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
            useVerseHint()
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

/// Toolbar streak indicator: flame + current streak count, pulsing with a
/// spring pop each time a word is solved (and once more at the full solve,
/// right as the streak number ticks up).
private struct StreakFlameView: View {
    let streak: Int
    let pulseTick: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "flame.fill")
            Text("\(streak)")
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(streak)))
        }
        // The toolbar lays this item out inside a circular glass background
        // sized for its ideal width, and without this it hands the HStack a
        // one-digit budget: every streak of 10 or more was rendering clipped to
        // its first digit, so the players with the most to be proud of were the
        // only ones shown the wrong number.
        .fixedSize()
        .foregroundStyle(streak > 0 ? Color.orange : Color.secondary)
        .animation(.snappy, value: streak)
        .phaseAnimator([1.0, 1.35], trigger: pulseTick) { content, scale in
            content.scaleEffect(reduceMotion ? 1.0 : scale)
        } animation: { _ in
            .spring(duration: 0.25, bounce: 0.6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Current streak: \(streak) days")
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
