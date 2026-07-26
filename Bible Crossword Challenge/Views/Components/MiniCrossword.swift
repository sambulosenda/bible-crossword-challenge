//
//  MiniCrossword.swift
//  Bible Crossword Challenge
//
//  A hand-sized crossword fragment, drawn with the same tile language as the
//  real grid but with none of its machinery — no puzzle model, no view model,
//  no persistence. Onboarding uses it twice: as the welcome hero (every letter
//  given) and as the interactive first solve. One component, so the second page
//  reads as the first page come alive.
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
    /// The cell awaiting input, drawn in the accent fill.
    var focus: MiniPoint?
    /// Cells to crown with the gold rim once their word lands.
    var celebrated: Set<MiniPoint> = []
    /// Small number drawn in the corner of a cell, as on a real grid.
    var numbers: [MiniPoint: Int] = [:]
    /// Diagonal cascade on first appearance. Off for a grid that is already
    /// on screen when the page arrives and would double up on the page's own
    /// entrance animation.
    var animatesIn: Bool = true
    var onTap: ((MiniPoint) -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Tiles grow with the text-size setting so the letter never outruns its
    /// box — but only so far: five unclamped tiles run off the side of the
    /// screen at accessibility sizes. Past the cap the glyph shrinks instead.
    @ScaledMetric(relativeTo: .title3) private var scaledSide: CGFloat = 46
    private var side: CGFloat { min(scaledSide, 58) }
    @State private var appeared = false

    private var columns: Int { layout.map(\.count).max() ?? 0 }

    var body: some View {
        VStack(spacing: Self.gap) {
            ForEach(0..<layout.count, id: \.self) { row in
                HStack(spacing: Self.gap) {
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

    private static let gap: CGFloat = 6

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

        return RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(isFocused ? Theme.accent : Theme.surface)
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        isCelebrated ? Theme.badgeRim : Color(.separator).opacity(0.6),
                        lineWidth: isCelebrated ? 2 : 1
                    )
            }
            .overlay(alignment: .topLeading) {
                if let n = numbers[p] {
                    Text("\(n)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(isFocused ? Theme.onInk.opacity(0.9) : .secondary)
                        .padding(3)
                }
            }
            .overlay {
                if let letter {
                    // Givens and typed letters look identical, as they do on a
                    // real grid — the accent fill marks where you are, not
                    // which letters are yours.
                    Text(String(letter))
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .foregroundStyle(isFocused ? Theme.onInk : .primary)
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
