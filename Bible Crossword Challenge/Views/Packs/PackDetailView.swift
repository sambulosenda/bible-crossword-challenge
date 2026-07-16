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

struct PackDetailView: View {
    let pack: PuzzlePack
    let profile: PlayerProfile

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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                header
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
        .sheet(isPresented: $showPaywall) { PaywallView() }
        // packCompleted is logged where it happens — the game screen's
        // completion hook — so it fires exactly once, even if this view is
        // never revisited.
        .task { analytics.log(.packOpened(id: pack.id)) }
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

            if progress.isComplete {
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
                Text("Unlock \(pack.title) and every other collection with Premium — \(pack.puzzleIDs.count) themed puzzles in this pack alone.")
            } actions: {
                Button {
                    showPaywall = true
                } label: {
                    Text("Unlock Premium").frame(maxWidth: 280)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.xl)
    }
}
