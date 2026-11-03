//
//  BadgeMedal.swift
//  Bible Crossword Challenge
//
//  An earned badge as one object everywhere it appears: the badge's own
//  symbol in gold on a soft gold disc with a gold rim. Profile → Badges drew
//  it this way; the completion screen showed a generic blue star in a gold
//  ring instead, so the badge you earned looked different from the badge you
//  then found (2026-11-03).
//

import SwiftUI

struct BadgeMedal: View {
    let symbol: String
    var size: CGFloat = 72

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.36, weight: .semibold))
            .foregroundStyle(Theme.badgeInk)
            .frame(width: size, height: size)
            .background(Theme.premiumWash, in: .circle)
            .overlay(Circle().strokeBorder(Theme.badgeRim, lineWidth: max(1.5, size * 0.035)))
            .shadow(color: Theme.badgeRim.opacity(0.22), radius: size * 0.08, y: size * 0.05)
            .accessibilityHidden(true)
    }
}

#Preview {
    HStack(spacing: 20) {
        BadgeMedal(symbol: "book")
        BadgeMedal(symbol: "flame.fill", size: 52)
    }
    .padding()
}
