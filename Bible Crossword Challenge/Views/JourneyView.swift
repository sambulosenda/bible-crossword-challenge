//
//  JourneyView.swift
//  Bible Crossword Challenge
//
//  Where a player's solving has taken them through Scripture. Achievements are
//  discrete; this is the continuous view — "I've been through twelve books".
//
//  Two thirds of the canon has no puzzle written for it yet, which is the fact
//  that shapes the whole screen. A grid of sixty-six cells mostly greyed out
//  reads as a scolding for work the player was never offered, so books with no
//  puzzles are drawn as absent rather than unfinished, and progress counts
//  against what actually exists.
//

import SwiftUI
import SwiftData

struct JourneyView: View {
    /// Which surface pushed it — see `JourneyCard`.
    var source: String = "read_tab"

    @Environment(\.puzzleProvider) private var puzzleProvider
    @Environment(\.analytics) private var analytics
    @Environment(StoreService.self) private var store
    @Query private var records: [PuzzleRecord]

    /// Recomputed when the records change — solving a puzzle elsewhere and
    /// coming back should move the map.
    @State private var rows: [BibleJourney.BookProgress] = []

    var body: some View {
        // The summary and legend on the left of a wide window, the map on
        // the right.
        CardColumns {
            summaryCard
            legendNote
        } more: {
            testamentSection(.old)
            testamentSection(.new)
        }
        .background(Theme.background)
        // "Books explored", not "Your journey": the Packs tab calls its paced
        // runs Journeys, and one word for two features made both harder to find.
        .navigationTitle("Books explored")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            reload()
            analytics.log(.journeyOpened(source: source))
        }
        .onChange(of: records.count, reload)
    }

    private func reload() {
        let solved = Set(records.filter(\.isCompleted).map(\.puzzleID))
        rows = BibleJourney.progress(
            completedPuzzleIDs: solved,
            puzzles: puzzleProvider.allPuzzles
        )
    }

    // MARK: - Summary

    private var reachable: [BibleJourney.BookProgress] { rows.filter { $0.available > 0 } }
    private var touched: [BibleJourney.BookProgress] { rows.filter { $0.solved > 0 } }

    /// The book a player should open next: the first in canon order with
    /// puzzles they haven't touched, falling back to any with puzzles left.
    private var nextBook: BibleJourney.BookProgress? {
        reachable.first { $0.solved == 0 } ?? reachable.first { !$0.isComplete }
    }

    /// Leads with what to do, not a score. On a first visit the old headline
    /// was a 56pt blue "0" — the loudest thing on the screen, and the least
    /// encouraging. The count still leads once there is one to show, and is
    /// counted against books *with puzzles*: against 66 it would be capped at
    /// two thirds by the content backlog, not the journey.
    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(touched.isEmpty
                     ? "Every puzzle you solve marks its book here"
                     : "\(touched.count) of \(reachable.count) books explored")
                    .font(.scripture(.title2, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                if !touched.isEmpty {
                    ProgressView(value: Double(touched.count), total: Double(max(reachable.count, 1)))
                        .tint(Theme.accent)
                        .padding(.vertical, Theme.Spacing.xs)
                    HStack(spacing: Theme.Spacing.l) {
                        testamentStat(.old)
                        testamentStat(.new)
                    }
                }
            }
            if let next = nextBook {
                NavigationLink {
                    JourneyBookView(book: next.book)
                } label: {
                    Label(
                        touched.isEmpty ? "Start with \(next.name)" : "Next: \(next.name)",
                        systemImage: "arrow.right"
                    )
                }
                .buttonStyle(.pillProminent)
                .accessibilityHint("\(next.available) puzzles from \(next.name)")
            }
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .elevatedCard()
    }

    private func testamentStat(_ testament: Testament) -> some View {
        let all = reachable.filter { $0.testament == testament }
        let done = all.filter { $0.solved > 0 }
        return Text("\(testament.label) \(done.count)/\(all.count)")
            .font(.subheadline)
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .accessibilityLabel("\(testament.label): \(done.count) of \(all.count) explored")
    }

    /// One line instead of a four-swatch key. Solved books carry their count
    /// (and a check once finished) on the chip, so only the faded state needs
    /// saying — and it's the one a player would otherwise read as their own
    /// omission.
    private var legendNote: some View {
        Text("Faded books don't have puzzles yet.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Spacing.xs)
    }

    // MARK: - The map

    private func testamentSection(_ testament: Testament) -> some View {
        let books = rows.filter { $0.testament == testament }
        return VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text(testament.label).sectionHeader()
                .padding(.horizontal, Theme.Spacing.xs)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 104), spacing: Theme.Spacing.s)],
                spacing: Theme.Spacing.s
            ) {
                ForEach(books) { row in
                    if row.state == .empty {
                        // Nothing to open, so it isn't a button — a control that
                        // does nothing is worse than a label.
                        JourneyChip(row: row)
                    } else {
                        // Destination-based rather than value-based on purpose.
                        // Profile pushes this screen with a destination link, and
                        // mixing the two mechanisms in one stack made a tapped
                        // book push and unwind again in the same breath.
                        NavigationLink {
                            JourneyBookView(book: row.book)
                        } label: {
                            JourneyChip(row: row)
                        }
                        .buttonStyle(PressableCardStyle())
                    }
                }
            }
        }
    }
}

// MARK: - Chip

/// One book on the map.
private struct JourneyChip: View {
    let row: BibleJourney.BookProgress

    var body: some View {
        HStack(spacing: 4) {
            Text(row.name)
                .font(.caption.weight(row.state == .deep ? .semibold : .regular))
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
            if row.isComplete {
                Image(systemName: "checkmark")
                    .font(.caption2.weight(.bold))
            } else if row.solved > 0 {
                Text("\(row.solved)")
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
            }
        }
        .foregroundStyle(JourneyStyle.text(row.state))
        .padding(.horizontal, Theme.Spacing.s)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(JourneyStyle.fill(row.state), in: .rect(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    JourneyStyle.border(row.state),
                    lineWidth: JourneyStyle.borderWidth(row.state)
                )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }

    private var label: String {
        switch row.state {
        case .empty: return "\(row.name), no puzzles yet"
        case .untouched: return "\(row.name), not yet explored, \(row.available) available"
        case .touched, .deep:
            let done = row.isComplete ? ", all solved" : ""
            return "\(row.name), \(row.solved) of \(row.available) solved\(done)"
        }
    }
}

/// One place deciding how a state looks, so the grid and its legend can't drift.
enum JourneyStyle {
    static func fill(_ state: BibleJourney.BookProgress.State) -> Color {
        switch state {
        // No tile at all: the book is absent from the game, not unfinished.
        case .empty: .clear
        case .untouched: Theme.surface
        case .touched: Theme.accent.opacity(0.13)
        case .deep: Theme.accent.opacity(0.30)
        }
    }

    /// Visited and explored are two strengths of one hue, which is a difference
    /// that survives neither a small swatch nor a colour-blind reader nor
    /// greyscale. Explored gets a drawn ring as well, so the distinction is
    /// carried by shape and not only by intensity.
    static func border(_ state: BibleJourney.BookProgress.State) -> Color {
        switch state {
        case .empty: .clear
        case .untouched: Color.primary.opacity(0.10)
        case .touched: Theme.accent.opacity(0.22)
        case .deep: Theme.accent.opacity(0.85)
        }
    }

    /// Explored draws a heavier ring; everything else a hairline.
    static func borderWidth(_ state: BibleJourney.BookProgress.State) -> CGFloat {
        state == .deep ? 2 : 1
    }

    static func text(_ state: BibleJourney.BookProgress.State) -> Color {
        switch state {
        case .empty: Color.secondary.opacity(0.45)
        case .untouched: .primary
        case .touched, .deep: Theme.accent
        }
    }
}

// MARK: - One book

/// The puzzles anchored to a book, and where the player stands in them.
struct JourneyBookView: View {
    let book: BibleCanon.Book

    @Environment(\.puzzleProvider) private var puzzleProvider
    @Environment(\.scripture) private var scripture
    @Query private var records: [PuzzleRecord]
    @State private var bibleBook: BibleBook?

    private var puzzles: [Puzzle] {
        puzzleProvider.allPuzzles.filter { BibleJourney.book(for: $0)?.name == book.name }
    }

    private var recordsByID: [String: PuzzleRecord] {
        records.byPuzzleID
    }

    var body: some View {
        let byID = recordsByID
        let solved = puzzles.filter { byID[$0.id]?.isCompleted == true }.count
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                header(solved: solved)
                    .padding(.bottom, Theme.Spacing.s)
                ForEach(puzzles) { puzzle in
                    PuzzleLinkRow(puzzle: puzzle, record: byID[puzzle.id], paywallSource: .journey)
                }
            }
            .padding(Theme.Spacing.m)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background)
        .navigationTitle(book.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await scripture.preload()
            bibleBook = scripture.book(named: book.name)
        }
    }

    /// Where the player stands in the book, and the way back to its text. A
    /// book with one puzzle was a single row on an empty page, with nothing
    /// tying the puzzles to the scripture they come from.
    private func header(solved: Int) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(book.testament.label).kicker()
                Text(progressLine(solved: solved))
                    .font(.scripture(.title3, weight: .semibold))
            }
            if let bibleBook {
                NavigationLink {
                    ChapterPickerView(book: bibleBook)
                } label: {
                    Label("Read \(book.name)", systemImage: "book")
                }
                .buttonStyle(.pillTonal)
            }
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .elevatedCard()
    }

    private func progressLine(solved: Int) -> String {
        let count = puzzles.count
        let noun = count == 1 ? "puzzle" : "puzzles"
        if solved == 0 { return "\(count) \(noun) drawn from \(book.name)" }
        if solved >= count { return "All \(count) \(noun) solved" }
        return "\(solved) of \(count) \(noun) solved"
    }
}

// MARK: - Puzzle row

/// One puzzle as a tappable row, gated the way every way into the catalogue
/// is. Shared by a book's page and the Verses tab's search.
struct PuzzleLinkRow: View {
    let puzzle: Puzzle
    let record: PuzzleRecord?
    let paywallSource: PaywallSource

    @Environment(\.puzzleProvider) private var puzzleProvider
    @Environment(\.openURL) private var openURL
    @Environment(StoreService.self) private var store
    @Environment(\.challengeService) private var challengeService
    @State private var showPaywall = false

    var body: some View {
        let access = PuzzleAccess(provider: puzzleProvider, challengedIDs: challengeService.pendingPuzzleIDs)
        // A browsable list of every puzzle would otherwise be a way around
        // the paywall.
        let unlocked = access.canPlay(puzzle, isPremium: store.isPremium, hasProgress: record != nil)

        Button {
            if unlocked {
                if let url = URL(string: "biblecrossword://puzzle?id=\(puzzle.id)") {
                    openURL(url)
                }
            } else {
                showPaywall = true
            }
        } label: {
            HStack(spacing: Theme.Spacing.m) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(puzzle.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: Theme.Spacing.s) {
                        DifficultyBadge(difficulty: puzzle.difficulty)
                        // The format, not the reference: a book's puzzles
                        // often share one verse ("Ruth 1:16" four times),
                        // and two of them share a title.
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                trailing(unlocked: unlocked)
            }
            .padding(Theme.Spacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .elevatedCard()
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(unlocked: unlocked))
        .accessibilityHint(unlocked ? "Opens this puzzle" : "Opens Premium upgrade options")
        .sheet(isPresented: $showPaywall) {
            PaywallView(source: paywallSource)
        }
    }

    private var detail: String {
        let format: String
        switch puzzle.kind {
        case .mini: format = "Mini"
        case .sunday: format = "Sunday"
        default: format = "Daily"
        }
        return "\(format) · \(puzzle.clueCount) clues"
    }

    @ViewBuilder
    private func trailing(unlocked: Bool) -> some View {
        if record?.isCompleted == true {
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(.green)
        } else if !unlocked {
            Image(systemName: "crown.fill")
                .font(.subheadline)
                .foregroundStyle(.yellow)
        } else {
            Image(systemName: "chevron.forward")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
    }

    private func accessibilityLabel(unlocked: Bool) -> String {
        var parts = [puzzle.title, puzzle.difficulty.label, detail]
        if record?.isCompleted == true {
            parts.append("solved")
        } else if !unlocked {
            parts.append("Premium")
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Journey

/// The way into the map. A row rather than the map itself: sixty-six books
/// would swamp a hub screen, and the count is the part worth seeing from
/// here. Lived on Profile until 2.8; the Read tab is its home now.
///
/// Its own type with its own query: as a computed property on the parent the
/// books-explored count (a pass over every record plus
/// `BibleJourney.booksTouched`) re-ran on every parent body evaluation.
/// Owning the query here means only record changes invalidate it, and the
/// query itself fetches solved records only.
struct JourneyCard: View {
    /// Which surface pushed it — `read_tab`, or `profile` before 2.8.
    var source: String = "read_tab"
    /// A row inside a grouped card rather than a card of its own.
    var grouped = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @Environment(\.puzzleProvider) private var puzzleProvider
    @Query(filter: #Predicate<PuzzleRecord> { $0.isCompleted })
    private var solvedRecords: [PuzzleRecord]

    var body: some View {
        NavigationLink {
            JourneyView(source: source)
        } label: {
            // The same row shape as Memory verses and Bookmarks beside it on
            // the Read tab: a disc icon, a headline, a caption.
            HStack(spacing: Theme.Spacing.m) {
                if !dynamicTypeSize.isAccessibilitySize {
                    Image(systemName: "map.fill")
                        .font(grouped ? .body : .title2)
                        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                        .foregroundStyle(Theme.accent)
                        .frame(width: grouped ? RowIcon.side : 44, height: grouped ? RowIcon.side : 44)
                        .background(Theme.accent.opacity(0.14), in: .circle)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Books explored")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(journeySummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, grouped ? Theme.Spacing.m : Theme.Spacing.l)
            .padding(.vertical, grouped ? 12 : Theme.Spacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
            .background {
                if !grouped { Color.clear.elevatedCard() }
            }
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Books explored. \(journeySummary)")
        .accessibilityHint("Opens the map of books you've explored")
    }

    /// Counted against the books that have puzzles, as the map's own
    /// headline is — this row said "of 66" while the screen it opens said
    /// "of 43", and against 66 the score could never pass two thirds.
    private var journeySummary: String {
        let rows = BibleJourney.progress(
            completedPuzzleIDs: Set(solvedRecords.map(\.puzzleID)),
            puzzles: puzzleProvider.allPuzzles
        )
        let reachable = rows.filter { $0.available > 0 }.count
        let explored = rows.filter { $0.solved > 0 }.count
        return "\(explored) of \(reachable) books with puzzles"
    }
}
