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
    @Environment(StoreService.self) private var store

    @State private var vm: GameViewModel
    @State private var showClues = false
    @State private var showCompletion = false
    @State private var showPaywall = false
    @State private var newlyUnlocked: [Achievement] = []

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
            if !rec.isCompleted, !rec.entries.isEmpty {
                vm.restore(rec.entries)
            }
            analytics.log(.dailyPuzzleStarted(puzzleID: puzzle.id))
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
            TimelineView(.periodic(from: vm.startDate, by: 1)) { _ in
                let secs = max(0, Int(Date().timeIntervalSince(vm.startDate)))
                Label(TimeFormat.clock(secs), systemImage: "timer")
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
        let didReveal: Bool
        switch type {
        case .letter: didReveal = vm.revealLetter()
        case .word: didReveal = vm.revealWord()
        }
        guard didReveal else { return }
        if !store.isPremium { profile.consumeHint() }
        analytics.log(.hintUsed(type: type.rawValue))
        saveProgress()
    }

    private func handleCompletion(seconds: Int) {
        let advanced = Streaks.registerCompletion(profile)
        analytics.log(.dailyPuzzleCompleted(puzzleID: puzzle.id, seconds: seconds))
        if advanced {
            analytics.log(.streakUpdated(streak: profile.currentStreak))
        }

        let unlocked = Achievements.newlyUnlocked(for: profile)
        for achievement in unlocked {
            profile.unlockedAchievementIDs.append(achievement.id)
            analytics.log(.achievementUnlocked(id: achievement.id))
        }
        newlyUnlocked = unlocked

        let rec = loadOrCreateRecord()
        rec.isCompleted = true
        rec.completedDate = Date()
        rec.elapsedSeconds = seconds
        rec.entries = vm.snapshot()
        rec.updatedAt = Date()
        try? context.save()

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
        rec.elapsedSeconds = max(0, Int(Date().timeIntervalSince(vm.startDate)))
        rec.updatedAt = Date()
        try? context.save()
    }
}
