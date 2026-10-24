//
//  MiniCrossword.swift
//  Bible Crossword Challenge
//
//  A hand-sized crossword fragment, drawn with the same tile language as the
//  real grid but with none of its machinery — no puzzle model, no view model,
//  no persistence. Onboarding uses it twice: as the welcome hero (every letter
//  given) and as the interactive first solve. One component, so the second page
//  reads as the first page come alive. The Premium offer uses it a third time,
//  smaller, so the page that asks for money is drawn in the same tiles as the
//  pages that earned the ask.
//

import SwiftUI

/// A single square in a fragment.
enum MiniTile: Equatable {
    /// Empty space — no cell is drawn here.
    case block
    /// A letter the player is shown rather than asked for: a crossing that is
    /// already filled, which is how a crossword looks mid-solve.
    case given(Character)
    /// A cell the player fills. Carries its answer so the grid can self-check
    /// without the caller keeping a parallel key.
    case blank(Character)

    var isBlank: Bool { if case .blank = self { true } else { false } }
}

/// Row/column coordinate inside a fragment.
struct MiniPoint: Hashable {
    let row: Int
    let col: Int
}

struct MiniCrossword: View {
    /// Row-major layout. Rows may be ragged; the grid pads to the longest.
    let layout: [[MiniTile]]
    /// Letters the player has typed, keyed by cell.
    var entries: [MiniPoint: Character] = [:]
    /// The cell awaiting input, drawn as the game draws its selected cell: a
    /// deeper step of the word tint with a 2pt accent border.
    var focus: MiniPoint?
    /// The word being answered, tinted as the game tints its active word.
    var activeWord: Set<MiniPoint> = []
    /// Cells to crown with the gold rim once their word lands.
    var celebrated: Set<MiniPoint> = []
    /// Small number drawn in the corner of a cell, as on a real grid.
    var numbers: [MiniPoint: Int] = [:]
    /// Diagonal cascade on first appearance. Off for a grid that is already
    /// on screen when the page arrives and would double up on the page's own
    /// entrance animation.
    var animatesIn: Bool = true
    /// The tile's side at the default text size. 46 is onboarding's; the
    /// Premium offer draws a smaller fragment above its headline.
    var tileSide: CGFloat = 46
    var onTap: ((MiniPoint) -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Tiles grow with the text-size setting so the letter never outruns its
    /// box — but only so far: five unclamped tiles run off the side of the
    /// screen at accessibility sizes. Past the cap the glyph shrinks instead.
    /// Scaled as a factor so every `tileSide` grows on the same curve; the
    /// cap is the 46 → 58 ceiling onboarding was tuned to, as a ratio.
    @ScaledMetric(relativeTo: .title3) private var typeScale: CGFloat = 1
    private var side: CGFloat { tileSide * min(typeScale, 58.0 / 46.0) }
    /// Gap and corner follow `tileSide`, so a small fragment keeps the same
    /// proportions as the full-size one instead of looking loosely spaced.
    /// Off the base size rather than the scaled one, which leaves onboarding's
    /// fixed 6pt gap and 10pt corner exactly as they were.
    private var gap: CGFloat { (tileSide * 6 / 46).rounded() }
    private var corner: CGFloat { tileSide * 10 / 46 }
    @State private var appeared = false

    private var columns: Int { layout.map(\.count).max() ?? 0 }

    var body: some View {
        VStack(spacing: gap) {
            ForEach(0..<layout.count, id: \.self) { row in
                HStack(spacing: gap) {
                    ForEach(0..<columns, id: \.self) { col in
                        tile(at: MiniPoint(row: row, col: col))
                    }
                }
            }
        }
        .onAppear { appeared = true }
        // The fragment is decoration around the clue and the CTA, which say
        // everything a screen reader needs.
        .accessibilityHidden(true)
    }

    private func tileAt(_ p: MiniPoint) -> MiniTile {
        guard p.row < layout.count, p.col < layout[p.row].count else { return .block }
        return layout[p.row][p.col]
    }

    @ViewBuilder
    private func tile(at p: MiniPoint) -> some View {
        let tile = tileAt(p)
        switch tile {
        case .block:
            Color.clear.frame(width: side, height: side)
        case .given(let letter):
            cell(p, letter: letter, isGiven: true)
        case .blank:
            cell(p, letter: entries[p], isGiven: false)
        }
    }

    private func cell(_ p: MiniPoint, letter: Character?, isGiven: Bool) -> some View {
        let isFocused = focus == p
        let isCelebrated = celebrated.contains(p)
        // The cascade runs on the diagonal so the fragment assembles from its
        // top-left corner rather than row by row, which reads as mechanical.
        let delay = Double(p.row + p.col) * 0.05
        // Hoisted out of the view chain: inline, the `max` calls pushed the
        // expression past what the type checker would resolve in time.
        let numberSize = max(side * 0.28, 9)
        let letterSize = max(side * 0.5, 12)

        // The game's own palette (`CellPalette`, `CellView`): the first cell a
        // player ever touches looks like every cell after it. It used to be a
        // solid accent block with a white letter — the treatment the game
        // retired in 3f0fff2 as the loudest thing on the screen.
        let isInWord = activeWord.contains(p)
        let fill = isFocused || isInWord
            ? CellPalette.fill(isSelected: isFocused, isInWord: isInWord, isCorrect: false)
            : Theme.surface
        let rim: Color = isFocused ? Theme.accent
            : isCelebrated ? Theme.badgeRim
            : Color(.separator).opacity(0.6)

        return RoundedRectangle(cornerRadius: corner, style: .continuous)
            .fill(fill)
            .overlay {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(rim, lineWidth: isFocused || isCelebrated ? 2 : 1)
            }
            .overlay(alignment: .topLeading) {
                if let n = numbers[p] {
                    Text("\(n)")
                        .font(.system(size: numberSize, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(3)
                }
            }
            .overlay {
                if let letter {
                    // Givens and typed letters look identical, as they do on a
                    // real grid — the border marks where you are, not which
                    // letters are yours.
                    // Sized off the cell, like the real grid's, rather than a
                    // text style shrunk to half to survive a large setting —
                    // a letter has one cell to live in either way, and
                    // halving a title3 put it under the readable floor.
                    Text(String(letter))
                        .font(.system(size: letterSize, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            .frame(width: side, height: side)
            .scaleEffect(isCelebrated && !reduceMotion ? 1.06 : 1)
            .animation(.spring(duration: 0.35, bounce: 0.4), value: isCelebrated)
            .animation(.spring(duration: 0.25, bounce: 0), value: isFocused)
            .animation(.spring(duration: 0.3, bounce: 0.3), value: letter)
            .opacity(shown ? 1 : 0)
            .scaleEffect(shown || reduceMotion ? 1 : 0.6)
            .animation(
                reduceMotion
                    ? .easeOut(duration: 0.2)
                    : .spring(duration: 0.5, bounce: 0.35).delay(animatesIn ? delay : 0),
                value: shown
            )
            .contentShape(.rect)
            .onTapGesture { if !isGiven { onTap?(p) } }
    }

    private var shown: Bool { animatesIn ? appeared : true }
}

#Preview("Fragments") {
    VStack(spacing: 40) {
        MiniCrossword(layout: MiniCrossword.faithHopeLove)
        MiniCrossword(
            layout: MiniCrossword.firstSolve,
            entries: [MiniPoint(row: 2, col: 1): "R"],
            focus: MiniPoint(row: 2, col: 2),
            numbers: [MiniPoint(row: 2, col: 0): 1]
        )
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Theme.background)
}

// MARK: - The two fragments onboarding uses

extension MiniCrossword {
    /// FAITH across, HOPE and LOVE crossing it — 1 Corinthians 13:13, and a
    /// hero that could only belong to this app.
    static let faithHopeLove: [[MiniTile]] = [
        [.given("F"), .given("A"), .given("I"), .given("T"), .given("H")],
        [.block,      .block,      .block,      .block,      .given("O")],
        [.block,      .block,      .block,      .block,      .given("P")],
        [.block,      .given("L"), .given("O"), .given("V"), .given("E")],
    ]

    /// GRACE already filled across the top, ARK to be typed down through its
    /// A. Two letters is the whole ask: enough to feel the mechanic, too short
    /// to stall on.
    ///
    /// Laid out wide rather than tall on purpose. The same fragment with GRACE
    /// running down was five rows — about 254pt — which pushed the keypad off
    /// the bottom of a 667pt screen, so an iPhone SE player had to scroll to
    /// type. Three rows is ~150pt and clears it.
    static let firstSolve: [[MiniTile]] = [
        [.given("G"), .given("R"), .given("A"), .given("C"), .given("E")],
        [.block,      .block,      .blank("R"), .block,      .block],
        [.block,      .block,      .blank("K"), .block,      .block],
    ]

    /// The blanks of `firstSolve`, in reading order.
    static let firstSolveBlanks = [MiniPoint(row: 1, col: 2), MiniPoint(row: 2, col: 2)]

    /// Every cell of 1 Down, for the gold rim when it lands.
    static let firstSolveWord: Set<MiniPoint> = [
        MiniPoint(row: 0, col: 2), MiniPoint(row: 1, col: 2), MiniPoint(row: 2, col: 2),
    ]
}
