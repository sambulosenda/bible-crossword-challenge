//
//  HintCountBadge.swift
//  Bible Crossword Challenge
//
//  The count on the Hints button: the free hints left today, in the accent,
//  ringed in the bar's own colour so it reads as sitting on the glyph.
//

import SwiftUI

struct HintCountBadge: View {
    let count: Int

    @ScaledMetric(relativeTo: .caption2) private var height: CGFloat = 16

    var body: some View {
        Text(count, format: .number)
            .font(.caption2.weight(.bold))
            .monospacedDigit()
            .foregroundStyle(.white)
            .padding(.horizontal, 4)
            .frame(minWidth: height, minHeight: height)
            .background(Theme.accent, in: .capsule)
            .overlay(Capsule().strokeBorder(Color(.systemBackground), lineWidth: 2).padding(-2))
            .fixedSize()
            // The button's value says it; the badge would be read twice.
            .accessibilityHidden(true)
    }
}
