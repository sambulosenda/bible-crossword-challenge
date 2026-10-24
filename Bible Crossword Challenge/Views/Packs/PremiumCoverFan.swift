//
//  PremiumCoverFan.swift
//  Bible Crossword Challenge
//
//  Three locked pack covers fanned like cards in a hand — the Premium page's
//  hero (design canvas, 2026-10-24). It replaced the FAITH/HOPE/LOVE tiles,
//  which decorated the page; the covers show what paying opens.
//

import SwiftUI

struct PremiumCoverFan: View {
    /// The pack the player came from, if any: its cover goes on top.
    var leadingPackID: String? = nil
    /// Shrinks the fan for the sheet's middle layout, where the full one
    /// misses by a few dozen points.
    var scale: CGFloat = 1

    @Environment(\.puzzleProvider) private var puzzleProvider

    /// Three premium packs on offer that have a book mark, so every cover
    /// carries one — the pack the player came from first. Out-of-season packs
    /// are hidden everywhere else in the app, so they aren't held up here
    /// either.
    private var covers: [(id: String, label: PackCoverLabel, fill: Color)] {
        var packs = puzzleProvider.availablePacks().filter(\.isPremium)
        if let leadingPackID, let index = packs.firstIndex(where: { $0.id == leadingPackID }) {
            packs.insert(packs.remove(at: index), at: 0)
        }
        return packs
            .lazy
            .map { (id: $0.id, label: PackCoverLabel(puzzles: puzzleProvider.puzzles(in: $0)), fill: $0.coverFill) }
            .filter { !$0.label.mark.isEmpty }
            .prefix(3)
            .map { $0 }
    }

    var body: some View {
        // Drawn left, right, then centre on top — so the first cover, the one
        // that leads, is drawn last.
        let covers = Array(self.covers.dropFirst()) + Array(self.covers.prefix(1))
        let poses: [(x: CGFloat, y: CGFloat, angle: Double)] = covers.count == 3
            ? [(0, 22, -10), (68, 22, 10), (34, 8, 0)]
            : [(0, 22, -10), (34, 8, 0)]
        ZStack(alignment: .topLeading) {
            ForEach(covers.indices, id: \.self) { index in
                let cover = covers[index], pose = poses[index]
                FanCover(mark: cover.label.mark, fill: cover.fill)
                    .rotationEffect(.degrees(pose.angle))
                    .offset(x: pose.x, y: pose.y)
            }
        }
        .frame(width: 132, height: 118, alignment: .topLeading)
        .scaleEffect(scale, anchor: .bottomTrailing)
        .frame(width: 132 * scale, height: 118 * scale)
        .accessibilityHidden(true)
    }
}

/// One cover in the fan: a short rule and the book's mark in serif, on the
/// pack's colour. `PackCover` at a size its padding and caption don't fit.
private struct FanCover: View {
    let mark: String
    let fill: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Capsule()
                .fill(.white.opacity(0.6))
                .frame(width: 14, height: 2)
            Spacer(minLength: 0)
            Text(mark)
                .font(.system(size: 22, weight: .semibold, design: .serif))
                .tracking(-0.4)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .foregroundStyle(.white)
        .padding(EdgeInsets(top: 9, leading: 8, bottom: 8, trailing: 8))
        .frame(width: 64, height: 86, alignment: .leading)
        .background(fill, in: .rect(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 10, y: 8)
    }
}
