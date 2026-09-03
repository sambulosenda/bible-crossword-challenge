//
//  ChapterReaderView.swift
//  Bible Crossword Challenge
//
//  Paged chapter reader. Swipe left/right to move through chapters (rolling
//  across book boundaries). Remembers the last chapter read, supports jump-to
//  and adjustable text size, and flashes a deep-linked verse into view.
//

import SwiftUI

struct ChapterReaderView: View {
    @Environment(\.scripture) private var scripture

    let startBook: String
    let startChapter: Int
    var highlightVerse: Int? = nil
    /// Which surface opened the reader. Nil when a host logs the close itself
    /// (the verse-first hint sheet), so one visit never reports twice.
    var source: String? = nil

    @Environment(\.analytics) private var analytics
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
                        ChapterPage(
                            book: locations[i].book,
                            chapter: locations[i].chapter,
                            fontSize: fontSize,
                            highlight: i == startIndex ? highlightVerse : nil,
                            scrolledPast: $scrolledPastVerse
                        )
                        .tag(i)
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
        .task { build() }
        .onChange(of: selection) { _, i in
            persist(i)
            if didSettle { pageTurns += 1 }
        }
        .onDisappear {
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
        didSettle = true
    }

    private func persist(_ i: Int) {
        guard locations.indices.contains(i) else { return }
        lastBook = locations[i].book
        lastChapter = locations[i].chapter.number
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
        let number = Text("\(verse.number) ")
            .font(.system(size: fontSize * 0.68, weight: .bold))
            .foregroundStyle(Theme.accent)
        let body = Text(verse.text)
            .font(.system(size: fontSize))
            .foregroundStyle(.primary)

        return (number + body)
            .lineSpacing(5)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 3)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                (flashing && verse.number == highlight) ? Theme.accent.opacity(0.18) : .clear,
                in: .rect(cornerRadius: 8, style: .continuous)
            )
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
