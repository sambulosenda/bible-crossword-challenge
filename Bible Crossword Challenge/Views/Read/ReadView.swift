//
//  ReadView.swift
//  Bible Crossword Challenge
//
//  The Read tab: the app's scripture surfaces in one place — resume the
//  chapter last open, memory verses, the journey map, and the whole Bible by
//  testament and book.
//
//  Until 2.8 none of this had a front door. The reader opened only from a
//  verse link, memory verses sat at the foot of Today, the journey map inside
//  Profile, and a flat list of fourteen achievements held the tab slot. In the
//  30 days to 2026-09-03, 22% of actives still reached the reader by verse
//  link alone; memory verses reached 4% and the journey 5%. Scripture is what
//  separates this app from every other crossword, so it gets the tab.
//

import SwiftUI

struct ReadView: View {
    @Environment(\.scripture) private var scripture
    @Environment(\.memoryVerses) private var memoryVerses
    @Environment(\.bookmarks) private var bookmarks
    @Environment(\.readingPlans) private var plans
    @Environment(\.analytics) private var analytics

    // Written by `ChapterReaderView` as the reader is paged, so the card below
    // resumes from the last chapter open whether it was reached from here or
    // from a puzzle's verse link.
    @AppStorage("read.lastBook") private var lastBook = ""
    @AppStorage("read.lastChapter") private var lastChapter = 0

    /// Everything the screen reads out of the Bible, taken in one pass after
    /// the decode. `body` never touches `scripture` itself: the first read
    /// decodes 4.6 MB of JSON, and doing that inside `body` put it on the
    /// main thread the first time the tab was drawn.
    @State private var snapshot: Snapshot?
    @State private var showReader = false
    @State private var showPlanReader = false

    /// Search: a reference, a book, or words in the text — see
    /// `ScriptureSearch`. Reaching a chapter was three taps with no other way
    /// in until 2.9.
    @State private var query = ""
    @State private var results = ScriptureSearch.Results()
    @State private var searchTarget: SearchTarget?
    @State private var searchBook: BibleBook?
    @AppStorage(RecentChapters.key) private var recentRaw = ""
    @State private var recentTarget: RecentChapters.Entry?

    /// A chapter (and maybe verse) a search result opens.
    private struct SearchTarget: Hashable {
        let book: String
        let chapter: Int
        let verse: Int?
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                SearchAware { searching in
                    if searching {
                        searchResults
                    } else {
                        VStack(spacing: Theme.Spacing.l) {
                            // The habit first, then the bookmark, then the shelves.
                            ReadingPlanCard(onRead: openPlanChapter)
                            resumeCard
                            recentRow
                            MemoryVerseCard(
                                dueCount: memoryVerses.dueCount,
                                activeCount: memoryVerses.entries.count
                            )
                            JourneyCard(source: "read_tab")
                            if !bookmarks.entries.isEmpty {
                                bookmarksCard
                            }
                            browseSection
                        }
                    }
                }
                .padding(Theme.Spacing.m)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .background(Theme.background)
            .navigationTitle("Read")
            .searchable(text: $query, prompt: "Verse, chapter or words")
            .onSubmit(of: .search) {
                analytics.log(.readSearch(kind: results.kind, results: results.count))
            }
            .task(id: query) {
                // Debounced, then off the main thread: a word scans 31,000
                // verses, which is tens of milliseconds the keyboard shouldn't
                // wait for.
                let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { results = ScriptureSearch.Results(); return }
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
                await scripture.preload()
                let books = scripture.books
                let found = await Task.detached(priority: .userInitiated) {
                    ScriptureSearch.search(trimmed, in: books)
                }.value
                guard !Task.isCancelled else { return }
                results = found
            }
            .navigationDestination(item: $searchTarget) { target in
                ChapterReaderView(
                    startBook: target.book,
                    startChapter: target.chapter,
                    highlightVerse: target.verse,
                    source: "read_search"
                )
            }
            .navigationDestination(item: $searchBook) { book in
                ChapterPickerView(book: book)
            }
            .navigationDestination(item: $recentTarget) { entry in
                ChapterReaderView(startBook: entry.book, startChapter: entry.chapter, source: "read_recent")
            }
            // Re-taken whenever the reader moves the bookmark, so coming back
            // from a chapter shows that chapter on the card.
            .task(id: "\(lastBook)#\(lastChapter)") {
                await scripture.preload()
                snapshot = Snapshot(
                    scripture: scripture,
                    lastBook: lastBook,
                    lastChapter: lastChapter
                )
            }
            .navigationDestination(isPresented: $showReader) {
                let point = snapshot ?? .placeholder
                ChapterReaderView(
                    startBook: point.book,
                    startChapter: point.chapter,
                    source: point.isFresh ? "read_start" : "read_continue"
                )
            }
            .navigationDestination(isPresented: $showPlanReader) {
                if let plan = plans.activePlan, let day = plans.nextDay {
                    ChapterReaderView(
                        startBook: plan.book,
                        startChapter: day,
                        source: "read_plan",
                        planChapter: PlanChapter(book: plan.book, chapter: day),
                        onPlanChapterRead: { markPlanRead(plan, day: day) }
                    )
                }
            }
            // The memory list pushes practice by value, as it does from Today.
            .navigationDestination(for: MemoryRoute.self) { _ in
                MemoryVerseListView(source: "read_tab")
            }
            .navigationDestination(for: MemoryPracticeRoute.self) { route in
                MemoryPracticeView(referenceKey: route.referenceKey, source: route.source)
            }
        }
    }

    // MARK: - Search

    /// Reads `isSearching`, which only exists below the `.searchable` view.
    private struct SearchAware<Content: View>: View {
        @Environment(\.isSearching) private var isSearching
        @ViewBuilder let content: (Bool) -> Content
        var body: some View { content(isSearching) }
    }

    @ViewBuilder
    private var searchResults: some View {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            if let ref = results.reference {
                searchRow(
                    title: ref.verse.map { "\(ref.book) \(ref.chapter):\($0)" } ?? "\(ref.book) \(ref.chapter)",
                    detail: "Open chapter",
                    symbol: "book"
                ) {
                    open(reference: ref)
                }
            }
            if let book = results.book {
                searchRow(title: book.name, detail: "\(book.chapterCount) chapters", symbol: "books.vertical") {
                    analytics.log(.scriptureOpened(reference: book.name, source: "read_search"))
                    searchBook = book
                }
            }
            if !results.verses.isEmpty {
                Text(results.verses.count == ScriptureSearch.maxHits
                     ? "First \(ScriptureSearch.maxHits) verses"
                     : "\(results.verses.count) \(results.verses.count == 1 ? "verse" : "verses")")
                    .kicker()
                    .padding(.horizontal, Theme.Spacing.xs)
                    .padding(.top, Theme.Spacing.s)
                ForEach(results.verses) { hit in
                    Button {
                        open(reference: ScriptureRef(book: hit.book, chapter: hit.chapter, verse: hit.verse))
                    } label: {
                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                            Text(hit.reference)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.accent)
                            Text(hit.text)
                                .font(.scripture(.body))
                                .foregroundStyle(.primary)
                                .lineSpacing(3)
                                .lineLimit(3)
                                .multilineTextAlignment(.leading)
                        }
                        .padding(Theme.Spacing.m)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .elevatedCard()
                    }
                    .buttonStyle(PressableCardStyle())
                    .accessibilityLabel("\(hit.reference). \(hit.text)")
                }
            }
            if results.isEmpty && trimmed.count >= ScriptureSearch.minWordLength {
                Text("Nothing found for “\(trimmed)”")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, Theme.Spacing.xl)
            } else if results.isEmpty {
                Text("Try “John 3:16”, “Ruth”, or “small voice”")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, Theme.Spacing.xl)
            }
        }
    }

    private func searchRow(title: String, detail: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.m) {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(Theme.accent)
                    .frame(width: 40, height: 40)
                    .background(Theme.accent.opacity(0.14), in: .circle)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(Theme.Spacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .elevatedCard()
        }
        .buttonStyle(PressableCardStyle())
    }

    private func open(reference ref: ScriptureRef) {
        let text = ref.verse.map { "\(ref.book) \(ref.chapter):\($0)" } ?? "\(ref.book) \(ref.chapter)"
        analytics.log(.scriptureOpened(reference: text, source: "read_search"))
        searchTarget = SearchTarget(book: ref.book, chapter: ref.chapter, verse: ref.verse)
    }

    // MARK: - Recent

    /// The last few chapters opened, minus the one the resume card already
    /// shows. Hidden until there are any.
    @ViewBuilder
    private var recentRow: some View {
        let point = snapshot ?? .placeholder
        let entries = RecentChapters.entries(from: recentRaw)
            .filter { !($0.book == point.book && $0.chapter == point.chapter) }
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Text("Recent")
                    .kicker()
                    .padding(.horizontal, Theme.Spacing.xs)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.Spacing.s) {
                        ForEach(entries) { entry in
                            Button {
                                analytics.log(.scriptureOpened(reference: entry.reference, source: "read_recent"))
                                recentTarget = entry
                            } label: {
                                Label(entry.reference, systemImage: "clock")
                                    .font(.subheadline.weight(.semibold))
                                    .padding(.horizontal, Theme.Spacing.m)
                                    .padding(.vertical, Theme.Spacing.s + 2)
                                    .background(Theme.surface, in: .capsule)
                                    .foregroundStyle(.primary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Opens \(entry.reference)")
                        }
                    }
                }
                .scrollClipDisabled()
            }
        }
    }

    // MARK: - Reading plan

    private func openPlanChapter() {
        guard let plan = plans.activePlan, let day = plans.nextDay else { return }
        analytics.log(.scriptureOpened(reference: "\(plan.book) \(day)", source: "read_plan"))
        showPlanReader = true
    }

    private func markPlanRead(_ plan: ReadingPlan, day: Int) {
        guard plans.markRead(day: day) else { return }
        analytics.log(.planChapterRead(plan: plan.id, day: day))
        if plans.isComplete {
            analytics.log(.planCompleted(plan: plan.id, days: day))
        }
    }

    // MARK: - Bookmarks

    private var bookmarksCard: some View {
        NavigationLink {
            BookmarksView()
        } label: {
            HStack(spacing: Theme.Spacing.m) {
                Image(systemName: "bookmark.fill")
                    .font(.title2)
                    .foregroundStyle(Theme.accent)
                    .frame(width: 44, height: 44)
                    .background(Theme.accent.opacity(0.14), in: .circle)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Bookmarks").kicker()
                    Text(bookmarks.entries.first?.reference ?? "")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("\(bookmarks.entries.count) \(bookmarks.entries.count == 1 ? "verse" : "verses") kept")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(Theme.Spacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .elevatedCard()
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Bookmarks, \(bookmarks.entries.count) verses kept")
        .accessibilityHint("Opens your bookmarked verses")
    }

    // MARK: - Snapshot

    private struct Snapshot {
        let book: String
        let chapter: Int
        /// True until any chapter has been read: the card says "start", not
        /// "continue", and opens the first page of the canon.
        let isFresh: Bool
        /// The chapter's opening verse, so the card shows scripture rather
        /// than a reference alone.
        let preview: String?
        let oldTestament: [BibleBook]
        let newTestament: [BibleBook]

        /// Stands in while the decode runs, drawn redacted. Canon counts are
        /// fixed, so the browse rows can show their real numbers meanwhile.
        static let placeholder = Snapshot(
            book: "Genesis", chapter: 1, isFresh: true, preview: nil,
            oldTestament: [], newTestament: []
        )

        init(book: String, chapter: Int, isFresh: Bool, preview: String?,
             oldTestament: [BibleBook], newTestament: [BibleBook]) {
            self.book = book
            self.chapter = chapter
            self.isFresh = isFresh
            self.preview = preview
            self.oldTestament = oldTestament
            self.newTestament = newTestament
        }

        init(scripture: ScriptureProvider, lastBook: String, lastChapter: Int) {
            let books = scripture.books
            let resumed = !lastBook.isEmpty && lastChapter > 0 && scripture.book(named: lastBook) != nil
            let book = resumed ? lastBook : (books.first?.name ?? "Genesis")
            let chapter = resumed ? lastChapter : 1
            self.init(
                book: book,
                chapter: chapter,
                isFresh: !resumed,
                preview: scripture.book(named: book)?
                    .chapters.first { $0.number == chapter }?
                    .verses.first?.text,
                oldTestament: books.filter { $0.testament == .old },
                newTestament: books.filter { $0.testament == .new }
            )
        }

        func books(in testament: Testament) -> [BibleBook] {
            testament == .old ? oldTestament : newTestament
        }
    }

    // MARK: - Resume

    private var resumeCard: some View {
        let point = snapshot ?? .placeholder
        let reference = "\(point.book) \(point.chapter)"
        return VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Text(point.isFresh ? "Start reading" : "Continue reading")
                    .kicker()
                Text(reference)
                    .font(.scripture(.title2, weight: .semibold))
                if let preview = point.preview {
                    Text(preview)
                        .font(.scripture(.body))
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)
                        .lineLimit(3)
                }
            }
            Button {
                analytics.log(.scriptureOpened(
                    reference: reference,
                    source: point.isFresh ? "read_start" : "read_continue"
                ))
                showReader = true
            } label: {
                Label(point.isFresh ? "Open \(reference)" : "Continue", systemImage: "book")
            }
            .buttonStyle(.pillProminent)
            .disabled(snapshot == nil)
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .elevatedCard()
        .redacted(reason: snapshot == nil ? .placeholder : [])
        .accessibilityElement(children: .contain)
    }

    // MARK: - Browse

    /// Fixed by the canon, so the rows can say so before the decode lands.
    private static let bookCounts: [Testament: Int] = [.old: 39, .new: 27]

    private var browseSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("The whole Bible")
                .kicker()
                .padding(.horizontal, Theme.Spacing.xs)
            ForEach(Testament.allCases, id: \.self) { testament in
                NavigationLink {
                    BookListView(
                        title: testament.label,
                        books: (snapshot ?? .placeholder).books(in: testament)
                    )
                } label: {
                    HStack(spacing: Theme.Spacing.m) {
                        Image(systemName: testament == .old ? "books.vertical.fill" : "book.closed.fill")
                            .font(.title2)
                            .foregroundStyle(Theme.accent)
                            .frame(width: 44, height: 44)
                            .background(Theme.accent.opacity(0.14), in: .circle)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(testament.label)
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Text("\(Self.bookCounts[testament, default: 0]) books")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(Theme.Spacing.l)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .elevatedCard()
                }
                .buttonStyle(PressableCardStyle())
                .disabled(snapshot == nil)
                .accessibilityLabel("\(testament.label), \(Self.bookCounts[testament, default: 0]) books")
            }
        }
    }
}

// MARK: - Books of a testament

struct BookListView: View {
    let title: String
    /// Already filtered to one testament by the parent's snapshot — nothing
    /// here re-reads the provider or filters inside `body`.
    let books: [BibleBook]

    var body: some View {
        List(books) { book in
            NavigationLink {
                ChapterPickerView(book: book)
            } label: {
                HStack {
                    Text(book.name)
                    Spacer()
                    Text("\(book.chapterCount)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(book.name), \(book.chapterCount) chapters")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Chapters of a book

struct ChapterPickerView: View {
    let book: BibleBook
    @Environment(\.analytics) private var analytics
    @State private var openChapter: Int?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 5)

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(book.chapters) { chapter in
                    Button {
                        analytics.log(.scriptureOpened(
                            reference: "\(book.name) \(chapter.number)",
                            source: "read_browse"
                        ))
                        openChapter = chapter.number
                    } label: {
                        Text("\(chapter.number)")
                            .font(.body.weight(.medium))
                            .monospacedDigit()
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(Theme.surface, in: .rect(cornerRadius: 12, style: .continuous))
                            .foregroundStyle(.primary)
                    }
                    // The card style, not the default: fifty accent-blue
                    // numerals read as fifty links, and the tile is the
                    // control here.
                    .buttonStyle(PressableCardStyle())
                    .accessibilityLabel("Chapter \(chapter.number)")
                }
            }
            .padding(Theme.Spacing.m)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background)
        .navigationTitle(book.name)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $openChapter) { chapter in
            ChapterReaderView(startBook: book.name, startChapter: chapter, source: "read_browse")
        }
    }
}
