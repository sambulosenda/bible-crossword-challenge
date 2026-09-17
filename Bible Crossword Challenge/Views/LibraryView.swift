//
//  LibraryView.swift
//  Bible Crossword Challenge
//
//  The library of every puzzle — searchable, filterable by difficulty and
//  completion status, with a one-tap jump to the next unsolved puzzle.
//
//  Free players see the same list behind a soft gate rather than a locked
//  screen: what they can play, then what Premium opens. The rule is in
//  `PuzzleAccess`; this file only draws it.
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
    @Environment(\.challengeService) private var challengeService
    @Query private var records: [PuzzleRecord]

    @State private var query = ""
    @State private var difficulty: PuzzleDifficulty?
    @State private var statusFilter: ArchiveStatusFilter = .all
    @State private var showPaywall = false

    private var puzzles: [Puzzle] { puzzleProvider.puzzles }
    private var minis: [Puzzle] { puzzleProvider.minis }
    private var sundays: [Puzzle] { puzzleProvider.sundays }

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

    /// Sunday Specials honour every filter the dailies do — they carry real
    /// difficulties, unlike the minis.
    private var filteredSundays: [Puzzle] {
        sundays.filter(matches)
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

    // MARK: - Free tier

    /// The soft gate. Two small windows of ids — see `PuzzleAccess` for the rule
    /// and why it holds no persisted state.
    private var access: PuzzleAccess {
        PuzzleAccess(provider: puzzleProvider, challengedIDs: challengeService.pendingPuzzleIDs)
    }

    private func canPlay(_ puzzle: Puzzle, gate: PuzzleAccess) -> Bool {
        gate.canPlay(
            puzzle,
            isPremium: store.isPremium,
            hasProgress: recordsByID[puzzle.id] != nil
        )
    }

    /// Everything the filters admit, split by whether this player can open it.
    /// Minis follow the dailies rather than interleaving: they're a different
    /// length of sitting, and the premium list already groups them apart.
    private func partitioned(gate: PuzzleAccess) -> (free: [Puzzle], locked: [Puzzle]) {
        let all = filtered + filteredSundays + filteredMinis
        var free: [Puzzle] = []
        var locked: [Puzzle] = []
        for puzzle in all {
            if canPlay(puzzle, gate: gate) { free.append(puzzle) } else { locked.append(puzzle) }
        }
        return (free, locked)
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.isPremium {
                    premiumList
                } else {
                    freeList
                }
            }
            .navigationTitle("Library")
            .navigationDestination(for: Puzzle.self) { puzzle in
                CrosswordGameView(puzzle: puzzle, profile: profile, entrySource: "library")
            }
            .sheet(isPresented: $showPaywall) {
                // Source stays "archive" even though the screen is now called
                // Library — renaming it would split this entry point's
                // conversion history in Firebase at an arbitrary point.
                PaywallView(source: .archive)
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

            if !filteredSundays.isEmpty {
                Section {
                    ForEach(filteredSundays) { sunday in
                        row(sunday)
                    }
                } header: {
                    Text("Sunday Specials")
                }
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
        // Same readable column as the card screens — a row stretched across a
        // 13" iPad puts its chevron half a metre from its title.
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity)
        .background(Theme.background)
        .searchable(text: $query, prompt: "Search puzzles")
        .toolbar { filterMenu }
        .overlay {
            if filtered.isEmpty && filteredSundays.isEmpty && filteredMinis.isEmpty {
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

    // MARK: - Free list

    /// The half most people see.
    ///
    /// This screen used to be all-or-nothing: a locked preview of four dimmed
    /// rows and an Unlock button, with no way to play anything. That maximised
    /// paywall pressure, at the cost of a player meeting "everything is locked"
    /// before they had seen enough of the collection to want it — and of
    /// contradicting the store listing, which invites them to revisit a library.
    ///
    /// Now the same list premium sees, with the gate drawn through it: what they
    /// can play first, what Premium opens underneath. The rule lives in
    /// `PuzzleAccess`; this only renders it.
    private var freeList: some View {
        let gate = access
        let split = partitioned(gate: gate)

        return List {
            if !split.free.isEmpty {
                Section {
                    ForEach(split.free) { row($0) }
                } header: {
                    freeHeader(freeCount: split.free.count)
                }
            }

            if !split.locked.isEmpty {
                Section {
                    ForEach(split.locked) { lockedRow($0) }
                } header: {
                    Text("Premium")
                } footer: {
                    upgradeFooter
                }
            }
        }
        .scrollContentBackground(.hidden)
        // See premiumList: keep rows at a readable width on iPad.
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity)
        .background(Theme.background)
        .searchable(text: $query, prompt: "Search puzzles")
        .toolbar { filterMenu }
        .overlay {
            if split.free.isEmpty && split.locked.isEmpty {
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

    /// States the allowance in the player's own terms, without claiming dates.
    ///
    /// "This week's seven" describes which puzzles are open, not when they were
    /// published — the pool rotates, so no puzzle belongs to a day (see the file
    /// note above). The count is what they can actually open right now, which
    /// grows past seven as they start puzzles and keep them.
    private func freeHeader(freeCount: Int) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("^[\(freeCount) puzzle](inflect: true) to play")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Text("This week's seven are free, and anything you start stays yours.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .textCase(nil)          // section headers upper-case by default
        .padding(.bottom, Theme.Spacing.xs)
        .accessibilityElement(children: .combine)
    }

    /// The upgrade path, kept where the locked rows are rather than as a screen
    /// of its own. Same promise the paywall opens with — see `PremiumCopy`.
    private var upgradeFooter: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            // Both numbers, deliberately. The reader meets the two totals
            // anyway, on Today and in onboarding, and a screen that says 82
            // while everything else says 177 reads as a contradiction rather
            // than as scoping.
            Text("Premium opens all \(puzzleProvider.totalPuzzleCount) puzzles, including every one of the \(puzzles.count) dailies in this archive — play and replay as often as you want.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button("Unlock Premium") { showPaywall = true }
                .buttonStyle(.pillProminent)
                .padding(.bottom, Theme.Spacing.s)
        }
        .textCase(nil)
        .padding(.top, Theme.Spacing.s)
    }

    /// A locked row: the same shape as a playable one so the list reads as one
    /// collection, but it opens the paywall instead of the puzzle.
    private func lockedRow(_ puzzle: Puzzle) -> some View {
        Button {
            showPaywall = true
        } label: {
            HStack(spacing: Theme.Spacing.m) {
                GridThumbnail(grid: puzzle.grid, tint: Color.primary.opacity(0.18))
                    .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(puzzle.title)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    HStack(spacing: Theme.Spacing.s) {
                        DifficultyBadge(difficulty: puzzle.difficulty)
                        Text("\(puzzle.clueCount) clues")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "lock.fill")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 2)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(puzzle.title), locked")
        .accessibilityHint("Opens Premium")
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
