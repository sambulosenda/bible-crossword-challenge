//
//  PackDetailView.swift
//  Bible Crossword Challenge
//
//  One collection: a header with progress, then its puzzles in authored order.
//  Premium packs show their contents but route play through the paywall (the
//  free starter pack plays straight through). Celebrates a fully-solved pack.
//
//  One page for every pack, locked or open (design canvas, 2026-10-24): a
//  full-bleed cover in the pack's colour, the verse the pack opens on, and
//  the puzzles it holds. Locked, the cover wears the Premium chip and one
//  offer is pinned to the bottom; open, the cover carries the player's
//  progress and the Start pill. Until 2026-10 a locked pack hid its list
//  behind a centred crown block — the page sold a pack without showing what
//  was in it, from the entry point that converts best (3 purchases from 14
//  openers in 60 days).
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

        // One view whether locked or open, so the paywall sheet below hangs
        // off something a purchase can't tear down: the page changes what it
        // shows, not what it is.
        return packPage(puzzles: puzzles, recordsByID: recordsByID, progress: progress)
        .background(Theme.background)
        .safeAreaInset(edge: .bottom) {
            if isLocked { CollectionLockedOffer { showPaywall = true } }
        }
        // White bar items over the cover; the system's own once it has
        // scrolled away and the bar sits on the paper.
        .toolbarColorScheme(headerScrolledAway ? nil : .dark, for: .navigationBar)
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

    // MARK: - Page

    @State private var headerScrolledAway = false

    /// The cover full-bleed under the bar, then the verse the pack opens on,
    /// then what's in it. One column at every width — the cover is the page's
    /// top edge, which a split into columns would cut in half.
    ///
    /// The open page was its own layout until 2026-10-24 — an icon header, a
    /// black pill, a card of book chips and a list with chevrons — so buying
    /// Premium turned the page into a plainer version of the one that sold it.
    private func packPage(
        puzzles: [Puzzle], recordsByID: [String: PuzzleRecord], progress: PackProgress
    ) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                cover(
                    label: PackCoverLabel(puzzles: puzzles),
                    progress: progress,
                    next: isLocked ? nil : nextPuzzle(puzzles, recordsByID: recordsByID),
                    recordsByID: recordsByID
                )
                .onScrolledUnderBar { headerScrolledAway = $0 }
                VStack(alignment: .leading, spacing: 28) {
                    CollectionOpening(first: puzzles.first, blurb: pack.blurb)
                    if isLocked {
                        lockedPuzzleList(puzzles)
                    } else {
                        puzzleList(puzzles, recordsByID: recordsByID)
                        booksLine(puzzles)
                    }
                }
                .padding(.horizontal, Theme.Spacing.m + Theme.Spacing.xs)
                .padding(.top, 28)
                .padding(.bottom, Theme.Spacing.l)
                .frame(maxWidth: 560, alignment: .leading)
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// The cover — see `CollectionPageCover` — with the rising steps in the
    /// corner. Locked, the gold chip says what it costs; open, the player's
    /// progress and the pill that plays the next puzzle take its place.
    private func cover(
        label: PackCoverLabel, progress: PackProgress, next: Puzzle?, recordsByID: [String: PuzzleRecord]
    ) -> some View {
        CollectionPageCover(
            title: pack.title,
            caption: coverCaption(label: label, total: progress.total),
            fill: pack.coverFill,
            isLocked: isLocked
        ) {
            GridMotif()
                .offset(x: 34, y: -28)
        } footer: {
            if !isLocked {
                coverProgress(progress)
                if let next {
                    playButton(next, recordsByID: recordsByID, progress: progress)
                        .padding(.top, Theme.Spacing.xs)
                }
            }
        }
    }

    /// Where the player stands, on the cover in white: nothing before the
    /// first solve (the caption already says how many there are), a bar and
    /// a count once begun, a seal once every puzzle is solved.
    @ViewBuilder
    private func coverProgress(_ progress: PackProgress) -> some View {
        if progress.isComplete {
            Label("Pack complete — every puzzle solved", systemImage: "checkmark.seal.fill")
                .font(.subheadline.weight(.semibold))
        } else if progress.solved > 0 {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                ProgressView(value: progress.fraction)
                    .tint(.white)
                Text("\(progress.solved) of \(progress.total) solved")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.82))
                    .monospacedDigit()
            }
            .accessibilityElement(children: .combine)
        }
    }

    /// "Psalms 120–134 · 5 puzzles", and for a seasonal pack when it goes —
    /// the honest reason to decide now, and a fact the app already knows.
    private func coverCaption(label: PackCoverLabel, total: Int) -> String {
        var parts = [Self.puzzleCount(total)]
        if !label.caption.isEmpty { parts.insert(label.caption, at: 0) }
        if let end = pack.seasonEnd() { parts.append("here until \(end.formatted(Self.seasonEndFormat))") }
        return parts.joined(separator: " · ")
    }

    /// "5 crosswords": the word for what they are, in a crossword app.
    private static func puzzleCount(_ total: Int) -> String {
        "\(total) crossword\(total == 1 ? "" : "s")"
    }

    // MARK: - Play

    /// The puzzle the button opens: one already begun, else the first not
    /// yet solved. Nil once every puzzle is solved.
    private func nextPuzzle(_ puzzles: [Puzzle], recordsByID: [String: PuzzleRecord]) -> Puzzle? {
        puzzles.first { PuzzleStatus(record: recordsByID[$0.id]) == .inProgress }
            ?? puzzles.first { recordsByID[$0.id]?.isCompleted != true }
    }

    /// The page's one action, as an album page has Play — the white pill on
    /// the cover's colour. Before it, the only way into a pack was to choose
    /// a row: the screen asked a question ("which one?") it already knew the
    /// answer to.
    private func playButton(
        _ puzzle: Puzzle, recordsByID: [String: PuzzleRecord], progress: PackProgress
    ) -> some View {
        let begun = progress.solved > 0 || PuzzleStatus(record: recordsByID[puzzle.id]) == .inProgress
        return NavigationLink(value: puzzle) {
            Label("\(begun ? "Continue" : "Start") · \(puzzle.title)", systemImage: "play.fill")
        }
        .buttonStyle(.pillOnColor)
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
    /// in this pack — the question the line answers is what finishing it would
    /// *add*.
    private var exploredBooks: Set<String> {
        let solved = Set(records.filter(\.isCompleted).map(\.puzzleID))
        return BibleJourney.booksTouched(
            completedPuzzleIDs: solved, puzzles: puzzleProvider.allPuzzles
        )
    }

    /// What finishing the pack would add to the books explored, as one line
    /// under the list — only when it adds any. It was a card of book chips
    /// (2026-10-24 and before): a fourth box on the page, and the chips
    /// looked like buttons and weren't. The caption already names the books.
    @ViewBuilder
    private func booksLine(_ puzzles: [Puzzle]) -> some View {
        let books = packBooks(puzzles)
        let explored = books.isEmpty ? [] : exploredBooks
        let fresh = books.filter { !explored.contains($0.name) }
        if !fresh.isEmpty {
            Label(journeyLine(fresh: fresh), systemImage: "book")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func journeyLine(fresh: [BibleCanon.Book]) -> String {
        // Not "your journey": the Packs tab calls its paced runs Journeys, and
        // the same word for the book map made one screen mean two things.
        "Finishing this adds \(fresh.map(\.displayName).formatted(.list(type: .and))) to the books you've explored."
    }

    // MARK: - Puzzle list

    /// A track list, as a book's contents page sets it: serif numerals in the
    /// pack's colour, each row naming its passage and difficulty, and the
    /// player's status on the right. No chevron, like every other row in the
    /// app — the whole row is the tap target.
    private func puzzleList(_ puzzles: [Puzzle], recordsByID: [String: PuzzleRecord]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s + Theme.Spacing.xs) {
            Text("In this pack").sectionHeader()
            CardGroup(dividerInset: TrackRow<EmptyView>.gridDividerInset) {
                ForEach(Array(puzzles.enumerated()), id: \.element.id) { index, puzzle in
                    let record = recordsByID[puzzle.id]
                    NavigationLink(value: puzzle) {
                        TrackRow(
                            number: index + 1,
                            title: puzzle.title,
                            detail: Self.detail(puzzle),
                            numeralTint: pack.accent,
                            grid: puzzle.grid
                        ) {
                            accessory(for: PuzzleStatus(record: record), record: record)
                        }
                    }
                    .buttonStyle(PressableCardStyle())
                }
            }
        }
    }

    /// "Psalm 23:1 · 7×7 · Easy": where it's from, how big, how hard — what
    /// a player chooses a crossword by. No time: the app keeps no estimate of
    /// one, and a guessed "~3 min" would be wrong half the time.
    static func detail(_ puzzle: Puzzle) -> String {
        "\(puzzle.reference) · \(puzzle.size)×\(puzzle.size) · \(puzzle.difficulty.label)"
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
            EmptyView()
        }
    }

    // MARK: - Locked state

    /// The pack's puzzles, shown rather than withheld: the titles are what a
    /// player is deciding to pay for, and each row's grid shows they're
    /// crosswords. Each row opens the paywall and wears a small lock
    /// (2026-10-25), so the tap is expected: a row that looked playable and
    /// opened an offer read as a trick.
    private func lockedPuzzleList(_ puzzles: [Puzzle]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s + Theme.Spacing.xs) {
            Text("In this pack").sectionHeader()
            CardGroup(dividerInset: TrackRow<EmptyView>.gridDividerInset) {
                ForEach(Array(puzzles.enumerated()), id: \.element.id) { index, puzzle in
                    Button {
                        showPaywall = true
                    } label: {
                        TrackRow(
                            number: index + 1,
                            title: puzzle.title,
                            detail: Self.detail(puzzle),
                            numeralTint: pack.accent,
                            grid: puzzle.grid
                        ) {
                            Image(systemName: "lock.fill")
                                .font(.footnote)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(PressableCardStyle())
                    .accessibilityLabel("\(puzzle.title). \(puzzle.size) by \(puzzle.size). \(puzzle.difficulty.label). \(puzzle.clueCount) clues. Premium")
                    .accessibilityHint("Opens Premium plans")
                }
            }
        }
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
    /// The puzzle's grid, drawn small in place of the number — a pack's rows,
    /// so the list reads as crosswords (2026-10-25). Journeys keep numbers:
    /// their order is the point.
    var grid: [String]? = nil
    @ViewBuilder let accessory: Accessory

    /// Where a list of these starts its dividers: under the title, past the
    /// number column.
    static var dividerInset: CGFloat { Theme.Spacing.m + 28 + Theme.Spacing.m }
    /// The same, past the grid column.
    static var gridDividerInset: CGFloat { Theme.Spacing.m + gridSide + Theme.Spacing.m }
    static var gridSide: CGFloat { 44 }

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            if let grid {
                // The pack's colour on a pale wash, as every icon square in the
                // app is set; the grid's own cells in it, blocks left out.
                let tint = numeralTint ?? Theme.accent
                // No gap past a Mini: at 32pt a 15×15's cells are 2pt, and a
                // 1pt gap left a faint scatter of dots instead of a grid.
                GridThumbnail(grid: grid, tint: tint, gap: grid.count > 9 ? 0 : 1, cropsToContent: true)
                    .padding(6)
                    .frame(width: Self.gridSide, height: Self.gridSide)
                    .background(tint.opacity(0.14), in: .rect(cornerRadius: 10, style: .continuous))
            } else {
                numeral
            }
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

    private var numeral: some View {
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
    }
}
