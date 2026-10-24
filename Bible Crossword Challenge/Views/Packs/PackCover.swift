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
    /// The book's short mark: "Ps", "1 Sa", "Lk". Empty when no puzzle's
    /// reference parses, so the caller can fall back.
    let mark: String
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
            mark = book.abbreviation
            let chapters = pairs.map(\.1)
            if let low = chapters.min(), let high = chapters.max() {
                caption = low == high ? "\(book.displayName) \(low)" : "\(book.displayName) \(low)–\(high)"
            } else {
                caption = book.displayName
            }
        } else if let first = books.first, let last = books.last {
            mark = first.abbreviation
            caption = "\(first.displayName) – \(last.displayName)"
        } else {
            mark = ""
            caption = ""
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

/// A pack cover tile, as the Packs shelf draws it.
struct PackCover: View {
    let label: PackCoverLabel
    let fill: Color
    /// The SF Symbol to draw when no reference parses.
    var fallbackSymbol: String = "square.stack.3d.up"
    var isLocked: Bool = false
    var progress: Double? = nil

    @ScaledMetric(relativeTo: .largeTitle) private var markSize: CGFloat = 40

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Capsule()
                .fill(.white.opacity(0.6))
                .frame(width: 20, height: 2)

            Spacer(minLength: Theme.Spacing.s)

            if label.mark.isEmpty {
                Image(systemName: fallbackSymbol)
                    .font(.largeTitle)
            } else {
                Text(label.mark)
                    .font(.system(size: markSize, weight: .semibold, design: .serif))
                    .tracking(-0.8)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            if !label.caption.isEmpty {
                Text(label.caption)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            if let progress {
                ProgressView(value: progress)
                    .tint(.white)
                    .padding(.top, Theme.Spacing.s)
            }
        }
        .foregroundStyle(.white)
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(fill, in: .rect(cornerRadius: Theme.cornerRadius, style: .continuous))
        .overlay(alignment: .topTrailing) {
            if isLocked {
                Image(systemName: "lock.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(.black.opacity(0.22), in: .circle)
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
        PackCover(label: PackCoverLabel(puzzles: []), fill: Color.blue.mix(with: .black, by: 0.25))
        PackCover(label: PackCoverLabel(puzzles: []), fill: Color.teal.mix(with: .black, by: 0.25), isLocked: true)
    }
    .frame(height: 200)
    .padding()
}
