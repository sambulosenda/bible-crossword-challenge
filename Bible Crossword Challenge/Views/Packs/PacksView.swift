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
    /// Held by `RootView` so a season-opening notification can push its pack
    /// onto this tab, the way the Today tab's path takes widget deep links.
    @Binding var path: NavigationPath

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
    private var quests: [QuestLine] { puzzleProvider.quests }

    var body: some View {
        NavigationStack(path: $path) {
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
            .navigationDestination(for: PackRoute.self) { route in
                PackDetailView(pack: route.pack, profile: profile, source: route.source)
            }
            .navigationDestination(for: QuestRoute.self) { route in
                QuestDetailView(quest: route.quest, profile: profile, source: route.source)
            }
            .navigationDestination(for: Puzzle.self) { puzzle in
                CrosswordGameView(puzzle: puzzle, profile: profile)
            }
        }
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.l) {
                questSection
                if !seasonalPacks.isEmpty {
                    section("In Season", packs: seasonalPacks)
                }
                section(quests.isEmpty && seasonalPacks.isEmpty ? nil : "All Collections", packs: evergreenPacks)
            }
            .padding(Theme.Spacing.m)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background)
    }

    /// The Journeys sit above the packs: an ordered, paced run is the stronger
    /// daily-return pitch, and there are only a few of them.
    @ViewBuilder
    private var questSection: some View {
        if !quests.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Text("Journeys").kicker().padding(.horizontal, Theme.Spacing.xs)
                ForEach(quests) { quest in
                    NavigationLink(value: QuestRoute(quest: quest, source: .packs)) {
                        QuestCard(
                            quest: quest,
                            progress: QuestProgress(quest: quest, recordsByID: recordsByID),
                            isLocked: quest.isPremium && !store.isPremium
                        )
                    }
                    .buttonStyle(PressableCardStyle())
                }
            }
        }
    }

    @ViewBuilder
    private func section(_ title: String?, packs: [PuzzlePack]) -> some View {
        if !packs.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                if let title {
                    Text(title).kicker().padding(.horizontal, Theme.Spacing.xs)
                }
                ForEach(packs) { pack in
                    NavigationLink(value: PackRoute(pack: pack, source: .packs)) {
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
