//
//  ArchiveView.swift
//  Bible Crossword Challenge
//
//  Premium-only library of every puzzle, searchable, with completion status.
//  Free users see a locked state that routes to the paywall.
//

import SwiftUI
import SwiftData

struct ArchiveView: View {
    let profile: PlayerProfile

    @Environment(\.puzzleProvider) private var puzzleProvider
    @Environment(StoreService.self) private var store
    @Query private var records: [PuzzleRecord]

    @State private var query = ""
    @State private var showPaywall = false

    private var puzzles: [Puzzle] { puzzleProvider.puzzles }

    private var filtered: [Puzzle] {
        guard !query.isEmpty else { return puzzles }
        return puzzles.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

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
            Section {
                ForEach(filtered) { puzzle in
                    row(puzzle)
                }
            } header: {
                Text("\(completedCount) of \(puzzles.count) completed")
            }
        }
        .searchable(text: $query, prompt: "Search puzzles")
        .overlay {
            if filtered.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
    }

    private func row(_ puzzle: Puzzle) -> some View {
        let record = records.first { $0.puzzleID == puzzle.id }
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
                Text("Unlock Premium · \(store.displayPrice)")
                    .frame(maxWidth: 280)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }
}
