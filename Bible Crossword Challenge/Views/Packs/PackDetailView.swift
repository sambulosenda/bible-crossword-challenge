//
//  PackDetailView.swift
//  Bible Crossword Challenge
//
//  One collection: a header with progress, then its puzzles in authored order.
//  Premium packs show their contents but route play through the paywall (the
//  free starter pack plays straight through). Celebrates a fully-solved pack.
//
//  Locked, it is its own page (design canvas, 2026-10-24): a full-bleed cover
//  in the pack's colour, the verse the pack opens on, the puzzles it holds,
//  and one offer pinned to the bottom. Until 2026-10 a locked pack hid its
//  list behind a centred crown block — the page sold a pack without showing
//  what was in it, from the entry point that converts best (3 purchases from
//  14 openers in 60 days).
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
    @State private var didLogOpen = false
    @Environment(StoreService.self) private var store
    @Query private var records: [PuzzleRecord]

    @State private var showPaywall = false

    private var puzzles: [Puzzle] { puzzleProvider.puzzles(in: pack) }
    private var isLocked: Bool { pack.isPremium && !store.isPremium }

    /// Day and month only ("12 April") — the year is never in question for a
    /// window that is, by definition, running right now.
    private static let seasonEndFormat = Date.FormatStyle().day().month(.wide)

    var body: some View {
        // The record lookup is built once per body pass and handed down. It
        // was a computed property, and every row read it twice — rebuilding a
        // dictionary of all the player's records for each read.
        let recordsByID = records.byPuzzleID
        let progress = PackProgress(pack: pack, recordsByID: recordsByID)
        let puzzles = self.puzzles

        // A ZStack, not a Group: a Group hands its modifiers to each branch,
        // and the paywall sheet below would be torn down with the locked
        // branch the moment a purchase opens the pack.
        return ZStack {
            if isLocked {
                lockedPage(puzzles: puzzles, total: progress.total)
            } else {
                // The collection on the left of a wide window, its puzzles on
                // the right.
                CardColumns(alignment: .leading) {
                    header(progress: progress, books: packBooks(puzzles))
                        .onScrolledUnderBar { headerScrolledAway = $0 }
                    if let next = nextPuzzle(puzzles, recordsByID: recordsByID) {
                        playButton(next, recordsByID: recordsByID, progress: progress)
                    }
                    booksCard(puzzles)
                } more: {
                    puzzleList(puzzles, recordsByID: recordsByID)
                }
            }
        }
        .background(Theme.background)
        .safeAreaInset(edge: .bottom) {
            if isLocked { lockedOffer }
        }
        // White bar items over the cover; the system's own once it has
        // scrolled away and the bar sits on the paper.
        .toolbarColorScheme(isLocked && !headerScrolledAway ? .dark : nil, for: .navigationBar)
        .navigationTitle(pack.title)
        .navigationBarTitleDisplayMode(.inline)
        // The header names the screen; the bar takes the name over only once
        // the header has scrolled under it.
        .revealedTitle(pack.title, when: headerScrolledAway)
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
        // Once per visit: `.task` runs again on every pop back from a pushed
        // puzzle, which counted one opener several times.
        .task {
            guard !didLogOpen else { return }
            didLogOpen = true
            analytics.log(.packOpened(id: pack.id, source: source.rawValue))
        }
    }

    // MARK: - Header

    @State private var headerScrolledAway = false

    /// Set on the paper, not in a card — the way the Journey screen's header
    /// already sat, and an album's in Music: the page's title isn't a module
    /// among modules.
    private func header(progress: PackProgress, books: [BibleCanon.Book]) -> some View {
        // One text column beside the cover: the status line under the blurb,
        // not under the cover, where it hung off a different left edge from
        // the title it describes.
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
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
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(pack.title).font(.title2.weight(.bold))
                    Text(pack.blurb)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                seasonLine

                // What it covers and how big it is, in one line. Locked or
                // unstarted, that's the whole status: a locked pack states
                // its size rather than the player's progress through it (see
                // `PackCard`), and an empty bar measures nothing.
                if isLocked || progress.solved == 0 {
                    Text(metaLine(books: books, total: progress.total))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                } else if progress.isComplete {
                    Label("Pack complete — every puzzle solved", systemImage: "checkmark.seal.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.green)
                } else {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        ProgressView(value: progress.fraction)
                            .tint(pack.accent)
                        Text("\(progress.solved) of \(progress.total) solved")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.xs)
        .padding(.top, Theme.Spacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// A locked pack as an editorial page (design canvas, 2026-10-24): its
    /// cover full-bleed under the bar, then the verse it opens on, then what's
    /// in it. One column at every width — the cover is the page's top edge,
    /// which a split into columns would cut in half.
    ///
    /// It was a feature card inside the margins with the book's mark behind
    /// the title — the same card the Packs tab leads with, so the page that
    /// sells the pack looked like the tab that listed it.
    private func lockedPage(puzzles: [Puzzle], total: Int) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                lockedCover(label: PackCoverLabel(puzzles: puzzles), total: total)
                    .onScrolledUnderBar { headerScrolledAway = $0 }
                VStack(alignment: .leading, spacing: 28) {
                    lockedOpening(puzzles.first)
                    lockedPuzzleList(puzzles)
                }
                .padding(.horizontal, Theme.Spacing.m + Theme.Spacing.xs)
                .padding(.top, 28)
                .padding(.bottom, Theme.Spacing.l)
                .frame(maxWidth: 560, alignment: .leading)
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// The cover: the pack's colour edge to edge, the rising steps in the
    /// corner, and the chip, the serif title and where in Scripture it sits.
    private func lockedCover(label: PackCoverLabel, total: Int) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s + Theme.Spacing.xs) {
            PremiumChip()
            Text(pack.title)
                .font(.system(.largeTitle, design: .serif, weight: .semibold))
                .tracking(-0.6)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(coverCaption(label: label, total: total))
                .font(.body)
                .foregroundStyle(.white.opacity(0.82))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: 560, alignment: .leading)
        .padding(.horizontal, Theme.Spacing.m + Theme.Spacing.xs)
        .padding(.top, Theme.Spacing.xl)
        .padding(.bottom, 28)
        // 290 under the bar, about 388 with it — the canvas's cover.
        .frame(maxWidth: .infinity, minHeight: 290, alignment: .bottom)
        .background(alignment: .bottomTrailing) {
            RisingSteps()
                .padding(.trailing, Theme.Spacing.m + Theme.Spacing.xs)
        }
        // The colour runs on up under the bar and the status bar, so the cover
        // is the page's top edge; the scroll view still insets its content
        // for the bar, which is where the type wants to start anyway.
        .background {
            pack.coverFill
                .padding(.top, -400)
                .ignoresSafeArea(edges: .top)
        }
        .accessibilityElement(children: .combine)
    }

    /// "Psalms 120–134 · 5 puzzles", and for a seasonal pack when it goes —
    /// the honest reason to decide now, and a fact the app already knows.
    private func coverCaption(label: PackCoverLabel, total: Int) -> String {
        var parts = [Self.puzzleCount(total)]
        if !label.caption.isEmpty { parts.insert(label.caption, at: 0) }
        if let end = pack.seasonEnd() { parts.append("here until \(end.formatted(Self.seasonEndFormat))") }
        return parts.joined(separator: " · ")
    }

    /// The verse the pack opens on, in serif, with where it's from and what
    /// the pack is. A pack whose first puzzle has no verse falls back to its
    /// blurb alone.
    @ViewBuilder
    private func lockedOpening(_ first: Puzzle?) -> some View {
        if let first, !first.verse.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(first.verse)
                    .font(.scripture(.title2))
                    .tracking(-0.2)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(first.reference) · \(pack.blurb)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
        } else {
            Text(pack.blurb)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private static func puzzleCount(_ total: Int) -> String {
        "\(total) puzzle\(total == 1 ? "" : "s")"
    }

    /// "Psalms · 5 puzzles"; past three books, just the count.
    private func metaLine(books: [BibleCanon.Book], total: Int) -> String {
        let count = "\(total) puzzle\(total == 1 ? "" : "s")"
        guard !books.isEmpty, books.count <= 3 else { return count }
        return books.map(\.displayName).joined(separator: ", ") + " · " + count
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

    // MARK: - Play

    /// The puzzle the button opens: one already begun, else the first not
    /// yet solved. Nil once every puzzle is solved.
    private func nextPuzzle(_ puzzles: [Puzzle], recordsByID: [String: PuzzleRecord]) -> Puzzle? {
        puzzles.first { PuzzleStatus(record: recordsByID[$0.id]) == .inProgress }
            ?? puzzles.first { recordsByID[$0.id]?.isCompleted != true }
    }

    /// The page's one action, as an album page has Play. Before it, the only
    /// way into a pack was to choose a row — the screen asked a question
    /// ("which one?") it already knew the answer to.
    private func playButton(
        _ puzzle: Puzzle, recordsByID: [String: PuzzleRecord], progress: PackProgress
    ) -> some View {
        let begun = progress.solved > 0 || PuzzleStatus(record: recordsByID[puzzle.id]) == .inProgress
        return NavigationLink(value: puzzle) {
            Label("\(begun ? "Continue" : "Start") · \(puzzle.title)", systemImage: "play.fill")
        }
        .buttonStyle(.pillProminent)
    }

    // MARK: - Books

    /// The books this collection's puzzles are drawn from, in reading order.
    ///
    /// Nothing maps packs to books: every puzzle already anchors to one through
    /// its verse reference, so a pack covers whatever its puzzles cover and the
    /// two can't fall out of step.
    private func packBooks(_ puzzles: [Puzzle]) -> [BibleCanon.Book] {
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

    /// Only when finishing the pack would add books the player hasn't
    /// explored. Otherwise the books are named in the header line, and a
    /// card of one chip — a bordered "Psalm" that looked like a button and
    /// wasn't — over "You've already played puzzles from all of these" said
    /// nothing worth a card.
    @ViewBuilder
    private func booksCard(_ puzzles: [Puzzle]) -> some View {
        let books = packBooks(puzzles)
        let explored = books.isEmpty ? [] : exploredBooks
        let fresh = books.filter { !explored.contains($0.name) }
        if !fresh.isEmpty {
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
                "Books in this pack: \(books.map(\.displayName).formatted(.list(type: .and))). "
                + journeyLine(fresh: fresh)
            )
        }
    }

    private func journeyLine(fresh: [BibleCanon.Book]) -> String {
        // Not "your journey": the Packs tab calls its paced runs Journeys, and
        // the same word for the book map made one screen mean two things.
        "Finishing this adds \(fresh.map(\.displayName).formatted(.list(type: .and))) to the books you've explored."
    }

    /// Explored books borrow the map's own fill, so the two screens agree about
    /// what "you've been here" looks like.
    private func bookChip(_ book: BibleCanon.Book, explored: Bool) -> some View {
        let state: BibleJourney.BookProgress.State = explored ? .touched : .untouched
        return Text(book.displayName)
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

    /// A track list: one grouped card, numbered rows, the difficulty in plain
    /// text. Five cards each wearing a coloured difficulty capsule made the
    /// list the loudest thing on the page.
    private func puzzleList(_ puzzles: [Puzzle], recordsByID: [String: PuzzleRecord]) -> some View {
        CardGroup(dividerInset: TrackRow<EmptyView>.dividerInset) {
            ForEach(Array(puzzles.enumerated()), id: \.element.id) { index, puzzle in
                let record = recordsByID[puzzle.id]
                NavigationLink(value: puzzle) {
                    TrackRow(number: index + 1, title: puzzle.title, detail: Self.detail(puzzle)) {
                        accessory(for: PuzzleStatus(record: record), record: record)
                    }
                }
                .buttonStyle(PressableCardStyle())
            }
        }
    }

    /// "Easy · 15 clues".
    static func detail(_ puzzle: Puzzle) -> String {
        "\(puzzle.difficulty.label) · \(puzzle.clueCount) clues"
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
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Locked state

    /// The pack's puzzles, shown rather than withheld: the titles are what a
    /// player is deciding to pay for. Each row opens the paywall. No lock on
    /// each row since 2026-10-24 — the chip on the cover already says
    /// Premium once, and five locks made a contents page read as a wall.
    /// Serif numerals in the pack's colour and the passage each comes from,
    /// as a book's contents page sets them.
    private func lockedPuzzleList(_ puzzles: [Puzzle]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s + Theme.Spacing.xs) {
            Text("In this pack").sectionHeader()
            CardGroup(dividerInset: TrackRow<EmptyView>.dividerInset) {
                ForEach(Array(puzzles.enumerated()), id: \.element.id) { index, puzzle in
                    Button {
                        showPaywall = true
                    } label: {
                        TrackRow(
                            number: index + 1,
                            title: puzzle.title,
                            detail: "\(puzzle.reference) · \(puzzle.difficulty.label)",
                            numeralTint: pack.accent
                        ) {
                            EmptyView()
                        }
                    }
                    .buttonStyle(PressableCardStyle())
                    .accessibilityLabel("\(puzzle.title). \(puzzle.difficulty.label). \(puzzle.clueCount) clues. Premium")
                    .accessibilityHint("Opens Premium plans")
                }
            }
        }
    }

    /// One offer, pinned where the thumb is: the ink pill, as the Premium
    /// page's own button, over a fade into the paper so the list scrolls away
    /// under it rather than ending at a hard edge (design canvas, 2026-10-24).
    /// The words are every Premium card's — never "Unlock", which overstates
    /// a tap that only opens the paywall (see `PremiumCopy.cardCTA`).
    private var lockedOffer: some View {
        VStack(spacing: 10) {
            Button(PremiumCopy.cardCTA(store)) { showPaywall = true }
                .buttonStyle(.pillProminent)
                .accessibilityHint("Opens Premium plans")
            Text(offerTerms)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Theme.Spacing.m + Theme.Spacing.xs)
        .padding(.top, Theme.Spacing.xl)
        .padding(.bottom, Theme.Spacing.s)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
        .background {
            LinearGradient(
                stops: [.init(color: Theme.background.opacity(0), location: 0),
                        .init(color: Theme.background, location: 0.3)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }

    /// "Then $9.99 a year · every pack included" — the price behind the
    /// button, and that it's the whole shelf, not this pack.
    private var offerTerms: String {
        guard let yearly = store.yearly else { return "Every pack included" }
        let price = "\(store.yearlyPriceText) a year"
        let lead = store.introOffer(for: yearly) != nil ? "Then \(price)" : price
        return "\(lead) · every pack included"
    }
}

// MARK: - Track row

/// One row of a collection's puzzle list, numbered the way an album's track
/// list is. Shared by packs and Journeys, locked and open.
struct TrackRow<Accessory: View>: View {
    let number: Int
    let title: String
    let detail: String
    /// Sets the number in serif, in this colour — a locked pack's contents
    /// page. Nil keeps the plain grey track number.
    var numeralTint: Color? = nil
    @ViewBuilder let accessory: Accessory

    /// Where a list of these starts its dividers: under the title, past the
    /// number column.
    static var dividerInset: CGFloat { Theme.Spacing.m + 28 + Theme.Spacing.m }

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            Group {
                if let numeralTint {
                    Text("\(number)")
                        .font(.system(.title2, design: .serif, weight: .semibold))
                        .foregroundStyle(numeralTint)
                } else {
                    Text("\(number)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .monospacedDigit()
            .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            accessory
        }
        .cardRowPadding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
    }
}
