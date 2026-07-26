//
//  GridThumbnail.swift
//  Bible Crossword Challenge
//
//  A miniature of a puzzle's grid: one dot per playable cell, nothing where the
//  blocks are. Used on the daily card to make one day look different from the
//  next, and on the paywall to show the library rather than describe it.
//
//  Drawn in a `Canvas` because a 15×15 grid is 225 cells and these appear
//  inside scrolling feeds, sometimes several at once.
//

import SwiftUI

struct GridThumbnail: View {
    /// Rows of the puzzle grid; "." marks a block.
    let grid: [String]
    var tint: Color = Color.accentColor.opacity(0.35)

    var body: some View {
        Canvas { context, size in
            let rows = grid.count
            let columns = grid.map(\.count).max() ?? 0
            guard rows > 0, columns > 0 else { return }

            let cell = min(size.width / CGFloat(columns), size.height / CGFloat(rows))
            // Centre the drawing: most grids are square, but a mini in a square
            // box would otherwise sit against the top-left corner.
            let originX = (size.width - cell * CGFloat(columns)) / 2
            let originY = (size.height - cell * CGFloat(rows)) / 2
            let dot = max(1, cell - 1)

            for (row, line) in grid.enumerated() {
                for (column, character) in line.enumerated() where character != "." {
                    let rect = CGRect(
                        x: originX + CGFloat(column) * cell,
                        y: originY + CGFloat(row) * cell,
                        width: dot,
                        height: dot
                    )
                    context.fill(Path(roundedRect: rect, cornerRadius: dot / 4), with: .color(tint))
                }
            }
        }
        // Decorative everywhere it's used; the surrounding text carries the news.
        .accessibilityHidden(true)
    }
}
