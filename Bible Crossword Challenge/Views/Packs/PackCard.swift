//
//  PackCard.swift
//  Bible Crossword Challenge
//
//  A single collection tile: cover symbol, title, blurb, and a progress bar.
//  Shows a crown when the pack is premium and the player hasn't upgraded.
//
//  Also home to the pieces the Journeys share with the packs — the cover
//  chip, the "next up" lead card, and the rules both rows follow as type
//  grows — so the two halves of the Packs tab can't drift apart.
//

import SwiftUI

// MARK: - Shared row layout

/// The rules a collection row follows as type grows. Shared by `PackCard` and
/// `QuestCard` so the Journeys and the Collections sitting on the same screen
/// can't break at different sizes.
enum CollectionCardLayout {
    /// At accessibility sizes the row stacks. A scaled cover and a chevron
    /// leave the text roughly a third of the card's width, and at AX3 that is
    /// narrow enough to hyphenate "Life of David" mid-word, one letter to a
    /// line. Stacking gives the text the full width back.
    static func isStacked(_ size: DynamicTypeSize) -> Bool { size.isAccessibilitySize }

    /// The cover keeps scaling with the text, but only so far: past this it is
    /// taking width the title needs more than the icon does.
    static func coverSize(_ scaled: CGFloat) -> CGFloat { min(scaled, 72) }

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
        size > .large ? nil : 3
    }

    /// A premium crown, joined to the title with a non-breaking space so it
    /// wraps as part of the last word rather than stranding itself on a line
    /// of its own.
    ///
    /// It is concatenated into the text run rather than sat beside it in a
    /// stack: as a sibling view it was laid out against the title's whole
    /// block, so the moment the title wrapped — which it does at large type,
    /// and at accessibility sizes always — the crown floated in the white
    /// space beside the shorter line instead of following the last word.
    static func title(_ text: String, locked: Bool) -> Text {
        let name = Text(text).font(.headline).foregroundStyle(Color.primary)
        guard locked else { return name }
        return name
            + Text(verbatim: "\u{00A0}")
            + Text(Image(systemName: "crown.fill")).font(.caption2).foregroundStyle(Color.yellow)
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

/// The one card at the top of the Packs tab that answers "what do I do here".
///
/// Every row on this screen used to carry the same weight — same cover, same
/// headline, same chevron — and with eight of nine crowned, the single
/// collection a free player could actually open was indistinguishable from
/// the eight they could not. The screen had no primary action and read as a
/// wall of locks.
///
/// This is a different class of object rather than a louder row: a larger
/// cover, a title a step up the scale, and the ink pill the app reserves for
/// its one loud action. The collection it promotes is lifted *out* of the
/// list below, so the screen never shows it twice.
struct CollectionLeadCard: View {
    let title: String
    let blurb: String
    let symbol: String
    let accent: Color
    /// "Journey · Step 1 of 5" — what kind of collection this is, and how far
    /// through it the player is.
    let meta: String
    let action: CollectionLeadAction

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .largeTitle) private var iconSize = 64

    private var isStacked: Bool { CollectionCardLayout.isStacked(dynamicTypeSize) }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            if isStacked {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    cover
                    heading
                }
            } else {
                HStack(spacing: Theme.Spacing.m) {
                    cover
                    heading
                    Spacer(minLength: 0)
                }
            }

            Text(blurb)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(meta)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()

            pill
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .elevatedCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Next up. \(title). \(blurb). \(meta). \(action.rawValue)")
    }

    private var cover: some View {
        CollectionCover(
            symbol: symbol,
            accent: accent,
            isLocked: false,
            side: CollectionCardLayout.coverSize(iconSize),
            font: .largeTitle
        )
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Next up").kicker()
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The `.pillProminent` treatment as a label rather than a button — the
    /// whole card is already the navigation link, and nesting a second
    /// tappable target inside it would give the row two hit areas that do the
    /// same thing. Metrics match `PillButtonStyle` so the two read as one
    /// component.
    private var pill: some View {
        Text(action.rawValue)
            .font(.headline)
            .foregroundStyle(Theme.onInk)
            .padding(.vertical, 15)
            .padding(.horizontal, Theme.Spacing.l)
            .frame(maxWidth: .infinity)
            .background(Theme.ink, in: .capsule)
    }
}

// MARK: - Pack card

struct PackCard: View {
    let pack: PuzzlePack
    let progress: PackProgress
    /// True when the pack's content is locked behind Premium for this player.
    let isLocked: Bool
    /// Off under the Packs tab's "With Premium" header, which says it once.
    var showsCrown = true

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .title) private var iconSize = 44

    /// The one badge this row shows, if any — drives both the capsule and the
    /// spoken label, so they can't say different things.
    private var packBadge: PackBadge? { PackBadge.forPack(pack) }

    private var isStacked: Bool { CollectionCardLayout.isStacked(dynamicTypeSize) }

    var body: some View {
        Group {
            if isStacked {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    HStack(spacing: Theme.Spacing.m) {
                        cover
                        Spacer(minLength: 0)
                        chevron
                    }
                    details
                }
            } else {
                HStack(spacing: Theme.Spacing.m) {
                    cover
                    details
                    Spacer(minLength: 0)
                    chevron
                }
            }
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .elevatedCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var cover: some View {
        CollectionCover(
            symbol: pack.coverSymbol,
            accent: pack.accent,
            isLocked: isLocked,
            side: CollectionCardLayout.coverSize(iconSize)
        )
    }

    private var chevron: some View {
        Image(systemName: "chevron.forward")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.xs) {
                CollectionCardLayout.title(pack.title, locked: isLocked && showsCrown)
                if let packBadge {
                    packBadge
                }
            }
            // Subheadline, not caption: this is the only description of
            // what is inside a pack, on the screen where someone decides
            // whether to pay for it. Caption grey is the size the rest of
            // this card's metadata uses — clue counts, progress — and a
            // sentence that has to be read to make a decision should not
            // be set in the same breath as the numbers beside it.
            Text(pack.blurb)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(CollectionCardLayout.blurbLineLimit(dynamicTypeSize))
                .fixedSize(horizontal: false, vertical: true)
            status
        }
    }

    // A locked pack states its size, not the player's progress through it.
    // Some Premium packs are still assembled from puzzles that also run in
    // the daily rotation, so a free player who has been solving dailies
    // accumulates real progress inside a collection they cannot open — and
    // once they had solved all of them the card rendered "Complete", with a
    // green seal, next to the crown. A Premium collection marked finished and
    // locked is the strongest possible argument that Premium is charging for
    // something the player already has. Whether that overlap should exist at
    // all is ticket 14; this is the display not volunteering it either way.
    @ViewBuilder
    private var status: some View {
        if isLocked {
            Text(puzzleCountText)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .padding(.top, 2)
        } else if progress.isComplete {
            Label("Complete", systemImage: "checkmark.seal.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.green)
                .padding(.top, 2)
        } else {
            ProgressView(value: progress.fraction)
                .tint(pack.accent)
                .padding(.top, 2)
            Text("\(progress.solved) of \(progress.total) solved")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    /// "5 puzzles" — what a locked pack says in place of progress.
    private var puzzleCountText: String {
        "\(progress.total) puzzle\(progress.total == 1 ? "" : "s")"
    }

    private var accessibilityLabel: String {
        var parts = [pack.title, pack.blurb]
        if isLocked { parts.append("Premium") }
        if let packBadge { parts.append(packBadge.label) }
        // Matches what's drawn: reading out progress the card no longer shows
        // would put the locked-and-complete contradiction back, in the one
        // place a sighted player can't see it to report it.
        if isLocked {
            parts.append(puzzleCountText)
        } else {
            parts.append(progress.isComplete
                ? "Complete"
                : "\(progress.solved) of \(progress.total) solved")
        }
        return parts.joined(separator: ". ")
    }
}
