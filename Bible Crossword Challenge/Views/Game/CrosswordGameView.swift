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
        .navigationTitle(puzzle.title)
        .navigationBarTitleDisplayMode(.inline)
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
                onHome: {
                    showCompletion = false
                    dismiss()
                }
            )
        }
        .sensoryFeedback(.success, trigger: vm.isComplete)
        .task {
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
                vm.resumeTimer()
            case .inactive, .background:
                // Leaving the foreground is the last reliable moment before the
                // app may be suspended/killed — freeze the clock and persist.
                vm.pauseTimer()
                saveProgress()
            @unknown default:
                break
            }
        }
        .onDisappear { saveProgress() }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
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
            } label: {
                Image(systemName: "lightbulb")
            }
            .accessibilityLabel("Hints")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                vm.toggleCheck()
            } label: {
                Image(systemName: vm.showErrors ? "checkmark.circle.fill" : "checkmark.circle")
            }
            .accessibilityLabel("Check answers")
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
        if vm.isComplete {
            Label(TimeFormat.clock(vm.completionSeconds), systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .monospacedDigit()
        } else {
            TimelineView(.periodic(from: vm.startDate, by: 1)) { context in
                Label(TimeFormat.clock(vm.elapsed(asOf: context.date)), systemImage: "timer")
                    .monospacedDigit()
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
        profile.bestSolveSeconds = min(profile.bestSolveSeconds ?? .max, seconds)
        if firstCompletion {
            if !rec.usedHint { profile.noHintSolves += 1 }
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

        // Today's puzzle is now solved — drop today's reminder and refresh copy.
        Task {
            await notifications.reschedule(for: profile, enabled: remindersEnabled, minutes: reminderMinutes)
        }

        showCompletion = true
    }

    // MARK: - Persistence

    private func loadOrCreateRecord() -> PuzzleRecord {
        let id = puzzle.id
        let descriptor = FetchDescriptor<PuzzleRecord>(predicate: #Predicate { $0.puzzleID == id })
        if let existing = try? context.fetch(descriptor).first {
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
