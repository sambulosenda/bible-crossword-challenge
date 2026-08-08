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

    /// Days left when the pack's window is closing — drives both the badge and
    /// the spoken label, so they can't say different things.
    private var closingDays: Int? { SeasonBadge.daysRemaining(for: pack) }

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
                    if let closingDays {
                        SeasonBadge(daysRemaining: closingDays)
                    }
                }
                Text(pack.blurb)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if progress.isComplete {
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
            Image(systemName: "chevron.right")
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

    private var accessibilityLabel: String {
        var parts = [pack.title, pack.blurb]
        if isLocked { parts.append("Premium") }
        if let closingDays { parts.append(SeasonBadge.text(daysRemaining: closingDays)) }
        parts.append(progress.isComplete
            ? "Complete"
            : "\(progress.solved) of \(progress.total) solved")
        return parts.joined(separator: ". ")
    }
}
