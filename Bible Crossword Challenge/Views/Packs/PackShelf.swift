//
//  PackShelf.swift
//  Bible Crossword Challenge
//
//  The pieces of the Packs shelf: a titled grid of cover tiles, the tile
//  itself, and the feature card that leads the tab.
//

import SwiftUI

/// A titled shelf of cover tiles. Two columns on a phone, four on a regular
/// width — an even count either way, so the grid divides cleanly at an
/// iPhone Duo's fold.
struct PackShelf<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s + 4) {
            Text(title)
                .sectionHeader()
                .accessibilityAddTraits(.isHeader)
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: 14, alignment: .top),
                    count: sizeClass == .regular ? 4 : 2
                ),
                alignment: .leading,
                spacing: Theme.Spacing.l
            ) {
                content
            }
        }
    }
}

/// One cover on a shelf: the tall typographic cover, then the title and where
/// the player stands, as Apple Books sets a shelf.
struct ShelfTile: View {
    let title: String
    let meta: String
    let label: PackCoverLabel
    let fallbackSymbol: String
    let isLocked: Bool
    var progress: Double? = nil
    var badge: PackBadge? = nil

    @ScaledMetric(relativeTo: .title) private var coverHeight: CGFloat = 190

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            PackCover(
                label: label,
                fallbackSymbol: fallbackSymbol,
                isLocked: isLocked,
                progress: progress
            )
            .frame(height: coverHeight)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                if let badge { badge }
                Text(meta)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel)
    }

    private var spokenLabel: String {
        var parts = [title]
        if !label.caption.isEmpty { parts.append(label.caption) }
        if let badge { parts.append(badge.label) }
        parts.append(meta)
        // The cover's lock is the only sign of it on screen; the caption
        // no longer repeats it.
        if isLocked { parts.append("Premium") }
        return parts.joined(separator: ". ")
    }
}

/// The collection to play next, as the tab's one feature card: white, as
/// Today's hero is (2026-11-03), the title in serif with the book's mark faint
/// behind it, the Journey's steps as a path, and one blue pill.
struct LeadFeatureCard: View {
    let kicker: String
    let title: String
    let mark: String
    /// Steps done and total, drawn as a path — for a Journey.
    var steps: (done: Int, total: Int)? = nil
    let actionTitle: String
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(kicker)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(title)
                        .font(.scripture(.title, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                }

                // A path reads only while the dots stay apart; past fourteen
                // steps they'd run together.
                if let steps, steps.total > 1, steps.total <= 14 {
                    StepPath(done: steps.done, total: steps.total, ink: .primary)
                        // A phone card's width. Across open iPhone Duo's
                        // ~830pt card five steps sat 190pt apart and the
                        // path read as a rule (2026-10-25).
                        .frame(maxWidth: 400, alignment: .leading)
                }

                HStack {
                    Spacer(minLength: 0)
                    Text(actionTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .frame(minHeight: 44)
                        .background(Theme.accent, in: .capsule)
                }
            }
            .foregroundStyle(.primary)
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(alignment: .topTrailing) {
                Text(mark)
                    .font(.system(size: 150, weight: .semibold, design: .serif))
                    .tracking(-6)
                    .foregroundStyle(Color.primary.opacity(0.05))
                    .lineLimit(1)
                    .fixedSize()
                    .offset(x: 10, y: -28)
                    .accessibilityHidden(true)
            }
            .clipShape(.rect(cornerRadius: Theme.featureCornerRadius, style: .continuous))
            .elevatedCard(cornerRadius: Theme.featureCornerRadius)
            .contentShape(.rect)
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Next up: \(title). \(kicker)")
        .accessibilityHint("\(actionTitle)s it")
    }
}

/// A Journey's steps as a path: done steps filled, the next one ringed and a
/// size larger, the rest outlined, joined by a line that fills behind them.
struct StepPath: View {
    let done: Int
    let total: Int
    /// White on a coloured shelf cover; `.primary` on a page's paper.
    var ink: Color = .white

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<total, id: \.self) { index in
                let isNext = index == done
                Circle()
                    .fill(index < done || isNext ? ink : Color.clear)
                    .overlay {
                        if index > done {
                            Circle().strokeBorder(ink.opacity(0.45), lineWidth: 2)
                        }
                    }
                    .padding(isNext ? -2 : 0)
                    .background {
                        if isNext {
                            Circle().fill(ink.opacity(0.3)).padding(-5)
                        }
                    }
                    .frame(width: 10, height: 10)
                if index < total - 1 {
                    Rectangle()
                        .fill(ink.opacity(index < done ? 1 : 0.3))
                        .frame(height: 2)
                }
            }
        }
        .padding(.horizontal, 3)
        .accessibilityHidden(true)
    }
}
