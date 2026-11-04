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

/// The cover: on the page's own paper with ink type since 2026-11-02 — it was
/// the collection's colour edge to edge, and the app keeps one colour (the
/// play pill's blue). A mark in the corner, the gold chip when it's locked,
/// the serif title and where in Scripture it sits, then whatever the page
/// puts under that — progress, a step path, the play pill.
struct CollectionPageCover<Mark: View, Footer: View>: View {
    let title: String
    let caption: String
    var isLocked = false
    /// A floor on the cover's height. None since 2026-11-03: the cover is
    /// just its type now, sized to it.
    var minHeight: CGFloat = 0
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
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            footer
        }
        .frame(maxWidth: 560, alignment: .leading)
        .padding(.horizontal, Theme.Spacing.m + Theme.Spacing.xs)
        // Tight under the bar, where a large title sits: 32pt here left an
        // empty band between the back button and the title (2026-11-03).
        .padding(.top, Theme.Spacing.xs)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .bottom)
        .background(alignment: .bottomTrailing) {
            mark
                .padding(.trailing, Theme.Spacing.m + Theme.Spacing.xs)
        }
        .accessibilityElement(children: .contain)
    }
}

/// The puzzle to play next on a collection's page, as a card: its grid, where
/// it sits in the collection, what it is, and the page's one action. Shared by
/// packs and Journeys (2026-11-03), so the two pages lead the same way.
struct UpNextCard<Action: View>: View {
    let puzzle: Puzzle
    let kicker: String
    /// A glyph before the kicker — the seal on a finished collection.
    var kickerSymbol: String? = nil
    /// The line under the title. Defaults to `puzzle.detailLine` (reference,
    /// size, difficulty); a caller can say it its own way, once.
    var detail: String? = nil
    /// One reassuring line under the puzzle — how long, what helps.
    var note: String? = nil
    /// 0...1 once the collection is under way; nil draws no bar (an empty bar
    /// is a gauge with nothing to measure).
    var progress: Double? = nil
    @ViewBuilder let action: Action

    /// The grid tile grows with the title beside it, as a shelf cover does.
    @ScaledMetric(relativeTo: .title3) private var gridSide: CGFloat = 72
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // Grid above the text at accessibility sizes: beside it, the grown
        // tile took the width the words need and broke the kicker mid-phrase
        // ("2 of / 7 done"). AnyLayout keeps identity across the swap.
        let header = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.s))
            : AnyLayout(HStackLayout(spacing: Theme.Spacing.m))
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            header {
                GridThumbnail(grid: puzzle.grid, tint: Color.secondary,
                              gap: puzzle.grid.count > 9 ? 0 : 1, cropsToContent: true)
                    .padding(gridSide / 9)
                    .frame(width: gridSide, height: gridSide)
                    .background(Color.primary.opacity(0.06),
                                in: .rect(cornerRadius: gridSide * 0.2, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        if let kickerSymbol {
                            Image(systemName: kickerSymbol).foregroundStyle(FeatureTint.solved)
                        }
                        Text(kicker)
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    Text(puzzle.title)
                        .font(.title3.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(detail ?? puzzle.detailLine)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            if let note {
                Text(note)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let progress {
                ProgressView(value: progress)
                    .tint(Theme.progressBar)
            }
            action
        }
        .padding(Theme.Spacing.m + Theme.Spacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .elevatedCard(cornerRadius: Theme.featureCornerRadius)
    }
}

/// The opening verse and what the collection is, at the foot of its page.
struct CollectionAbout: View {
    let heading: String
    let first: Puzzle?
    let blurb: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s + Theme.Spacing.xs) {
            Text(heading).sectionHeader()
            CollectionOpening(first: first, blurb: blurb)
        }
    }
}

/// What the collection is, then the verse it opens on. The blurb leads:
/// it answers the "About" heading above it. The verse sits in a card set
/// like Today's verse of the day — body serif, reference in ink — rather
/// than bare title2 serif, which outranked the page's own headings and
/// left the description as fine print after the reference (2026-11-04).
struct CollectionOpening: View {
    let first: Puzzle?
    let blurb: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text(blurb)
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            if let first, !first.verse.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    Text(first.verse)
                        .font(.scripture(.body))
                        .lineSpacing(6)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(first.reference)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Theme.Spacing.l)
                .elevatedCard()
                .accessibilityElement(children: .combine)
            }
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

    /// The price behind the button, in the buy screens' words (see
    /// `PremiumCopy.terms`).
    private var terms: String {
        PremiumCopy.terms(store) ?? "Every pack and Journey included"
    }
}
