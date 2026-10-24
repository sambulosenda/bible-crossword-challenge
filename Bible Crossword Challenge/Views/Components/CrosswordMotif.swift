//
//  CrosswordMotif.swift
//  Bible Crossword Challenge
//
//  A faint 5×5 crossword pattern for the corner of a feature card: the app's
//  own mark, so a solid-colour card reads as this app's rather than a generic
//  banner. White at low opacity, so it sits on any of the hero fills.
//

import SwiftUI

struct CrosswordMotif: View {
    /// Side of one square. Scales with Dynamic Type so the mark keeps its
    /// proportion to the title beside it.
    @ScaledMetric(relativeTo: .title2) private var cell: CGFloat = 12

    /// Black squares, by index in reading order — an asymmetric scatter, so
    /// it reads as a puzzle rather than a checkerboard.
    private static let blocks: Set<Int> = [0, 5, 9, 13, 17, 22, 24]

    var body: some View {
        Grid(horizontalSpacing: cell / 4, verticalSpacing: cell / 4) {
            ForEach(0..<5, id: \.self) { row in
                GridRow {
                    ForEach(0..<5, id: \.self) { column in
                        RoundedRectangle(cornerRadius: cell / 4, style: .continuous)
                            .fill(.white.opacity(Self.blocks.contains(row * 5 + column) ? 0.08 : 0.22))
                            .frame(width: cell, height: cell)
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    CrosswordMotif()
        .padding()
        .background(Theme.heroDaily)
}
