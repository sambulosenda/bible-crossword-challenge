//
//  PackCover.swift
//  Bible Crossword Challenge
//
//  A pack's typographic cover: the short name of the book it draws from, set
//  large in serif on the pack's colour under a short rule — a spine label —
//  with where in that book underneath ("Psalms 120–134"). The app's own mark
//  for its collections, in place of a stock SF Symbol on a tint.
//

import SwiftUI

/// What a pack's cover says, worked out from its puzzles' verse references —
/// nothing maps packs to books, and every puzzle already anchors to one.
struct PackCoverLabel: Equatable {
    /// The book's name, set large on a shelf cover: "Psalms", "1 Samuel".
    /// It was the short mark ("Ps", "1 Sa", "Mk") until 2026-11-04 —
    /// scholar's shorthand most players can't read. Empty when no puzzle's
    /// reference parses, so the caller can fall back.
    let mark: String
    /// The line under the name on a shelf cover, which already names the
    /// book: "Chapters 120–134", or "through John" for several books.
    let subtitle: String
    /// Where the pack sits: "Psalms 120–134" for one book, "Matthew – John"
    /// for several.
    let caption: String
    /// The Testament most of the pack's puzzles come from, for shelving.
    let testament: Testament?

    init(puzzles: [Puzzle]) {
        let pairs = puzzles.compactMap { puzzle -> (BibleCanon.Book, Int)? in
            guard let ref = ScriptureRef(puzzle.reference),
                  let book = BibleCanon.book(named: ref.book) else { return nil }
            return (book, ref.chapter)
        }
        var seen: Set<String> = []
        let books = pairs.map(\.0)
            .filter { seen.insert($0.name).inserted }
            .sorted { BibleCanon.position(of: $0.name) < BibleCanon.position(of: $1.name) }

        if books.count == 1, let book = books.first {
            mark = book.displayName
            let chapters = pairs.map(\.1)
            if let low = chapters.min(), let high = chapters.max() {
                caption = low == high ? "\(book.displayName) \(low)" : "\(book.displayName) \(low)–\(high)"
                subtitle = low == high ? "Chapter \(low)" : "Chapters \(low)–\(high)"
            } else {
                caption = book.displayName
                subtitle = ""
            }
        } else if let first = books.first, let last = books.last {
            mark = first.displayName
            caption = "\(first.displayName) – \(last.displayName)"
            subtitle = "through \(last.displayName)"
        } else {
            mark = ""
            caption = ""
            subtitle = ""
        }

        let oldCount = pairs.filter { $0.0.testament == .old }.count
        testament = pairs.isEmpty ? nil : (oldCount * 2 >= pairs.count ? .old : .new)
    }
}

extension PuzzlePack {
    /// The pack's colour deepened by a quarter, so white type on its cover
    /// clears 4.5:1 — the lightest accent (#C8912B) was 2.7:1 as authored.
    var coverFill: Color {
        accent.mix(with: .black, by: 0.25)
    }
}

extension QuestLine {
    /// The Journey's colour deepened the same way as a pack's cover.
    var coverFill: Color {
        accent.mix(with: .black, by: 0.25)
    }
}

/// A pack cover tile, as the Packs shelf draws it: ink type on a white card
/// since 2026-11-03. No progress bar since 2026-11-04: it lifted and shrank
/// the name on covers that had one, so a row's names didn't line up, and the
/// line under the cover already says how far along it is. A shelf of solid colour blocks put six or eight hues on
/// one screen; the serif mark is what makes it read as a book.
struct PackCover: View {
    let label: PackCoverLabel
    /// The collection's first grid, in the corner where a book's cover has
    /// its emblem: it says crossword at a glance (2026-11-03). Replaced a
    /// short rule that said nothing.
    var grid: [String]? = nil
    /// The SF Symbol to draw when no reference parses.
    var fallbackSymbol: String = "square.stack.3d.up"
    var isLocked: Bool = false

    @ScaledMetric(relativeTo: .largeTitle) private var markSize: CGFloat = 34

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let grid {
                // Full secondary: at 0.6 the grid was near-invisible grey on
                // white, and it's the one thing that says "crossword".
                GridThumbnail(grid: grid, tint: Color.secondary,
                              gap: grid.count > 9 ? 0 : 1, cropsToContent: true)
                    .frame(width: 28, height: 28)
            }

            Spacer(minLength: Theme.Spacing.s)

            if label.mark.isEmpty {
                Image(systemName: fallbackSymbol)
                    .font(.largeTitle)
            } else {
                Text(label.mark)
                    .font(.system(size: markSize, weight: .semibold, design: .serif))
                    .tracking(-0.8)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
            }
            if !label.subtitle.isEmpty {
                Text(label.subtitle)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .foregroundStyle(.primary)
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .elevatedCard()
        .overlay(alignment: .topTrailing) {
            if isLocked {
                Image(systemName: "lock.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(Color.primary.opacity(0.06), in: .circle)
                    .padding(12)
            }
        }
        // The tile's text says it all to sighted players; the shelf's link
        // carries the spoken label.
        .accessibilityHidden(true)
    }
}

#Preview {
    HStack(spacing: 14) {
        PackCover(label: PackCoverLabel(puzzles: []))
        PackCover(label: PackCoverLabel(puzzles: []), isLocked: true)
    }
    .frame(height: 200)
    .padding()
}
