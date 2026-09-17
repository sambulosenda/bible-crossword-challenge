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
    /// Whether a correct entry paints green. Split from `showError` because
    /// auto-check marks only mistakes — green-on-correct everywhere would turn
    /// the mode into an answer oracle; the manual check shows both.
    let showCorrect: Bool
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
            && lhs.showCorrect == rhs.showCorrect
            && lhs.flash == rhs.flash
    }

    private var errorVisible: Bool {
        showError && cell.entry != nil && !cell.isCorrect
    }

    private var correctVisible: Bool {
        showCorrect && cell.entry != nil && cell.isCorrect
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
                        // The number is the cell's only tie to its clue, and
                        // purely proportional it was the first thing to become
                        // unreadable: 6pt on the 24pt cell a 15x15 gets in
                        // portrait. It keeps a floor of its own and a heavier
                        // weight. 11pt — the platform minimum — does not fit
                        // inside a 24pt cell without crowding the letter; the
                        // real remedy for a board this tight is the zoom
                        // viewport, which `CrosswordGridView` falls back to.
                        Text("\(number)")
                            .font(.system(size: max(side * 0.28, 9), weight: .semibold))
                            .foregroundStyle(isSelected ? Color.white.opacity(0.9) : .secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .padding(.leading, side * 0.07)
                            .padding(.top, side * 0.04)
                    }

                    if let entry = cell.entry {
                        // A pencilled letter reads as handwriting-in-the-margin:
                        // smaller, lighter, and grey, so the eye keeps parsing
                        // pen letters as the real grid.
                        Text(String(entry))
                            .font(.system(
                                // Floored so a pencilled letter stays readable
                                // on a small cell, while keeping enough of a
                                // gap from the pen letter above it to read as
                                // provisional.
                                size: max(side * (cell.isPencil ? 0.42 : 0.5), cell.isPencil ? 10 : 12),
                                weight: cell.isPencil ? .regular : .semibold,
                                design: .rounded
                            ))
                            .foregroundStyle(CellPalette.textColor(isSelected: isSelected, isPencil: cell.isPencil))
                            .scaleEffect(flash && !reduceMotion ? 1.18 : 1.0)
                            .transition(reduceMotion ? .opacity : .scale(scale: 0.4).combined(with: .opacity))
                            // Identity follows the letter so overtyping a filled
                            // cell re-pops instead of swapping text in place.
                            .id("\(entry)\(cell.isPencil ? "p" : "")")
                    }

                    // Non-colour cue for correctness when colour can't be relied on.
                    if differentiateWithoutColor, errorVisible || correctVisible {
                        Image(systemName: errorVisible ? "xmark" : "checkmark")
                            // This mark is the whole non-colour cue, so it gets
                            // the same floor treatment as the number.
                            .font(.system(size: max(side * 0.24, 9), weight: .bold))
                            .foregroundStyle(errorVisible ? Color.red : Color.green)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                            .padding(side * 0.06)
                    }
                }
                .frame(width: side, height: side)
                .overlay(
                    Rectangle().strokeBorder(CellPalette.border, lineWidth: 0.5)
                )
                // Pops each typed letter in with a restrained spring. This fires
                // on every keystroke (100+ a session), so the overshoot stays
                // subtle — a big bounce here reads as motion-noise, not feedback.
                .animation(reduceMotion ? nil : .spring(duration: 0.22, bounce: 0.2), value: cell.entry)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        }
    }

    private var accessibilityLabel: String {
        let base = "Row \(cell.pos.row + 1), Column \(cell.pos.col + 1)"
        guard let entry = cell.entry else { return "\(base), empty" }
        let letter = cell.isPencil ? "\(String(entry)), pencilled in" : String(entry)
        if errorVisible { return "\(base), \(letter), incorrect" }
        if correctVisible { return "\(base), \(letter), correct" }
        return "\(base), \(letter)"
    }
}
