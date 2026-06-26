//
//  ArchiveView.swift
//  Bible Crossword Challenge
//
//  Premium-only library of every puzzle — searchable, filterable by difficulty
//  and completion status, with a one-tap jump to the next unsolved puzzle. Free
//  users see a locked state that routes to the paywall.
//

import SwiftUI
import SwiftData

struct ArchiveView: View {
    let profile: PlayerProfile

    @Environment(\.puzzleProvider) private var puzzleProvider
    @Environment(StoreService.self) private var store
    @Query private var records: [PuzzleRecord]

    @State private var query = ""
    @State private var difficulty: PuzzleDifficulty?
    @State private var statusFilter: ArchiveStatusFilter = .all
    @State private var showPaywall = false

    private var puzzles: [Puzzle] { puzzleProvider.puzzles }

    /// One lookup built per body pass, reused by filtering and rows instead of
    /// scanning `records` for every puzzle. `puzzleID` is unique, so this is safe.
    private var recordsByID: [String: PuzzleRecord] {
        Dictionary(uniqueKeysWithValues: records.map { ($0.puzzleID, $0) })
    }

    private func status(for puzzle: Puzzle) -> PuzzleStatus {
        PuzzleStatus(record: recordsByID[puzzle.id])
    }

    private var filtered: [Puzzle] {
        puzzles.filter { puzzle in
            (query.isEmpty || puzzle.title.localizedCaseInsensitiveContains(query))
                && (difficulty == nil || puzzle.difficulty == difficulty)
                && statusMatches(puzzle)
        }
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
            .navigationTitle("Archive")
            .navigationDestination(for: Puzzle.self) { puzzle in
                CrosswordGameView(puzzle: puzzle, profile: profile)
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
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
                Text("\(completedCount) of \(puzzles.count) completed")
            }
        }
        .searchable(text: $query, prompt: "Search puzzles")
        .toolbar { filterMenu }
        .overlay {
            if filtered.isEmpty {
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

    private var lockedState: some View {
        ContentUnavailableView {
            Label("Premium Feature", systemImage: "crown.fill")
                .foregroundStyle(.yellow)
        } description: {
            Text("Unlock the full archive of \(puzzles.count) puzzles to browse and replay any day's challenge.")
        } actions: {
            Button {
                showPaywall = true
            } label: {
                Text("Unlock Premium")
                    .frame(maxWidth: 280)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
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
