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
    /// Where the square sits in its words — VoiceOver's label for it. See
    /// `GameViewModel.clueContext(at:)`.
    var clueContext = ""
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
            && lhs.clueContext == rhs.clueContext
    }

    /// Rounded tiles a few points apart on the game's grey ground, blocks
    /// included as soft grey tiles (2026-10-24 design). The printed board it
    /// replaced — squares a hairline apart on a beige rule, black blocks —
    /// read as a newspaper page. Blocks stay tiles, not gaps, so a 15×15
    /// still shows where each word ends.
    private var gap: CGFloat { max(2, (side * 0.08).rounded()) }
    private var tileRadius: CGFloat { min(9, max(3, side * 0.18)) }
    private var tile: RoundedRectangle { RoundedRectangle(cornerRadius: tileRadius, style: .continuous) }

        private var errorVisible: Bool {
        showError && cell.entry != nil && !cell.isCorrect
    }

    private var correctVisible: Bool {
        showCorrect && cell.entry != nil && cell.isCorrect
    }

    /// The clue number's size, floored so it stays readable on a 15×15.
    private var numberSize: CGFloat { max(side * 0.24, 9) }
    private var numberTop: CGFloat { max(side * 0.06, 2) }
    /// The strip a clue number takes across the top of its square. The
    /// letter is laid out in what's left, rather than nudged down by a fixed
    /// share of the square — at about 26pt the number's 9pt floor took half
    /// the square, and the nudged letter sat on top of it ("11" through "C",
    /// 2026-10-24).
    private var numberBand: CGFloat { numberTop + numberSize * 0.9 }

    private var baseLetterSize: CGFloat {
        max(side * (cell.isPencil ? 0.42 : 0.5), cell.isPencil ? 10 : 12)
    }

    /// Whether a numbered square's letter has to drop under the number. On a
    /// Mini's big tiles a centred letter clears the digits, and dropping it
    /// anyway left the numbered squares' letters lower than their neighbours'
    /// (2026-10-24). On a 15×15 the number's floor takes too much of the
    /// square for that.
    private var dropsLetterUnderNumber: Bool {
        guard cell.number != nil else { return false }
        // A capital's height is about 0.72 of its point size, a digit's
        // bottom about 0.8 of the number's below its top padding.
        let capTop = (side - gap) / 2 - baseLetterSize * 0.36
        let digitBottom = numberTop + numberSize * 0.8
        return capTop < digitBottom + 1
    }

    /// The letter's size: half the square, floored for small boards, and in
    /// a numbered square it drops in, no taller than the room under the
    /// number allows.
    private var letterSize: CGFloat {
        let base = baseLetterSize
        guard dropsLetterUnderNumber else { return base }
        // A capital's height is about 0.72 of its point size; the rest is
        // breathing room above and below it.
        let room = side - gap - numberBand - max(side * 0.04, 1)
        return min(base, room / 0.78)
    }

    var body: some View {
        if cell.isBlock {
            tile.fill(Theme.gridBlock)
                .frame(width: side - gap, height: side - gap)
                .frame(width: side, height: side)
                .accessibilityHidden(true)
        } else {
            Button(action: onTap) {
                ZStack {
                    // The tints are washes, so they sit on the empty fill
                    // rather than on the board's rule colour behind the cell.
                    CellPalette.empty
                    CellPalette.fill(
                        isSelected: isSelected,
                        isInWord: isInWord,
                        isCorrect: correctVisible
                    )

                    // Green pulse when this cell's word was just completed.
                    if flash {
                        Color.green.opacity(0.5)
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
                        // Ink at 70% on a tinted square: secondary grey on the
                        // selected square's blue measured 2.7:1 — the faintest
                        // number on the board was the one being looked at
                        // (2026-10-24). About 5.4:1 now; white squares keep
                        // the quieter grey.
                        Text("\(number)")
                            .font(.system(size: numberSize, weight: .semibold))
                            .foregroundStyle(isSelected || isInWord || correctVisible
                                             ? AnyShapeStyle(Color.primary.opacity(0.7))
                                             : AnyShapeStyle(.secondary))
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            // Clear of the selected cell's 2pt border.
                            .padding(.leading, max(side * 0.1, 3))
                            .padding(.top, numberTop)
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
                                // provisional — see `letterSize`.
                                size: letterSize,
                                // Plain SF, as print sets a crossword's
                                // letters; the rounded face read as a toy.
                                weight: cell.isPencil ? .regular : .medium
                            ))
                            // A wrong letter is itself the signal: red, where
                            // the eye already is, rather than a badge beside it.
                            .foregroundStyle(errorVisible ? CellPalette.error : CellPalette.textColor(isPencil: cell.isPencil))
                            .scaleEffect(flash && !reduceMotion ? 1.18 : 1.0)
                            // Under the number when the square is too small to
                            // centre it clear of the digits (see
                            // `dropsLetterUnderNumber`), centred otherwise.
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(.top, dropsLetterUnderNumber ? numberBand : 0)
                            .transition(reduceMotion ? .opacity : .scale(scale: 0.4).combined(with: .opacity))
                            // Identity follows the letter so overtyping a filled
                            // cell re-pops instead of swapping text in place.
                            .id("\(entry)\(cell.isPencil ? "p" : "")")
                    }

                    // And a short rule under it, so the mark is a shape for
                    // everyone, not only under Differentiate Without Color.
                    // It replaced a red corner tab: clipped by the tile's
                    // round corner it read as a dog-ear or a badge, and the
                    // black letter beside it never looked wrong. Floored like
                    // the number so it survives a 24pt cell.
                    if errorVisible {
                        Capsule()
                            .fill(CellPalette.error)
                            .frame(width: side * 0.34, height: max(side * 0.045, 2))
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                            .padding(.bottom, max(side * 0.1, 3))
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
                .frame(width: side - gap, height: side - gap)
                .clipShape(tile)
                .overlay {
                    // The selected cell is marked by its border; its fill is
                    // only a step deeper than the rest of the word.
                    if isSelected {
                        tile.strokeBorder(Theme.accent, lineWidth: 2)
                    }
                }
                .frame(width: side, height: side)
                .contentShape(.rect)
                // Pops each typed letter in with a restrained spring. This fires
                // on every keystroke (100+ a session), so the overshoot stays
                // subtle — a big bounce here reads as motion-noise, not feedback.
                .animation(reduceMotion ? nil : .spring(duration: 0.22, bounce: 0.2), value: cell.entry)
            }
            .buttonStyle(.plain)
            // The label says where the square is, by its clues; the value
            // says what's in it, so VoiceOver reads a change of letter as a
            // change of value rather than a new element.
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue(accessibilityValue)
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        }
    }

    private var accessibilityLabel: String {
        clueContext.isEmpty ? "Row \(cell.pos.row + 1), Column \(cell.pos.col + 1)" : clueContext
    }

    private var accessibilityValue: String {
        guard let entry = cell.entry else { return "Empty" }
        let letter = cell.isPencil ? "\(String(entry)), pencilled in" : String(entry)
        if errorVisible { return "\(letter), incorrect" }
        if correctVisible { return "\(letter), correct" }
        return letter
    }
}
