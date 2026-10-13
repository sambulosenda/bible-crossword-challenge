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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
    /// Puzzles whose title matches the query — the app's own content, which
    /// search used to skip for the Bible's.
    @State private var puzzleHits: [Puzzle] = []
    /// See `featuredReferences`. Built once on the first search: the bundle
    /// doesn't change while the app runs.
    @State private var featuredCache: Set<String>?
    /// The query the current results answer. "Nothing found" waits for it to
    /// catch up with the box — it flashed for every query while the scan ran.
    @State private var searchedQuery = ""
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
                        recentRow
                    } more: {
                        // One group for reading, and no second loud card:
                        // "continue", the two testaments and the plans used
                        // to be four stacked cards, the first with a pill of
                        // its own competing with the memory card's.
                        browseSection
                        progressGroup
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
                guard !trimmed.isEmpty else { results = ScriptureSearch.Results(); puzzleHits = []; searchedQuery = ""; return }
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
                await scripture.preload()
                let books = scripture.books
                let featured = featuredCache ?? featuredReferences
                if featuredCache == nil { featuredCache = featured }
                let found = await Task.detached(priority: .userInitiated) {
                    ScriptureSearch.search(trimmed, in: books, featured: featured)
                }.value
                guard !Task.isCancelled else { return }
                results = found
                puzzleHits = matchingPuzzles(trimmed)
                searchedQuery = trimmed
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
            if !puzzleHits.isEmpty {
                Text("Puzzles").sectionHeader()
                    .padding(.horizontal, Theme.Spacing.xs)
                SearchPuzzleRows(puzzles: puzzleHits)
            }
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
                // Ranked, so "top" is honest now; "First 50" described canon
                // order, which is what buried Psalm 23.
                Text(results.totalVerses > results.verses.count
                     ? "Top \(results.verses.count) of \(results.totalVerses) verses"
                     : "\(results.verses.count) \(results.verses.count == 1 ? "verse" : "verses")")
                    .sectionHeader()
                    .padding(.horizontal, Theme.Spacing.xs)
                    .padding(.top, puzzleHits.isEmpty ? 0 : Theme.Spacing.m)
                ForEach(results.verses) { hit in
                    Button {
                        open(reference: ScriptureRef(book: hit.book, chapter: hit.chapter, verse: hit.verse))
                    } label: {
                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                            // Ink, not accent: the whole card is the control.
                            Text(hit.reference)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(highlighted(hit.text, matching: trimmed))
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
            if results.isEmpty && puzzleHits.isEmpty && trimmed.count >= ScriptureSearch.minWordLength && searchedQuery == trimmed {
                Text("Nothing found for “\(trimmed)”")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, Theme.Spacing.xl)
            } else if results.isEmpty && puzzleHits.isEmpty && trimmed.count < ScriptureSearch.minWordLength {
                Text("Try “John 3:16”, “Ruth”, or “small voice”")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, Theme.Spacing.xl)
            }
        }
    }

    /// The verse with the searched words set in ink and the rest in
    /// secondary, so the eye lands on why each verse matched.
    private func highlighted(_ text: String, matching query: String) -> AttributedString {
        // Three lines hold about 120 characters; a match past that was cut
        // off mid-word ("pouch of his s…"). Start the excerpt a few words
        // before it instead.
        var shown = text
        if let match = text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]),
           text.distance(from: text.startIndex, to: match.lowerBound) > 90 {
            let back = text.index(match.lowerBound, offsetBy: -50)
            let wordStart = text[back...].firstIndex(of: " ").map { text.index(after: $0) } ?? back
            shown = "…" + text[wordStart...]
        }
        var out = AttributedString(shown)
        out.foregroundColor = .secondary
        var searchStart = out.startIndex
        while let range = out[searchStart...].range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) {
            out[range].foregroundColor = .primary
            out[range].font = .scripture(.body, weight: .semibold)
            searchStart = range.upperBound
        }
        return out
    }

    /// Every reference the puzzles are built on — their verses and their
    /// clues' — which search ranks first.
    private var featuredReferences: Set<String> {
        var refs: Set<String> = []
        for puzzle in puzzleProvider.allPuzzles {
            refs.insert(puzzle.reference)
            for clue in puzzle.clues { if let r = clue.reference { refs.insert(r) } }
        }
        return refs
    }

    /// Up to three puzzles whose title contains the query, one per title:
    /// the bundle reuses a title across formats. Three, not more: five tall
    /// cards pushed every verse below the keyboard.
    private func matchingPuzzles(_ query: String) -> [Puzzle] {
        guard query.count >= ScriptureSearch.minWordLength else { return [] }
        var seen: Set<String> = []
        return puzzleProvider.allPuzzles
            .filter { $0.title.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
            .filter { seen.insert($0.title).inserted }
            .prefix(3)
            .map { $0 }
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
        // Minus the book being resumed: "Ruth 1" beside "Continue · Ruth 2"
        // is the same reading twice. What's left is somewhere else.
        let entries = RecentChapters.entries(from: recentRaw)
            .filter { !hasReadBefore || $0.book != point.book }
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Text("Recent")
                    .sectionHeader()
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

    // MARK: - Your progress

    /// What the player has kept and covered, as one card with no header: a
    /// "Your Bible" label over a single row was a heading for nothing.
    private var progressGroup: some View {
        VStack(spacing: 0) {
            if !bookmarks.entries.isEmpty {
                NavigationLink {
                    BookmarksView()
                } label: {
                    groupRow(symbol: "bookmark.fill", title: "Bookmarks", subtitle: bookmarksSummary)
                }
                .buttonStyle(PressableCardStyle())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Bookmarks. \(bookmarksSummary)")
                .accessibilityHint("Opens your bookmarked verses")
                groupDivider
            }
            JourneyCard(source: "read_tab", grouped: true)
        }
        .elevatedCard()
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
                    Text("Start with a well-loved verse or one from a puzzle you've solved. A few blanks at a time, a little more each day.")
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
                Text("From your puzzles").sectionHeader()
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
        let oldTestament: [BibleBook]
        let newTestament: [BibleBook]

        /// Stands in while the decode runs, drawn redacted. Canon counts are
        /// fixed, so the browse rows can show their real numbers meanwhile.
        static let placeholder = Snapshot(
            book: "Genesis", chapter: 1, isFresh: true,
            oldTestament: [], newTestament: []
        )

        init(book: String, chapter: Int, isFresh: Bool,
             oldTestament: [BibleBook], newTestament: [BibleBook]) {
            self.book = book
            self.chapter = chapter
            self.isFresh = isFresh
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
                oldTestament: books.filter { $0.testament == .old },
                newTestament: books.filter { $0.testament == .new }
            )
        }

        func books(in testament: Testament) -> [BibleBook] {
            testament == .old ? oldTestament : newTestament
        }
    }

    // MARK: - Rows

    /// One row of the reading group: a disc icon, a headline, a caption, a
    /// chevron — the shape of every navigation row on this tab.
    private func groupRow(symbol: String, title: String, subtitle: String) -> some View {
        HStack(spacing: Theme.Spacing.m) {
            // Decorative, so it gives way at accessibility sizes: beside it
            // "Old Testament" broke as "Testa-ment" at AX5.
            if !dynamicTypeSize.isAccessibilitySize {
                Image(systemName: symbol)
                    .font(.title2)
                    .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                    .foregroundStyle(Theme.accent)
                    .frame(width: 44, height: 44)
                    .background(Theme.accent.opacity(0.14), in: .circle)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.forward")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.vertical, Theme.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
    }

    private var groupDivider: some View {
        Divider().padding(.leading, Theme.Spacing.l + (dynamicTypeSize.isAccessibilitySize ? 0 : 44 + Theme.Spacing.m))
    }

    /// Where reading left off, as a row: the memory card above owns the tab's
    /// one prominent action, and a second card with its own pill split it.
    private var resumeRow: some View {
        let point = snapshot ?? .placeholder
        let reference = "\(point.book) \(point.chapter)"
        return Button {
            analytics.log(.scriptureOpened(reference: reference, source: "read_continue"))
            showReader = true
        } label: {
            groupRow(symbol: "book.fill", title: reference, subtitle: "Continue reading")
        }
        .buttonStyle(PressableCardStyle())
        .disabled(snapshot == nil)
        .redacted(reason: snapshot == nil ? .placeholder : [])
        .accessibilityLabel("Continue reading \(reference)")
    }

    // MARK: - Browse

    /// Fixed by the canon, so the rows can say so before the decode lands.
    private static let bookCounts: [Testament: Int] = [.old: 39, .new: 27]

    private var browseSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("The Bible")
                .sectionHeader()
                .padding(.horizontal, Theme.Spacing.xs)
            VStack(spacing: 0) {
                if hasReadBefore {
                    resumeRow
                    groupDivider
                }
                ForEach(Testament.allCases, id: \.self) { testament in
                    NavigationLink {
                        BookListView(
                            title: testament.label,
                            books: (snapshot ?? .placeholder).books(in: testament)
                        )
                    } label: {
                        groupRow(
                            symbol: testament == .old ? "books.vertical.fill" : "book.closed.fill",
                            title: testament.label,
                            subtitle: "\(Self.bookCounts[testament, default: 0]) books"
                        )
                    }
                    .buttonStyle(PressableCardStyle())
                    .disabled(snapshot == nil)
                    .accessibilityLabel("\(testament.label), \(Self.bookCounts[testament, default: 0]) books")
                    groupDivider
                }
                // The plans' invite, as the group's last row. It was a card
                // of its own closing the tab; 4 players started a plan in the
                // 30 days to 2026-10-03.
                NavigationLink {
                    ReadingPlansView()
                } label: {
                    groupRow(symbol: "book.pages", title: "Reading plans", subtitle: "A chapter a day through one book")
                }
                .buttonStyle(PressableCardStyle())
            }
            .elevatedCard()
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
        // Readable width, as every other list here: on iPhone Duo open the
        // rows ran 950pt with the chapter count stranded at the far edge.
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity)
        .background(Theme.background)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Chapters of a book

struct ChapterPickerView: View {
    let book: BibleBook
    @Environment(\.analytics) private var analytics
    @Environment(\.puzzleProvider) private var puzzleProvider
    @State private var openChapter: Int?
    @AppStorage("read.lastBook") private var lastBook = ""
    @AppStorage("read.lastChapter") private var lastChapter = 0

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 5)

    /// Chapters a puzzle's verse or clue is drawn from — the reader's way
    /// back into the game, marked on the grid. Computed once on appear: it
    /// parses every reference in the bundle, ~3,800 strings.
    @State private var marked: Set<Int> = []

    private func puzzleChapters() -> Set<Int> {
        var chapters: Set<Int> = []
        for puzzle in puzzleProvider.allPuzzles {
            let refs = [puzzle.reference] + puzzle.clues.compactMap(\.reference)
            for raw in refs {
                if let ref = ScriptureRef(raw), ref.book == book.name { chapters.insert(ref.chapter) }
            }
        }
        return chapters
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                if !marked.isEmpty {
                    Label("Puzzles draw on the chapters marked with a dot.", systemImage: "circle.fill")
                        .labelStyle(DotLabelStyle())
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, Theme.Spacing.xs)
                }
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(book.chapters) { chapter in
                        let hasPuzzle = marked.contains(chapter.number)
                        let isLast = lastBook == book.name && lastChapter == chapter.number
                        Button {
                            analytics.log(.scriptureOpened(
                                reference: "\(book.name) \(chapter.number)",
                                source: "read_browse"
                            ))
                            openChapter = chapter.number
                        } label: {
                            VStack(spacing: 3) {
                                Text("\(chapter.number)")
                                    .font(.body.weight(.medium))
                                    .monospacedDigit()
                                Circle()
                                    .fill(Theme.accent)
                                    .frame(width: 5, height: 5)
                                    .opacity(hasPuzzle ? 1 : 0)
                            }
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(Theme.surface, in: .rect(cornerRadius: 12, style: .continuous))
                            .overlay {
                                // Where reading left off, by a ring — the same
                                // mark the game uses for "you are here".
                                if isLast {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(Theme.accent, lineWidth: 2)
                                }
                            }
                            .foregroundStyle(.primary)
                        }
                        // The card style, not the default: fifty accent-blue
                        // numerals read as fifty links, and the tile is the
                        // control here.
                        .buttonStyle(PressableCardStyle())
                        .accessibilityLabel(accessibilityLabel(chapter.number, hasPuzzle: hasPuzzle, isLast: isLast))
                    }
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
        .task(id: book.name) { marked = puzzleChapters() }
    }

    private func accessibilityLabel(_ number: Int, hasPuzzle: Bool, isLast: Bool) -> String {
        var parts = ["Chapter \(number)"]
        if isLast { parts.append("where you left off") }
        if hasPuzzle { parts.append("has puzzles") }
        return parts.joined(separator: ", ")
    }
}

/// A 5pt accent dot in place of the label's icon, matching the grid's mark.
private struct DotLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: Theme.Spacing.s) {
            Circle().fill(Theme.accent).frame(width: 5, height: 5)
            configuration.title
        }
    }
}

// MARK: - Search puzzle rows

/// The puzzles a search matched. Its own view so the record query lives here:
/// on `ReadView` every saved record redrew the whole Verses tab, for rows
/// that only exist mid-search.
private struct SearchPuzzleRows: View {
    let puzzles: [Puzzle]
    /// Every record, not just solved ones: a puzzle with progress counts as
    /// playable even unsolved.
    @Query private var records: [PuzzleRecord]

    var body: some View {
        let byID = records.byPuzzleID
        ForEach(puzzles) { puzzle in
            // The archive's wall: search reaches the catalogue the way the
            // Library does, not through a book.
            PuzzleLinkRow(puzzle: puzzle, record: byID[puzzle.id], paywallSource: .archive)
        }
    }
}
