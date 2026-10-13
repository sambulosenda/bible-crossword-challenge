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
        // inside each row's closure: `recordsByID` rebuilt a dictionary of
        // every record the player owns once per card, and the pack list was
        // re-filtered for seasonality three times on the way down the screen.
        let recordsByID = records.byPuzzleID
        // A pack a Journey already covers is dropped here, so nothing
        // downstream — the sections, the empty state, the lead — can count
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
                    list(packs: packs, recordsByID: recordsByID)
                }
            }
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
    /// the sort and each row all read it — it used to be built separately by
    /// the lead's pick and again by every row it then drew.
    private struct ProgressBook {
        let packs: [String: PackProgress]
        let quests: [String: QuestProgress]

        // Built from the same lists the rows come from, so a miss shouldn't
        // happen — but a miss is a fresh progress, not a crash.
        let recordsByID: [String: PuzzleRecord]

        func of(_ pack: PuzzlePack) -> PackProgress {
            packs[pack.id] ?? PackProgress(pack: pack, recordsByID: recordsByID)
        }
        func of(_ quest: QuestLine) -> QuestProgress {
            quests[quest.id] ?? QuestProgress(quest: quest, recordsByID: recordsByID)
        }
    }

    private func list(packs: [PuzzlePack], recordsByID: [String: PuzzleRecord]) -> some View {
        let book = ProgressBook(
            packs: Dictionary(packs.map { ($0.id, PackProgress(pack: $0, recordsByID: recordsByID)) },
                              uniquingKeysWith: { a, _ in a }),
            quests: Dictionary(quests.map { ($0.id, QuestProgress(quest: $0, recordsByID: recordsByID)) },
                               uniquingKeysWith: { a, _ in a }),
            recordsByID: recordsByID
        )
        let lead = self.lead(packs: packs, book: book)
        // The promoted collection is lifted out of its section rather than
        // repeated under it — the screen has just stopped showing the same
        // collection twice, and the lead card must not put it back.
        let shownQuests = Self.playOrder(
            quests.filter { $0.id != lead?.questID },
            solved: { book.of($0).solved }, isComplete: { book.of($0).isComplete }
        )
        let seasonal = packs.filter { $0.isSeasonal && $0.id != lead?.packID }
        let evergreen = Self.playOrder(
            packs.filter { !$0.isSeasonal && $0.id != lead?.packID },
            solved: { book.of($0).solved }, isComplete: { book.of($0).isComplete }
        )

        // A free player's locked Journeys and packs gather under one offer
        // instead of a crown on every row: five of seven rows were crowned
        // and nothing on the tab said, once, what would open them. Seasonal
        // packs stay in their own section either way — the season is the
        // reason to look now.
        let openQuests = shownQuests.filter { !isLocked($0.isPremium) }
        let lockedQuests = shownQuests.filter { isLocked($0.isPremium) }
        // Finished packs go to the foot of the tab under their own header.
        // In "Free" they were the whole section for anyone past the
        // tutorial — one finished pack, the only free thing listed.
        let openEvergreen = evergreen.filter { !isLocked($0.isPremium) }
        let openPacks = openEvergreen.filter { !book.of($0).isComplete }
        let finishedPacks = openEvergreen.filter { book.of($0).isComplete }
        let lockedPacks = evergreen.filter { isLocked($0.isPremium) }
        let anythingAbove = lead != nil || !openQuests.isEmpty || !seasonal.isEmpty

        // A native inset-grouped List since 2026-10-13: system rows, chevrons,
        // separators and highlight, instead of hand-built cards that looked
        // like iOS without behaving like it. The warm paper stays behind it.
        return List {
            leadSection(lead)
            questSection(quests: openQuests, book: book)
            if !seasonal.isEmpty {
                section("In season", packs: seasonal, book: book)
            }
            section(
                anythingAbove ? (store.isPremium ? "All packs" : "Free") : nil,
                packs: openPacks,
                book: book
            )
            premiumSection(quests: lockedQuests, packs: lockedPacks, book: book)
            section("Finished", packs: finishedPacks, book: book)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        // Rows at a readable width on iPad, as the Library's are.
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity)
        .background(Theme.background)
    }

    /// Something to do first: one under way, then one not begun, and a
    /// finished one last — the order Today's packs shelf already uses. In
    /// authored order "First Steps · Complete" led All packs for everyone
    /// past the tutorial. Stable within each group.
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

    /// The one thing to do here, as the first row: the collection under way
    /// (or the first one open), with an App Store–style pill naming the step.
    @ViewBuilder
    private func leadSection(_ lead: Lead?) -> some View {
        switch lead {
        case let .quest(quest, progress):
            if let action = CollectionLeadAction.forRow(
                isLocked: false, solved: progress.solved, isComplete: progress.isComplete
            ) {
                leadRow(
                    open: { path.append(QuestRoute(quest: quest, source: .packs)) },
                    symbol: quest.coverSymbol, accent: quest.accent, title: quest.title,
                    meta: "Journey · " + QuestProgress.stepLine(solved: progress.solved, total: progress.total),
                    action: action
                )
            }
        case let .pack(pack, progress):
            if let action = CollectionLeadAction.forRow(
                isLocked: false, solved: progress.solved, isComplete: progress.isComplete
            ) {
                leadRow(
                    open: { path.append(PackRoute(pack: pack, source: .packs)) },
                    symbol: pack.coverSymbol, accent: pack.accent, title: pack.title,
                    meta: "Pack · \(progress.solved) of \(progress.total) solved",
                    action: action
                )
            }
        case nil:
            EmptyView()
        }
    }

    private func leadRow(
        // A closure, not an AnyHashable route: NavigationPath keys its
        // destinations by the appended type, and an AnyHashable matched none.
        open: @escaping () -> Void, symbol: String, accent: Color, title: String,
        meta: String, action: CollectionLeadAction
    ) -> some View {
        Section {
            Button {
                open()
            } label: {
                HStack(spacing: Theme.Spacing.m) {
                    CollectionCover(symbol: symbol, accent: accent, isLocked: false,
                                    side: 52, font: .title2, cornerRadius: 12)
                    VStack(alignment: .leading, spacing: 2) {
                        // Concrete colours: inside a list button the
                        // hierarchical styles resolve against the tint.
                        Text(title).font(.headline).foregroundStyle(Color.primary)
                        Text(meta).font(.subheadline).foregroundStyle(Color(uiColor: .secondaryLabel))
                    }
                    Spacer(minLength: Theme.Spacing.s)
                    // The App Store's GET pill: tinted fill, accent label.
                    Text(action.rawValue)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, Theme.Spacing.m)
                        .padding(.vertical, 6)
                        .background(Color(.tertiarySystemFill), in: .capsule)
                }
                .padding(.vertical, Theme.Spacing.xs)
                .contentShape(.rect)
            }
            // The list's own button style, for the system tap highlight;
            // text is set to primary above, so nothing turns accent.
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Next up: \(title). \(meta)")
            .accessibilityHint("\(action.rawValue)s it")
        } header: {
            Text("Next up")
        }
        .headerProminence(.increased)
    }

    private func isLocked(_ isPremiumContent: Bool) -> Bool {
        isPremiumContent && !store.isPremium
    }

    // MARK: - Sections
    //
    // List sections with prominent headers, as Music and the App Store set
    // theirs. Rows are NavigationLinks, so the chevron, highlight and
    // separators are the system's own.

    /// Everything Premium would open, under one offer at the head of the
    /// section. Locked rows carry a lock beside the chevron.
    @ViewBuilder
    private func premiumSection(
        quests: [QuestLine], packs: [PuzzlePack], book: ProgressBook
    ) -> some View {
        if !quests.isEmpty || !packs.isEmpty {
            Section {
                premiumOffer(count: quests.count + packs.count)
                ForEach(quests) { quest in
                    NavigationLink(value: QuestRoute(quest: quest, source: .packs)) {
                        CollectionRow(quest: quest, progress: book.of(quest), isLocked: true)
                    }
                }
                ForEach(packs) { pack in
                    NavigationLink(value: PackRoute(pack: pack, source: .packs)) {
                        CollectionRow(pack: pack, progress: book.of(pack), isLocked: true)
                    }
                }
            } header: {
                Text("With Premium")
            }
            .headerProminence(.increased)
        }
    }

    /// The one offer on the tab — same words as Today's card
    /// (see `PremiumCopy.cardCTA`).
    private func premiumOffer(count: Int) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Every pack and Journey")
                    .font(.headline)
                Text("\(count) more to play below, plus hints whenever you need them.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                showPaywall = true
            } label: {
                Text(PremiumCopy.cardCTA(store))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.onInk)
                    .padding(.horizontal, Theme.Spacing.m)
                    .padding(.vertical, Theme.Spacing.s)
                    .background(Theme.ink, in: .capsule)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .buttonStyle(.borderless)
            .accessibilityHint("Opens Premium plans")
        }
        .padding(.vertical, Theme.Spacing.s)
    }

    /// The Journeys sit above the packs: an ordered, paced run is the stronger
    /// daily-return pitch, and there are only a few of them.
    @ViewBuilder
    private func questSection(quests: [QuestLine], book: ProgressBook) -> some View {
        if !quests.isEmpty {
            Section {
                ForEach(quests) { quest in
                    NavigationLink(value: QuestRoute(quest: quest, source: .packs)) {
                        CollectionRow(quest: quest, progress: book.of(quest),
                                      isLocked: isLocked(quest.isPremium))
                    }
                }
            } header: {
                Text("Journeys")
            }
            .headerProminence(.increased)
        }
    }

    @ViewBuilder
    private func section(
        _ title: String?,
        packs: [PuzzlePack],
        book: ProgressBook
    ) -> some View {
        if !packs.isEmpty {
            Section {
                ForEach(packs) { pack in
                    NavigationLink(value: PackRoute(pack: pack, source: .packs)) {
                        CollectionRow(pack: pack, progress: book.of(pack),
                                      isLocked: isLocked(pack.isPremium))
                    }
                }
            } header: {
                if let title { Text(title) }
            }
            .headerProminence(.increased)
        }
    }
}

// MARK: - Row

/// A pack or Journey as a native list row: a 36pt cover, title, two lines of
/// blurb and a status line — "Pack · 5 puzzles", progress, or Complete. The
/// list supplies the chevron; a locked row adds a lock before it.
private struct CollectionRow: View {
    let symbol: String
    let accent: Color
    let title: String
    let blurb: String
    let isLocked: Bool
    let badge: PackBadge?
    let status: Status

    enum Status {
        case size(String)
        case progress(fraction: Double, text: String)
        case complete
    }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(pack: PuzzlePack, progress: PackProgress, isLocked: Bool) {
        symbol = pack.coverSymbol; accent = pack.accent; title = pack.title
        blurb = pack.blurb; self.isLocked = isLocked; badge = PackBadge.forPack(pack)
        let size = "Pack · \(progress.total) puzzle\(progress.total == 1 ? "" : "s")"
        // A locked pack states its size, never progress (see `PackCard.status`).
        status = isLocked || progress.solved == 0 ? .size(size)
            : progress.isComplete ? .complete
            : .progress(fraction: progress.fraction, text: "\(progress.solved) of \(progress.total) solved")
    }

    init(quest: QuestLine, progress: QuestProgress, isLocked: Bool) {
        symbol = quest.coverSymbol; accent = quest.accent; title = quest.title
        blurb = quest.blurb; self.isLocked = isLocked; badge = nil
        status = isLocked || progress.solved == 0 ? .size("Journey · \(progress.total) days")
            : progress.isComplete ? .complete
            : .progress(fraction: progress.fraction,
                        text: QuestProgress.stepLine(solved: progress.solved, total: progress.total))
    }

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
            CollectionCover(symbol: symbol, accent: accent, isLocked: isLocked,
                            side: 36, font: .body, cornerRadius: 9)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Theme.Spacing.xs) {
                    Text(title).font(.headline)
                    if let badge { badge }
                }
                Text(blurb)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(CollectionCardLayout.blurbLineLimit(dynamicTypeSize))
                statusView
                    .padding(.top, 2)
            }
            Spacer(minLength: 0)
            if isLocked {
                Image(systemName: "lock.fill")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .frame(maxHeight: .infinity)
            }
        }
        .padding(.vertical, Theme.Spacing.xs)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var statusView: some View {
        switch status {
        case let .size(text):
            Text(text).font(.caption).foregroundStyle(.secondary).monospacedDigit()
        case .complete:
            Label("Complete", systemImage: "checkmark.seal.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.green)
        case let .progress(fraction, text):
            VStack(alignment: .leading, spacing: 2) {
                ProgressView(value: fraction).tint(accent)
                Text(text).font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
        }
    }

    private var accessibilityLabel: String {
        var parts = [title, blurb]
        if isLocked { parts.append("Premium") }
        if let badge { parts.append(badge.label) }
        switch status {
        case let .size(text): parts.append(text)
        case .complete: parts.append("Complete")
        case let .progress(_, text): parts.append(text)
        }
        return parts.joined(separator: ". ")
    }
}
