//
//  QuestDetailView.swift
//  Bible Crossword Challenge
//
//  One Journey: its title, then today's step as a card with its grid and the
//  page's one button, the steps in walking order with their grids, and the
//  verse it opens on at the foot (2026-11-03; it was the pack page's layout,
//  which read as a document rather than a game). Steps unlock front to back —
//  the sequence is the feature — but pacing stays soft: finishing today's step
//  swaps the copy to "ready tomorrow" without ever locking the next one.
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

/// A Journey step opened from a Journey — its page or the Puzzles tab's lead.
/// Its own type, not a bare `Puzzle`, so the game logs `entrySource:
/// "journey"`: until 2026-11-03 these logged as whichever stack pushed them
/// ("pack" on the Puzzles tab, "home", "profile"), and Journey starts were
/// unreadable. Every stack that can show a Journey page registers it.
struct JourneyPuzzleRoute: Hashable {
    let puzzle: Puzzle
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
                    // Today's step first, as a card with its grid: the one
                    // thing to do here (2026-11-03). The verse and blurb went
                    // to the foot — between the button and the list they
                    // pushed the steps off the first screen.
                    if !isLocked {
                        upNextCard(steps: steps, progress: progress)
                    }
                    stepList(steps, recordsByID: recordsByID, progress: progress)
                    CollectionAbout(heading: "About this Journey", first: steps.first, blurb: quest.blurb)
                }
                .padding(.horizontal, Theme.Spacing.m + Theme.Spacing.xs)
                .padding(.top, Theme.Spacing.s)
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

    /// The title and where in Scripture it runs. No step path since
    /// 2026-11-03: the step list below already shows where the player stands,
    /// and the path said it a third time.
    private func cover(steps: [Puzzle], progress: QuestProgress) -> some View {
        let label = PackCoverLabel(puzzles: steps)
        let size = "\(progress.total) step\(progress.total == 1 ? "" : "s"), one a day"
        return CollectionPageCover(
            title: quest.title,
            caption: label.caption.isEmpty ? size : "\(label.caption) · \(size)",
            isLocked: isLocked
        ) {
            EmptyView()
        } footer: {
            EmptyView()
        }
    }

    // MARK: - Up next

    /// Today's step as a card: its grid, where it sits in the run, what it
    /// is, and the page's one action. Finished, the card says so and offers
    /// the first step again.
    @ViewBuilder
    private func upNextCard(steps: [Puzzle], progress: QuestProgress) -> some View {
        if progress.isComplete, let first = steps.first {
            UpNextCard(
                puzzle: first,
                kicker: "Complete · \(progress.total) of \(progress.total)",
                kickerSymbol: "checkmark.seal.fill"
            ) {
                NavigationLink(value: JourneyPuzzleRoute(puzzle: first)) {
                    Label("Play again from step 1", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.pillTonal)
            }
        } else if let index = progress.currentIndex, steps.indices.contains(index) {
            let puzzle = steps[index]
            UpNextCard(
                puzzle: puzzle,
                kicker: progress.steppedToday
                    ? "Step \(index + 1) of \(progress.total) · ready tomorrow"
                    : "Step \(index + 1) of \(progress.total) · today",
                kickerSymbol: nil
            ) {
                playButton(puzzle, index: index, progress: progress)
            }
        }
    }

    // MARK: - Play

    /// The page's one action: the current step, the blue pill. Once today's
    /// step is done the next still opens — pacing is soft — but the pill drops
    /// to its quiet weight, so playing ahead is offered rather than urged.
    private func playButton(_ puzzle: Puzzle, index: Int, progress: QuestProgress) -> some View {
        Group {
            if progress.steppedToday {
                NavigationLink(value: JourneyPuzzleRoute(puzzle: puzzle)) {
                    Label("Play ahead", systemImage: "forward.fill")
                }
                .buttonStyle(.pillTonal)
            } else {
                NavigationLink(value: JourneyPuzzleRoute(puzzle: puzzle)) {
                    Label(index == 0 ? "Start" : "Play step \(index + 1)", systemImage: "play.fill")
                }
                .buttonStyle(.pillAccent)
            }
        }
    }

    // MARK: - Steps

    /// The path as one grouped list, as a pack's puzzles: each step's grid,
    /// passage and difficulty. Locked, every row opens the paywall and none
    /// wears a lock — the chip on the cover says Premium once. Open, done
    /// steps carry a check, today's step says so in blue, and later steps say
    /// what opens them (they were faded to half, which read as broken).
    private func stepList(
        _ steps: [Puzzle], recordsByID: [String: PuzzleRecord], progress: QuestProgress
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s + Theme.Spacing.xs) {
            Text("The steps").sectionHeader()
            CardGroup(dividerInset: TrackRow<EmptyView>.gridDividerInset) {
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
        } else {
            NavigationLink(value: JourneyPuzzleRoute(puzzle: puzzle)) {
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
            detail: puzzle.detailLine,
            numeralTint: Color.secondary,
            grid: puzzle.grid
        ) {
            if !isLocked {
                switch state {
                case .done:
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                case .current:
                    Text("Today")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                case .upcoming:
                    Label("After step \(index)", systemImage: "lock.fill")
                        .labelStyle(.titleAndIcon)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
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
            .cardRowPadding()
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
