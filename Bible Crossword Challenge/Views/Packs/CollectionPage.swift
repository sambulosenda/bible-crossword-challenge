//
//  CollectionPage.swift
//  Bible Crossword Challenge
//
//  The parts a collection's page is built from — a pack's and a Journey's
//  alike (design canvas, 2026-10-24): the full-bleed cover in its colour,
//  the verse it opens on, and the offer pinned to the bottom when it's
//  locked. One set, so the two pages can't drift apart again; the Journey
//  page had kept an older layout of its own after the pack page moved on.
//

import SwiftUI

/// The cover: the collection's colour edge to edge and up under the bar, a
/// mark in the corner, the gold chip when it's locked, the serif title and
/// where in Scripture it sits, then whatever the page puts under that —
/// progress, a step path, the play pill.
struct CollectionPageCover<Mark: View, Footer: View>: View {
    let title: String
    let caption: String
    let fill: Color
    var isLocked = false
    /// The cover's height under the bar. 200 since 2026-10-25 (about 300 with
    /// the bar): at 290 the cover took nearly half a 17e and the contents
    /// started under the pinned offer.
    var minHeight: CGFloat = 200
    /// Drawn in the bottom-trailing corner, behind the type.
    @ViewBuilder var mark: Mark
    @ViewBuilder var footer: Footer

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s + Theme.Spacing.xs) {
            if isLocked {
                PremiumChip()
            }
            Text(title)
                .font(.system(.largeTitle, design: .serif, weight: .semibold))
                .tracking(-0.6)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(caption)
                .font(.body)
                .foregroundStyle(.white.opacity(0.82))
                .fixedSize(horizontal: false, vertical: true)
            footer
        }
        .foregroundStyle(.white)
        .frame(maxWidth: 560, alignment: .leading)
        .padding(.horizontal, Theme.Spacing.m + Theme.Spacing.xs)
        .padding(.top, Theme.Spacing.xl)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .bottom)
        .background(alignment: .bottomTrailing) {
            mark
                .padding(.trailing, Theme.Spacing.m + Theme.Spacing.xs)
        }
        // The colour runs on up under the bar and the status bar, so the cover
        // is the page's top edge; the scroll view still insets its content
        // for the bar, which is where the type wants to start anyway.
        .background {
            fill
                .padding(.top, -400)
                .ignoresSafeArea(edges: .top)
        }
        .accessibilityElement(children: .contain)
    }
}

/// The verse the collection opens on, in serif, with where it's from and
/// what the collection is. Falls back to the blurb alone when the first
/// puzzle has no verse.
struct CollectionOpening: View {
    let first: Puzzle?
    let blurb: String

    var body: some View {
        if let first, !first.verse.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(first.verse)
                    .font(.scripture(.title2))
                    .tracking(-0.2)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(first.reference) · \(blurb)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
        } else {
            Text(blurb)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A locked collection's one offer, pinned where the thumb is: the ink pill,
/// as the Premium page's own button, over a fade into the paper so the list
/// scrolls away under it rather than ending at a hard edge. The words are
/// every Premium card's — never "Unlock", which overstates a tap that only
/// opens the paywall (see `PremiumCopy.cardCTA`).
struct CollectionLockedOffer: View {
    let onOpen: () -> Void

    @Environment(StoreService.self) private var store

    var body: some View {
        VStack(spacing: 10) {
            Button(PremiumCopy.cardCTA(store), action: onOpen)
                .buttonStyle(.pillProminent)
                .accessibilityHint("Opens Premium plans")
            Text(terms)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Theme.Spacing.m + Theme.Spacing.xs)
        .padding(.top, Theme.Spacing.xl)
        .padding(.bottom, Theme.Spacing.s)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
        .background {
            LinearGradient(
                stops: [.init(color: Theme.background.opacity(0), location: 0),
                        .init(color: Theme.background, location: 0.3)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }

    /// "Then $9.99 a year · every pack and Journey" — the price behind the
    /// button, and that it's the whole shelf, not this one collection.
    private var terms: String {
        guard let yearly = store.yearly else { return "Every pack and Journey included" }
        let price = "\(store.yearlyPriceText) a year"
        let lead = store.introOffer(for: yearly) != nil ? "Then \(price)" : price
        return "\(lead) · every pack and Journey"
    }
}
