//
//  CellView.swift
//  Bible Crossword Challenge
//
//  A single crossword cell. Equatable so SwiftUI skips redrawing cells whose
//  visual inputs are unchanged — important for keystroke latency on large grids.
//

import SwiftUI

struct CellView: View, Equatable {
    let cell: CellState
    let side: CGFloat
    let isSelected: Bool
    let isInWord: Bool
    let showError: Bool
    /// Transient green pulse shown when the cell's word was just completed.
    let flash: Bool
    let onTap: () -> Void

    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static func == (lhs: CellView, rhs: CellView) -> Bool {
        lhs.cell == rhs.cell
            && lhs.side == rhs.side
            && lhs.isSelected == rhs.isSelected
            && lhs.isInWord == rhs.isInWord
            && lhs.showError == rhs.showError
            && lhs.flash == rhs.flash
    }

    private var errorVisible: Bool {
        showError && cell.entry != nil && !cell.isCorrect
    }

    private var correctVisible: Bool {
        showError && cell.entry != nil && cell.isCorrect
    }

    var body: some View {
        if cell.isBlock {
            // Blocks are invisible: on these sparse criss-cross grids the word
            // slots float on the background instead of sitting in a black slab.
            Color.clear
                .frame(width: side, height: side)
                .accessibilityHidden(true)
        } else {
            Button(action: onTap) {
                ZStack {
                    Rectangle()
                        .fill(CellPalette.fill(
                            isSelected: isSelected,
                            isInWord: isInWord,
                            showError: errorVisible,
                            isCorrect: correctVisible
                        ))

                    // Green pulse when this cell's word was just completed.
                    if flash {
                        Rectangle().fill(Color.green.opacity(0.5))
                    }

                    if let number = cell.number {
                        Text("\(number)")
                            .font(.system(size: side * 0.26, weight: .medium))
                            .foregroundStyle(isSelected ? Color.white.opacity(0.9) : .secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .padding(.leading, side * 0.07)
                            .padding(.top, side * 0.04)
                    }

                    if let entry = cell.entry {
                        Text(String(entry))
                            .font(.system(size: side * 0.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(CellPalette.textColor(isSelected: isSelected))
                            .scaleEffect(flash && !reduceMotion ? 1.18 : 1.0)
                            .transition(reduceMotion ? .opacity : .scale(scale: 0.4).combined(with: .opacity))
                            // Identity follows the letter so overtyping a filled
                            // cell re-pops instead of swapping text in place.
                            .id(entry)
                    }

                    // Non-colour cue for correctness when colour can't be relied on.
                    if differentiateWithoutColor, errorVisible || correctVisible {
                        Image(systemName: errorVisible ? "xmark" : "checkmark")
                            .font(.system(size: side * 0.22, weight: .bold))
                            .foregroundStyle(errorVisible ? Color.red : Color.green)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                            .padding(side * 0.06)
                    }
                }
                .frame(width: side, height: side)
                .overlay(
                    Rectangle().strokeBorder(CellPalette.border, lineWidth: 0.5)
                )
                // Pops each typed letter in with a small spring bounce.
                .animation(reduceMotion ? nil : .spring(duration: 0.22, bounce: 0.55), value: cell.entry)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        }
    }

    private var accessibilityLabel: String {
        let base = "Row \(cell.pos.row + 1), Column \(cell.pos.col + 1)"
        guard let entry = cell.entry else { return "\(base), empty" }
        if errorVisible { return "\(base), \(String(entry)), incorrect" }
        if correctVisible { return "\(base), \(String(entry)), correct" }
        return "\(base), \(String(entry))"
    }
}
