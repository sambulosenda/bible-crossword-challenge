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
    @State private var didLogOpen = false
    @Environment(StoreService.self) private var store
    @Query private var records: [PuzzleRecord]

    @State private var showPaywall = false

    private var steps: [Puzzle] { puzzleProvider.puzzles(in: quest) }
    private var isLocked: Bool { quest.isPremium && !store.isPremium }

    var body: some View {
        // Built once per body pass and handed down — it was a computed
        // property that every step row rebuilt, once per row.
        let recordsByID = records.byPuzzleID
        let progress = QuestProgress(quest: quest, recordsByID: recordsByID)
        let steps = self.steps

        // The Journey on the left of a wide window, its steps on the right.
        return CardColumns(alignment: .leading) {
            header(progress: progress)
                .onScrolledUnderBar { headerScrolledAway = $0 }
            if !isLocked, let index = progress.currentIndex, steps.indices.contains(index) {
                playButton(steps[index], index: index, progress: progress)
            }
        } more: {
            stepList(steps, recordsByID: recordsByID, progress: progress)
        }
        .background(Theme.background)
        .safeAreaInset(edge: .bottom) {
            if isLocked { lockedOffer }
        }
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

    // MARK: - Header

    @State private var headerScrolledAway = false

    private func header(progress: QuestProgress) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack(spacing: Theme.Spacing.m) {
                // Neutral while locked, like the row it was opened from:
                // colour on these screens means "you can open this".
                CollectionCover(
                    symbol: quest.coverSymbol,
                    accent: quest.accent,
                    isLocked: isLocked,
                    side: 64,
                    font: .largeTitle,
                    cornerRadius: 16
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(quest.title).font(.title2.weight(.bold))
                    Text(quest.blurb)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if isLocked || progress.solved == 0 {
                // Locked states size, not progress — see `PackCard` for why —
                // and so does a run not yet begun: an empty bar measures
                // nothing.
                Text("\(progress.total) step\(progress.total == 1 ? "" : "s"), one a day")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            } else if progress.isComplete {
                Label("Journey complete", systemImage: "checkmark.seal.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.green)
            } else {
                // The bar and its line as one unit; they sat a full stack gap
                // apart and read as two separate things.
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    ProgressView(value: progress.fraction)
                        .tint(quest.accent)
                    Text(progressLine(progress))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.xs)
        .padding(.top, Theme.Spacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// "Step 3 of 7" plus the soft-pacing nudge when today's step is done.
    private func progressLine(_ progress: QuestProgress) -> String {
        let position = "Step \(min(progress.solved + 1, progress.total)) of \(progress.total)"
        return progress.steppedToday
            ? "\(position) — today's step is done, the next is ready tomorrow"
            : position
    }

    // MARK: - Play

    /// The page's one action: the current step. Once today's step is done the
    /// next still opens — pacing is soft — but the button drops to the tonal
    /// pill, so playing ahead is offered rather than urged.
    private func playButton(_ puzzle: Puzzle, index: Int, progress: QuestProgress) -> some View {
        Group {
            if progress.steppedToday {
                NavigationLink(value: puzzle) {
                    Label("Play ahead · \(puzzle.title)", systemImage: "forward.fill")
                }
                .buttonStyle(.pillTonal)
            } else {
                NavigationLink(value: puzzle) {
                    Label("\(index == 0 ? "Start" : "Step \(index + 1)") · \(puzzle.title)",
                          systemImage: "play.fill")
                }
                .buttonStyle(.pillProminent)
            }
        }
    }

    // MARK: - Steps

    /// The path as one grouped list — steps are a sequence, and a card per
    /// step broke it into separate things. Locked, the same list shows what
    /// the Journey holds, each row opening the paywall, as a locked pack does.
    private func stepList(
        _ steps: [Puzzle], recordsByID: [String: PuzzleRecord], progress: QuestProgress
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text(isLocked ? "Included with Premium" : "The path")
                .sectionHeader()
                .padding(.horizontal, Theme.Spacing.xs)
            CardGroup(dividerInset: CollectionCardLayout.dividerInset) {
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
                row(index: index, puzzle: puzzle, state: .upcoming, dims: false)
            }
            .buttonStyle(PressableCardStyle())
            .accessibilityHint("Opens Premium plans")
        } else if state == .upcoming {
            // Not navigable: the sequence is the point. It unlocks the moment
            // the step before it is solved — no date gate, just order.
            row(index: index, puzzle: puzzle, state: state, dims: true)
        } else {
            NavigationLink(value: puzzle) {
                row(index: index, puzzle: puzzle, state: state, dims: false)
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

    private func row(index: Int, puzzle: Puzzle, state: StepState, dims: Bool) -> some View {
        HStack(spacing: Theme.Spacing.m) {
            stepMarker(index: index, state: state)
            VStack(alignment: .leading, spacing: 2) {
                Text(puzzle.title)
                    .font(.headline.weight(state == .current ? .semibold : .regular))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(puzzle.reference)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if isLocked {
                Image(systemName: "lock.fill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if state != .upcoming {
                Image(systemName: "chevron.forward")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .cardRowPadding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
        .opacity(dims ? 0.5 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(stepAccessibilityLabel(index: index, puzzle: puzzle, state: state))
    }

    /// The same rounded square as every row icon in the app: a green check
    /// when done, the Journey's colour on the step that's up, and the step's
    /// number on a neutral square for the rest.
    @ViewBuilder
    private func stepMarker(index: Int, state: StepState) -> some View {
        switch state {
        case .done:
            RowIcon(symbol: "checkmark", tint: FeatureTint.solved)
        case .current where !isLocked:
            RowIcon(symbol: "play.fill", tint: quest.accent)
        default:
            Text("\(index + 1)")
                .font(.headline)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                .frame(width: 44, height: 44)
                .background(Color.primary.opacity(0.06), in: .rect(cornerRadius: 12, style: .continuous))
                .accessibilityHidden(true)
        }
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

    // MARK: - Locked

    /// The same shape as `PackDetailView`'s locked state: the steps shown,
    /// one offer pinned where the thumb is. This screen had drifted to a
    /// centred crown block in system yellow over an "Unlock Premium" button —
    /// the word the app keeps off any button that only opens the paywall (see
    /// `PremiumCopy.cardCTA`), while the pack screen one tap away said it the
    /// house way.
    private var lockedOffer: some View {
        VStack(spacing: Theme.Spacing.s) {
            Text("\(quest.puzzleIDs.count) steps, one a day. Opens with every pack and Journey in Premium.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button(PremiumCopy.cardCTA(store)) { showPaywall = true }
                .buttonStyle(.pillProminent)
        }
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, Theme.Spacing.s)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
        .background(Theme.background)
    }
}

// MARK: - Row card (Packs tab)

/// A Journey's tile in the Packs tab list — the quest sibling of `PackCard`.
struct QuestCard: View {
    let quest: QuestLine
    let progress: QuestProgress
    let isLocked: Bool
    /// Off under the Packs tab's "With Premium" header, which says it once.
    var showsCrown = true

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .title) private var iconSize = 44

    private var isStacked: Bool { CollectionCardLayout.isStacked(dynamicTypeSize) }

    var body: some View {
        Group {
            if isStacked {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    HStack(spacing: Theme.Spacing.m) {
                        cover
                        Spacer(minLength: 0)
                        chevron
                    }
                    details
                }
            } else {
                CollectionCardLayout.row(cover: cover, details: details, chevron: chevron)
            }
        }
        .cardRowPadding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .elevatedCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var cover: some View {
        CollectionCover(
            symbol: quest.coverSymbol,
            accent: quest.accent,
            isLocked: isLocked,
            side: CollectionCardLayout.coverSize(iconSize)
        )
    }

    private var chevron: some View {
        Image(systemName: "chevron.forward")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            CollectionCardLayout.title(quest.title, locked: isLocked && showsCrown)
            Text(quest.blurb)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(CollectionCardLayout.blurbLineLimit(dynamicTypeSize))
                .fixedSize(horizontal: false, vertical: true)
            status
        }
    }

    // Locked states size, not progress — same reasoning as
    // `PackCard`: premium quests overlap the daily rotation.
    // Unstarted states its size as well, like `PackCard`.
    @ViewBuilder
    private var status: some View {
        if isLocked || progress.solved == 0 {
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
            Text(QuestProgress.stepLine(solved: progress.solved, total: progress.total))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private var accessibilityLabel: String {
        var parts = [quest.title, quest.blurb]
        if isLocked {
            parts.append("Premium")
            parts.append("\(progress.total) steps")
        } else if progress.solved == 0 {
            parts.append("\(progress.total) steps, one a day")
        } else {
            parts.append(progress.isComplete
                ? "Complete"
                : QuestProgress.stepLine(solved: progress.solved, total: progress.total))
        }
        return parts.joined(separator: ". ")
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
            HStack(spacing: Theme.Spacing.m) {
                // The Journey feature's tint, not this Journey's own colour:
                // on Today each row is coloured by what kind of thing it is.
                // The Packs tab keeps the per-Journey colour on its covers.
                RowIcon(symbol: quest.coverSymbol, tint: FeatureTint.journey)
                // No kicker: Today's "Keep going" header names the group, and
                // the subtitle says it's a journey.
                VStack(alignment: .leading, spacing: 2) {
                    Text(headline)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.forward")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .cardRowPadding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .elevatedCard()
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

    private var subtitle: String {
        if progress.solved == 0 { return "Journey · \(progress.total) steps, one a day" }
        if progress.steppedToday { return "Step \(progress.solved) of \(progress.total) done · next one tomorrow" }
        // "Step", as the Packs tab and the journey itself count it.
        return "Journey · \(QuestProgress.stepLine(solved: progress.solved, total: progress.total)) is ready"
    }
}
