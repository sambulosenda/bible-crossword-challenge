//
//  CrosswordGameView.swift
//  Bible Crossword Challenge
//
//  Hosts the grid, clue bar and keyboard, and wires the engine to persistence,
//  hints, streaks, achievements, analytics and the completion screen.
//

import SwiftUI
import SwiftData

struct CrosswordGameView: View {
    let puzzle: Puzzle
    let profile: PlayerProfile

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.analytics) private var analytics
    @Environment(\.notifications) private var notifications
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(StoreService.self) private var store

    @AppStorage("remindersEnabled") private var remindersEnabled = false
    @AppStorage("reminderMinutes") private var reminderMinutes = ReminderTime.defaultMinutes

    @State private var vm: GameViewModel
    @State private var showClues = false
    @State private var showCompletion = false
    @State private var showPaywall = false
    @State private var newlyUnlocked: [Achievement] = []
    /// Whether this solve crossed a streak milestone that granted a freeze.
    @State private var earnedFreeze = false
    /// Keeps the screen focused so a hardware keyboard can type into the grid.
    @FocusState private var gridFocused: Bool

    init(puzzle: Puzzle, profile: PlayerProfile) {
        self.puzzle = puzzle
        self.profile = profile
        _vm = State(initialValue: GameViewModel(puzzle: puzzle))
    }

    var body: some View {
        VStack(spacing: 0) {
            CrosswordGridView(vm: vm)
                .padding(Theme.Spacing.m)
                .frame(maxHeight: .infinity)

            ClueBarView(vm: vm)

            LetterKeyboardView(
                onLetter: { vm.enter($0) },
                onDelete: { vm.delete() }
            )
            .background(Color(.systemBackground))
        }
        .background(Color(.systemGroupedBackground))
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
            PaywallView()
        }
        .fullScreenCover(isPresented: $showCompletion) {
            CompletionView(
                puzzle: puzzle,
                seconds: vm.completionSeconds,
                streak: profile.currentStreak,
                newAchievements: newlyUnlocked,
                earnedFreeze: earnedFreeze,
                totalCompleted: profile.totalPuzzlesCompleted,
                onHome: {
                    showCompletion = false
                    dismiss()
                }
            )
        }
        .sensoryFeedback(.success, trigger: vm.isComplete)
        .task {
            gridFocused = true
            vm.onComplete = { seconds in handleCompletion(seconds: seconds) }
            let rec = loadOrCreateRecord()
            if !rec.isCompleted {
                // Seed accumulated time before restoring, since restoring a
                // fully-filled grid can trigger completion.
                vm.seedElapsed(rec.elapsedSeconds)
                if !rec.entries.isEmpty {
                    vm.restore(rec.entries)
                }
            }
            analytics.log(.dailyPuzzleStarted(puzzleID: puzzle.id))
            #if DEBUG
            // Screenshot helpers, triggered by launch arguments — no visible UI.
            let args = ProcessInfo.processInfo.arguments
            if args.contains("-uiFillSolved") {
                vm.fillSolvedNoComplete()
            } else if args.contains("-uiAutoSolve") {
                vm.autoSolve()
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
        .onDisappear {
            vm.pauseTimer()
            saveProgress()
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
                }
                Section {
                    Toggle(isOn: Binding(
                        get: { vm.showErrors },
                        set: { _ in vm.toggleCheck() }
                    )) {
                        Label("Check Answers", systemImage: "checkmark.circle")
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

    @ViewBuilder
    private var timerView: some View {
        // No leading icon and fixedSize: the principal slot gets squeezed
        // between the streak flame and the trailing buttons, and a Label
        // truncates the time there ("2:14…").
        if vm.isComplete {
            Text(TimeFormat.clock(vm.completionSeconds))
                .foregroundStyle(.green)
                .monospacedDigit()
                .fixedSize()
        } else {
            TimelineView(.periodic(from: vm.startDate, by: 1)) { context in
                Text(TimeFormat.clock(vm.elapsed()))
                    .monospacedDigit()
                    .fixedSize()
                    // Drives the clock: ticks stop whenever this timer isn't
                    // actually rendering, so hidden time never accrues.
                    .onChange(of: context.date) { _, now in vm.tick(now: now) }
            }
        }
    }

    private var hintsRemainingText: String {
        if store.isPremium { return "Unlimited" }
        return "\(profile.hintsRemaining(isPremium: false))"
    }

    // MARK: - Actions

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
        }
        guard didReveal else {
            rec.usedHint = priorUsedHint
            return
        }
        if !store.isPremium { profile.consumeHint() }
        analytics.log(.hintUsed(type: type.rawValue))
        saveProgress()
    }

    private func handleCompletion(seconds: Int) {
        let rec = loadOrCreateRecord()
        let firstCompletion = !rec.isCompleted

        let freezesBefore = profile.streakFreezes
        let advanced = Streaks.registerCompletion(profile)
        earnedFreeze = profile.streakFreezes > freezesBefore
        analytics.log(.dailyPuzzleCompleted(puzzleID: puzzle.id, seconds: seconds))
        if advanced {
            analytics.log(.streakUpdated(streak: profile.currentStreak))
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
        rec.updatedAt = Date()
        try? context.save()
        WidgetBridge.publish(profile)

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

    // MARK: - Persistence

    private func loadOrCreateRecord() -> PuzzleRecord {
        let id = puzzle.id
        let descriptor = FetchDescriptor<PuzzleRecord>(predicate: #Predicate { $0.puzzleID == id })
        // CloudKit sync may have delivered a duplicate for this puzzle from
        // another device — merge instead of blindly taking the first match.
        if let matches = try? context.fetch(descriptor),
           let existing = SyncMerge.mergeRecords(matches, context: context) {
            return existing
        }
        let rec = PuzzleRecord(puzzleID: id)
        context.insert(rec)
        return rec
    }

    private func saveProgress() {
        guard !vm.isComplete, vm.hasAnyEntries else { return }
        let rec = loadOrCreateRecord()
        guard !rec.isCompleted else { return }
        rec.entries = vm.snapshot()
        rec.elapsedSeconds = vm.elapsed()
        rec.updatedAt = Date()
        try? context.save()
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
