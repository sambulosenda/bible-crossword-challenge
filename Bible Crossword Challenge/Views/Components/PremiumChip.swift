//
//  PremiumChip.swift
//  Bible Crossword Challenge
//
//  The mark Premium wears wherever it appears — the offer page, a locked
//  pack's cover. Gold with a crown, so "this is the paid thing" reads before a
//  word does; grey caps only ever said "label".
//

import SwiftUI

struct PremiumChip: View {
    var body: some View {
        Label("Premium", systemImage: "crown.fill")
            .font(.footnote.weight(.bold))
            // Fixed near-black: the chip is gold in both appearances.
            .foregroundStyle(Color(white: 0.1))
            .padding(.vertical, 5)
            .padding(.horizontal, 12)
            .background(Theme.badgeRim, in: .capsule)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Bible Crossword Premium")
    }
}

#Preview {
    PremiumChip()
        .padding()
}
