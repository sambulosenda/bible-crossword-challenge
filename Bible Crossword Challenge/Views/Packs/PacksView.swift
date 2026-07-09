//
//  PacksView.swift
//  Bible Crossword Challenge
//
//  The "Packs" tab: curated collections of related puzzles. Free to browse; a
//  premium pack shows its contents but gates play behind the paywall (the free
//  starter pack is always playable). Seasonal packs surface only in-window.
//

import SwiftUI
import SwiftData

struct PacksView: View {
    let profile: PlayerProfile

    @Environment(\.puzzleProvider) private var puzzleProvider
    @Environment(StoreService.self) private var store
    @Query private var records: [PuzzleRecord]

    /// One lookup per body pass, shared by every pack's progress calc.
    private var recordsByID: [String: PuzzleRecord] {
        Dictionary(records.map { ($0.puzzleID, $0) }, uniquingKeysWith: { a, _ in a })
    }

    private var packs: [PuzzlePack] { puzzleProvider.availablePacks() }
    private var seasonalPacks: [PuzzlePack] { packs.filter(\.isSeasonal) }
    private var evergreenPacks: [PuzzlePack] { packs.filter { !$0.isSeasonal } }

    var body: some View {
        NavigationStack {
            Group {
                if packs.isEmpty {
                    ContentUnavailableView(
                        "No Collections Yet",
                        systemImage: "square.stack.3d.up",
                        description: Text("Themed puzzle packs will appear here.")
                    )
                } else {
                    list
                }
            }
            .navigationTitle("Packs")
            .navigationDestination(for: PuzzlePack.self) { pack in
                PackDetailView(pack: pack, profile: profile)
            }
            .navigationDestination(for: Puzzle.self) { puzzle in
                CrosswordGameView(puzzle: puzzle, profile: profile)
            }
        }
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.l) {
                if !seasonalPacks.isEmpty {
                    section("In Season", packs: seasonalPacks)
                }
                section(seasonalPacks.isEmpty ? nil : "All Collections", packs: evergreenPacks)
            }
            .padding(Theme.Spacing.m)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background)
    }

    @ViewBuilder
    private func section(_ title: String?, packs: [PuzzlePack]) -> some View {
        if !packs.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                if let title {
                    Text(title).kicker().padding(.horizontal, Theme.Spacing.xs)
                }
                ForEach(packs) { pack in
                    NavigationLink(value: pack) {
                        PackCard(
                            pack: pack,
                            progress: PackProgress(pack: pack, recordsByID: recordsByID),
                            isLocked: pack.isPremium && !store.isPremium
                        )
                    }
                    .buttonStyle(PressableCardStyle())
                }
            }
        }
    }
}
