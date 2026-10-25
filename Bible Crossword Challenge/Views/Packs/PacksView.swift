//
//  PacksView.swift
//  Bible Crossword Challenge
//
//  The "Packs" tab: curated collections of related puzzles. Free to browse; a
//  premium pack shows its contents but gates play behind the paywall (the free
//  starter pack is always playable). Seasonal packs surface only in-window.
//
//  A bookshelf since 2026-10-24: one feature card for the collection to play
//  next, then shelves of tall typographic covers — the Journeys, anything in
//  season, and the packs by Testament, the way the Bible itself is shelved.
//  It was an inset-grouped list of symbol rows (2026-10-13): native, but every
//  collection looked the same at a glance, and the covers carried nothing of
//  the book a pack draws from. Locked collections keep their colour now, with
//  a lock on the cover, rather than greying out — a shelf of grey was a shelf
//  of nothing to want.
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
    @State private var showPaywall = false

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
        // inside each tile's closure.
        let recordsByID = records.byPuzzleID
        // A pack a Journey already covers is dropped here, so nothing
        // downstream — the shelves, the empty state, the lead — can count
        // the same collection twice.
        let packs = PuzzlePack.notShadowedByQuests(puzzleProvider.availablePacks(), quests: quests)

        return NavigationStack(path: $path) {
            Group {
                if packs.isEmpty && quests.isEmpty {
                    ContentUnavailableView(
                        "No Packs Yet",
                        systemImage: "square.stack.3d.up",
                        description: Text("Themed puzzle packs will appear here.")
                    )
                } else {
                    shelves(packs: packs, recordsByID: recordsByID)
                }
            }
            .background(Theme.background)
            .navigationTitle("Packs")
            // Large, as Today's is: a tab root names itself at the top and
            // hands the name to the bar on scroll.
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showPaywall) {
                // `pack_locked` rather than a new label: the offer stands over
                // the locked packs themselves, and a new source would move the
                // cross-platform constants for a surface this quiet.
                PaywallView(source: .packLocked)
            }
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

    /// Every collection's progress, worked out once per body pass. The lead,
    /// the sort and each tile all read it.
    private struct ProgressBook {
        let packs: [String: PackProgress]
        let quests: [String: QuestProgress]

        // Built from the same lists the tiles come from, so a miss shouldn't
        // happen — but a miss is a fresh progress, not a crash.
        let recordsByID: [String: PuzzleRecord]

        func of(_ pack: PuzzlePack) -> PackProgress {
            packs[pack.id] ?? PackProgress(pack: pack, recordsByID: recordsByID)
        }
        func of(_ quest: QuestLine) -> QuestProgress {
            quests[quest.id] ?? QuestProgress(quest: quest, recordsByID: recordsByID)
        }
    }

    private func shelves(packs: [PuzzlePack], recordsByID: [String: PuzzleRecord]) -> some View {
        let book = ProgressBook(
            packs: Dictionary(packs.map { ($0.id, PackProgress(pack: $0, recordsByID: recordsByID)) },
                              uniquingKeysWith: { a, _ in a }),
            quests: Dictionary(quests.map { ($0.id, QuestProgress(quest: $0, recordsByID: recordsByID)) },
                               uniquingKeysWith: { a, _ in a }),
            recordsByID: recordsByID
        )
        let packLabels = Dictionary(
            packs.map { ($0.id, PackCoverLabel(puzzles: puzzleProvider.puzzles(in: $0))) },
            uniquingKeysWith: { a, _ in a }
        )
        let lead = self.lead(packs: packs, book: book)

        // The promoted collection is lifted out of its shelf rather than
        // repeated on it. On each shelf: something to do first, locked after
        // what's open, finished last.
        let shownQuests = openFirst(Self.playOrder(
            quests.filter { $0.id != lead?.questID },
            solved: { book.of($0).solved }, isComplete: { book.of($0).isComplete }
        ), isPremium: \.isPremium)
        let seasonal = packs.filter { $0.isSeasonal && $0.id != lead?.packID }
        let evergreen = openFirst(Self.playOrder(
            packs.filter { !$0.isSeasonal && $0.id != lead?.packID },
            solved: { book.of($0).solved }, isComplete: { book.of($0).isComplete }
        ), isPremium: \.isPremium)
        let oldTestament = evergreen.filter { packLabels[$0.id]?.testament != .new }
        let newTestament = evergreen.filter { packLabels[$0.id]?.testament == .new }

        let lockedCount = quests.filter { isLocked($0.isPremium) }.count
            + packs.filter { isLocked($0.isPremium) }.count

        return ScrollView {
            LazyVStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                leadCard(lead, packLabels: packLabels)

                if !shownQuests.isEmpty {
                    PackShelf(title: "Journeys") {
                        ForEach(shownQuests) { quest in
                            NavigationLink(value: QuestRoute(quest: quest, source: .packs)) {
                                questTile(quest, progress: book.of(quest))
                            }
                            .buttonStyle(PressableCardStyle())
                        }
                    }
                }
                packShelf("In season", packs: seasonal, book: book, labels: packLabels)
                packShelf("Old Testament", packs: oldTestament, book: book, labels: packLabels)
                packShelf("New Testament", packs: newTestament, book: book, labels: packLabels)

                // A free player's one offer for everything locked above,
                // at the foot of the tab rather than a lock on its own.
                if lockedCount > 0 {
                    premiumOffer(count: lockedCount)
                }
            }
            .padding(.horizontal, Theme.Spacing.l - 4)
            .padding(.top, Theme.Spacing.s)
            .padding(.bottom, Theme.Spacing.l)
            // A readable width on iPad, as the Library's is.
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
    }

    /// Something to do first: one under way, then one not begun, and a
    /// finished one last — the order Today's packs shelf already uses.
    /// Stable within each group.
    private static func playOrder<T>(
        _ items: [T], solved: (T) -> Int, isComplete: (T) -> Bool
    ) -> [T] {
        func rank(_ item: T) -> Int {
            if isComplete(item) { return 2 }
            return solved(item) > 0 ? 0 : 1
        }
        return items.enumerated()
            .sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }
            .map(\.element)
    }

    /// What this player can open, ahead of what Premium would open; stable
    /// within each group.
    private func openFirst<T>(_ items: [T], isPremium: KeyPath<T, Bool>) -> [T] {
        items.filter { !isLocked($0[keyPath: isPremium]) }
            + items.filter { isLocked($0[keyPath: isPremium]) }
    }

    private func isLocked(_ isPremiumContent: Bool) -> Bool {
        isPremiumContent && !store.isPremium
    }

    // MARK: - Lead

    /// Which single collection gets promoted.
    ///
    /// Something already begun beats something not yet begun: the useful next
    /// step is the one in progress. A locked or finished collection is never
    /// the lead — there is nothing to start. Journeys are considered first,
    /// because a paced run is the stronger reason to come back tomorrow.
    private func lead(packs: [PuzzlePack], book: ProgressBook) -> Lead? {
        let openQuests = quests
            .filter { !$0.isPremium || store.isPremium }
            .map { ($0, book.of($0)) }
            .filter { !$0.1.isComplete }
        let openPacks = packs
            .filter { !$0.isPremium || store.isPremium }
            .map { ($0, book.of($0)) }
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
    private func leadCard(_ lead: Lead?, packLabels: [String: PackCoverLabel]) -> some View {
        switch lead {
        case let .quest(quest, progress):
            if let action = CollectionLeadAction.forRow(
                isLocked: false, solved: progress.solved, isComplete: progress.isComplete
            ) {
                LeadFeatureCard(
                    kicker: "Journey · " + QuestProgress.stepLine(solved: progress.solved, total: progress.total),
                    title: quest.title,
                    mark: PackCoverLabel(puzzles: puzzleProvider.puzzles(in: quest)).mark,
                    fill: quest.coverFill,
                    steps: (progress.solved, progress.total),
                    actionTitle: Self.actionTitle(action),
                    open: { path.append(QuestRoute(quest: quest, source: .packs)) }
                )
            }
        case let .pack(pack, progress):
            if let action = CollectionLeadAction.forRow(
                isLocked: false, solved: progress.solved, isComplete: progress.isComplete
            ) {
                LeadFeatureCard(
                    kicker: "Pack · \(progress.solved) of \(progress.total) solved",
                    title: pack.title,
                    mark: packLabels[pack.id]?.mark ?? "",
                    fill: pack.coverFill,
                    actionTitle: Self.actionTitle(action),
                    open: { path.append(PackRoute(pack: pack, source: .packs)) }
                )
            }
        case nil:
            EmptyView()
        }
    }

    /// "Continue", not "Resume", on the card's pill: it reads as the next
    /// step of something under way rather than a paused video.
    private static func actionTitle(_ action: CollectionLeadAction) -> String {
        action == .resume ? "Continue" : "Start"
    }

    // MARK: - Shelves

    @ViewBuilder
    private func packShelf(
        _ title: String, packs: [PuzzlePack], book: ProgressBook, labels: [String: PackCoverLabel]
    ) -> some View {
        if !packs.isEmpty {
            PackShelf(title: title) {
                ForEach(packs) { pack in
                    NavigationLink(value: PackRoute(pack: pack, source: .packs)) {
                        packTile(pack, progress: book.of(pack), label: labels[pack.id])
                    }
                    .buttonStyle(PressableCardStyle())
                }
            }
        }
    }

    private func packTile(_ pack: PuzzlePack, progress: PackProgress, label: PackCoverLabel?) -> some View {
        let locked = isLocked(pack.isPremium)
        let size = "\(progress.total) puzzle\(progress.total == 1 ? "" : "s")"
        // A locked pack states its size, never progress. Not "· Premium":
        // the cover's lock already says it (2026-10-25).
        let meta = locked ? size
            : progress.isComplete ? "Complete"
            : progress.solved > 0 ? "\(progress.solved) of \(progress.total) solved"
            : size
        return ShelfTile(
            title: pack.title,
            meta: meta,
            label: label ?? PackCoverLabel(puzzles: []),
            fill: pack.coverFill,
            fallbackSymbol: pack.coverSymbol,
            isLocked: locked,
            progress: !locked && progress.solved > 0 && !progress.isComplete ? progress.fraction : nil,
            badge: PackBadge.forPack(pack)
        )
    }

    private func questTile(_ quest: QuestLine, progress: QuestProgress) -> some View {
        let locked = isLocked(quest.isPremium)
        let meta = locked ? "\(progress.total) days"
            : progress.isComplete ? "Complete"
            : progress.solved > 0 ? QuestProgress.stepLine(solved: progress.solved, total: progress.total)
            : "\(progress.total) steps, one a day"
        return ShelfTile(
            title: quest.title,
            meta: meta,
            label: PackCoverLabel(puzzles: puzzleProvider.puzzles(in: quest)),
            fill: quest.coverFill,
            fallbackSymbol: quest.coverSymbol,
            isLocked: locked,
            progress: !locked && progress.solved > 0 && !progress.isComplete ? progress.fraction : nil
        )
    }

    // MARK: - Offer

    /// The one offer on the tab, dressed as Today's Premium card: the chip,
    /// what you get, then the accent button and the price
    /// (`PremiumOfferCTA`). The whole card opens the paywall.
    private func premiumOffer(count: Int) -> some View {
        Button {
            showPaywall = true
        } label: {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    PremiumChip()
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Every pack and Journey")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(Color.primary)
                        Text("\(count) more to play above, plus hints whenever you need them.")
                            .font(.subheadline)
                            .foregroundStyle(Color(uiColor: .secondaryLabel))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                PremiumOfferCTA()
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .elevatedCard()
            .contentShape(.rect)
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens Premium plans")
    }
}
