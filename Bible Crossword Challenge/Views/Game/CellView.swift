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

    #if DEBUG
    /// Screenshot helper: `-uiHideNumbers` draws tiles without clue numbers —
    /// same family as -uiHideSelection.
    private static let hidesNumbers = ProcessInfo.processInfo.arguments.contains("-uiHideNumbers")
    #else
    private static let hidesNumbers = false
    #endif

    static func == (lhs: CellView, rhs: CellView) -> Bool {
        lhs.cell == rhs.cell
            && lhs.side == rhs.side
            && lhs.isSelected == rhs.isSelected
            && lhs.isInWord == rhs.isInWord
            && lhs.showError == rhs.showError
            && lhs.showCorrect == rhs.showCorrect
            && lhs.flash == rhs.flash
    }

    /// Cells are tiles, the shape the app's grids take everywhere else (the
    /// onboarding fragment, the Today thumbnail), not rows of a table: a gap
    /// of paper between each and a continuous corner. The gap is a smaller
    /// share of the side than the onboarding tile's (8% vs 13%) because a
    /// 15×15 has 24pt cells and every point of gap is a point off the letter.
    private var tileGap: CGFloat { max(side * 0.08, 1.5) }
    private var tileShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: side * 0.18, style: .continuous)
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
                    tileShape
                        .fill(CellPalette.fill(
                            isSelected: isSelected,
                            isInWord: isInWord,
                            isCorrect: correctVisible
                        ))

                    // Green pulse when this cell's word was just completed.
                    if flash {
                        tileShape.fill(Color.green.opacity(0.5))
                    }

                    if let number = cell.number, !Self.hidesNumbers {
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
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            // Clear of the tile's rounded corner and the
                            // selected cell's 2pt border.
                            .padding(.leading, max(side * 0.1, 3))
                            .padding(.top, max(side * 0.06, 2))
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
                            .foregroundStyle(CellPalette.textColor(isPencil: cell.isPencil))
                            .scaleEffect(flash && !reduceMotion ? 1.18 : 1.0)
                            .transition(reduceMotion ? .opacity : .scale(scale: 0.4).combined(with: .opacity))
                            // Identity follows the letter so overtyping a filled
                            // cell re-pops instead of swapping text in place.
                            .id("\(entry)\(cell.isPencil ? "p" : "")")
                    }

                    // A wrong letter is marked by shape for everyone, not
                    // only under Differentiate Without Color: the corner
                    // triangle crossword players already read as "wrong",
                    // opposite the number so the two never touch. Floored
                    // like the number so it survives a 24pt cell.
                    if errorVisible {
                        ErrorCornerMark()
                            .fill(Color.red)
                            .frame(width: max(side * 0.3, 8), height: max(side * 0.3, 8))
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    }

                    // Correct stays a green wash; the check is the non-colour
                    // cue when colour can't be relied on.
                    if differentiateWithoutColor, correctVisible {
                        Image(systemName: "checkmark")
                            .font(.system(size: max(side * 0.24, 9), weight: .bold))
                            .foregroundStyle(Color.green)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                            .padding(side * 0.06)
                    }
                }
                .frame(width: side - tileGap, height: side - tileGap)
                .clipShape(tileShape)
                .overlay(
                    // The selected cell is marked by its border; its fill is
                    // only a step deeper than the rest of the word. The quiet
                    // rim on the rest keeps a white tile visible on paper.
                    tileShape.strokeBorder(
                        isSelected ? Theme.accent : CellPalette.border,
                        lineWidth: isSelected ? 2 : 1
                    )
                )
                .frame(width: side, height: side)
                .contentShape(.rect)
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

/// The wrong-letter mark: a right triangle filling the cell's top-trailing
/// corner.
struct ErrorCornerMark: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            p.closeSubpath()
        }
    }
}
