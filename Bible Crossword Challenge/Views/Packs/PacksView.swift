//
//  PacksView.swift
//  Bible Crossword Challenge
//
//  The "Packs" tab: curated collections of related puzzles. Free to browse; a
//  premium pack shows its contents but gates play behind the paywall (the free
//  starter pack is always playable). Seasonal packs surface only in-window.
//
//  The screen reads in three levels: one lead card for the thing to do now,
//  then the Journeys, then the collections. Everything below the lead is a
//  browse row of equal weight — the promotion is what carries the hierarchy,
//  so no row has to shout.
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

    /// The collection promoted to the top of the tab, carried with the
    /// progress that was already computed to choose it.
    ///
    /// Quests and packs share ids where a collection ships as both, so the
    /// lead has to say which list it came from, not just which collection.
    private enum Lead {
        case quest(QuestLine, QuestProgress)
        case pack(PuzzlePack, PackProgress)

        var questID: String? { if case let .quest(q, _) = self { q.id } else { nil } }
        var packID: String? { if case let .pack(p, _) = self { p.id } else { nil } }
    }

    private var quests: [QuestLine] { puzzleProvider.quests }

    var body: some View {
        // Built once per body pass and handed down, rather than recomputed
        // inside each row's closure: `recordsByID` rebuilt a dictionary of
        // every record the player owns once per card, and the pack list was
        // re-filtered for seasonality three times on the way down the screen.
        let recordsByID = Dictionary(records.map { ($0.puzzleID, $0) }, uniquingKeysWith: { a, _ in a })
        // A pack a Journey already covers is dropped here, so nothing
        // downstream — the sections, the empty state, the lead — can count
        // the same collection twice.
        let packs = PuzzlePack.notShadowedByQuests(puzzleProvider.availablePacks(), quests: quests)

        return NavigationStack(path: $path) {
            Group {
                if packs.isEmpty && quests.isEmpty {
                    ContentUnavailableView(
                        "No Collections Yet",
                        systemImage: "square.stack.3d.up",
                        description: Text("Themed puzzle packs will appear here.")
                    )
                } else {
                    list(packs: packs, recordsByID: recordsByID)
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
                CrosswordGameView(puzzle: puzzle, profile: profile, entrySource: "pack")
            }
        }
    }

    private func list(packs: [PuzzlePack], recordsByID: [String: PuzzleRecord]) -> some View {
        let lead = self.lead(packs: packs, recordsByID: recordsByID)
        // The promoted collection is lifted out of its section rather than
        // repeated under it — the screen has just stopped showing the same
        // collection twice, and the lead card must not put it back.
        let shownQuests = quests.filter { $0.id != lead?.questID }
        let seasonal = packs.filter { $0.isSeasonal && $0.id != lead?.packID }
        let evergreen = packs.filter { !$0.isSeasonal && $0.id != lead?.packID }
        let anythingAbove = lead != nil || !shownQuests.isEmpty || !seasonal.isEmpty

        // The lead and the Journeys on the left of a wide window, the
        // collections on the right.
        return CardColumns {
            leadCard(lead)
            questSection(quests: shownQuests, recordsByID: recordsByID)
        } more: {
            if !seasonal.isEmpty {
                section("In Season", packs: seasonal, recordsByID: recordsByID)
            }
            section(
                anythingAbove ? "All Collections" : nil,
                packs: evergreen,
                recordsByID: recordsByID
            )
        }
        .background(Theme.background)
    }

    // MARK: - Lead

    /// Which single collection gets promoted.
    ///
    /// Something already begun beats something not yet begun: the useful next
    /// step is the one in progress. A locked or finished collection is never
    /// the lead — there is nothing to start. Journeys are considered first,
    /// because a paced run is the stronger reason to come back tomorrow.
    private func lead(packs: [PuzzlePack], recordsByID: [String: PuzzleRecord]) -> Lead? {
        let openQuests = quests
            .filter { !$0.isPremium || store.isPremium }
            .map { ($0, QuestProgress(quest: $0, recordsByID: recordsByID)) }
            .filter { !$0.1.isComplete }
        let openPacks = packs
            .filter { !$0.isPremium || store.isPremium }
            .map { ($0, PackProgress(pack: $0, recordsByID: recordsByID)) }
            .filter { !$0.1.isComplete }

        if let started = openQuests.first(where: { $0.1.solved > 0 }) {
            return .quest(started.0, started.1)
        }
        if let started = openPacks.first(where: { $0.1.solved > 0 }) {
            return .pack(started.0, started.1)
        }
        if let first = openQuests.first { return .quest(first.0, first.1) }
        if let first = openPacks.first { return .pack(first.0, first.1) }
        return nil
    }

    @ViewBuilder
    private func leadCard(_ lead: Lead?) -> some View {
        switch lead {
        case let .quest(quest, progress):
            if let action = CollectionLeadAction.forRow(
                isLocked: false, solved: progress.solved, isComplete: progress.isComplete
            ) {
                NavigationLink(value: QuestRoute(quest: quest, source: .packs)) {
                    CollectionLeadCard(
                        title: quest.title,
                        blurb: quest.blurb,
                        symbol: quest.coverSymbol,
                        accent: quest.accent,
                        meta: "Journey · "
                            + QuestProgress.stepLine(solved: progress.solved, total: progress.total),
                        action: action
                    )
                }
                .buttonStyle(PressableCardStyle())
            }
        case let .pack(pack, progress):
            if let action = CollectionLeadAction.forRow(
                isLocked: false, solved: progress.solved, isComplete: progress.isComplete
            ) {
                NavigationLink(value: PackRoute(pack: pack, source: .packs)) {
                    CollectionLeadCard(
                        title: pack.title,
                        blurb: pack.blurb,
                        symbol: pack.coverSymbol,
                        accent: pack.accent,
                        meta: "Collection · \(progress.solved) of \(progress.total) solved",
                        action: action
                    )
                }
                .buttonStyle(PressableCardStyle())
            }
        case nil:
            EmptyView()
        }
    }

    // MARK: - Sections

    /// The Journeys sit above the packs: an ordered, paced run is the stronger
    /// daily-return pitch, and there are only a few of them.
    @ViewBuilder
    private func questSection(quests: [QuestLine], recordsByID: [String: PuzzleRecord]) -> some View {
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
    private func section(
        _ title: String?,
        packs: [PuzzlePack],
        recordsByID: [String: PuzzleRecord]
    ) -> some View {
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
