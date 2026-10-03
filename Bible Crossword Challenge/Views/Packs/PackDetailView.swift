//
//  PackDetailView.swift
//  Bible Crossword Challenge
//
//  One collection: a header with progress, then its puzzles in authored order.
//  Premium packs show their contents but route play through the paywall (the
//  free starter pack plays straight through). Celebrates a fully-solved pack.
//
//  Locked, it lists the puzzles with a lock on each and pins one offer to the
//  bottom. Until 2026-10 a locked pack hid its list behind a centred crown
//  block — the page sold a pack without showing what was in it, from the
//  entry point that converts best (3 purchases from 14 openers in 60 days).
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
        // The collection on the left of a wide window, its puzzles on the
        // right.
        CardColumns(alignment: .leading) {
            header
            // Shown locked as well as unlocked: which books a collection
            // covers is part of deciding whether to buy it.
            booksCard
        } more: {
            if isLocked {
                lockedPuzzleList
            } else {
                puzzleList
            }
        }
        .background(Theme.background)
        .safeAreaInset(edge: .bottom) {
            if isLocked { lockedOffer }
        }
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
                // Neutral while locked, like the row it was opened from:
                // colour on these screens means "you can open this".
                CollectionCover(
                    symbol: pack.coverSymbol,
                    accent: pack.accent,
                    isLocked: isLocked,
                    side: 64,
                    font: .largeTitle,
                    cornerRadius: 16
                )
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
                Text("Books in this pack").kicker()

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
                "Books in this pack: \(books.map(\.name).formatted(.list(type: .and))). "
                + journeyLine(fresh: fresh)
            )
        }
    }

    private func journeyLine(fresh: [BibleCanon.Book]) -> String {
        // Not "your journey": the Packs tab calls its paced runs Journeys, and
        // the same word for the book map made one screen mean two things.
        guard !fresh.isEmpty else { return "You've already played puzzles from all of these." }
        return "Finishing this adds \(fresh.map(\.name).formatted(.list(type: .and))) to the books you've explored."
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
            Image(systemName: "chevron.forward")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Locked state

    /// The pack's puzzles, shown rather than withheld: the titles are what a
    /// player is deciding to pay for. Each row opens the paywall.
    private var lockedPuzzleList: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("Included with Premium").kicker()
                .padding(.horizontal, Theme.Spacing.xs)
            ForEach(puzzles) { puzzle in
                Button {
                    showPaywall = true
                } label: {
                    HStack(spacing: Theme.Spacing.m) {
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
                        Image(systemName: "lock.fill")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                    .padding(Theme.Spacing.l)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .elevatedCard()
                }
                .buttonStyle(PressableCardStyle())
                .accessibilityLabel("\(puzzle.title). \(puzzle.difficulty.label). \(puzzle.clueCount) clues. Premium")
                .accessibilityHint("Opens Premium plans")
            }
        }
    }

    /// One offer, pinned where the thumb is. Same words as every other card
    /// that opens the paywall — never "Unlock", which overstates a tap that
    /// only opens it (see `PremiumCopy.cardCTA`). It replaced a "Premium
    /// Collection" headline in system yellow: 1.39:1 on the paper canvas.
    private var lockedOffer: some View {
        VStack(spacing: Theme.Spacing.s) {
            Text(lockedNote)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button(PremiumCopy.cardCTA(store)) { showPaywall = true }
                .buttonStyle(.pillProminent)
        }
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.top, Theme.Spacing.s)
        .padding(.bottom, Theme.Spacing.s)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
        .background(Theme.background)
    }

    /// For a seasonal pack, the date it goes away — the honest reason to decide
    /// now, and a fact the app already knows, so it belongs here rather than in
    /// urgency copy.
    private var lockedNote: String {
        let base = "Opens with every pack and Journey in Premium."
        guard let end = pack.seasonEnd() else { return base }
        return "Here until \(end.formatted(Self.seasonEndFormat)). " + base
    }
}
