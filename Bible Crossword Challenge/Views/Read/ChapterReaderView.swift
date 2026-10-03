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

    @Environment(\.analytics) private var analytics
    @Environment(\.memoryVerses) private var memoryVerses
    @Environment(\.bookmarks) private var bookmarks
    @Environment(\.displayScale) private var displayScale
    @Environment(\.dismiss) private var dismiss
    @Environment(StoreService.self) private var store
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
        return ChapterPage(
            book: loc.book,
            chapter: loc.chapter,
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

    private func verseRow(_ verse: BibleVerse) -> some View {
        // Floored at the platform's 11pt minimum: at the smallest base the
        // reader offers, a proportional number came out at 9.5pt and the
        // bookmark at 8.4.
        let number = Text("\(verse.number) ")
            .font(.system(size: max(readingSize * 0.68, 11), weight: .bold))
            .foregroundStyle(Theme.accent)
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
