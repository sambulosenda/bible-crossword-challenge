//
//  BookmarksView.swift
//  Bible Crossword Challenge
//
//  The verses kept from the reader, newest first. Each opens its chapter
//  with the verse brought into view; swipe removes.
//

import SwiftUI

struct BookmarksView: View {
    @Environment(\.bookmarks) private var bookmarks
    @Environment(\.analytics) private var analytics

    @State private var opened: BookmarkStore.Entry?

    var body: some View {
        Group {
            if bookmarks.entries.isEmpty {
                ContentUnavailableView {
                    Label("No bookmarks", systemImage: "bookmark")
                } description: {
                    Text("Touch and hold a verse in the reader to keep it here.")
                }
            } else {
                List {
                    ForEach(bookmarks.entries) { entry in
                        Button {
                            analytics.log(.scriptureOpened(reference: entry.reference, source: "read_bookmark"))
                            opened = entry
                        } label: {
                            BookmarkRow(entry: entry)
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            bookmarks.remove(id: bookmarks.entries[index].id)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
        }
        .background(Theme.background)
        .navigationTitle("Bookmarks")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { analytics.log(.bookmarksOpened(count: bookmarks.entries.count)) }
        .navigationDestination(item: $opened) { entry in
            ChapterReaderView(
                startBook: entry.book,
                startChapter: entry.chapter,
                highlightVerse: entry.verse,
                source: "read_bookmark"
            )
        }
    }
}

private struct BookmarkRow: View {
    let entry: BookmarkStore.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.reference)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.accent)
            Text(entry.verseText)
                .font(.scripture(.body))
                .foregroundStyle(.primary)
                .lineLimit(3)
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the chapter at this verse")
    }
}
