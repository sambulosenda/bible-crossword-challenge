//
//  PackShelf.swift
//  Bible Crossword Challenge
//
//  The pieces of the Puzzles tab's shelves: a titled grid of cover tiles and
//  the tile itself. The tab's lead is an `UpNextCard` since 2026-11-03.
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
    /// The collection's first grid, drawn small on the cover.
    var grid: [String]? = nil
    let fallbackSymbol: String
    let isLocked: Bool
    var badge: PackBadge? = nil

    /// 130 since 2026-11-03: at 190 the cover was mostly blank white, and
    /// three Journeys filled the first screen.
    @ScaledMetric(relativeTo: .title) private var coverHeight: CGFloat = 130

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            PackCover(
                label: label,
                grid: grid,
                fallbackSymbol: fallbackSymbol,
                isLocked: isLocked
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

