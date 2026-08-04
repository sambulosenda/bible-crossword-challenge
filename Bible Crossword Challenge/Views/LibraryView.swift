//
//  LibraryView.swift
//  Bible Crossword Challenge
//
//  Premium-only library of every puzzle — searchable, filterable by difficulty
//  and completion status, with a one-tap jump to the next unsolved puzzle. Free
//  users see a locked state that routes to the paywall.
//
//  Called a library, not an archive, because that is what it is: the daily
//  puzzle rotates with `days % pool.count` (see PuzzleProvider.rotated), so
//  every puzzle recurs every 82 days and none of them belongs to a date. Copy
//  here promises a collection to browse, never a day to go back to.
//

import SwiftUI
import SwiftData

struct LibraryView: View {
    let profile: PlayerProfile

    @Environment(\.puzzleProvider) private var puzzleProvider
    @Environment(StoreService.self) private var store
    @Query private var records: [PuzzleRecord]

    @State private var query = ""
    @State private var difficulty: PuzzleDifficulty?
    @State private var statusFilter: ArchiveStatusFilter = .all
    @State private var showPaywall = false

    private var puzzles: [Puzzle] { puzzleProvider.puzzles }
    private var minis: [Puzzle] { puzzleProvider.minis }

    /// One lookup built per body pass, reused by filtering and rows instead of
    /// scanning `records` for every puzzle. `puzzleID` is unique, so this is safe.
    private var recordsByID: [String: PuzzleRecord] {
        Dictionary(uniqueKeysWithValues: records.map { ($0.puzzleID, $0) })
    }

    private func status(for puzzle: Puzzle) -> PuzzleStatus {
        PuzzleStatus(record: recordsByID[puzzle.id])
    }

    private var filtered: [Puzzle] {
        puzzles.filter(matches)
    }

    /// Minis honour the search and status filters; the difficulty filter only
    /// narrows the full-size list (minis are all quick and easy by design).
    private var filteredMinis: [Puzzle] {
        guard difficulty == nil else { return [] }
        return minis.filter { mini in
            (query.isEmpty || mini.title.localizedCaseInsensitiveContains(query))
                && statusMatches(mini)
        }
    }

    private func matches(_ puzzle: Puzzle) -> Bool {
        (query.isEmpty || puzzle.title.localizedCaseInsensitiveContains(query))
            && (difficulty == nil || puzzle.difficulty == difficulty)
            && statusMatches(puzzle)
    }

    private func statusMatches(_ puzzle: Puzzle) -> Bool {
        switch statusFilter {
        case .all: return true
        case .unsolved: return status(for: puzzle) != .completed
        case .completed: return status(for: puzzle) == .completed
        }
    }

    /// First puzzle the player hasn't completed, honouring the difficulty filter.
    private var nextUnsolved: Puzzle? {
        puzzles.first {
            (difficulty == nil || $0.difficulty == difficulty) && status(for: $0) != .completed
        }
    }

    private var isFiltering: Bool { difficulty != nil || statusFilter != .all }

    private var completedCount: Int {
        let ids = Set(puzzles.map(\.id))
        return records.filter { $0.isCompleted && ids.contains($0.puzzleID) }.count
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.isPremium {
                    premiumList
                } else {
                    lockedState
                }
            }
            .navigationTitle("Library")
            .navigationDestination(for: Puzzle.self) { puzzle in
                CrosswordGameView(puzzle: puzzle, profile: profile)
            }
            .sheet(isPresented: $showPaywall) {
                // Source stays "archive" even though the screen is now called
                // Library — renaming it would split this entry point's
                // conversion history in Firebase at an arbitrary point.
                PaywallView(source: "archive")
            }
        }
    }

    // MARK: - Premium list

    private var premiumList: some View {
        List {
            if query.isEmpty, statusFilter != .completed, let next = nextUnsolved {
                Section {
                    nextUnsolvedRow(next)
                }
            }

            Section {
                ForEach(filtered) { puzzle in
                    row(puzzle)
                }
            } header: {
                progressHeader
            }

            if !filteredMinis.isEmpty {
                Section {
                    ForEach(filteredMinis) { mini in
                        row(mini)
                    }
                } header: {
                    Text("Minis")
                }
            }
        }
        // Warm paper canvas behind the native list rows (see ProfileView).
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .searchable(text: $query, prompt: "Search puzzles")
        .toolbar { filterMenu }
        .overlay {
            if filtered.isEmpty && filteredMinis.isEmpty {
                if query.isEmpty {
                    ContentUnavailableView(
                        "No Puzzles",
                        systemImage: "line.3.horizontal.decrease.circle",
                        description: Text("No puzzles match these filters.")
                    )
                } else {
                    ContentUnavailableView.search(text: query)
                }
            }
        }
    }

    /// Completion as a bar, not a sentence. This is the one screen whose whole
    /// subject is how much of the collection you've finished, and it was
    /// stating that in a grey section header.
    private var progressHeader: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack {
                Text("\(completedCount) of \(puzzles.count) solved")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
                if completedCount > 0 {
                    Text("\(Int((Double(completedCount) / Double(max(puzzles.count, 1)) * 100).rounded()))%")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            ProgressView(value: Double(completedCount), total: Double(max(puzzles.count, 1)))
                .tint(Theme.accent)
        }
        .textCase(nil)          // section headers upper-case by default
        .padding(.bottom, Theme.Spacing.xs)
        .accessibilityElement(children: .combine)
    }

    @ToolbarContentBuilder
    private var filterMenu: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Picker("Difficulty", selection: $difficulty) {
                    Text("All Difficulties").tag(PuzzleDifficulty?.none)
                    ForEach(PuzzleDifficulty.allCases, id: \.self) { difficulty in
                        Text(difficulty.label).tag(Optional(difficulty))
                    }
                }
                .pickerStyle(.inline)

                Picker("Show", selection: $statusFilter) {
                    ForEach(ArchiveStatusFilter.allCases) { filter in
                        Text(filter.label).tag(filter)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Image(systemName: isFiltering
                    ? "line.3.horizontal.decrease.circle.fill"
                    : "line.3.horizontal.decrease.circle")
            }
            .accessibilityLabel("Filter")
        }
    }

    private func nextUnsolvedRow(_ puzzle: Puzzle) -> some View {
        NavigationLink(value: puzzle) {
            HStack(spacing: Theme.Spacing.m) {
                Image(systemName: "play.circle.fill")
                    .font(.title)
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Next unsolved")
                        .font(.subheadline.weight(.semibold))
                    Text(puzzle.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 2)
        }
        .accessibilityLabel("Next unsolved puzzle, \(puzzle.title)")
    }

    private func row(_ puzzle: Puzzle) -> some View {
        let record = recordsByID[puzzle.id]
        let status = PuzzleStatus(record: record)

        return NavigationLink(value: puzzle) {
            HStack(spacing: Theme.Spacing.m) {
                // Each puzzle's own grid shape. Eighty-two rows of title-plus-
                // badge are indistinguishable at a glance; the shape is what
                // makes one scannable from the next, and it's real data.
                GridThumbnail(grid: puzzle.grid, tint: thumbnailTint(for: status))
                    .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(puzzle.title)
                        .font(.headline)
                    HStack(spacing: Theme.Spacing.s) {
                        DifficultyBadge(difficulty: puzzle.difficulty)
                        Text("\(puzzle.clueCount) clues")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                accessory(for: status, record: record)
            }
            .padding(.vertical, 2)
        }
    }

    /// Solved grids sit back; unsolved ones keep the accent, so scrolling the
    /// list shows at a glance how far through the collection you are.
    private func thumbnailTint(for status: PuzzleStatus) -> Color {
        status == .completed
            ? Color.primary.opacity(0.18)
            : Theme.accent.opacity(0.40)
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
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
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

    /// The half most people see. It used to be a `ContentUnavailableView` with
    /// a yellow crown and the headline "Premium Feature" — the name of a
    /// business model rather than a benefit, set in system yellow on paper at
    /// 1.39:1, which fails every contrast threshold including large text.
    ///
    /// Now it shows the collection it's withholding: real titles, real grids,
    /// locked. Same device as the paywall's pack strip.
    private var lockedState: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    Text("Premium")
                        .kicker()
                    Text("Every puzzle,\nwhenever you like.")
                        .font(.scripture(.largeTitle, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    // Both numbers, deliberately. This used to quote only the
                    // archive's own count to avoid looking like a different
                    // claim from the paywall's — but the reader meets the two
                    // totals anyway, on Today and in onboarding, and a screen
                    // that says 82 while everything else says 177 reads as a
                    // contradiction rather than as scoping. Naming the whole
                    // library *and* this screen's share of it settles that in
                    // one sentence, and sells the larger thing while it's at it.
                    Text("All \(puzzleProvider.totalPuzzleCount) puzzles, including every one of the \(puzzles.count) dailies in this archive — play and replay as often as you want.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                lockedPreview

                Button {
                    showPaywall = true
                } label: {
                    Text("Unlock Premium")
                }
                .buttonStyle(.pillProminent)
            }
            .padding(Theme.Spacing.l)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background)
    }

    /// Four real rows from the collection, dimmed and locked.
    private var lockedPreview: some View {
        VStack(spacing: 0) {
            ForEach(Array(puzzles.prefix(4)), id: \.id) { puzzle in
                HStack(spacing: Theme.Spacing.m) {
                    GridThumbnail(grid: puzzle.grid, tint: Color.primary.opacity(0.18))
                        .frame(width: 34, height: 34)
                    Text(puzzle.title)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "lock.fill")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(Theme.Spacing.m)

                if puzzle.id != puzzles.prefix(4).last?.id {
                    Rectangle()
                        .fill(Color.primary.opacity(0.06))
                        .frame(height: 1)
                        .padding(.leading, Theme.Spacing.m)
                }
            }
        }
        .elevatedCard()
        .accessibilityElement(children: .ignore)
        // Four rows are shown; the label describes the archive they stand for,
        // which is the daily pool rather than the whole library.
        .accessibilityLabel("Locked preview of the \(puzzles.count) daily puzzles in this archive")
    }
}

// MARK: - Status filter

private enum ArchiveStatusFilter: String, CaseIterable, Identifiable {
    case all, unsolved, completed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "All"
        case .unsolved: return "Unsolved"
        case .completed: return "Completed"
        }
    }
}
