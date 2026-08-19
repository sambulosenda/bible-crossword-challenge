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

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.analytics) private var analytics
    @Environment(\.puzzleProvider) private var puzzleProvider
    @Environment(\.notifications) private var notifications
    @Environment(\.gameCenter) private var gameCenter
    @Environment(\.challengeService) private var challengeService
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
    /// Keeps the screen focused so a hardware keyboard can type into the grid.
    @FocusState private var gridFocused: Bool

    init(puzzle: Puzzle, profile: PlayerProfile) {
        self.puzzle = puzzle
        self.profile = profile
        _vm = State(initialValue: GameViewModel(puzzle: puzzle))
    }

    var body: some View {
        VStack(spacing: 0) {
            if let challenge = incomingChallenge {
                ChallengeTargetChip(name: challenge.challengerName, seconds: challenge.seconds)
                    .padding(.top, Theme.Spacing.xs)
            }

            CrosswordGridView(vm: vm)
                .padding(Theme.Spacing.m)
                .frame(maxHeight: .infinity)

            ClueBarView(vm: vm)

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
        .navigationTitle(puzzle.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar { toolbarContent }
        .sheet(isPresented: $showClues) {
            ClueListView(vm: vm)
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(source: "hint_limit")
        }
        // Presented locally like the clue list's reader — the ReaderRouter
        // cover hangs off the tab bar and would detach this view from its
        // window, firing the abandonment log for what is just a hint. A sheet
        // keeps the grid attached (and its TimelineView ticking), so the clock
        // is gated by `isTimerSuppressed` instead: reading must cost no time.
        .sheet(item: $verseHintTarget, onDismiss: {
            vm.isTimerSuppressed = false
        }) { target in
            ReaderModal(target: target)
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
            analytics.log(.dailyPuzzleStarted(puzzleID: puzzle.id, isResume: isResume))
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
                    // Absent (not disabled) when the clue has no reference —
                    // a dimmed row would advertise a hint most clues can't
                    // offer yet. See ClueListView for the same discipline.
                    if vm.activeSlot?.reference != nil {
                        Button {
                            useVerseHint()
                        } label: {
                            Label("Show the Verse", systemImage: "book")
                        }
                    }
                    Button {
                        useHint(.letter)
                    } label: {
                        Label("Reveal Letter", systemImage: "a.square")
                    }
                    Button {
                        useHint(.word)
                    } label: {
                        Label("Reveal Word", systemImage: "text.word.spacing")
                    }
                    Button(role: .destructive) {
                        showRevealPuzzleConfirm = true
                    } label: {
                        Label("Reveal Puzzle", systemImage: "square.grid.3x3.fill")
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
                Image(systemName: "lightbulb")
            }
            .accessibilityLabel("Hints and check answers")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                showClues = true
            } label: {
                Image(systemName: "list.bullet")
            }
            .accessibilityLabel("Clue list")
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

    private var hintsRemainingText: String {
        if store.isPremium { return "Unlimited" }
        return "\(profile.hintsRemaining(isPremium: false))"
    }

    // MARK: - Actions

    /// Free one-shot check. Marks wrong cells (until edited), flashes correct
    /// ones, and deliberately never touches `usedHint` — checking is play,
    /// not aid, and must not cost anyone the Unaided/Purist achievements.
    private func runCheck(_ scope: CheckScope) {
        guard let wrong = vm.check(scope) else { return }
        analytics.log(.checkUsed(scope: scope.rawValue, wrongCount: wrong))
    }

    private func useHint(_ type: HintType) {
        guard profile.hintsRemaining(isPremium: store.isPremium) > 0 else {
            showPaywall = true
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
        // own path (`useVerseHint`) with per-clue charging.
        case .verse: didReveal = false
        }
        guard didReveal else {
            rec.usedHint = priorUsedHint
            return
        }
        if !store.isPremium { profile.consumeHint() }
        analytics.log(.hintUsed(type: type.rawValue))
        saveProgress()
    }

    /// The third hint: open the passage the answer comes from and let the
    /// player find the word themselves. Charges the shared quota once per
    /// clue — re-opening the same passage to re-read it is free.
    private func useVerseHint() {
        guard let slot = vm.activeSlot,
              let reference = slot.reference,
              let target = ReaderRouter.Target(reference: reference) else { return }

        if !vm.hasVerseHinted(slot) {
            guard profile.hintsRemaining(isPremium: store.isPremium) > 0 else {
                showPaywall = true
                return
            }
            let rec = loadOrCreateRecord()
            rec.usedHint = true
            vm.markVerseHinted(slot)
            if !store.isPremium { profile.consumeHint() }
            analytics.log(.hintUsed(type: HintType.verse.rawValue))
            saveProgress()
        }

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
        WidgetBridge.publish(profile)

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
        let total = vm.totalPlayableCount
        let percent = total > 0
            ? Int((Double(vm.filledPlayableCount) / Double(total) * 100).rounded())
            : 0
        analytics.log(.puzzleAbandoned(
            puzzleID: puzzle.id,
            fillPercent: percent,
            seconds: vm.elapsed(),
            hintsUsed: vm.hintsUsed
        ))
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
