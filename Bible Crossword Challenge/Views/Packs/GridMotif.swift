//
//  GridMotif.swift
//  Bible Crossword Challenge
//
//  A faint crossword in the corner of a pack's cover: rounded squares on the
//  cover's colour, a few left out as blocks, tilted a few degrees. It replaced
//  the rising steps on pack covers (2026-10-25): the steps were handsome but
//  said nothing about what was inside, and a pack page in a crossword app
//  should say crosswords before a word is read. Journeys keep their step path.
//

import SwiftUI

struct GridMotif: View {
    private static let side = 7
    /// Blocks, by row: the shape of a small crossword, not a random scatter.
    private static let blocks: Set<Int> = [0, 4, 8, 12, 16, 20, 24, 28, 32, 36, 40, 44, 48]

    var body: some View {
        Grid(horizontalSpacing: 4, verticalSpacing: 4) {
            ForEach(0..<Self.side, id: \.self) { row in
                GridRow {
                    ForEach(0..<Self.side, id: \.self) { column in
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(.white.opacity(Self.blocks.contains(row * Self.side + column) ? 0.06 : 0.16))
                            .frame(width: 22, height: 22)
                    }
                }
            }
        }
        .rotationEffect(.degrees(-8))
        .accessibilityHidden(true)
    }
}
