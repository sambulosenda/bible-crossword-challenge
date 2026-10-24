//
//  RisingSteps.swift
//  Bible Crossword Challenge
//
//  Fifteen bars climbing to the right, each a shade brighter than the last —
//  the locked pack cover's mark (design canvas, 2026-10-24). A way up, for a
//  page that sells the rest of the climb.
//

import SwiftUI

struct RisingSteps: View {
    var count = 15

    var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(0..<count, id: \.self) { step in
                UnevenRoundedRectangle(topLeadingRadius: 3, topTrailingRadius: 3, style: .continuous)
                    .fill(.white.opacity(0.06 + Double(step) * 0.008))
                    .frame(width: 9, height: 24 + CGFloat(step) * 15)
            }
        }
        .accessibilityHidden(true)
    }
}
