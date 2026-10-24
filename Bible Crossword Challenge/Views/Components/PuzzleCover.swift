//
//  PuzzleCover.swift
//  Bible Crossword Challenge
//
//  A puzzle's small typographic cover for the Library: the short mark of the
//  book its verse comes from ("Lk", "Ex", "Ps") in serif, on its kind's
//  colour — blue for the Daily, teal for the Mini, rust for the Sunday
//  Special. The pack covers' language at row size (2026-10-24).
//
//  It replaced a miniature of the puzzle's grid in pale blue dots, which was
//  real data but too faint to read at 34pt, and looked alike row after row.
//

import SwiftUI

struct PuzzleCover: View {
    let puzzle: Puzzle
    /// Grey, for a puzzle Premium opens: the same shape as a playable row's,
    /// without the colour that says "you can play this".
    var isLocked = false
    var side: CGFloat = 44

    /// The book's short mark, or nil when the reference doesn't parse.
    private var mark: String? {
        guard let ref = ScriptureRef(puzzle.reference),
              let book = BibleCanon.book(named: ref.book) else { return nil }
        return book.abbreviation
    }

    private var fill: Color {
        if isLocked { return Color.primary.opacity(0.08) }
        if puzzle.isMini { return Theme.heroMini }
        if puzzle.isSunday { return Theme.heroSunday }
        return Theme.heroDaily
    }

    var body: some View {
        Group {
            if let mark {
                Text(mark)
                    .font(.system(size: side * 0.4, weight: .semibold, design: .serif))
                    .tracking(-0.3)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, 4)
            } else {
                Image(systemName: "square.grid.3x3")
                    .font(.system(size: side * 0.4))
            }
        }
        .foregroundStyle(isLocked ? AnyShapeStyle(.secondary) : AnyShapeStyle(.white))
        .frame(width: side, height: side)
        .background(fill, in: .rect(cornerRadius: side * 0.23, style: .continuous))
        // The row's title and passage say it all.
        .accessibilityHidden(true)
    }
}
