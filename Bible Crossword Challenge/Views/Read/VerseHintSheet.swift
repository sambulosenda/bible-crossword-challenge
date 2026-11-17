//
//  VerseHintSheet.swift
//  Bible Crossword Challenge
//
//  The verse hint's sheet: the verse the clue comes from, with the verse on
//  either side for sense, and the chapter one tap away.
//
//  It used to open the whole chapter with the verse flashed. In the 30 days
//  to 2026-09-03 that was 1,490 of the reader's 1,630 opens — 58 players
//  opening it 26 times each — and every one of them was mid-grid looking for
//  an answer, not sitting down to read. Verse first is what that moment
//  asks for; `reader_closed.expanded` says how often the chapter is wanted.
//

import SwiftUI

struct VerseHintSheet: View {
    let target: ReaderRouter.Target

    @Environment(\.scripture) private var scripture
    @Environment(\.analytics) private var analytics
    @Environment(\.dismiss) private var dismiss

    @State private var window: [BibleVerse]?
    @State private var expanded = false
    @State private var detent: PresentationDetent = .medium
    @State private var openedAt = Date()

    var body: some View {
        NavigationStack {
            Group {
                if let window {
                    passage(window)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(Theme.background)
            .navigationTitle(reference)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .navigationDestination(isPresented: $expanded) {
                // No `source`: this sheet reports the visit, chapter included.
                ChapterReaderView(
                    startBook: target.book,
                    startChapter: target.chapter,
                    highlightVerse: target.verse,
                    // Opened from a clue: the player is mid-solve.
                    showsPuzzleLink: false
                )
            }
        }
        .presentationDetents([.medium, .large], selection: $detent)
        .task {
            await scripture.preload()
            window = Self.window(around: target, in: scripture)
        }
        // The chapter wants the room; the verse alone doesn't.
        .onChange(of: expanded) { if expanded { detent = .large } }
        // On the stack, not its root: the root disappears under the pushed
        // chapter too, and this must fire once, when the sheet goes.
        .onDisappear {
            analytics.log(.readerClosed(
                source: target.source,
                seconds: Int(Date().timeIntervalSince(openedAt).rounded()),
                chaptersPaged: 0,
                scrolledPastVerse: false,
                expanded: expanded
            ))
        }
    }

    private var reference: String { Self.reference(for: target) }

    static func reference(for target: ReaderRouter.Target) -> String {
        if let verse = target.verse {
            return "\(target.book) \(target.chapter):\(verse)"
        }
        return "\(target.book) \(target.chapter)"
    }

    private func passage(_ verses: [BibleVerse]) -> some View {
        ScrollView {
            VersePassageContent(target: target, verses: verses) {
                expanded = true
            }
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.vertical, Theme.Spacing.m)
        }
    }

    /// The deep-linked verse with one on each side; the chapter's first two
    /// verses for a chapter-only reference. Empty if the passage can't be
    /// found, which the caller has already guarded against.
    static func window(around target: ReaderRouter.Target, in scripture: ScriptureProvider) -> [BibleVerse] {
        guard let chapter = scripture.chapter(ScriptureRef(book: target.book, chapter: target.chapter))?.chapter
        else { return [] }
        let verses = chapter.verses
        guard let verse = target.verse,
              let index = verses.firstIndex(where: { $0.number == verse })
        else { return Array(verses.prefix(2)) }
        let lower = max(0, index - 1)
        let upper = min(verses.count - 1, index + 1)
        return Array(verses[lower...upper])
    }
}

/// The passage a verse hint shows — the verse at reading size between its
/// quieter neighbours, then the chapter and the memory door — shared by the
/// sheet and the panel that stands beside the board on a wide window.
struct VersePassageContent: View {
    let target: ReaderRouter.Target
    let verses: [BibleVerse]
    let onReadChapter: () -> Void

    @Environment(\.analytics) private var analytics
    @Environment(\.memoryVerses) private var memoryVerses
    @Environment(StoreService.self) private var store

    private var reference: String { VerseHintSheet.reference(for: target) }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                ForEach(verses) { verse in
                    verseRow(verse, isTarget: verse.number == (target.verse ?? verses.first?.number))
                }
            }

            VStack(spacing: Theme.Spacing.s) {
                Button(action: onReadChapter) {
                    Label("Read the chapter", systemImage: "book")
                }
                .buttonStyle(.pillTonal)

                memorizeButton
            }
        }
    }

    /// The verse the clue came from, into memory verses in one tap. This
    /// sheet is where players actually meet the verse (92% of reader opens
    /// in the 30 days to 2026-09-03) and it offered nothing to do with it —
    /// the chapter long-press that does was found by one player in a month.
    /// Adds without leaving the grid; practice waits on Today's card. Absent
    /// when the free shelf is full: a door onto a paywall isn't worth showing
    /// (38 opens, 0 buys in the 30 days to 2026-09-10).
    @ViewBuilder
    private var memorizeButton: some View {
        if let number = target.verse,
           let verse = verses.first(where: { $0.number == number }),
           MemoryCloze.isEligible(verseText: verse.text) {
            if memoryVerses.entry(for: MemoryCloze.referenceKey(reference)) != nil {
                Label("In Memory Verses", systemImage: "brain.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.s)
                    .accessibilityLabel("\(reference) is in your memory verses")
            } else if memoryVerses.canStartNewVerse(isPremium: store.isPremium) {
                Button {
                    memoryVerses.start(reference: reference, verseText: verse.text)
                    analytics.log(.memoryVerseAdded(reference: reference, source: "hint_sheet"))
                } label: {
                    Label("Learn it by heart", systemImage: "brain")
                }
                .buttonStyle(.pillTonal)
                .accessibilityHint("Adds the verse to your memory verses")
            }
        }
    }

    /// The verse the clue came from at reading size; its neighbours smaller
    /// and quieter, there for the sense of the line rather than as more to
    /// read.
    private func verseRow(_ verse: BibleVerse, isTarget: Bool) -> some View {
        // Secondary, as the reader sets them: blue means tappable, and a
        // verse number isn't.
        let number = Text("\(verse.number) ")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
        let body = Text(verse.text)
            .font(.scripture(isTarget ? .title3 : .subheadline))
        return (number + body)
            .lineSpacing(isTarget ? 5 : 3)
            .foregroundStyle(isTarget ? .primary : .secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel("\(isTarget ? "Verse" : "Nearby verse") \(verse.number). \(verse.text)")
    }
}

/// The verse hint standing in the keypad's column on a wide window (iPhone
/// Duo unfolded, or folded like a laptop), where the clue list stands: the
/// board stays in view and the keys stay under the thumb, so the player
/// reads the verse beside the word it answers. A sheet covered the board.
struct VerseHintPanel: View {
    let target: ReaderRouter.Target
    /// "15 Across · Prophetess who held court under a palm tree": the clue
    /// the list showed in this spot, which the verse now stands in for.
    let clueLine: String?
    let onClose: () -> Void
    let onReadChapter: () -> Void

    @Environment(\.scripture) private var scripture
    @State private var verses: [BibleVerse]?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(VerseHintSheet.reference(for: target))
                        .font(.headline)
                    if let clueLine {
                        Text(clueLine)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: Theme.Spacing.s)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close the verse")
            }
            .padding(.leading, Theme.Spacing.m)
            .padding(.top, Theme.Spacing.xs)

            ScrollView {
                Group {
                    if let verses {
                        VersePassageContent(target: target, verses: verses, onReadChapter: onReadChapter)
                    } else {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, Theme.Spacing.m)
                .padding(.bottom, Theme.Spacing.m)
            }
            .scrollIndicators(.hidden)
        }
        .background(Theme.surface, in: .rect(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, Theme.Spacing.s)
        .task(id: target.id) {
            await scripture.preload()
            verses = VerseHintSheet.window(around: target, in: scripture)
        }
    }
}
