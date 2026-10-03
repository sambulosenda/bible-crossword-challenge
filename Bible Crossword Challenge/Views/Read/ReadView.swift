//
//  ReadView.swift
//  Bible Crossword Challenge
//
//  The Verses tab (the Read tab until 2026-10): the verses the player is
//  making their own — memory verses due today first, then the verses their
//  solved puzzles gave them — and below that the reader: resume, search, the
//  book map and the whole Bible.
//
//  Refocused on 2026-10-03. As "Read" it was a reader's front door that about
//  10 of 461 actives used in 30 days, while memory verses were the habit most
//  tied to coming back (half of early users who touched them returned at day
//  7). The reader stays — it's one tap from any verse here — but it is no
//  longer the headline. The type and file keep the old name, and analytics
//  sources keep `read_*`, so the history reads straight through the rename.
//
//  Until 2.8 none of this had a front door. The reader opened only from a
//  verse link, memory verses sat at the foot of Today, the journey map inside
//  Profile, and a flat list of fourteen achievements held the tab slot. In the
//  30 days to 2026-09-03, 22% of actives still reached the reader by verse
//  link alone; memory verses reached 4% and the journey 5%. Scripture is what
//  separates this app from every other crossword, so it gets the tab.
//

import SwiftUI
import SwiftData

struct ReadView: View {
    @Environment(\.scripture) private var scripture
    @Environment(\.memoryVerses) private var memoryVerses
    @Environment(\.puzzleProvider) private var puzzleProvider
    @Environment(\.readerRouter) private var readerRouter
    @Query(filter: #Predicate<PuzzleRecord> { $0.isCompleted })
    private var solvedRecords: [PuzzleRecord]
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
            SearchAware { searching in
                if searching {
                    ScrollView {
                        searchResults
                            .padding(Theme.Spacing.m)
                            .frame(maxWidth: 560)
                            .frame(maxWidth: .infinity)
                    }
                } else {
                    // The habit and the bookmark on the left of a wide
                    // window, the shelves on the right.
                    CardColumns {
                        // The player's own verses first: what's due to
                        // practise, then what their puzzles gave them.
                        memoryLeadCard
                        solvedVersesSection
                        // Then reading — a running plan, and the bookmark
                        // only when there is one. A first visit used to open
                        // on "Open Genesis 1" in the tab's loud pill, the
                        // least likely thing anyone came for (6 players in
                        // 30 days to 2026-10-03).
                        ReadingPlanCard(showsInvite: false, onRead: openPlanChapter)
                        if hasReadBefore {
                            resumeCard
                        }
                        recentRow
                        scriptureSection
                    } more: {
                        browseSection
                        // The invite closes the tab instead of opening it:
                        // 4 players started a plan in 30 days.
                        ReadingPlanCard(showsActive: false, onRead: openPlanChapter)
                    }
                }
            }
            .background(Theme.background)
            .navigationTitle("Verses")
            // Always showing: the fastest way to "John 3:16" was hidden until
            // the page was pulled down.
            .searchable(
                text: $query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Verse, chapter or words"
            )
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
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.forward")
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

    /// A chapter has been opened before, known without decoding the Bible.
    private var hasReadBefore: Bool { !lastBook.isEmpty && lastChapter > 0 }

    // MARK: - Your scripture

    /// What the player has kept and covered, under one header. Memory verses
    /// left this group for the top of the tab.
    private var scriptureSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("Your Bible").kicker()
                .padding(.horizontal, Theme.Spacing.xs)
            if !bookmarks.entries.isEmpty {
                bookmarksCard
            }
            JourneyCard(source: "read_tab")
        }
    }

    // MARK: - Memory verses (lead)

    /// The tab's one loud action, and it is practice: review what's due, carry
    /// on with what's in progress, or pick a first verse. Each state names the
    /// next step rather than the feature.
    private var memoryLeadCard: some View {
        let entries = memoryVerses.entries
        let due = entries.filter { memoryVerses.isDue($0) }
        let learning = entries.filter { !$0.isMastered }.count
        let mastered = entries.count - learning

        return VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Text("Memory verses").kicker()
                if let first = due.first {
                    Text(due.count == 1 ? "1 verse to review" : "\(due.count) verses to review")
                        .font(.scripture(.title2, weight: .semibold))
                    Text(first.verseText)
                        .font(.scripture(.body))
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)
                        .lineLimit(3)
                    Text(first.reference)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                } else if !entries.isEmpty {
                    Text("Nothing due today")
                        .font(.scripture(.title2, weight: .semibold))
                    Text(progressLine(learning: learning, mastered: mastered))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Learn a verse by heart")
                        .font(.scripture(.title2, weight: .semibold))
                    Text("Start with one from a puzzle you've solved. A few blanks at a time, a little more each day.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let first = due.first {
                NavigationLink(value: MemoryPracticeRoute(referenceKey: first.referenceKey, source: "verses_tab")) {
                    Label("Review", systemImage: "brain")
                }
                .buttonStyle(.pillProminent)
            } else {
                NavigationLink(value: MemoryRoute()) {
                    Text(entries.isEmpty ? "Choose a verse" : "See your verses")
                }
                .buttonStyle(entries.isEmpty ? .pillProminent : .pillTonal)
            }
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .elevatedCard()
    }

    private func progressLine(learning: Int, mastered: Int) -> String {
        var parts: [String] = []
        if learning > 0 { parts.append("\(learning) learning") }
        if mastered > 0 { parts.append("\(mastered) mastered") }
        return parts.joined(separator: " · ") + ". Come back tomorrow for the next round."
    }

    // MARK: - From your puzzles

    /// The verses behind the puzzles most recently finished — the scripture a
    /// player has actually met here, which is the reason this tab exists.
    private var solvedVerses: [Puzzle] {
        let byID = Dictionary(
            puzzleProvider.allPuzzles.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var seen: Set<String> = []
        return solvedRecords
            .sorted { ($0.completedDate ?? .distantPast) > ($1.completedDate ?? .distantPast) }
            .compactMap { byID[$0.puzzleID] }
            .filter { seen.insert($0.reference).inserted }
            .prefix(3)
            .map { $0 }
    }

    @ViewBuilder
    private var solvedVersesSection: some View {
        let verses = solvedVerses
        if !verses.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Text("From your puzzles").kicker()
                    .padding(.horizontal, Theme.Spacing.xs)
                VStack(spacing: 0) {
                    ForEach(Array(verses.enumerated()), id: \.element.id) { index, puzzle in
                        if index > 0 {
                            Divider().padding(.leading, Theme.Spacing.l)
                        }
                        Button {
                            analytics.log(.scriptureOpened(reference: puzzle.reference, source: "verses_solved"))
                            readerRouter.open(reference: puzzle.reference, source: "verses_solved")
                        } label: {
                            HStack(alignment: .top, spacing: Theme.Spacing.m) {
                                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                                    Text(puzzle.reference)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    Text(puzzle.verse)
                                        .font(.scripture(.subheadline))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                    Text(puzzle.title)
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.forward")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(Theme.Spacing.l)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(.rect)
                        }
                        .buttonStyle(PressableCardStyle())
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(puzzle.reference). \(puzzle.verse). From \(puzzle.title)")
                        .accessibilityHint("Opens the passage")
                    }
                }
                .elevatedCard()
            }
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
                    .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                    .foregroundStyle(Theme.accent)
                    .frame(width: 44, height: 44)
                    .background(Theme.accent.opacity(0.14), in: .circle)
                // The name leads, as on every other row under the header; the
                // latest reference moves into the line beneath it.
                VStack(alignment: .leading, spacing: 2) {
                    Text("Bookmarks")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(bookmarksSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.forward")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(Theme.Spacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .elevatedCard()
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Bookmarks. \(bookmarksSummary)")
        .accessibilityHint("Opens your bookmarked verses")
    }

    private var bookmarksSummary: String {
        let count = bookmarks.entries.count
        let kept = "\(count) \(count == 1 ? "verse" : "verses") kept"
        guard let latest = bookmarks.entries.first?.reference else { return kept }
        return "\(kept) · latest \(latest)"
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
            // Tonal: the memory card above owns the tab's one loud action.
            .buttonStyle(.pillTonal)
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
                        Image(systemName: "chevron.forward")
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
