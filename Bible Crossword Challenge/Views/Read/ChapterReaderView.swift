//
//  ChapterReaderView.swift
//  Bible Crossword Challenge
//
//  Paged chapter reader. Swipe left/right to move through chapters (rolling
//  across book boundaries). Remembers the last chapter read, supports jump-to
//  and adjustable text size, and flashes a deep-linked verse into view.
//
//  Touch and hold a verse for its actions — memorize, bookmark, share, copy.
//  Memorize is the point: until 2.8 the only way into memory verses was a
//  solved puzzle, so the reader fed nothing back into the game.
//
//  A chapter ends with chips for the puzzles that cite it (2.9). Completion
//  has offered "Read the passage" since 2.6; this is the way back.
//

import SwiftUI
import SwiftData

/// What a verse's touch-and-hold menu offers.
enum VerseAction: String {
    case memorize, bookmark, share, copy
}

/// The chapter a reading plan asked for. The matching page shows a footer
/// that marks the day read.
struct PlanChapter: Equatable {
    let book: String
    let chapter: Int
}

/// A puzzle offered at the foot of a chapter.
struct PuzzleChip: Identifiable {
    let puzzle: Puzzle
    let solved: Bool
    /// Outside the free window and never started — tapping opens the paywall.
    let locked: Bool
    var id: String { puzzle.id }
}

struct ChapterReaderView: View {
    @Environment(\.scripture) private var scripture

    let startBook: String
    let startChapter: Int
    var highlightVerse: Int? = nil
    /// Which surface opened the reader. Nil when a host logs the close itself
    /// (the verse-first hint sheet), so one visit never reports twice.
    var source: String? = nil
    /// Set when a reading plan opened the reader: that chapter's page ends
    /// with "Mark chapter as read", which calls `onPlanChapterRead` and pops.
    var planChapter: PlanChapter? = nil
    var onPlanChapterRead: (() -> Void)? = nil

    @Environment(\.analytics) private var analytics
    @Environment(\.memoryVerses) private var memoryVerses
    @Environment(\.bookmarks) private var bookmarks
    @Environment(\.displayScale) private var displayScale
    @Environment(\.dismiss) private var dismiss
    @Environment(StoreService.self) private var store
    @Environment(\.challengeService) private var challengeService
    @Environment(\.puzzleProvider) private var puzzleProvider
    @Environment(\.puzzleLaunch) private var puzzleLaunch
    @Query private var records: [PuzzleRecord]
    @State private var paywall: PaywallEntry?
    /// The free-tier gate, built once the reader settles — it scans the
    /// rotation windows, which isn't per-render work.
    @State private var access: PuzzleAccess?
    /// Chapter indices whose chips were already reported this visit, so paging
    /// back and forth doesn't count as new impressions.
    @State private var chipsLogged: Set<Int> = []
    @State private var shareItems: ShareItems?
    @State private var toast: String?
    @State private var openedAt = Date()
    /// Page turns after the opening chapter settled — the swipe from `0` to
    /// the start index in `build()` is setup, not reading.
    @State private var pageTurns = 0
    @State private var didSettle = false
    /// Whether the player scrolled the deep-linked verse's page by hand.
    @State private var scrolledPastVerse = false

    @AppStorage("read.lastBook") private var lastBook = ""
    @AppStorage("read.lastChapter") private var lastChapter = 0
    @AppStorage("read.fontSize") private var fontSize = 19.0
    @AppStorage(RecentChapters.key) private var recentRaw = ""

    @State private var locations: [ChapterLoc] = []
    @State private var startIndex = 0
    @State private var selection = 0
    @State private var showJump = false

    /// A flattened position: one entry per chapter across the whole Bible, so a
    /// swipe past the last chapter of a book lands on the next book.
    struct ChapterLoc: Hashable {
        let book: String
        let chapter: BibleChapter
    }

    var body: some View {
        Group {
            if locations.isEmpty {
                ProgressView()
            } else {
                TabView(selection: $selection) {
                    ForEach(locations.indices, id: \.self) { i in
                        page(at: i).tag(i)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .ignoresSafeArea(.container, edges: .bottom)
            }
        }
        .background(Theme.background)
        .navigationTitle(currentTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { fontSize = min(fontSize + 2, 30) } label: { Label("Larger text", systemImage: "textformat.size.larger") }
                        .disabled(fontSize >= 30)
                    Button { fontSize = max(fontSize - 2, 14) } label: { Label("Smaller text", systemImage: "textformat.size.smaller") }
                        .disabled(fontSize <= 14)
                } label: {
                    Image(systemName: "textformat.size")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showJump = true } label: { Image(systemName: "list.bullet") }
                    .accessibilityLabel("Jump to book or chapter")
            }
        }
        .task {
            await scripture.preload()
            build()
        }
        .sheet(item: $paywall) { entry in
            PaywallView(source: entry.source)
        }
        .sheet(item: $shareItems) { share in
            ShareSheet(items: share.items) { completed in
                analytics.log(.shareCompleted(kind: "share_verse", completed: completed))
            }
        }
        .overlay(alignment: .bottom) {
            if let toast {
                Text(toast)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.onInk)
                    .padding(.horizontal, Theme.Spacing.l)
                    .padding(.vertical, Theme.Spacing.s)
                    .background(Theme.ink, in: .capsule)
                    .padding(.bottom, Theme.Spacing.xl)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .animation(.spring(duration: 0.35), value: toast)
        .sensoryFeedback(.success, trigger: toast) { _, new in new != nil }
        .onChange(of: selection) { _, i in
            persist(i)
            logChips(at: i)
            if didSettle { pageTurns += 1 }
        }
        .onDisappear {
            if locations.indices.contains(selection) {
                recentRaw = RecentChapters.recording(
                    book: locations[selection].book, chapter: locations[selection].chapter.number, in: recentRaw
                )
            }
            guard let source else { return }
            analytics.log(.readerClosed(
                source: source,
                seconds: Int(Date().timeIntervalSince(openedAt).rounded()),
                chaptersPaged: pageTurns,
                scrolledPastVerse: scrolledPastVerse,
                expanded: true
            ))
        }
        .sheet(isPresented: $showJump) {
            JumpSheet(books: scripture.books) { book, chapter in
                if let idx = locations.firstIndex(where: { $0.book == book && $0.chapter.number == chapter }) {
                    selection = idx
                }
                showJump = false
            }
        }
    }

    /// One chapter's page. Its own function: inline in the `ForEach`, the
    /// closures plus the bookmark and plan lookups were more than the type
    /// checker would resolve in one expression.
    private func page(at i: Int) -> ChapterPage {
        let loc = locations[i]
        let bookmarked: Set<Int> = bookmarks.bookmarkedVerses(book: loc.book, chapter: loc.chapter.number)
        let isPlanChapter: Bool = planChapter == PlanChapter(book: loc.book, chapter: loc.chapter.number)
        return ChapterPage(
            book: loc.book,
            chapter: loc.chapter,
            fontSize: fontSize,
            highlight: i == startIndex ? highlightVerse : nil,
            scrolledPast: $scrolledPastVerse,
            bookmarked: bookmarked,
            memorizable: { verse in memorizeState(for: verse, in: loc) },
            showsPlanFooter: isPlanChapter,
            chips: chips(for: loc),
            onAction: { action, verse in handle(action, verse, in: loc) },
            onChip: handleChip,
            onMarkRead: markPlanChapterRead
        )
    }

    private var currentTitle: String {
        guard locations.indices.contains(selection) else { return startBook }
        let loc = locations[selection]
        return "\(loc.book) \(loc.chapter.number)"
    }

    private func build() {
        guard locations.isEmpty else { return }
        var built: [ChapterLoc] = []
        built.reserveCapacity(1200)
        for book in scripture.books {
            for chapter in book.chapters {
                built.append(ChapterLoc(book: book.name, chapter: chapter))
            }
        }
        locations = built
        let idx = built.firstIndex { $0.book == startBook && $0.chapter.number == startChapter } ?? 0
        startIndex = idx
        selection = idx
        persist(idx)
        recentRaw = RecentChapters.recording(book: startBook, chapter: startChapter, in: recentRaw)
        access = PuzzleAccess(provider: puzzleProvider, challengedIDs: challengeService.pendingPuzzleIDs)
        logChips(at: idx)
        didSettle = true
    }

    private func persist(_ i: Int) {
        guard locations.indices.contains(i) else { return }
        lastBook = locations[i].book
        lastChapter = locations[i].chapter.number
    }

    // MARK: - Verse actions

    /// The share sheet's payload, wrapped so `.sheet(item:)` can present it.
    private struct ShareItems: Identifiable {
        let id = UUID()
        let items: [Any]
    }

    enum MemorizeState {
        /// Can be started from here.
        case available
        /// Already in memory verses.
        case held
        /// Too long for the memory grid — see `MemoryCloze.isEligible`.
        case ineligible
    }

    private func memorizeState(for verse: BibleVerse, in loc: ChapterLoc) -> MemorizeState {
        let reference = reference(for: verse, in: loc)
        if memoryVerses.entry(for: MemoryCloze.referenceKey(reference)) != nil { return .held }
        return MemoryCloze.isEligible(verseText: verse.text) ? .available : .ineligible
    }

    private func reference(for verse: BibleVerse, in loc: ChapterLoc) -> String {
        "\(loc.book) \(loc.chapter.number):\(verse.number)"
    }

    private func handle(_ action: VerseAction, _ verse: BibleVerse, in loc: ChapterLoc) {
        let reference = reference(for: verse, in: loc)
        analytics.log(.verseAction(kind: action.rawValue, reference: reference))
        switch action {
        case .memorize:
            // Same gate as starting a candidate from the memory list.
            guard memoryVerses.canStartNewVerse(isPremium: store.isPremium) else {
                analytics.log(.paywallOpened(source: "memory_verse_limit"))
                paywall = PaywallEntry(source: "memory_verse_limit")
                return
            }
            _ = memoryVerses.start(reference: reference, verseText: verse.text)
            analytics.log(.memoryVerseStarted(reference: reference, level: 1))
            show("Added to Memory Verses")
        case .bookmark:
            let kept = bookmarks.toggle(
                book: loc.book, chapter: loc.chapter.number, verse: verse.number, verseText: verse.text
            )
            show(kept ? "Bookmarked" : "Bookmark removed")
        case .share:
            let renderer = ImageRenderer(content: VerseShareCard(verse: verse.text, reference: reference))
            renderer.scale = displayScale
            var items: [Any] = []
            if let image = renderer.uiImage { items.append(image) }
            items.append("“\(verse.text)” — \(reference)")
            if let url = ShareConfig.storeURL(kind: "share_verse") { items.append(url) }
            shareItems = ShareItems(items: items)
        case .copy:
            UIPasteboard.general.string = "“\(verse.text)” — \(reference)"
            show("Copied")
        }
    }

    private func show(_ message: String) {
        toast = message
        Task {
            try? await Task.sleep(for: .seconds(1.8))
            if toast == message { toast = nil }
        }
    }

    // MARK: - Puzzle chips

    /// Chips are for someone reading. Opened from the grid (the hint, a clue's
    /// citation) the player is mid-puzzle, and an offer to start another one
    /// is a way out, not a way in. The verse-first hint sheet passes no source
    /// and is covered by the same rule.
    private var chipsEnabled: Bool {
        guard let source else { return false }
        return source != "hint" && source != "clue"
    }

    private func chips(for loc: ChapterLoc) -> [PuzzleChip] {
        guard chipsEnabled, let access else { return [] }
        let ids = puzzleProvider.chapterIndex.puzzleIDs(book: loc.book, chapter: loc.chapter.number)
        guard !ids.isEmpty else { return [] }
        let recordsByID = Dictionary(records.map { ($0.puzzleID, $0) }, uniquingKeysWith: { a, _ in a })
        return ids.compactMap { id in
            guard let puzzle = puzzleProvider.puzzle(id: id) else { return nil }
            let record = recordsByID[id]
            let playable = access.canPlay(puzzle, isPremium: store.isPremium, hasProgress: record != nil)
            return PuzzleChip(puzzle: puzzle, solved: record?.isCompleted ?? false, locked: !playable)
        }
    }

    private func logChips(at i: Int) {
        guard let source, locations.indices.contains(i), !chipsLogged.contains(i) else { return }
        let shown = chips(for: locations[i])
        guard !shown.isEmpty else { return }
        chipsLogged.insert(i)
        analytics.log(.readPuzzleChipsShown(
            book: locations[i].book,
            chapter: locations[i].chapter.number,
            count: shown.count,
            lockedCount: shown.filter(\.locked).count,
            source: source
        ))
    }

    private func handleChip(_ chip: PuzzleChip) {
        analytics.log(.readPuzzleChipTapped(puzzleID: chip.puzzle.id, locked: chip.locked, source: source ?? ""))
        if chip.locked {
            analytics.log(.paywallOpened(source: "read_chip"))
            paywall = PaywallEntry(source: "read_chip")
        } else {
            puzzleLaunch.play(id: chip.puzzle.id)
        }
    }

    // MARK: - Reading plan

    private func markPlanChapterRead() {
        onPlanChapterRead?()
        dismiss()
    }
}

// MARK: - One chapter's text

private struct ChapterPage: View {
    let book: String
    let chapter: BibleChapter
    let fontSize: Double
    var highlight: Int?
    /// Set once the player scrolls this page by hand after a deep-linked
    /// verse has been brought into view. Only the highlighted page reports.
    @Binding var scrolledPast: Bool
    /// Verse numbers bookmarked in this chapter.
    let bookmarked: Set<Int>
    let memorizable: (BibleVerse) -> ChapterReaderView.MemorizeState
    /// Whether this is a reading plan's chapter for today.
    let showsPlanFooter: Bool
    /// Puzzles that cite this chapter, best first. Empty hides the section.
    let chips: [PuzzleChip]
    let onAction: (VerseAction, BibleVerse) -> Void
    let onChip: (PuzzleChip) -> Void
    let onMarkRead: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var flashing = false
    /// True after the programmatic scroll to the verse has landed — offsets
    /// before that are the app moving the page, not the reader.
    @State private var settled = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    Text("Chapter \(chapter.number)")
                        .kicker()
                        .padding(.bottom, Theme.Spacing.xs)

                    ForEach(chapter.verses) { verse in
                        verseRow(verse).id(verse.number)
                    }

                    if !chips.isEmpty {
                        chipRow
                            .padding(.top, Theme.Spacing.l)
                            // Clears the tab bar when nothing follows — see the
                            // plan footer below.
                            .padding(.bottom, showsPlanFooter ? 0 : 96)
                    }

                    if showsPlanFooter {
                        Button(action: onMarkRead) {
                            Label("Mark chapter as read", systemImage: "checkmark")
                        }
                        .buttonStyle(.pillProminent)
                        .padding(.top, Theme.Spacing.l)
                        // The pager ignores the bottom safe area so text can
                        // run under the tab bar; the one control down here
                        // must clear it.
                        .padding(.bottom, 96)
                        .accessibilityHint("Marks today's chapter read and returns")
                    }
                }
                // A measure a reader can actually track — scripture set across
                // a full iPad landscape width is a 40-word line.
                .frame(maxWidth: 640, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.vertical, Theme.Spacing.m)
            }
            .task(id: highlight) {
                guard let target = highlight else { return }
                try? await Task.sleep(for: .milliseconds(60))
                withAnimation(.easeInOut) { proxy.scrollTo(target, anchor: .center) }
                // Past the scroll animation before offsets count as reading.
                try? await Task.sleep(for: .milliseconds(500))
                settled = true
                guard !reduceMotion else { return }
                flashing = true
                try? await Task.sleep(for: .milliseconds(600))
                withAnimation(.easeOut(duration: 0.7)) { flashing = false }
            }
            // A threshold, not any change: a settled page still reports tiny
            // offsets, and only a real drag should flip the flag — which then
            // stays flipped, so this writes state at most once.
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { old, new in
                guard settled, !scrolledPast, abs(new - old) > 24 else { return }
                scrolledPast = true
            }
        }
    }

    /// The puzzles this chapter appears in, as a scrolling row of chips.
    private var chipRow: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("Puzzles from this chapter")
                .kicker()
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.s) {
                    ForEach(chips) { chip in
                        Button { onChip(chip) } label: { chipLabel(chip) }
                            .buttonStyle(.plain)
                            .accessibilityLabel(chipAccessibility(chip))
                            .accessibilityHint(chip.locked ? "Opens the upgrade offer" : "Opens the puzzle")
                    }
                }
            }
            // Let the row bleed to the screen edge on the way out while its
            // first chip stays on the text margin.
            .scrollClipDisabled()
        }
    }

    private func chipLabel(_ chip: PuzzleChip) -> some View {
        HStack(spacing: Theme.Spacing.xs + 2) {
            Image(systemName: chip.solved ? "checkmark.circle.fill" : chip.locked ? "lock.fill" : "square.grid.3x3.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(chip.solved ? Color.green : chip.locked ? Color.secondary : Theme.accent)
            Text(chip.puzzle.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Circle()
                .fill(chip.puzzle.difficulty.tint)
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, Theme.Spacing.s + 2)
        .background(Theme.surface, in: .capsule)
        .foregroundStyle(chip.locked ? .secondary : .primary)
    }

    private func chipAccessibility(_ chip: PuzzleChip) -> String {
        var parts = [chip.puzzle.title, chip.puzzle.difficulty.label]
        if chip.solved { parts.append("solved") }
        if chip.locked { parts.append("locked, Premium") }
        return parts.joined(separator: ", ")
    }

    private func verseRow(_ verse: BibleVerse) -> some View {
        let number = Text("\(verse.number) ")
            .font(.system(size: fontSize * 0.68, weight: .bold))
            .foregroundStyle(Theme.accent)
        // Serif, like every other place scripture is set (Today's verse, the
        // completion card, the share card). Until 2.9 the reader — the one
        // surface that exists for reading — was the exception.
        let body = Text(verse.text)
            .font(.system(size: fontSize, design: .serif))
            .foregroundStyle(.primary)
        // A small mark after the text, inside the run so it wraps with it.
        let mark = bookmarked.contains(verse.number)
            ? Text(" ") + Text(Image(systemName: "bookmark.fill"))
                .font(.system(size: fontSize * 0.6))
                .foregroundStyle(Theme.accent)
            : Text("")

        return (number + body + mark)
            .lineSpacing(5)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 3)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                (flashing && verse.number == highlight) ? Theme.accent.opacity(0.18) : .clear,
                in: .rect(cornerRadius: 8, style: .continuous)
            )
            .contentShape(.rect)
            .contextMenu { verseMenu(verse) }
            .accessibilityLabel("Verse \(verse.number). \(verse.text)\(bookmarked.contains(verse.number) ? ". Bookmarked" : "")")
            .accessibilityHint("Touch and hold for memorize, bookmark, share and copy")
    }

    @ViewBuilder
    private func verseMenu(_ verse: BibleVerse) -> some View {
        switch memorizable(verse) {
        case .available:
            Button { onAction(.memorize, verse) } label: {
                Label("Memorize this verse", systemImage: "brain")
            }
        case .held:
            Label("In Memory Verses", systemImage: "brain.fill")
        case .ineligible:
            EmptyView()
        }
        Button { onAction(.bookmark, verse) } label: {
            if bookmarked.contains(verse.number) {
                Label("Remove bookmark", systemImage: "bookmark.slash")
            } else {
                Label("Bookmark", systemImage: "bookmark")
            }
        }
        Button { onAction(.share, verse) } label: {
            Label("Share", systemImage: "square.and.arrow.up")
        }
        Button { onAction(.copy, verse) } label: {
            Label("Copy", systemImage: "doc.on.doc")
        }
    }
}

// MARK: - Jump to book/chapter

private struct JumpSheet: View {
    let books: [BibleBook]
    let onPick: (_ book: String, _ chapter: Int) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(Testament.allCases, id: \.self) { testament in
                    Section(testament.label) {
                        ForEach(books.filter { $0.testament == testament }) { book in
                            NavigationLink(book.name) {
                                JumpChapterGrid(book: book) { chapter in
                                    onPick(book.name, chapter)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Jump to")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

private struct JumpChapterGrid: View {
    let book: BibleBook
    let onSelect: (Int) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 5)

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(book.chapters) { chapter in
                    Button { onSelect(chapter.number) } label: {
                        Text("\(chapter.number)")
                            .font(.body.weight(.medium))
                            .monospacedDigit()
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(Theme.surface, in: .rect(cornerRadius: 12, style: .continuous))
                            .foregroundStyle(.primary)
                    }
                }
            }
            .padding(Theme.Spacing.m)
        }
        .background(Theme.background)
        .navigationTitle(book.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
