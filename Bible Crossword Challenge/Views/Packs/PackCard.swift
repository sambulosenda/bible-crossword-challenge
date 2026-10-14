//
//  PackCard.swift
//  Bible Crossword Challenge
//
//  The pieces packs and Journeys share: the cover chip, the lead action and
//  the rules their rows follow as type grows. The rows themselves are
//  `CollectionRow` in PacksView, a native list row since 2026-10-13.
//

import SwiftUI

// MARK: - Shared row layout

/// The rules collection rows share as type grows (see `CollectionRow` in
/// PacksView and the Journey step list).
enum CollectionCardLayout {
    /// How many lines the blurb may take.
    ///
    /// It was a flat two. That clipped The Shepherd's Psalm at the default
    /// size, and at xxxLarge — the largest *non*-accessibility size, an
    /// ordinary setting rather than an assistive one — it clipped every blurb
    /// on the screen at once. The blurb is the only description of what is
    /// inside a collection, on the screen where someone decides whether to
    /// pay for it, so above the default size it gets whatever it needs; three
    /// is kept as a guard at the default so one long line of authored copy
    /// can't stretch a row unnoticed.
    static func blurbLineLimit(_ size: DynamicTypeSize) -> Int? {
        // Two at the default size, not three: five locked rows of three-line
        // copy filled a screen, and the pack page carries the full blurb.
        size > .large ? nil : 2
    }
}

// MARK: - Cover chip

/// A collection's cover tile.
///
/// Colour on this screen means one thing: you can open this. Every pack and
/// Journey carries its own `accentHex`, and rendering all of them at once put
/// six unrelated hues down one column — green, tan, blue, blue, rust, pink —
/// where the tint signalled nothing except that somebody had picked a colour.
/// Meanwhile eight of the nine rows were locked, and nothing but a caption-
/// sized crown said so.
///
/// So the accent is now spent on availability. A collection you can play
/// wears its own colour; a locked one wears the same neutral tonal fill as
/// every other locked thing, and the crown confirms it. The character that
/// used to live in the tints lives in the cover symbols, which are per
/// collection and unaffected.
struct CollectionCover: View {
    let symbol: String
    let accent: Color
    let isLocked: Bool
    let side: CGFloat
    /// The symbol's own size. Defaults to the row's; the lead card and the
    /// detail headers set their own, larger one.
    var font: Font = .title2
    /// Kept concentric with whatever encloses it — the row's card wants 14,
    /// the larger detail-header chip wants 16.
    var cornerRadius: CGFloat = 14

    var body: some View {
        Image(systemName: symbol)
            .font(font)
            .foregroundStyle(isLocked ? AnyShapeStyle(.secondary) : AnyShapeStyle(accent))
            .frame(width: side, height: side)
            .background(fill, in: .rect(cornerRadius: cornerRadius, style: .continuous))
    }

    /// Matches `PillButtonStyle.tonal`'s fill, so "quiet surface" is one
    /// value across the app rather than a per-view guess.
    private var fill: Color {
        isLocked ? Color.primary.opacity(0.06) : accent.opacity(0.14)
    }
}

// MARK: - Lead card

/// The call to action on the lead card.
enum CollectionLeadAction: String {
    case start = "Start"
    case resume = "Resume"

    /// `nil` when there is nothing to do: a finished collection has no next
    /// step worth promoting, and a locked one's only action is the paywall.
    static func forRow(isLocked: Bool, solved: Int, isComplete: Bool) -> CollectionLeadAction? {
        guard !isLocked, !isComplete else { return nil }
        return solved > 0 ? .resume : .start
    }
}
