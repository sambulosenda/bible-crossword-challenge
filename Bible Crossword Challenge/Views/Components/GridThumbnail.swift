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
    /// Gap between dots, in points at the drawn cell size. The default reads as
    /// a grid of separate squares; dropping it fuses the dots into a denser mark
    /// for small renderings, where a 1pt gap eats a fifth of every cell.
    var gap: CGFloat = 1
    /// Trim to the bounding box of the playable cells before drawing. Off by
    /// default, so feed thumbnails keep the authored canvas and a row of them
    /// stays aligned to a common frame. On when the grid is a standalone mark:
    /// a puzzle padded with blocks down one side otherwise centres its *canvas*
    /// and hangs the puzzle off to the side, which inside a disc reads as a bug.
    var cropsToContent: Bool = false

    var body: some View {
        Canvas { context, size in
            let grid = cropsToContent ? Self.cropped(self.grid) : self.grid
            let rows = grid.count
            let columns = grid.map(\.count).max() ?? 0
            guard rows > 0, columns > 0 else { return }

            let cell = min(size.width / CGFloat(columns), size.height / CGFloat(rows))
            // Centre the drawing: most grids are square, but a mini in a square
            // box would otherwise sit against the top-left corner.
            let originX = (size.width - cell * CGFloat(columns)) / 2
            let originY = (size.height - cell * CGFloat(rows)) / 2
            let dot = max(1, cell - gap)

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

    /// The grid trimmed to the bounding box of its playable cells.
    static func cropped(_ rows: [String]) -> [String] {
        let cells = rows.map(Array.init)
        let filled = cells.enumerated().flatMap { row, line in
            line.enumerated().compactMap { column, character in
                character == "." ? nil : (row, column)
            }
        }
        guard let firstRow = filled.map(\.0).min(), let lastRow = filled.map(\.0).max(),
              let firstColumn = filled.map(\.1).min(), let lastColumn = filled.map(\.1).max()
        else { return rows }

        return cells[firstRow...lastRow].map { line in
            String((firstColumn...lastColumn).map { line.indices.contains($0) ? line[$0] : "." })
        }
    }
}
