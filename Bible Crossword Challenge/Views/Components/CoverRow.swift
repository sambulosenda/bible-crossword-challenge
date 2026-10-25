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

    /// The cover's side. Fixed, with the glyph capped like `RowIcon`'s, so a
    /// large text size grows the text column rather than the artwork.
    static let coverSide: CGFloat = 52

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            // Pale, every row alike, Premium's crown included (2026-10-25):
            // its solid gold block was the loudest thing on Today. The
            // feature's colour lives on the glyph and its wash, nowhere else
            // in the row.
            CollectionCover(
                symbol: symbol,
                accent: tint,
                isLocked: false,
                side: Self.coverSide,
                font: .title3,
                cornerRadius: 12
            )
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
                        .tint(Theme.progressBar)
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
