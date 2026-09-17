//
//  PackDetailView.swift
//  Bible Crossword Challenge
//
//  One collection: a header with progress, then its puzzles in authored order.
//  Premium packs show their contents but route play through the paywall (the
//  free starter pack plays straight through). Celebrates a fully-solved pack.
//

import SwiftUI
import SwiftData

/// The surfaces that can open a pack. A closed set rather than a bare string,
/// so a new entry point has to name itself here and can't quietly ship as an
/// untracked one.
enum PackOpenSource: String, Hashable {
    case home
    case packs
    case notification
}

/// A pack push, tagged with the surface that made it.
///
/// Pushing a bare `PuzzlePack` was enough while every route looked the same;
/// it isn't now that `pack_opened` has to say *where* from, and a navigation
/// value is the only thing that travels from the tap to the screen that logs.
struct PackRoute: Hashable {
    let pack: PuzzlePack
    let source: PackOpenSource
}

struct PackDetailView: View {
    let pack: PuzzlePack
    let profile: PlayerProfile
    /// Which surface pushed this pack — carried on `pack_opened` so the Home
    /// carousel, the Packs tab and a season-opening notification can be told
    /// apart when judging whether a discovery surface is doing any work.
    let source: PackOpenSource

    @Environment(\.puzzleProvider) private var puzzleProvider
    @Environment(\.analytics) private var analytics
    @Environment(StoreService.self) private var store
    @Query private var records: [PuzzleRecord]

    @State private var showPaywall = false

    private var recordsByID: [String: PuzzleRecord] {
        Dictionary(records.map { ($0.puzzleID, $0) }, uniquingKeysWith: { a, _ in a })
    }

    private var puzzles: [Puzzle] { puzzleProvider.puzzles(in: pack) }
    private var progress: PackProgress { PackProgress(pack: pack, recordsByID: recordsByID) }
    private var isLocked: Bool { pack.isPremium && !store.isPremium }

    /// Day and month only ("12 April") — the year is never in question for a
    /// window that is, by definition, running right now.
    private static let seasonEndFormat = Date.FormatStyle().day().month(.wide)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                header
                // Shown locked as well as unlocked: which books a collection
                // covers is part of deciding whether to buy it.
                booksCard
                if isLocked {
                    lockedState
                } else {
                    puzzleList
                }
            }
            .padding(Theme.Spacing.m)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background)
        .navigationTitle(pack.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPaywall) {
            // A seasonal pack gets its name into the promise: "the collections
            // are waiting" is true all year, and this one isn't.
            PaywallView(
                source: .packLocked,
                subject: pack.isSeasonal ? pack.title : nil,
                contextPackID: pack.id
            )
        }
        // packCompleted is logged where it happens — the game screen's
        // completion hook — so it fires exactly once, even if this view is
        // never revisited.
        .task { analytics.log(.packOpened(id: pack.id, source: source.rawValue)) }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack(spacing: Theme.Spacing.m) {
                Image(systemName: pack.coverSymbol)
                    .font(.largeTitle)
                    .foregroundStyle(pack.accent)
                    .frame(width: 64, height: 64)
                    .background(pack.accent.opacity(0.14), in: .rect(cornerRadius: 16, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(pack.title).font(.title2.weight(.bold))
                    Text(pack.blurb)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            seasonLine

            // Locked, the header states the pack's size rather than the
            // player's progress through it — see `PackCard` for why. This
            // screen said it louder: "Pack complete — every puzzle solved",
            // directly above a Premium Collection lock and an Unlock button.
            if isLocked {
                Text("\(progress.total) puzzle\(progress.total == 1 ? "" : "s")")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            } else if progress.isComplete {
                Label("Pack complete — every puzzle solved", systemImage: "checkmark.seal.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.green)
            } else {
                ProgressView(value: progress.fraction) {
                    Text("\(progress.solved) of \(progress.total) solved")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .tint(pack.accent)
            }
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .elevatedCard()
        .accessibilityElement(children: .combine)
    }

    /// How long the pack is here for. Early in a window that's a date the player
    /// can plan around; in the closing fortnight the countdown says more than
    /// the date does, so the badge takes over rather than sitting beside it.
    @ViewBuilder
    private var seasonLine: some View {
        if let closingDays = SeasonBadge.daysRemaining(for: pack) {
            SeasonBadge(daysRemaining: closingDays)
        } else if let end = pack.seasonEnd() {
            Label(
                "In season until \(end.formatted(Self.seasonEndFormat))",
                systemImage: "calendar"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Books

    /// The books this collection's puzzles are drawn from, in reading order.
    ///
    /// Nothing maps packs to books: every puzzle already anchors to one through
    /// its verse reference, so a pack covers whatever its puzzles cover and the
    /// two can't fall out of step. Finishing a pack moves the journey map on its
    /// own — this card is what makes that visible beforehand.
    private var packBooks: [BibleCanon.Book] {
        var seen: Set<String> = []
        let books = puzzles.compactMap { BibleJourney.book(for: $0) }
            .filter { seen.insert($0.name).inserted }
        return books.sorted { BibleCanon.position(of: $0.name) < BibleCanon.position(of: $1.name) }
    }

    /// Books the player has already reached anywhere in their solving, not just
    /// in this pack — the question the card answers is what finishing it would
    /// *add*.
    private var exploredBooks: Set<String> {
        let solved = Set(records.filter(\.isCompleted).map(\.puzzleID))
        return BibleJourney.booksTouched(
            completedPuzzleIDs: solved, puzzles: puzzleProvider.allPuzzles
        )
    }

    @ViewBuilder
    private var booksCard: some View {
        let books = packBooks
        if !books.isEmpty {
            let explored = exploredBooks
            let fresh = books.filter { !explored.contains($0.name) }

            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                Text("Books in this collection").kicker()

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 96), spacing: Theme.Spacing.s)],
                    spacing: Theme.Spacing.s
                ) {
                    ForEach(books) { book in
                        bookChip(book, explored: explored.contains(book.name))
                    }
                }

                Text(journeyLine(fresh: fresh))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Theme.Spacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .elevatedCard()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                "Books in this collection: \(books.map(\.name).formatted(.list(type: .and))). "
                + journeyLine(fresh: fresh)
            )
        }
    }

    private func journeyLine(fresh: [BibleCanon.Book]) -> String {
        guard !fresh.isEmpty else { return "All of these are already part of your journey." }
        return "Finishing this adds \(fresh.map(\.name).formatted(.list(type: .and))) to your journey."
    }

    /// Explored books borrow the map's own fill, so the two screens agree about
    /// what "you've been here" looks like.
    private func bookChip(_ book: BibleCanon.Book, explored: Bool) -> some View {
        let state: BibleJourney.BookProgress.State = explored ? .touched : .untouched
        return Text(book.name)
            .font(.caption.weight(.medium))
            // A second line rather than 8pt type: the longest book names run
            // to "1 Thessalonians", and shrinking a 12pt caption by a third to
            // keep them on one line is the app overriding the size the reader
            // asked for.
            .lineLimit(2)
            .minimumScaleFactor(0.8)
            .foregroundStyle(JourneyStyle.text(state))
            .padding(.horizontal, Theme.Spacing.s)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(JourneyStyle.fill(state), in: .rect(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(JourneyStyle.border(state), lineWidth: JourneyStyle.borderWidth(state))
            }
    }

    // MARK: - Puzzle list

    private var puzzleList: some View {
        VStack(spacing: Theme.Spacing.s) {
            ForEach(puzzles) { puzzle in
                NavigationLink(value: puzzle) {
                    row(puzzle)
                }
                .buttonStyle(PressableCardStyle())
            }
        }
    }

    private func row(_ puzzle: Puzzle) -> some View {
        let status = PuzzleStatus(record: recordsByID[puzzle.id])
        return HStack(spacing: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(puzzle.title).font(.headline).foregroundStyle(.primary)
                HStack(spacing: Theme.Spacing.s) {
                    DifficultyBadge(difficulty: puzzle.difficulty)
                    Text("\(puzzle.clueCount) clues")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            accessory(for: status, record: recordsByID[puzzle.id])
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .elevatedCard()
    }

    @ViewBuilder
    private func accessory(for status: PuzzleStatus, record: PuzzleRecord?) -> some View {
        switch status {
        case .completed:
            HStack(spacing: Theme.Spacing.xs) {
                if let secs = record?.elapsedSeconds, secs > 0 {
                    Text(TimeFormat.clock(secs))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            }
        case .inProgress:
            Text("In progress")
                .font(.caption.weight(.medium))
                .foregroundStyle(.orange)
        case .start:
            Image(systemName: "chevron.right")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Locked state

    private var lockedState: some View {
        VStack(spacing: Theme.Spacing.m) {
            ContentUnavailableView {
                Label("Premium Collection", systemImage: "crown.fill")
                    .foregroundStyle(.yellow)
            } description: {
                Text(lockedDescription)
            } actions: {
                Button {
                    showPaywall = true
                } label: {
                    Text("Unlock Premium")
                }
                .buttonStyle(.pillProminent)
                .frame(maxWidth: 280)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.xl)
    }

    /// States the size of the pack, and for a seasonal one the date it goes
    /// away. The deadline is the honest reason to decide now, and it's a fact
    /// the app already knows — so it belongs here rather than in urgency copy.
    private var lockedDescription: String {
        let base = "Unlock \(pack.title) and every other collection with Premium — "
            + "\(pack.puzzleIDs.count) themed puzzles in this pack alone."
        guard let end = pack.seasonEnd() else { return base }
        return base + " This one is only here until \(end.formatted(Self.seasonEndFormat))."
    }
}
