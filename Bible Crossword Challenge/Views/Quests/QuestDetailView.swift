//
//  QuestDetailView.swift
//  Bible Crossword Challenge
//
//  One Journey, on the same page as a pack (design canvas, 2026-10-24): the
//  cover full-bleed in the Journey's colour with its step path, the verse it
//  opens on, then its steps in walking order. Steps unlock front to back —
//  the sequence is the feature — but pacing stays soft: finishing today's step
//  swaps the copy to "back tomorrow" without ever locking the next one.
//  Premium Journeys show their steps but gate play behind the paywall, like
//  premium packs.
//
//  It kept an older layout of its own — grey icon, a lock on every row, the
//  blue offer button — after the pack page moved on, so the two screens one
//  tap apart on the Packs tab looked like two apps.
//

import SwiftUI
import SwiftData

/// The surfaces that can open a quest — same closed-set contract as
/// `PackOpenSource`, so `quest_opened` can always say where from.
enum QuestOpenSource: String, Hashable {
    case home
    case packs
    case profile
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
    @State private var didLogOpen = false
    @Environment(StoreService.self) private var store
    @Query private var records: [PuzzleRecord]

    @State private var showPaywall = false
    @State private var headerScrolledAway = false

    private var steps: [Puzzle] { puzzleProvider.puzzles(in: quest) }
    private var isLocked: Bool { quest.isPremium && !store.isPremium }

    var body: some View {
        // Built once per body pass and handed down — it was a computed
        // property that every step row rebuilt, once per row.
        let recordsByID = records.byPuzzleID
        let progress = QuestProgress(quest: quest, recordsByID: recordsByID)
        let steps = self.steps

        // One view whether locked or open, so the paywall sheet below hangs
        // off something a purchase can't tear down. One column at every
        // width, as the pack page: the cover is the page's top edge.
        return ScrollView {
            VStack(spacing: 0) {
                cover(steps: steps, progress: progress)
                    .onScrolledUnderBar { headerScrolledAway = $0 }
                VStack(alignment: .leading, spacing: 28) {
                    CollectionOpening(first: steps.first, blurb: quest.blurb)
                    stepList(steps, recordsByID: recordsByID, progress: progress)
                }
                .padding(.horizontal, Theme.Spacing.m + Theme.Spacing.xs)
                .padding(.top, 28)
                .padding(.bottom, Theme.Spacing.l)
                .frame(maxWidth: 560, alignment: .leading)
            }
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background)
        .safeAreaInset(edge: .bottom) {
            if isLocked { CollectionLockedOffer { showPaywall = true } }
        }
        // White bar items over the cover; the system's own once it has
        // scrolled away and the bar sits on the paper.
        .toolbarColorScheme(headerScrolledAway ? nil : .dark, for: .navigationBar)
        .navigationTitle(quest.title)
        .navigationBarTitleDisplayMode(.inline)
        // The header names the screen; the bar takes the name over only once
        // the header has scrolled under it.
        .revealedTitle(quest.title, when: headerScrolledAway)
        .sheet(isPresented: $showPaywall) {
            PaywallView(source: .questLocked)
        }
        // questCompleted is logged in the game screen's completion hook, so it
        // fires exactly once even if this screen is never revisited.
        // Once per visit: `.task` runs again on every pop back from a pushed
        // puzzle, which counted one opener several times.
        .task {
            guard !didLogOpen else { return }
            didLogOpen = true
            analytics.log(.questOpened(id: quest.id, source: source.rawValue))
        }
    }

    // MARK: - Cover

    /// The pack page's cover, with the Journey's step path where a pack has
    /// its rising steps — the path is what a Journey is, and the Packs shelf
    /// already draws it on the Journey's card. Locked, the chip; open, where
    /// the player stands and the pill for today's step.
    private func cover(steps: [Puzzle], progress: QuestProgress) -> some View {
        let label = PackCoverLabel(puzzles: steps)
        let size = "\(progress.total) step\(progress.total == 1 ? "" : "s"), one a day"
        return CollectionPageCover(
            title: quest.title,
            caption: label.caption.isEmpty ? size : "\(label.caption) · \(size)",
            fill: quest.coverFill,
            isLocked: isLocked
        ) {
            EmptyView()
        } footer: {
            StepPath(done: isLocked ? 0 : progress.solved, total: progress.total)
                .padding(.vertical, Theme.Spacing.xs)
            if !isLocked {
                if progress.isComplete {
                    Label("Journey complete", systemImage: "checkmark.seal.fill")
                        .font(.subheadline.weight(.semibold))
                } else if progress.solved > 0 {
                    Text(progressLine(progress))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.82))
                        .monospacedDigit()
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let index = progress.currentIndex, steps.indices.contains(index) {
                    playButton(steps[index], index: index, progress: progress)
                        .padding(.top, Theme.Spacing.xs)
                }
            }
        }
    }

    /// "Step 3 of 7" plus the soft-pacing nudge when today's step is done.
    private func progressLine(_ progress: QuestProgress) -> String {
        let position = "Step \(min(progress.solved + 1, progress.total)) of \(progress.total)"
        return progress.steppedToday
            ? "\(position) — today's step is done, the next is ready tomorrow"
            : position
    }

    // MARK: - Play

    /// The page's one action: the current step, the white pill on the cover.
    /// Once today's step is done the next still opens — pacing is soft — but
    /// the pill drops to its quiet weight, so playing ahead is offered rather
    /// than urged.
    private func playButton(_ puzzle: Puzzle, index: Int, progress: QuestProgress) -> some View {
        Group {
            if progress.steppedToday {
                NavigationLink(value: puzzle) {
                    Label("Play ahead · \(puzzle.title)", systemImage: "forward.fill")
                }
                .buttonStyle(.pillOnColorTonal)
            } else {
                NavigationLink(value: puzzle) {
                    Label("\(index == 0 ? "Start" : "Step \(index + 1)") · \(puzzle.title)",
                          systemImage: "play.fill")
                }
                .buttonStyle(.pillOnColor)
            }
        }
    }

    // MARK: - Steps

    /// The path as one grouped list, as a pack's puzzles: serif numerals in
    /// the Journey's colour, each step's passage and difficulty. Locked, every
    /// row opens the paywall and none wears a lock — the chip on the cover
    /// says Premium once. Open, done steps carry a check, today's step says
    /// so, and later steps sit back until the one before is solved.
    private func stepList(
        _ steps: [Puzzle], recordsByID: [String: PuzzleRecord], progress: QuestProgress
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s + Theme.Spacing.xs) {
            Text("The steps").sectionHeader()
            CardGroup(dividerInset: TrackRow<EmptyView>.dividerInset) {
                ForEach(Array(steps.enumerated()), id: \.element.id) { index, puzzle in
                    stepRow(index: index, puzzle: puzzle,
                            state: stepState(index: index, recordsByID: recordsByID, progress: progress))
                }
            }
        }
    }

    @ViewBuilder
    private func stepRow(index: Int, puzzle: Puzzle, state: StepState) -> some View {
        if isLocked {
            Button {
                showPaywall = true
            } label: {
                row(index: index, puzzle: puzzle, state: .upcoming)
            }
            .buttonStyle(PressableCardStyle())
            .accessibilityHint("Opens Premium plans")
        } else if state == .upcoming {
            // Not navigable: the sequence is the point. It unlocks the moment
            // the step before it is solved — no date gate, just order.
            row(index: index, puzzle: puzzle, state: state)
                .opacity(0.5)
        } else {
            NavigationLink(value: puzzle) {
                row(index: index, puzzle: puzzle, state: state)
            }
            .buttonStyle(PressableCardStyle())
        }
    }

    private enum StepState { case done, current, upcoming }

    private func stepState(
        index: Int, recordsByID: [String: PuzzleRecord], progress: QuestProgress
    ) -> StepState {
        if recordsByID[quest.puzzleIDs[index]]?.isCompleted == true { return .done }
        return index == progress.currentIndex ? .current : .upcoming
    }

    private func row(index: Int, puzzle: Puzzle, state: StepState) -> some View {
        TrackRow(
            number: index + 1,
            title: puzzle.title,
            detail: PackDetailView.detail(puzzle),
            numeralTint: quest.accent
        ) {
            if !isLocked {
                switch state {
                case .done:
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                case .current:
                    Text("Today")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                case .upcoming:
                    EmptyView()
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(stepAccessibilityLabel(index: index, puzzle: puzzle, state: state))
    }

    private func stepAccessibilityLabel(index: Int, puzzle: Puzzle, state: StepState) -> String {
        let position = "Step \(index + 1) of \(quest.puzzleIDs.count)"
        if isLocked { return "\(position), \(puzzle.title). Premium" }
        switch state {
        case .done: return "\(position), \(puzzle.title), complete"
        case .current: return "\(position), \(puzzle.title), up next"
        case .upcoming: return "\(position), \(puzzle.title), locked until the step before is solved"
        }
    }
}

extension QuestProgress {
    /// "Step 1 of 5" — shared by the row and the lead card so the same run
    /// can't be described two ways on one screen.
    static func stepLine(solved: Int, total: Int) -> String {
        "Step \(min(solved + 1, total)) of \(total)"
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
            // The Journey feature's tint, not this Journey's own colour: on
            // Today each row is coloured by what kind of thing it is. The
            // Packs tab keeps the per-Journey colour on its covers. The bar
            // shows once a step is walked — an empty one is a gauge with
            // nothing to measure.
            CoverRow(
                symbol: quest.coverSymbol,
                tint: FeatureTint.journey,
                title: headline,
                subtitle: subtitle,
                progress: progress.solved > 0 ? progress.fraction : nil
            )
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Journey. \(headline). \(subtitle)")
    }

    // Title is the pack's name and never wraps; the state goes in the
    // subtitle. The old headline ("Day 3 of 5 — the next step is ready",
    // "Begin the Beginnings journey") truncated at default type on every
    // phone, and the blurb under it truncated too.
    private var headline: String { quest.title }

    /// "Journey" leads the line only before the first step; after that the
    /// cover and the bar say what kind of thing this is.
    private var subtitle: String {
        if progress.solved == 0 { return "Journey · \(progress.total) steps, one a day" }
        if progress.steppedToday { return "Step \(progress.solved) of \(progress.total) done · next one tomorrow" }
        // "Step", as the Packs tab and the journey itself count it.
        return "\(QuestProgress.stepLine(solved: progress.solved, total: progress.total)) is ready"
    }
}
