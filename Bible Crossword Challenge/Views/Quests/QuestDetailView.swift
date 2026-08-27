//
//  QuestDetailView.swift
//  Bible Crossword Challenge
//
//  One Journey: a header with progress, then its steps in walking order. Steps
//  unlock front to back — the sequence is the feature — but pacing stays soft:
//  finishing today's step swaps the copy to "back tomorrow" without ever
//  locking the next one. Premium quests show their steps but gate play behind
//  the paywall, like premium packs.
//

import SwiftUI
import SwiftData

/// The surfaces that can open a quest — same closed-set contract as
/// `PackOpenSource`, so `quest_opened` can always say where from.
enum QuestOpenSource: String, Hashable {
    case home
    case packs
}

/// A quest push, tagged with the surface that made it.
struct QuestRoute: Hashable {
    let quest: QuestLine
    let source: QuestOpenSource
}

struct QuestDetailView: View {
    let quest: QuestLine
    let profile: PlayerProfile
    let source: QuestOpenSource

    @Environment(\.puzzleProvider) private var puzzleProvider
    @Environment(\.analytics) private var analytics
    @Environment(StoreService.self) private var store
    @Query private var records: [PuzzleRecord]

    @State private var showPaywall = false

    private var recordsByID: [String: PuzzleRecord] {
        Dictionary(records.map { ($0.puzzleID, $0) }, uniquingKeysWith: { a, _ in a })
    }

    private var steps: [Puzzle] { puzzleProvider.puzzles(in: quest) }
    private var progress: QuestProgress { QuestProgress(quest: quest, recordsByID: recordsByID) }
    private var isLocked: Bool { quest.isPremium && !store.isPremium }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                header
                if isLocked {
                    lockedState
                } else {
                    stepList
                }
            }
            .padding(Theme.Spacing.m)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background)
        .navigationTitle(quest.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPaywall) {
            PaywallView(source: "quest_locked")
        }
        // questCompleted is logged in the game screen's completion hook, so it
        // fires exactly once even if this screen is never revisited.
        .task { analytics.log(.questOpened(id: quest.id, source: source.rawValue)) }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack(spacing: Theme.Spacing.m) {
                Image(systemName: quest.coverSymbol)
                    .font(.largeTitle)
                    .foregroundStyle(quest.accent)
                    .frame(width: 64, height: 64)
                    .background(quest.accent.opacity(0.14), in: .rect(cornerRadius: 16, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(quest.title).font(.title2.weight(.bold))
                    Text(quest.blurb)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if isLocked {
                // Locked states size, not progress — see `PackCard` for why.
                Text("\(progress.total) step\(progress.total == 1 ? "" : "s"), one a day")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if progress.isComplete {
                Label("Journey complete", systemImage: "checkmark.seal.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.green)
            } else {
                ProgressView(value: progress.fraction)
                    .tint(quest.accent)
                Text(progressLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    /// "Step 3 of 7" plus the soft-pacing nudge when today's step is done.
    private var progressLine: String {
        let position = "Step \(min(progress.solved + 1, progress.total)) of \(progress.total)"
        return progress.steppedToday
            ? "\(position) — today's step is done, the next is ready tomorrow"
            : position
    }

    // MARK: - Steps

    private var stepList: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("The Path").kicker().padding(.horizontal, Theme.Spacing.xs)
            ForEach(Array(steps.enumerated()), id: \.element.id) { index, puzzle in
                stepRow(index: index, puzzle: puzzle)
            }
        }
    }

    @ViewBuilder
    private func stepRow(index: Int, puzzle: Puzzle) -> some View {
        let state = stepState(index: index)
        if state == .upcoming {
            // Not navigable: the sequence is the point. It unlocks the moment
            // the step before it is solved — no date gate, just order.
            row(index: index, puzzle: puzzle, state: state)
        } else {
            NavigationLink(value: puzzle) {
                row(index: index, puzzle: puzzle, state: state)
            }
            .buttonStyle(PressableCardStyle())
        }
    }

    private enum StepState { case done, current, upcoming }

    private func stepState(index: Int) -> StepState {
        if recordsByID[quest.puzzleIDs[index]]?.isCompleted == true { return .done }
        return index == progress.currentIndex ? .current : .upcoming
    }

    private func row(index: Int, puzzle: Puzzle, state: StepState) -> some View {
        HStack(spacing: Theme.Spacing.m) {
            stepMarker(index: index, state: state)
            VStack(alignment: .leading, spacing: 2) {
                Text(puzzle.title)
                    .font(.subheadline.weight(state == .current ? .semibold : .regular))
                    .foregroundStyle(state == .upcoming ? .secondary : .primary)
                Text(puzzle.reference)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if state != .upcoming {
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .elevatedCard()
        .opacity(state == .upcoming ? 0.55 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(stepAccessibilityLabel(index: index, puzzle: puzzle, state: state))
    }

    private func stepMarker(index: Int, state: StepState) -> some View {
        ZStack {
            Circle()
                .fill(state == .done ? Color.green.opacity(0.15) : quest.accent.opacity(state == .current ? 0.15 : 0.06))
                .frame(width: 36, height: 36)
            switch state {
            case .done:
                Image(systemName: "checkmark")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.green)
            case .current:
                Image(systemName: "play.fill")
                    .font(.subheadline)
                    .foregroundStyle(quest.accent)
            case .upcoming:
                Text("\(index + 1)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func stepAccessibilityLabel(index: Int, puzzle: Puzzle, state: StepState) -> String {
        let position = "Step \(index + 1) of \(steps.count)"
        switch state {
        case .done: return "\(position), \(puzzle.title), complete"
        case .current: return "\(position), \(puzzle.title), up next"
        case .upcoming: return "\(position), \(puzzle.title), locked until the step before is solved"
        }
    }

    // MARK: - Locked

    private var lockedState: some View {
        VStack(spacing: Theme.Spacing.m) {
            ContentUnavailableView(
                "Premium Journey",
                systemImage: "crown.fill",
                description: Text("Unlock Premium to walk every Journey, a step a day.")
            )
            Button {
                showPaywall = true
            } label: {
                Text("Unlock Premium")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }
}

// MARK: - Row card (Packs tab)

/// A Journey's tile in the Packs tab list — the quest sibling of `PackCard`.
struct QuestCard: View {
    let quest: QuestLine
    let progress: QuestProgress
    let isLocked: Bool

    @ScaledMetric(relativeTo: .title) private var iconSize = 52

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            Image(systemName: quest.coverSymbol)
                .font(.title2)
                .foregroundStyle(quest.accent)
                .frame(width: iconSize, height: iconSize)
                .background(quest.accent.opacity(0.14), in: .rect(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                HStack(spacing: Theme.Spacing.xs) {
                    Text(quest.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    if isLocked {
                        Image(systemName: "crown.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                    }
                }
                Text(quest.blurb)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                // Locked states size, not progress — same reasoning as
                // `PackCard`: premium quests overlap the daily rotation.
                if isLocked {
                    Text("\(progress.total) steps, one a day")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .padding(.top, 2)
                } else if progress.isComplete {
                    Label("Complete", systemImage: "checkmark.seal.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                        .padding(.top, 2)
                } else {
                    ProgressView(value: progress.fraction)
                        .tint(quest.accent)
                        .padding(.top, 2)
                    Text("Step \(min(progress.solved + 1, progress.total)) of \(progress.total)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .elevatedCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        var parts = [quest.title, quest.blurb]
        if isLocked {
            parts.append("Premium")
            parts.append("\(progress.total) steps")
        } else {
            parts.append(progress.isComplete
                ? "Complete"
                : "Step \(min(progress.solved + 1, progress.total)) of \(progress.total)")
        }
        return parts.joined(separator: ". ")
    }
}

// MARK: - Home card

/// The Journey's slot on Home — same shape as `MemoryVerseCard`, with a copy
/// ladder that carries the one-step-a-day framing.
struct QuestHomeCard: View {
    let quest: QuestLine
    let progress: QuestProgress

    var body: some View {
        NavigationLink(value: QuestRoute(quest: quest, source: .home)) {
            HStack(spacing: Theme.Spacing.m) {
                Image(systemName: quest.coverSymbol)
                    .font(.title2)
                    .foregroundStyle(quest.accent)
                    .frame(width: 44, height: 44)
                    .background(quest.accent.opacity(0.14), in: .circle)
                VStack(alignment: .leading, spacing: 2) {
                    Label("JOURNEY", systemImage: "map").kicker()
                    Text(headline)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(subtitle)
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
            .elevatedCard()
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Journey. \(headline). \(subtitle)")
    }

    private var headline: String {
        if progress.solved == 0 { return "Begin the \(quest.title) journey" }
        if progress.steppedToday { return "Step \(progress.solved) of \(progress.total) done" }
        return "Day \(progress.solved + 1) of \(progress.total) — the next step is ready"
    }

    private var subtitle: String {
        if progress.solved == 0 { return quest.blurb }
        if progress.steppedToday { return "The next step will be waiting tomorrow." }
        return quest.title
    }
}
