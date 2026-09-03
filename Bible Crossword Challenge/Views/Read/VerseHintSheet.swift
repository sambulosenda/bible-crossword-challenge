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
                    highlightVerse: target.verse
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

    private var reference: String {
        if let verse = target.verse {
            return "\(target.book) \(target.chapter):\(verse)"
        }
        return "\(target.book) \(target.chapter)"
    }

    private func passage(_ verses: [BibleVerse]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    ForEach(verses) { verse in
                        verseRow(verse, isTarget: verse.number == (target.verse ?? verses.first?.number))
                    }
                }

                Button {
                    expanded = true
                } label: {
                    Label("Read the chapter", systemImage: "book")
                }
                .buttonStyle(.pillTonal)
            }
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.vertical, Theme.Spacing.m)
        }
    }

    /// The verse the clue came from at reading size; its neighbours smaller
    /// and quieter, there for the sense of the line rather than as more to
    /// read.
    private func verseRow(_ verse: BibleVerse, isTarget: Bool) -> some View {
        let number = Text("\(verse.number) ")
            .font(.caption.weight(.bold))
            .foregroundStyle(Theme.accent)
        let body = Text(verse.text)
            .font(.scripture(isTarget ? .title3 : .subheadline))
        return (number + body)
            .lineSpacing(isTarget ? 5 : 3)
            .foregroundStyle(isTarget ? .primary : .secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel("\(isTarget ? "Verse" : "Nearby verse") \(verse.number). \(verse.text)")
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
