//
//  CoverRow.swift
//  Bible Crossword Challenge
//
//  A row for something the player is partway through — a Journey, their
//  memory verses, the next badge, a reading plan — drawn the way YouVersion
//  lists plans: a cover in the feature's colour, the title, where they stand,
//  and a slim bar when there's a count to fill. No chevron and no divider;
//  the whole row is the tap target and space separates one from the next.
//
//  It replaced the settings-style row (36pt grey icon square, hairline
//  divider, chevron) on Today's "Keep going", where a Journey halfway done
//  looked the same as a menu item.
//

import SwiftUI

struct CoverRow: View {
    let symbol: String
    let tint: Color
    let title: String
    let subtitle: String
    /// 0...1 when the row has a count to fill; nil draws no bar.
    var progress: Double? = nil
    /// A solid cover in `tint` with a near-black glyph — the Premium mark, as
    /// the gold chip wears it. The pale tinted cover is for things in
    /// progress, and a pale gold crown read as one more badge beside them.
    var solid = false

    /// The cover's side. Fixed, with the glyph capped like `RowIcon`'s, so a
    /// large text size grows the text column rather than the artwork.
    static let coverSide: CGFloat = 52

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            Group {
                if solid {
                    Image(systemName: symbol)
                        .font(.title3)
                        // Fixed near-black, as on the chip: gold in both
                        // appearances.
                        .foregroundStyle(Color(white: 0.1))
                        .frame(width: Self.coverSide, height: Self.coverSide)
                        .background(tint, in: .rect(cornerRadius: 12, style: .continuous))
                } else {
                    CollectionCover(
                        symbol: symbol,
                        accent: tint,
                        isLocked: false,
                        side: Self.coverSide,
                        font: .title3,
                        cornerRadius: 12
                    )
                }
            }
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let progress {
                    ProgressView(value: progress)
                        .tint(tint)
                        .padding(.top, 2)
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
    }
}

#Preview {
    VStack(spacing: Theme.Spacing.m) {
        CoverRow(symbol: "leaf", tint: .green, title: "Beginnings",
                 subtitle: "Step 3 of 5 is ready", progress: 0.4)
        CoverRow(symbol: "brain.fill", tint: .indigo, title: "Memory verses",
                 subtitle: "Pick one from a puzzle you solved")
    }
    .padding()
    .background(Theme.background)
}
