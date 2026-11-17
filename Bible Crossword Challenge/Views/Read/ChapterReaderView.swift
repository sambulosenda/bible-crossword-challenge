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

import SwiftUI

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
    /// Whether a chapter's end links to the puzzles drawn from its book. Off
    /// in the modal a clue's verse opens: that player is mid-solve, and a way
    /// into other puzzles would pull them out of the one they're in.
    var showsPuzzleLink = true

    @Environment(\.analytics) private var analytics
    @Environment(\.memoryVerses) private var memoryVerses
    @Environment(\.bookmarks) private var bookmarks
    @Environment(\.displayScale) private var displayScale
    @Environment(\.dismiss) private var dismiss
    @Environment(StoreService.self) private var store
    @Environment(\.puzzleProvider) private var puzzleProvider
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
    /// Puzzles in the bundle per book, for the chapter footer's link back into
    /// the game. Counted once in `build()`, not per page.
    @State private var puzzlesByBook: [String: Int] = [:]

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
        // Reading gets the screen, as play does: the tab bar sat over the
        // last lines of every chapter. Back returns to the tab.
        .toolbarVisibility(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { fontSize = min(fontSize + 2, 30) } label: { Label("Larger text", systemImage: "textformat.size.larger") }
                        .disabled(fontSize >= 30)
                    Button { fontSize = max(fontSize - 2, 14) } label: { Label("Smaller text", systemImage: "textformat.size.smaller") }
                        .disabled(fontSize <= 14)
                } label: {
                    Label("Text size", systemImage: "textformat.size")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showJump = true } label: { Label("Jump to book or chapter", systemImage: "list.bullet") }
            }
        }
        .task {
            await scripture.preload()
            build()
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
        let next = locations.indices.contains(i + 1) ? locations[i + 1] : nil
        let puzzleBook = showsPuzzleLink ? BibleCanon.book(named: loc.book) : nil
        return ChapterPage(
            book: loc.book,
            chapter: loc.chapter,
            nextTitle: next.map { "\($0.book) \($0.chapter.number)" },
            onNext: { withAnimation { selection = i + 1 } },
            puzzleBook: puzzleBook,
            puzzleCount: puzzleBook.map { puzzlesByBook[$0.name] ?? 0 } ?? 0,
            fontSize: fontSize,
            highlight: i == startIndex ? highlightVerse : nil,
            scrolledPast: $scrolledPastVerse,
            bookmarked: bookmarked,
            memorizable: { verse in memorizeState(for: verse, in: loc) },
            showsPlanFooter: isPlanChapter,
            onAction: { action, verse in handle(action, verse, in: loc) },
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
        puzzlesByBook = Dictionary(
            BibleJourney.progress(completedPuzzleIDs: [], puzzles: puzzleProvider.allPuzzles)
                .map { ($0.name, $0.available) },
            uniquingKeysWith: { first, _ in first }
        )
        let idx = built.firstIndex { $0.book == startBook && $0.chapter.number == startChapter } ?? 0
        startIndex = idx
        selection = idx
        persist(idx)
        recentRaw = RecentChapters.recording(book: startBook, chapter: startChapter, in: recentRaw)
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
        /// A free player's shelf is full — see `MemoryVerseStore.canStartNewVerse`.
        case shelfFull
    }

    private func memorizeState(for verse: BibleVerse, in loc: ChapterLoc) -> MemorizeState {
        let reference = reference(for: verse, in: loc)
        if memoryVerses.entry(for: MemoryCloze.referenceKey(reference)) != nil { return .held }
        guard MemoryCloze.isEligible(verseText: verse.text) else { return .ineligible }
        return memoryVerses.canStartNewVerse(isPremium: store.isPremium) ? .available : .shelfFull
    }

    private func reference(for verse: BibleVerse, in loc: ChapterLoc) -> String {
        "\(loc.book) \(loc.chapter.number):\(verse.number)"
    }

    private func handle(_ action: VerseAction, _ verse: BibleVerse, in loc: ChapterLoc) {
        let reference = reference(for: verse, in: loc)
        analytics.log(.verseAction(kind: action.rawValue, reference: reference))
        switch action {
        case .memorize:
            // Same gate as starting a candidate from the memory list. The menu
            // already reads "shelf full" in this state; this covers a shelf
            // that filled while the menu was open.
            guard memoryVerses.canStartNewVerse(isPremium: store.isPremium) else {
                show("Master a verse to make room")
                return
            }
            _ = memoryVerses.start(reference: reference, verseText: verse.text)
            analytics.log(.memoryVerseAdded(reference: reference, source: "reader"))
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
    /// "Ruth 2" — nil on the last chapter of Revelation.
    let nextTitle: String?
    let onNext: () -> Void
    /// The book's puzzles, linked from the chapter's end; nil when the host
    /// turned the link off.
    let puzzleBook: BibleCanon.Book?
    let puzzleCount: Int
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
    let onAction: (VerseAction, BibleVerse) -> Void
    let onMarkRead: () -> Void

    /// The system's Dynamic Type multiplier, read as a metric that scales from
    /// 100. `fontSize` is a raw point value the reader's own control sets, so
    /// on its own it ignored the text size chosen in Settings entirely —
    /// someone reading everything else at an accessibility size opened a
    /// chapter and got 19pt. The control now picks the base and the system
    /// setting multiplies it, the way a reader's size control should compose
    /// with Dynamic Type rather than replace it.
    @ScaledMetric(relativeTo: .body) private var typeScale: Double = 100

    /// The reader's base size with the system's text-size setting applied.
    private var readingSize: Double { fontSize * typeScale / 100 }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var flashing = false
    /// True after the programmatic scroll to the verse has landed — offsets
    /// before that are the app moving the page, not the reader.
    @State private var settled = false

    /// The page's measured size, for `isSpread`.
    @State private var pageSize: CGSize = .zero
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// Two pages side by side, as a printed Bible opens, on a window wide
    /// enough for two readable columns: iPhone Duo open on its side or
    /// folded like a book, an iPad in landscape. One column across that
    /// width ran every line over the Duo's hinge.
    private var isSpread: Bool {
        horizontalSizeClass == .regular
            && pageSize.width >= 760
            && pageSize.width > pageSize.height
    }

    var body: some View {
        // Measured off the page itself, not the branch inside it: the
        // spread is an empty scroll until its verses are measured, zero
        // wide, so measuring the content flipped it back to the column,
        // which measured wide again — a loop that hung the reader.
        Color.clear
            .overlay {
                if isSpread {
                    spreads
                } else {
                    column(chapter.verses[...], endsChapter: true)
                }
            }
            .onGeometryChange(for: CGSize.self) { proxy in
                proxy.size
            } action: { size in
                pageSize = size
            }
    }

    // MARK: - Spreads

    /// One thing set on a page: a verse, or the chapter's end.
    private enum PageItem: Hashable {
        case verse(Int)
        case end
    }

    /// The chapter set as pages, two to a spread, and the tallest page's
    /// content (taller than a page only when one verse is, at the largest
    /// text sizes).
    private struct Pagination {
        let pages: [[PageItem]]
        let tallest: CGFloat
        var spreadCount: Int { (pages.count + 1) / 2 }
    }

    /// The left and right panes' widths, measured off the spread on screen:
    /// on the Duo folded like a book they differ, the seam sitting on the
    /// hinge rather than mid-window.
    @State private var paneWidths: [CGFloat] = [0, 0]
    /// What the spreads last reported, before it holds still. Each spread
    /// is laid out evenly for a frame before its seam seats on the hinge,
    /// so taken straight these flipped the pages' widths whenever a spread
    /// was built, reflowing the chapter and losing the place.
    @State private var reportedPaneWidths: [CGFloat] = [0, 0]
    /// The spread at the top of the scroll.
    @State private var visibleSpread: Int?
    /// Each verse's height set at each pane's width, and the chapter end's.
    @State private var rowHeights: [[Int: CGFloat]] = [[:], [:]]
    @State private var endHeights: [CGFloat?] = [nil, nil]
    /// The text width each side's heights were last set at. Pagination
    /// waits until it matches the pane's: heights from a width the split
    /// has since left (its first pass, before the seam settles on the
    /// hinge) paged the chapter wrongly and sent a deep link astray.
    @State private var measuredWidths: [CGFloat] = [0, 0]
    /// The height a spread fills: the scroll view's, less its insets.
    @State private var spreadHeight: CGFloat = 0

    /// Room at a page's foot for its number.
    private static let folioRoom: CGFloat = 28

    /// The width text sets at in a pane: the page's 24pt margins off it,
    /// capped at the reader's 640pt measure.
    private func textWidth(_ side: Int) -> CGFloat {
        max(min(paneWidths[side] - 2 * Theme.Spacing.l, 640), 1)
    }

    private func height(of item: PageItem, side: Int) -> CGFloat? {
        switch item {
        case .verse(let number): rowHeights[side][number]
        case .end: endHeights[side]
        }
    }

    /// Verses flowed onto pages in reading order, left page then right, a
    /// verse never split across two. Nil until every height is measured.
    private var pagination: Pagination? {
        guard spreadHeight > 0,
              paneWidths.allSatisfy({ $0 > 0 }),
              (0...1).allSatisfy({ abs(measuredWidths[$0] - textWidth($0)) < 0.5 })
        else { return nil }
        let room = spreadHeight - 2 * Theme.Spacing.m - Self.folioRoom
        let items = chapter.verses.map { PageItem.verse($0.number) } + [.end]
        var pages: [[PageItem]] = [[]]
        var used: CGFloat = 0
        var tallest: CGFloat = 0
        for item in items {
            guard let here = height(of: item, side: (pages.count - 1) % 2) else { return nil }
            if used + here > room, !pages[pages.count - 1].isEmpty {
                pages.append([])
                guard let there = height(of: item, side: (pages.count - 1) % 2) else { return nil }
                used = there
            } else {
                used += here
            }
            pages[pages.count - 1].append(item)
            tallest = max(tallest, used)
        }
        return Pagination(pages: pages, tallest: tallest)
    }

    /// The spread holding the deep-linked verse.
    private func highlightSpread(in layout: Pagination?) -> Int? {
        guard let target = highlight, let layout,
              let page = layout.pages.firstIndex(where: { $0.contains(.verse(target)) })
        else { return nil }
        return page / 2
    }

    private var versesByNumber: [Int: BibleVerse] {
        Dictionary(chapter.verses.map { ($0.number, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// The chapter as an open book: two pages a spread, the text running
    /// down the left page and on down the right, and the next spread a
    /// swipe up, snapping a whole spread at a time. Sideways still turns
    /// the chapter. Each page used to be a scroll of its own, so a long
    /// chapter's right page began thirty verses on from the left's first
    /// line.
    private var spreads: some View {
        let layout = pagination
        return ScrollView {
            LazyVStack(spacing: 0) {
                if let layout {
                    let height = max(spreadHeight, layout.tallest + 2 * Theme.Spacing.m + Self.folioRoom)
                    ForEach(0..<layout.spreadCount, id: \.self) { s in
                        spread(s, of: layout)
                            .frame(height: height)
                    }
                } else {
                    // Blank pages until the verses are measured: the
                    // panes' widths are read off this spread.
                    spread(left: [], right: [], index: 0)
                        .frame(height: max(spreadHeight, 1))
                }
            }
            .frame(maxWidth: .infinity)
            .scrollTargetLayout()
        }
        // By spread, not offset: when the page's height changes (the bars
        // settling after the push, a fold) every spread grows, and an
        // offset kept would leave the reader between two.
        .scrollPosition(id: $visibleSpread, anchor: .top)
        .scrollTargetBehavior(.viewAligned)
        .onScrollGeometryChange(for: CGFloat.self) { @Sendable geometry in
            geometry.containerSize.height - geometry.contentInsets.top - geometry.contentInsets.bottom
        } action: { _, height in
            spreadHeight = height
        }
        // Reading on is turning to another spread once the deep-linked
        // verse's has been brought into view. Noted once the scroll comes
        // to rest: the flag is the reader's state, and changing it
        // mid-fling redrew the pager and stopped the spread short of its
        // snap.
        .onScrollPhaseChange { _, phase in
            guard phase == .idle, settled, !scrolledPast,
                  let target = highlightSpread(in: pagination), visibleSpread != target
            else { return }
            scrolledPast = true
        }
        // Keyed on the verse's spread, not the verse: the pages can
        // reflow after the first layout (the split seating its seam on
        // the hinge), and the verse should follow them until the
        // reader moves on.
        .task(id: highlightSpread(in: layout)) {
            guard let spread = highlightSpread(in: layout), !scrolledPast else { return }
            settled = false
            try? await Task.sleep(for: .milliseconds(60))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut) { visibleSpread = spread }
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            settled = true
            guard !reduceMotion else { return }
            flashing = true
            try? await Task.sleep(for: .milliseconds(600))
            withAnimation(.easeOut(duration: 0.7)) { flashing = false }
        }
        .background { measuringRig }
        .task(id: reportedPaneWidths) {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled, paneWidths != reportedPaneWidths else { return }
            paneWidths = reportedPaneWidths
        }
    }

    private func spread(_ s: Int, of layout: Pagination) -> some View {
        spread(
            left: layout.pages[2 * s],
            right: 2 * s + 1 < layout.pages.count ? layout.pages[2 * s + 1] : [],
            index: s
        )
    }

    @ViewBuilder
    private func spread(left: [PageItem], right: [PageItem], index s: Int) -> some View {
        if #available(iOS 27.1, *) {
            // The system's split puts the seam on the hinge when the Duo is
            // folded like a book, and leaves a gutter flat.
            ArrangementView {
                page(left, folio: 2 * s + 1, side: 0)
            } secondary: {
                page(right, folio: 2 * s + 2, side: 1)
            }
            .arrangementViewStyle(.split.axes(.horizontal))
        } else {
            HStack(spacing: 0) {
                page(left, folio: 2 * s + 1, side: 0)
                page(right, folio: 2 * s + 2, side: 1)
            }
        }
    }

    /// One page: its verses from the top, its number at the foot.
    private func page(_ items: [PageItem], folio: Int, side: Int) -> some View {
        let verses = versesByNumber
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(items, id: \.self) { item in
                switch item {
                case .verse(let number):
                    if let verse = verses[number] {
                        verseRow(verse)
                    }
                case .end:
                    VStack(spacing: 0) { endOfChapter }
                }
            }
            Spacer(minLength: 0)
            if !items.isEmpty {
                Text("\(folio)")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .frame(height: Self.folioRoom, alignment: .bottom)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: 640, alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.vertical, Theme.Spacing.m)
        // The pane's width, for the measuring columns. Read off the spread
        // on screen: a hidden split laid out beside it got one pane only.
        // Only a spread wholly in view counts — one part scrolled away
        // splits evenly instead of seating its seam on the hinge. Whole
        // points, down: the hinge split reports fractions that differ from
        // spread to spread.
        .onGeometryChange(for: CGFloat?.self) { proxy in
            guard let visible = proxy.bounds(of: .scrollView),
                  visible.minY <= 1, visible.maxY >= proxy.size.height - 1
            else { return nil }
            return proxy.size.width.rounded(.down)
        } action: { width in
            guard let width, reportedPaneWidths[side] != width else { return }
            reportedPaneWidths[side] = width
        }
    }

    /// Never seen: every verse set at each pane's width, for `pagination`
    /// to flow the pages from.
    private var measuringRig: some View {
        ZStack(alignment: .topLeading) {
            measuringColumn(0)
            measuringColumn(1)
        }
        .hidden()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func measuringColumn(_ side: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(chapter.verses) { verse in
                verseRow(verse)
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.size.height
                    } action: { height in
                        rowHeights[side][verse.number] = height
                    }
            }
            VStack(spacing: 0) { endOfChapter }
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { height in
                    endHeights[side] = height
                }
        }
        .frame(width: textWidth(side))
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            measuredWidths[side] = width
        }
    }

    /// The chapter as one scrolling column: the reader's page everywhere
    /// but a wide window.
    private func column(_ verses: ArraySlice<BibleVerse>, endsChapter: Bool) -> some View {
        let holdsHighlight = highlight.map { target in verses.contains { $0.number == target } } ?? false
        return ScrollViewReader { proxy in
            ScrollView {
                // No "Chapter N" kicker: the title above already says it.
                // Verses sit a line-gap apart rather than a card-gap, so the
                // chapter reads as running text, not a list of rows.
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(verses) { verse in
                        verseRow(verse).id(verse.number)
                    }

                    if endsChapter {
                        endOfChapter
                    }
                }
                // A measure a reader can actually track — scripture set across
                // a full iPad landscape width is a 40-word line.
                .frame(maxWidth: 640, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.vertical, Theme.Spacing.m)
            }
            .task(id: holdsHighlight ? highlight : nil) {
                guard holdsHighlight, let target = highlight else { return }
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
            // `@Sendable`: the transform isn't, in the SDK, so it would
            // inherit main-actor isolation and trap if SwiftUI measured
            // off the main thread (see `Theme.adaptive`).
            .onScrollGeometryChange(for: CGFloat.self) { @Sendable geometry in
                geometry.contentOffset.y
            } action: { old, new in
                guard holdsHighlight, settled, !scrolledPast, abs(new - old) > 24 else { return }
                scrolledPast = true
            }
        }
    }

    /// The next chapter and the book's puzzles, or the reading plan's
    /// mark-read on its chapter.
    @ViewBuilder
    private var endOfChapter: some View {
        if !showsPlanFooter {
            chapterFooter
        }

        if showsPlanFooter {
            Button(action: onMarkRead) {
                Label("Mark chapter as read", systemImage: "checkmark")
            }
            .buttonStyle(.pillProminent)
            .padding(.top, Theme.Spacing.l)
            // The pager ignores the bottom safe area; clear the
            // home indicator.
            .padding(.bottom, Theme.Spacing.xl)
            .accessibilityHint("Marks today's chapter read and returns")
        }
    }

    /// Where a chapter goes when it ends. The next chapter was a sideways
    /// swipe nothing on screen mentioned, so a finished chapter read as a
    /// dead end; and the book's puzzles were never offered from the text
    /// they're drawn from.
    @ViewBuilder
    private var chapterFooter: some View {
        VStack(spacing: Theme.Spacing.s) {
            if let nextTitle {
                Button(action: onNext) {
                    HStack {
                        Text(nextTitle)
                            .font(.headline)
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.right")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(.primary)
                    .padding(Theme.Spacing.m)
                    .frame(maxWidth: .infinity)
                    .background(Theme.surface, in: .rect(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(PressableCardStyle())
                .accessibilityLabel("Next chapter, \(nextTitle)")
            }
            if let puzzleBook, puzzleCount > 0 {
                NavigationLink {
                    JourneyBookView(book: puzzleBook)
                } label: {
                    HStack {
                        Label(
                            puzzleCount == 1 ? "1 puzzle from \(book)" : "\(puzzleCount) puzzles from \(book)",
                            systemImage: "square.grid.3x3"
                        )
                        .font(.subheadline.weight(.semibold))
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.forward")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .foregroundStyle(.primary)
                    .padding(Theme.Spacing.m)
                    .frame(maxWidth: .infinity)
                    .background(Theme.surface, in: .rect(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(PressableCardStyle())
            }
        }
        .padding(.top, Theme.Spacing.xl)
        .padding(.bottom, Theme.Spacing.xl)
    }

    private func verseRow(_ verse: BibleVerse) -> some View {
        // Floored at the platform's 11pt minimum: at the smallest base the
        // reader offers, a proportional number came out at 9.5pt and the
        // bookmark at 8.4.
        // Secondary, not accent: blue means tappable across the app, and the
        // number isn't — the verse's actions are a touch-and-hold anywhere on
        // it. Raised a little, the way a printed Bible sets it.
        let number = Text("\(verse.number) ")
            .font(.system(size: max(readingSize * 0.62, 11), weight: .semibold))
            .baselineOffset(readingSize * 0.25)
            .foregroundStyle(.secondary)
        // Serif, like every other place scripture is set (Today's verse, the
        // completion card, the share card). Until 2.9 the reader — the one
        // surface that exists for reading — was the exception.
        let body = Text(verse.text)
            .font(.system(size: readingSize, design: .serif))
            .foregroundStyle(.primary)
        // A small mark after the text, inside the run so it wraps with it.
        let mark = bookmarked.contains(verse.number)
            ? Text(" ") + Text(Image(systemName: "bookmark.fill"))
                .font(.system(size: max(readingSize * 0.6, 11)))
                .foregroundStyle(Theme.accent)
            : Text("")

        return (number + body + mark)
            .lineSpacing(5)
            .fixedSize(horizontal: false, vertical: true)
            // Half the line spacing each side: verse to verse is one line-gap.
            .padding(.vertical, 2.5)
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
        case .shelfFull:
            Label("Master a verse to make room", systemImage: "brain")
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
