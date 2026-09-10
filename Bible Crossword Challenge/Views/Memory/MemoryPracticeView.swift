//
//  MemoryPracticeView.swift
//  Bible Crossword Challenge
//
//  The memory-verse practice session: the verse-shaped grid with this level's
//  words blanked, played through the unchanged crossword engine and components.
//
//  Deliberately a light host, not `CrosswordGameView` — no PuzzleRecord, no
//  timer, no streaks, no achievements. A session is one to three minutes;
//  abandoning it just discards the grid, and mastery lives in
//  `MemoryVerseStore` alone.
//

import SwiftUI

/// Navigation value pushing a practice session for a held verse.
struct MemoryPracticeRoute: Hashable {
    let referenceKey: String
    /// Which surface pushed the session — `memory_verse_started.source`.
    var source: String = "list"
}

struct MemoryPracticeView: View {
    let referenceKey: String
    /// Which surface opened the session — `memory_verse_started.source`.
    var source: String = "list"

    @Environment(\.memoryVerses) private var memoryVerses
    @Environment(\.analytics) private var analytics
    @Environment(\.dismiss) private var dismiss
    @AppStorage("autoCheckErrors") private var autoCheckErrors = false

    @State private var vm: GameViewModel?
    @State private var built: MemoryCloze.Built?
    @State private var showPeek = false
    @State private var outcome: MemoryVerseStore.CompletionOutcome?
    @State private var didLogStart = false

    /// Keeps the screen focused so a hardware keyboard can type into the grid.
    @FocusState private var gridFocused: Bool

    private var entry: MemoryVerseStore.Entry? { memoryVerses.entry(for: referenceKey) }

    var body: some View {
        Group {
            if let vm, let built, let entry {
                session(vm: vm, built: built, entry: entry)
            } else {
                // Only reachable if the stored verse text stopped fitting the
                // layout — which build-time bounds make effectively impossible.
                ContentUnavailableView(
                    "This verse can't be practiced",
                    systemImage: "text.book.closed",
                    description: Text("Choose another verse from your list.")
                )
            }
        }
        .navigationTitle(entry?.reference ?? "Memory Verse")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .background(Theme.background)
        .onAppear { setUpIfNeeded() }
        .sheet(isPresented: $showPeek) { peekSheet }
        .sheet(item: $outcome) { completionSheet($0) }
    }

    private func setUpIfNeeded() {
        guard vm == nil, let entry,
              let built = MemoryCloze.build(
                reference: entry.reference,
                verseText: entry.verseText,
                level: entry.playLevel
              ) else { return }
        // Same holdout as the crossword grid: flag off means no nudge
        // anywhere, so the control group's experience is one thing.
        let model = GameViewModel(
            puzzle: built.puzzle,
            stallNudgeEnabled: FeatureFlags.isEnabled(.stallNudge)
        )
        model.autoCheck = autoCheckErrors
        model.restore(built.prefill)
        // Land on the first blanked word, not cell (0,0) of a revealed one.
        if let firstBlank = model.acrossSlots.first(where: { built.blankedWordIndices.contains($0.number - 1) }) {
            model.select(slot: firstBlank)
        }
        model.onComplete = { _ in finishSession(model: model, entry: entry) }
        self.built = built
        self.vm = model

        if !didLogStart {
            didLogStart = true
            analytics.log(.memoryVerseStarted(reference: entry.reference, level: entry.playLevel, source: source))
        }
    }

    private func finishSession(model: GameViewModel, entry: MemoryVerseStore.Entry) {
        let result = memoryVerses.recordCompletion(
            referenceKey: entry.referenceKey,
            hintFree: model.hintsUsed == 0
        )
        analytics.log(.memoryVerseCompleted(
            reference: entry.reference,
            level: entry.playLevel,
            leveledUp: result.leveledUp,
            hintsUsed: model.hintsUsed
        ))
        if result.mastered {
            analytics.log(.memoryVerseMastered(reference: entry.reference))
        }
        outcome = result
    }

    // MARK: - Session

    private func session(vm: GameViewModel, built: MemoryCloze.Built, entry: MemoryVerseStore.Entry) -> some View {
        VStack(spacing: 0) {
            header(built: built, entry: entry)

            CrosswordGridView(vm: vm)
                .padding(.horizontal, Theme.Spacing.m)
                .frame(maxHeight: .infinity)

            ClueBarView(vm: vm)
            LetterKeyboardView(
                onLetter: { vm.enter($0) },
                onDelete: { vm.delete() }
            )
        }
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
        .onAppear { gridFocused = true }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        vm.revealLetter()
                    } label: {
                        Label("Reveal a Letter", systemImage: "lightbulb")
                    }
                    Button {
                        vm.noteVerseHint()
                        showPeek = true
                    } label: {
                        Label("Peek at the Verse", systemImage: "book")
                    }
                } label: {
                    Image(systemName: "lightbulb")
                }
                .accessibilityLabel("Hints")
            }
        }
    }

    /// Level dots and what this session asks — the one line that frames the
    /// grid as practice rather than a puzzle. Hints stay available, but the
    /// header says plainly what they cost.
    private func header(built: MemoryCloze.Built, entry: MemoryVerseStore.Entry) -> some View {
        HStack(spacing: Theme.Spacing.m) {
            MasteryDots(level: entry.level)
            Text(headerText(built: built, entry: entry))
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, Theme.Spacing.s)
        .accessibilityElement(children: .combine)
    }

    private func headerText(built: MemoryCloze.Built, entry: MemoryVerseStore.Entry) -> String {
        if built.blankedWordIndices.count == built.wordCount {
            return entry.isMastered ? "Mastered · full recall" : "Full recall — every word from memory"
        }
        return "Level \(entry.level) · \(built.blankedWordIndices.count) of \(built.wordCount) words hidden"
    }

    // MARK: - Peek

    /// The whole verse, readable, then back to the grid. Free, but it forfeits
    /// the level-up — recall the player didn't do isn't recall.
    private var peekSheet: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            Label("PEEK", systemImage: "book").kicker()
            if let entry {
                Text(entry.verseText)
                    .font(.scripture(.title3))
                    .lineSpacing(6)
                Text(entry.reference)
                    .font(.headline)
                    .foregroundStyle(Theme.accent)
            }
            Text("Peeking keeps this round from raising your mastery level.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.xl)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .background(Theme.background)
    }

    // MARK: - Completion

    private func completionSheet(_ result: MemoryVerseStore.CompletionOutcome) -> some View {
        VStack(spacing: Theme.Spacing.xl) {
            VStack(spacing: Theme.Spacing.m) {
                Image(systemName: result.mastered ? "medal.fill" : "checkmark.seal.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(result.mastered ? .yellow : .green)
                Text(completionTitle(result))
                    .font(.scripture(.title2, weight: .bold))
                    .multilineTextAlignment(.center)
                MasteryDots(level: result.newLevel, animateTo: result.leveledUp)
            }

            if let entry {
                VStack(spacing: Theme.Spacing.m) {
                    Text(entry.verseText)
                        .font(.scripture(.title3))
                        .lineSpacing(6)
                        .multilineTextAlignment(.center)
                    Text(entry.reference)
                        .font(.headline)
                        .foregroundStyle(Theme.accent)
                }
            }

            Text(completionDetail(result))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                outcome = nil
                dismiss()
            } label: {
                Text("Done").frame(maxWidth: .infinity)
            }
            .buttonStyle(.pillProminent)
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .interactiveDismissDisabled()
    }

    private func completionTitle(_ result: MemoryVerseStore.CompletionOutcome) -> String {
        if result.mastered { return "You know this verse by heart" }
        if result.leveledUp { return "Level \(result.newLevel) reached" }
        return "Verse complete"
    }

    private func completionDetail(_ result: MemoryVerseStore.CompletionOutcome) -> String {
        if result.mastered {
            return "Mastered. It stays in your list for an occasional full-recall review."
        }
        if result.leveledUp {
            return "Next time, more of the verse is up to you. It'll be due for review in \(reviewDaysText)."
        }
        if let vm, vm.hintsUsed > 0 {
            return "Practiced with hints — finish a round without them to raise your level."
        }
        // The spacing held the level. Say how long, or a flawless round that
        // "didn't count" reads as a bug and the next attempt is a re-run now.
        if let entry, let at = memoryVerses.levelUpAvailableAt(entry) {
            let wait = TimeFormat.countdown(at.timeIntervalSinceNow)
            return "Flawless. Level-ups need a break between rounds — the next one counts in \(wait)."
        }
        return "Practiced. Come back after a break to raise your level."
    }

    private var reviewDaysText: String {
        guard let entry, let due = memoryVerses.dueDate(entry), let last = entry.lastPracticedAt else {
            return "a day"
        }
        let days = max(1, Calendar.current.dateComponents([.day], from: last, to: due).day ?? 1)
        return days == 1 ? "a day" : "\(days) days"
    }
}

/// `sheet(item:)` needs identity; the outcome of one completion is one moment.
extension MemoryVerseStore.CompletionOutcome: Identifiable {
    var id: String { "\(newLevel)-\(leveledUp)" }
}

// MARK: - Mastery dots

/// Five dots, one per mastery level — the mode's progress glyph, shared by the
/// practice header, the completion sheet, and the verse list rows.
struct MasteryDots: View {
    let level: Int
    /// Pop the newest dot in — the completion sheet's level-up beat.
    var animateTo: Bool = false

    @State private var shown = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...MemoryVerseStore.masteredLevel, id: \.self) { dot in
                Circle()
                    .fill(dot <= level ? Theme.accent : Color(.tertiarySystemFill))
                    .frame(width: 8, height: 8)
                    .scaleEffect(animateTo && dot == level && !shown ? 0.1 : 1)
            }
        }
        .onAppear {
            guard animateTo else { return }
            withAnimation(.spring(duration: 0.5, bounce: 0.5).delay(0.3)) { shown = true }
        }
        .accessibilityElement()
        .accessibilityLabel("Mastery level \(level) of \(MemoryVerseStore.masteredLevel)")
    }
}
