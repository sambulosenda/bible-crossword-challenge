//
//  PackCard.swift
//  Bible Crossword Challenge
//
//  A single collection tile: cover symbol, title, blurb, and a progress bar.
//  Shows a crown when the pack is premium and the player hasn't upgraded.
//

import SwiftUI

struct PackCard: View {
    let pack: PuzzlePack
    let progress: PackProgress
    /// True when the pack's content is locked behind Premium for this player.
    let isLocked: Bool

    @ScaledMetric(relativeTo: .title) private var iconSize = 52

    /// The one badge this row shows, if any — drives both the capsule and the
    /// spoken label, so they can't say different things.
    private var packBadge: PackBadge? { PackBadge.forPack(pack) }

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            cover
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                HStack(spacing: Theme.Spacing.xs) {
                    Text(pack.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    if isLocked {
                        Image(systemName: "crown.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                    }
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
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                // A locked pack states its size, not the player's progress
                // through it. Some Premium packs are still assembled from
                // puzzles that also run in the daily rotation, so a free player
                // who has been solving dailies accumulates real progress inside
                // a collection they cannot open — and once they had solved all
                // of them the card rendered "Complete", with a green seal, next
                // to the crown. A Premium collection marked finished and locked
                // is the strongest possible argument that Premium is charging
                // for something the player already has. Whether that overlap
                // should exist at all is ticket 14; this is the display not
                // volunteering it either way.
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
            Spacer(minLength: 0)
            Image(systemName: "chevron.forward")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .elevatedCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var cover: some View {
        Image(systemName: pack.coverSymbol)
            .font(.title2)
            .foregroundStyle(pack.accent)
            .frame(width: iconSize, height: iconSize)
            .background(pack.accent.opacity(0.14), in: .rect(cornerRadius: 14, style: .continuous))
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
