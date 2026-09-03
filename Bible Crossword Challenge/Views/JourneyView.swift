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
        ScrollView {
            VStack(spacing: Theme.Spacing.l) {
                summaryCard
                legend
                testamentSection(.old)
                testamentSection(.new)
            }
            .padding(Theme.Spacing.m)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background)
        .navigationTitle("Your journey")
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

    /// The headline number counts books *with puzzles*, not all sixty-six.
    /// Against 66 the score would be permanently capped at half and would fall
    /// every time the canon didn't change — which is to say it would measure the
    /// content backlog, not the journey.
    private var summaryCard: some View {
        VStack(spacing: Theme.Spacing.m) {
            Text("\(touched.count)")
                .font(.system(size: 56, weight: .bold, design: .serif))
                .monospacedDigit()
                .foregroundStyle(Theme.accent)
            Text(touched.count == 1 ? "book explored" : "books explored")
                .kicker()

            Text("of \(reachable.count) with puzzles so far")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Divider()

            HStack(spacing: Theme.Spacing.l) {
                testamentStat(.old)
                testamentStat(.new)
            }
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity)
        .elevatedCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summaryLabel)
    }

    private var summaryLabel: String {
        let books = touched.count == 1 ? "book" : "books"
        return "\(touched.count) \(books) explored, of \(reachable.count) that have puzzles so far."
    }

    private func testamentStat(_ testament: Testament) -> some View {
        let all = reachable.filter { $0.testament == testament }
        let done = all.filter { $0.solved > 0 }
        return VStack(spacing: 2) {
            Text("\(done.count)/\(all.count)")
                .font(.title3.weight(.bold))
                .monospacedDigit()
            Text(testament.label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(testament.label): \(done.count) of \(all.count) explored")
    }

    /// Four fills is more than a screen can carry unexplained, and "no puzzles
    /// yet" is the one a player would otherwise read as their own omission.
    private var legend: some View {
        HStack(spacing: Theme.Spacing.m) {
            legendItem(.deep, "Explored")
            legendItem(.touched, "Visited")
            legendItem(.untouched, "Not yet")
            legendItem(.empty, "No puzzles")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }

    private func legendItem(_ state: BibleJourney.BookProgress.State, _ label: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(JourneyStyle.fill(state))
                .frame(width: 11, height: 11)
                .overlay {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .strokeBorder(
                            JourneyStyle.border(state),
                            lineWidth: JourneyStyle.borderWidth(state)
                        )
                }
            Text(label)
        }
    }

    // MARK: - The map

    private func testamentSection(_ testament: Testament) -> some View {
        let books = rows.filter { $0.testament == testament }
        return VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text(testament.label).kicker()
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
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
            if row.solved > 0 {
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
        case .empty: Color.primary.opacity(0.03)
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
        case .empty: Color.primary.opacity(0.04)
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
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @Environment(StoreService.self) private var store
    @Query private var records: [PuzzleRecord]
    @State private var showPaywall = false

    private var puzzles: [Puzzle] {
        puzzleProvider.allPuzzles.filter { BibleJourney.book(for: $0)?.name == book.name }
    }

    private var recordsByID: [String: PuzzleRecord] {
        Dictionary(records.map { ($0.puzzleID, $0) }, uniquingKeysWith: { a, _ in a })
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.s) {
                ForEach(puzzles) { puzzle in
                    row(puzzle)
                }
            }
            .padding(Theme.Spacing.m)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background)
        .navigationTitle(book.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPaywall) {
            PaywallView(source: "journey")
        }
    }

    @ViewBuilder
    private func row(_ puzzle: Puzzle) -> some View {
        let record = recordsByID[puzzle.id]
        let access = PuzzleAccess(provider: puzzleProvider)
        // The map is a new way into the catalogue, so it answers to the same
        // gate as every other one — a browsable list of every puzzle would
        // otherwise be a way around the paywall.
        let unlocked = access.canPlay(puzzle, isPremium: store.isPremium, hasProgress: record != nil)

        Button {
            if unlocked {
                if let url = URL(string: "biblecrossword://puzzle?id=\(puzzle.id)") {
                    openURL(url)
                    dismiss()
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
                        Text(puzzle.reference)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                trailing(record: record, unlocked: unlocked)
            }
            .padding(Theme.Spacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .elevatedCard()
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(puzzle, record: record, unlocked: unlocked))
        .accessibilityHint(unlocked ? "Opens this puzzle" : "Opens Premium upgrade options")
    }

    @ViewBuilder
    private func trailing(record: PuzzleRecord?, unlocked: Bool) -> some View {
        if record?.isCompleted == true {
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(.green)
        } else if !unlocked {
            Image(systemName: "crown.fill")
                .font(.subheadline)
                .foregroundStyle(.yellow)
        } else {
            Image(systemName: "chevron.right")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    private func accessibilityLabel(_ puzzle: Puzzle, record: PuzzleRecord?, unlocked: Bool) -> String {
        var parts = [puzzle.title, puzzle.difficulty.label, puzzle.reference]
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

    @Environment(\.puzzleProvider) private var puzzleProvider
    @Query(filter: #Predicate<PuzzleRecord> { $0.isCompleted })
    private var solvedRecords: [PuzzleRecord]

    var body: some View {
        NavigationLink {
            JourneyView(source: source)
        } label: {
            HStack(spacing: Theme.Spacing.m) {
                Image(systemName: "map.fill")
                    .font(.title)
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your journey")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(journeySummary)
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
        .accessibilityLabel("Your journey. \(journeySummary)")
        .accessibilityHint("Opens the map of books you've explored")
    }

    private var journeySummary: String {
        let count = booksExplored
        if count == 0 { return "See which books of the Bible you've explored" }
        return "\(count) \(count == 1 ? "book" : "books") of the Bible explored"
    }

    private var booksExplored: Int {
        BibleJourney.booksTouched(
            completedPuzzleIDs: Set(solvedRecords.map(\.puzzleID)),
            puzzles: puzzleProvider.allPuzzles
        ).count
    }
}
