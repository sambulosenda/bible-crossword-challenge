//
//  PremiumOfferView.swift
//  Bible Crossword Challenge
//
//  The Premium offer itself — promise, benefits, plans — shared by the two
//  surfaces that sell it: `PaywallView` (a sheet, reached from every in-app
//  entry point) and onboarding's final page.
//
//  These were two implementations of one offer, and they drifted every time
//  either changed. The copy had already been pulled into `PremiumCopy` and
//  `PremiumBenefit` for exactly that reason; what stayed split was the part
//  that mattered most — the *offer*. Onboarding sold the yearly plan alone,
//  with no monthly, no lifetime, no per-month figure and no savings badge, to
//  91% of everyone who has ever seen a paywall in this app. It also couldn't be
//  audited beside the sheet, because there was no shared thing to audit.
//
//  Now anything true of the offer is true in one place. What stays per-surface
//  is only the chrome: how the screen is dismissed, where the CTA sits, and the
//  promise at the top — which each surface still chooses, because the sheet
//  knows the entry point and onboarding knows whether the player just solved
//  their first clue.
//

import SwiftUI
import StoreKit

private extension View {
    /// The shared look of a thing you can pick on this page: a white card on
    /// the paper, with an ink border on the one that's chosen — the CTA's
    /// colour, so the page has one action colour (design canvas, 2026-10-24).
    /// The accent border it had was a second blue beside a black button.
    ///
    /// Selection used to be said three times — a tint, a border and a check.
    /// Two is how the system says it, and with the benefits off their card
    /// these are the only white surfaces on the page, so "white" now means
    /// "you can choose this" without any help.
    func planChrome(selected: Bool) -> some View {
        background(Theme.surface,
                   in: .rect(cornerRadius: Theme.cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .strokeBorder(selected ? Theme.ink : Color(.separator).opacity(0.6),
                                  lineWidth: selected ? 2 : 1)
            }
            // Without this the card only answers to taps that land on the
            // glyphs themselves: a SwiftUI button's hit area is its content,
            // and neither the padding nor the background extends it. Most of a
            // card this size is padding, so most of it was dead to the touch.
            .contentShape(.rect(cornerRadius: Theme.cornerRadius, style: .continuous))
    }
}

struct PremiumOfferView: View {
    /// The promise, chosen by the surface presenting it, said as the line
    /// under the fixed headline — see `offerHeader`.
    let headline: String

    /// Which plan is selected.
    ///
    /// Owned by the caller because on both surfaces the CTA that acts on it
    /// sits outside this view — pinned to the sheet's bottom edge, or down in
    /// onboarding's shared controls row.
    @Binding var selectedID: String

    /// When non-nil, the blocks fade in on a stagger, as onboarding's other
    /// pages do. Nil on the sheet, which is already an animated presentation.
    var entranceActive: Bool? = nil

    /// The pack the player just bounced off, when they came from one. It takes
    /// the front of the cover fan, so the collection that sent them here is
    /// the one on top.
    ///
    /// The fan replaced the "Locked collections" list on 2026-10-24: three
    /// covers already name the packs Premium opens, and the list was a second
    /// copy that pushed the page past the screen.
    var highlightedPackID: String? = nil

    /// Drops the decoration — the chip and the cover fan — for a screen the
    /// whole offer doesn't fit. Each surface offers both sizes to a
    /// `ViewThatFits` and lets layout pick: on a 667pt iPhone SE the full page
    /// pushed the prices and the timeline behind the purchase button, and the
    /// price is the one thing that must be on screen when the button is.
    /// Nothing that describes the offer is ever dropped, only what decorates it.
    var compact: Bool = false

    /// Keeps the chip and a smaller fan in the compact layout. Both surfaces
    /// offer it as a middle size: on a 6.3" phone the full header missed by a
    /// few dozen points and the compact page left that room empty above the
    /// headline.
    var keepsSmallHero: Bool = false

    /// The compact page with its gaps a step closer, for the phones it still
    /// overflows: on a 6.1" 17e the onboarding page ran 67pt long, which put
    /// "Or monthly" under the buy button with nothing to say it was there
    /// (2026-11-11). Only the space between things gives; nothing is dropped
    /// or resized.
    var tight: Bool = false

    /// A Free | Premium table instead of the benefit list — for paywalls a
    /// player reaches from inside the app, who already knows the free tier.
    /// Onboarding keeps the list: a first-run player has no free tier yet.
    var comparesWithFree: Bool = false

    /// The carousel of what Premium opens. Left out by a page that has to
    /// scroll: it rests on its foot, by the plans, and the card at its head
    /// sat cut in half under the top bar (iPhone Duo, 2026-11-16).
    var showsPreviews: Bool = true

    @Environment(StoreService.self) private var store
    @Environment(\.puzzleProvider) private var puzzleProvider
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// The plan radio's diameter, scaled with the text.
    @ScaledMetric(relativeTo: .title3) private var radioSize: CGFloat = 22
    @Environment(\.accessibilityReduceMotion) private var reduceMotion


    var body: some View {
        // Three groups, spaced as groups: what this is, what you get, what
        // you pay. Tight inside each, open between them — one uniform gap
        // made every block on the page look equally related to every other.
        // A step tighter in both compact layouts: on a 667pt iPhone SE the
        // group gaps were the ~24pt that left the trial timeline's last line
        // under the pinned button, and on a 17e sheet they were part of what
        // kept the chip and the fan off the page.
        // 16 when tight: still twice the gap inside a group, so the three
        // still read as three.
        let groupGap = tight ? Theme.Spacing.m : (compact ? Theme.Spacing.l : Theme.Spacing.xl)
        VStack(alignment: .leading, spacing: groupGap) {
            staggered(offerHeader, delay: 0)
            if showsPreviews, !previews.isEmpty {
                staggered(previewShelf, delay: 0.07)
            }
            if comparesWithFree {
                staggered(comparison, delay: 0.14)
            } else {
                staggered(featureList, delay: 0.14)
            }

            if store.isPremium {
                premiumBadge
            } else if store.products.isEmpty {
                productsPlaceholder
            } else {
                // No App Store rating line since 2026-10-24: with the
                // headline, the subhead and the benefits it was a fourth voice
                // before the price. No trial timeline since 2026-10-13.
                staggered(plans, delay: 0.23)
            }
        }
    }

    /// The plan the CTA outside this view would buy. Derived rather than passed
    /// in: the binding is the caller's, but everything on this page that has to
    /// describe the selection needs the product, not the id.
    private var selectedProduct: Product? {
        store.products.first { $0.id == selectedID }
    }

    /// Applies onboarding's entrance treatment when the caller asked for it and
    /// leaves the view alone otherwise.
    @ViewBuilder
    private func staggered<V: View>(_ view: V, delay: Double) -> some View {
        if let entranceActive {
            view.entrance(active: entranceActive, delay: delay, reduceMotion: reduceMotion)
        } else {
            view
        }
    }

    // MARK: - Header

    /// The header, as the design canvas draws it (2026-10-24): the
    /// gold chip over a large serif promise on the left, a fan of locked pack
    /// covers on the right, one line under both. Left-aligned on the page's
    /// one edge, like every other screen; the centred stack it replaced was
    /// the only centred page in the app.
    ///
    /// The fan is what Premium opens, where the FAITH/HOPE/LOVE tiles were
    /// decoration — onboarding drew those, and the solved word, until
    /// 2026-10-24; the canvas sends its "Keep going" to this same page. It goes in the tightest layout and at accessibility sizes,
    /// where the promise needs the width.
    /// The promise, broken over two lines as the canvas draws it. On a page
    /// short enough to have dropped its previews it runs on one line where
    /// the width allows: a line of large type is 41pt the plans need more.
    @ViewBuilder
    private var headlineText: some View {
        if showsPreviews {
            Text(PremiumCopy.sheetHeadline)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            // Allowed to shrink a little to stay on the line: iPhone Duo
            // closed has 334pt for the 358pt it sets at full size.
            Text(PremiumCopy.sheetHeadline.replacingOccurrences(of: "\n", with: " "))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
    }

    private var offerHeader: some View {
        // 8pt rather than 12 between the chip, the headline and the line
        // under them when the page is short — the last few points the chip
        // needed on a 17e sheet.
        let gap = compact ? Theme.Spacing.s : Theme.Spacing.s + Theme.Spacing.xs
        return VStack(alignment: .leading, spacing: gap) {
            HStack(alignment: .bottom, spacing: Theme.Spacing.s) {
                VStack(alignment: .leading, spacing: gap) {
                    if !compact || keepsSmallHero {
                        PremiumChip()
                    }
                    headlineText
                        .font(.scripture(.largeTitle, weight: .semibold))
                        .tracking(-0.4)
                        .accessibilityAddTraits(.isHeader)
                }
                Spacer(minLength: 0)
            }
            // Where the player came from is said here, under the fixed
            // headline, rather than as it: the per-entry lines ran to three
            // and four lines beside the fan, and the page fell back to the
            // layout without the chip and the fan on a 17e (2026-10-24).
            Text(subhead)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let rating = AppStoreRating.shared.displayable {
                ratingLine(rating)
            }
        }
        .task { await AppStoreRating.shared.refreshIfStale() }
    }

    /// "★★★★★ 4.9 on the App Store" — the store's own figure for the player's
    /// storefront, shown only when it has enough ratings (`AppStoreRating`).
    /// Gold stars, as the Premium chip: the page's one decoration colour.
    private func ratingLine(_ rating: AppStoreRating.Summary) -> some View {
        let value = AppStoreRating.formatted(rating.average)
        return HStack(spacing: 6) {
            HStack(spacing: 1) {
                ForEach(0..<5, id: \.self) { _ in
                    Image(systemName: "star.fill")
                }
            }
            .font(.caption2)
            .foregroundStyle(Theme.badgeRim)
            Text("\(value) on the App Store")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rated \(value) out of 5 on the App Store")
    }

    /// The entry point's own line, unbroken — its hand-set breaks are for a
    /// headline. The standing promise has nothing specific to say, so those
    /// entry points keep the line about what Premium is for.
    private var subhead: String {
        headline == PremiumCopy.promise
            ? PremiumCopy.subhead
            : headline.replacingOccurrences(of: "\n", with: " ")
    }

    /// The introductory offer on the *selected* plan, when there is one and the
    /// player hasn't already used theirs.
    ///
    /// Keyed to the selection rather than to `store.yearly`: only yearly
    /// carries an introductory offer, so an unkeyed read would show the
    /// free-tier reassurance to a trial-holder the moment they tapped monthly
    /// — which is correct, and stops the header describing an offer the CTA
    /// underneath isn't making.
    private var trialText: String? {
        guard let selectedProduct else { return nil }
        return store.introOfferText(for: selectedProduct)
    }

    // MARK: - Preview

    /// What Premium looks like, by name: the first Premium Journey, then up
    /// to two Premium packs (in-season first). See `previewShelf`.
    private struct Preview: Identifiable {
        let id: String
        let title: String
        let symbol: String
        let accent: Color
    }

    private var previews: [Preview] {
        var cards: [Preview] = []
        if let quest = puzzleProvider.quests.first(where: \.isPremium) {
            cards.append(Preview(id: "quest-\(quest.id)", title: quest.title,
                                 symbol: quest.coverSymbol, accent: quest.accent))
        }
        // Not a pack that ships as a Journey (Today's rule): Life of David
        // is both, and the card would show it twice.
        let packs = PuzzlePack.notShadowedByQuests(
            puzzleProvider.availablePacks(), quests: puzzleProvider.quests
        ).filter(\.isPremium)
        let ordered = packs.filter(\.isSeasonal) + packs.filter { !$0.isSeasonal }
        for pack in ordered.prefix(2) {
            cards.append(Preview(id: "pack-\(pack.id)", title: pack.title,
                                 symbol: pack.coverSymbol, accent: pack.accent))
        }
        return cards
    }

    /// What Premium opens, at a glance: the covers side by side, overlapped
    /// like books on a shelf, with their names beside them.
    ///
    /// A swipeable carousel until 2026-11-22. With 5 seconds on the page
    /// (median), almost nobody swiped, so two of its three cards went unseen
    /// and the dots under it were clutter. Static, all three show at once.
    private var previewShelf: some View {
        HStack(spacing: Theme.Spacing.m) {
            HStack(spacing: -12) {
                ForEach(Array(previews.enumerated()), id: \.element.id) { index, card in
                    previewCover(card)
                        .zIndex(Double(previews.count - index))
                }
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Every Journey & pack")
                    .font(.headline)
                Text(previewNames)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: .rect(cornerRadius: Theme.cornerRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    /// One cover: the pack's symbol on its colour, ringed in the card's white
    /// so the overlap reads as separate covers rather than one shape.
    private func previewCover(_ card: Preview) -> some View {
        Image(systemName: card.symbol)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 40, height: 40)
            .background(card.accent.gradient, in: .rect(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Theme.surface, lineWidth: 2)
            }
    }

    /// "350+ puzzles": the size of what Premium opens, on one line beside
    /// the covers. "Life of David and 4 more" counted collections and
    /// undersold it (2026-11-22). Rounded down to a ten, so "+" stays true.
    private var previewNames: String {
        let total = puzzleProvider.totalPuzzleCount
        guard total >= 20 else { return previews.first?.title ?? "" }
        return "\(total / 10 * 10)+ puzzles"
    }

    // MARK: - Free vs Premium

    /// The free tier as it stands (2026-11): today's puzzles plus a 7-day
    /// window, 1 hint a day after the learning window, 3 verses being learned
    /// at a time, First Steps and two free Journeys. Update with the limits.
    private static let comparisonRows: [(label: String, free: String, premium: String)] = [
        ("Puzzles", "Last 7 days", "Every one"),
        ("Hints", "1 a day", "Unlimited"),
        ("Memory verses", "3 at a time", "Unlimited"),
        ("Packs & Journeys", "A few", "All"),
        // 2026-11-24: free players earn a freeze per seven-day run; Premium
        // adds one every week on top (`Streaks.refillPremiumFreeze`).
        ("Streak freezes", "Earned", "+1 every week"),
    ]

    private var comparison: some View {
        Grid(alignment: .leading, horizontalSpacing: Theme.Spacing.m, verticalSpacing: tight ? 7 : Theme.Spacing.s + 2) {
            GridRow {
                Text("")
                Text("Free")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                Label("Premium", systemImage: "crown.fill")
                    .font(.footnote.weight(.semibold))
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(Theme.badgeRim)
            }
            ForEach(Self.comparisonRows, id: \.label) { row in
                Divider().gridCellColumns(3)
                GridRow {
                    Text(row.label)
                        .font(.subheadline)
                    Text(row.free)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(row.premium)
                        .font(.subheadline.weight(.semibold))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    // MARK: - Benefits

    /// The benefits, on the page itself rather than in a card.
    ///
    /// A row of chips since 2026-11-22, not three icon rows: with the preview
    /// card above and the plan below, the rows made three stacked lists of
    /// the same weight and the page read as crowded. Tonal, not white — white
    /// is the plan card's, the one thing here you can choose.
    private var featureList: some View {
        ChipFlow(spacing: Theme.Spacing.s) {
            ForEach(PremiumBenefit.all) { benefit in
                Text(benefit.short)
                    .font(.footnote.weight(.medium))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(Color.primary.opacity(0.07), in: .capsule)
                    .accessibilityLabel(benefit.title)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var premiumBadge: some View {
        Label("You're Premium — thank you!", systemImage: "checkmark.seal.fill")
            .font(.headline)
            .foregroundStyle(.green)
            .padding(.vertical, Theme.Spacing.l)
    }

    /// Loading spinner while products fetch; a retry card if the fetch failed.
    @ViewBuilder private var productsPlaceholder: some View {
        VStack(spacing: Theme.Spacing.m) {
            if store.productsLoadFailed {
                Label("Couldn't load plans", systemImage: "wifi.exclamationmark")
                    .font(.headline)
                Text("Check your connection and try again.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Retry") {
                    Task { await store.refresh() }
                }
                .buttonStyle(.borderedProminent)
            } else {
                ProgressView("Loading plans…")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.Spacing.xl)
        .elevatedCard()
    }

    // MARK: - Plans

    /// The subscriptions as a radio group, stacked, with the lifetime unlock
    /// demoted to a line beneath them (design canvas, 2026-10-24).
    ///
    /// They sat side by side for a while, as one comparison. At a phone's
    /// width each card then stacked five lines — badge, name, price, per-week,
    /// saving — and the unchosen price went grey, which read as disabled. One
    /// row per plan says the whole offer in a line: what it's called, and
    /// what it costs and when.
    private var plans: some View {
        VStack(spacing: tight ? Theme.Spacing.s : Theme.Spacing.s + 2) {
            // Two cards, Yearly first and selected (2026-11-22, at Sambulo's
            // request). Monthly was a quiet link under one card for two
            // weeks; as a card it shows the price Yearly's saving is
            // measured against. The trial tag, the saving and the ink
            // border keep the choice from reading as even.
            if let yearly = subscriptionProducts.first(where: { $0.id == StoreService.yearlyID }) {
                planRow(yearly)
            }
            if let monthly = subscriptionProducts.first(where: { $0.id == StoreService.monthlyID }) {
                planRow(monthly)
            }
            if let lifetime = store.products.first(where: { $0.id == StoreService.lifetimeID }) {
                lifetimeLink(lifetime)
            }
        }
        // Spring the selection between plans instead of snapping.
        .animation(.snappy(duration: 0.2), value: selectedID)
        .sensoryFeedback(.selection, trigger: selectedID)
    }

    /// Yearly and monthly, in that order — never lifetime, which has its own line.
    private var subscriptionProducts: [Product] {
        store.products.filter { $0.id != StoreService.lifetimeID }
    }

    private func planRow(_ product: Product) -> some View {
        let selected = product.id == selectedID
        return Button {
            selectedID = product.id
        } label: {
            HStack(spacing: Theme.Spacing.m) {
                selectionMark(selected)
                // The price on the card's right edge, the line under the
                // name wrapping if it must (a 17e has ~190pt for it). At
                // accessibility sizes the price goes under the name instead:
                // there's no width for a column beside it.
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 1) {
                        planHeading(product)
                        planSubtitle(product)
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    HStack(alignment: .center, spacing: Theme.Spacing.s) {
                        VStack(alignment: .leading, spacing: 2) {
                            planHeading(product)
                            if let note = planNote(product) {
                                Text(note)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer(minLength: Theme.Spacing.s)
                        planPrice(product)
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .planChrome(selected: selected)
            .overlay(alignment: .topTrailing) {
                if let save = savingsPercent(product) {
                    savingsBadge(save)
                        .offset(x: -Theme.Spacing.m, y: -9)
                }
            }
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    /// The plan's name and its trial tag, when this Apple ID can still take
    /// the trial. Until 2026-11-22 the card never said a trial existed — only
    /// the button and the small line under it did — and the tap rate fell
    /// from 13% to 5% when the trial went from 7 days to 3. The saving has
    /// its own badge on the card's corner (`savingsBadge`).
    ///
    /// Side by side where they fit, the tag under the name where they don't.
    /// In one row on a 375pt phone the tag kept its width and the name gave
    /// way, breaking as "Yearl / y" and "Monthl / y" (iPhone SE, 2026-11-24).
    private func planHeading(_ product: Product) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Theme.Spacing.s) { planHeadingParts(product) }
            VStack(alignment: .leading, spacing: 3) { planHeadingParts(product) }
        }
    }

    @ViewBuilder
    private func planHeadingParts(_ product: Product) -> some View {
        Text(planTitle(product))
            .font(.headline)
            .lineLimit(1)
            .fixedSize()
        if let tag = planTag(product) {
            Text(tag)
                .font(.caption.weight(.bold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .foregroundStyle(Theme.onInk)
                .background(Theme.ink, in: .capsule)
                .fixedSize()
        }
    }

    private func planTag(_ product: Product) -> String? {
        store.introOffer(for: product).map { "\($0.duration) free" }
    }

    /// The line under the name in the wide layout: what happens after the
    /// trial — "3 days free, then billed yearly", "Then $4.99/month" — or,
    /// with no trial, how the plan bills.
    private func planNote(_ product: Product) -> String? {
        let trial = store.introOffer(for: product)
        switch product.id {
        case StoreService.yearlyID:
            return trial.map { "\($0.duration) free, then billed yearly" } ?? "Billed yearly"
        case StoreService.monthlyID:
            return trial == nil ? "Billed monthly" : "Then \(product.displayPrice)/month"
        default:
            return nil
        }
    }

    /// "SAVE 83%" on the card's top-right corner, half over its edge, in the
    /// Premium chip's gold. Yearly against twelve months of Monthly.
    private func savingsBadge(_ percent: Int) -> some View {
        Text("SAVE \(percent)%")
            .font(.caption2.weight(.heavy))
            .tracking(0.3)
            // Fixed near-black: the badge is gold in both appearances, as
            // the Premium chip is.
            .foregroundStyle(Color(white: 0.1))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Theme.badgeRim, in: .capsule)
            .fixedSize()
            .accessibilityLabel("Save \(percent)%")
    }

    /// The price, on the card's right edge. The billed amount leads and is
    /// the heavier of the two; the per-month figure is smaller and secondary
    /// (Guideline 3.1.2, as `planSubtitle`).
    private func planPrice(_ product: Product) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text("\(product.displayPrice)\(store.periodText(for: product) ?? "")")
                .font(.subheadline.weight(.semibold))
            if product.id == StoreService.yearlyID {
                Text("only \((product.price / 12).formatted(product.priceFormatStyle))/month")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .fixedSize()
    }

    /// Lifetime, as a line under the plans rather than a third card. At about
    /// two years of the yearly plan it's a real choice, not a decoy — it stays
    /// selectable and keeps its own price — but few take it, and a third card
    /// asked everyone to rank three things before they could do anything.
    private func lifetimeLink(_ product: Product) -> some View {
        let selected = product.id == selectedID
        return Button {
            selectedID = product.id
        } label: {
            HStack(spacing: Theme.Spacing.s) {
                if selected {
                    selectionMark(true)
                        .font(.subheadline)
                }
                Text("Or pay once — \(product.displayPrice) forever")
                    .font(.subheadline.weight(selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Color.primary : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    /// The one mark every option on this page uses to say "this is the one":
    /// a filled ink disc with the check knocked out, or an empty ring.
    @ViewBuilder
    private func selectionMark(_ selected: Bool) -> some View {
        // A radio: a ring, with the dot in it when chosen (2026-11-22, as the
        // example paywall draws it). Sized off the text, so it scales.
        ZStack {
            Circle()
                .strokeBorder(selected ? Theme.ink : Color(.tertiaryLabel), lineWidth: selected ? 2 : 1.5)
            if selected {
                Circle()
                    .fill(Theme.ink)
                    .padding(5)
            }
        }
        .frame(width: radioSize, height: radioSize)
        .accessibilityHidden(true)
    }

    // MARK: - Plan copy

    private func planTitle(_ product: Product) -> String {
        PremiumOfferView.planTitle(product)
    }

    /// The plan's name, as both surfaces' analytics label it. Static so the CTA
    /// outside this view can name the plan it is about to buy without
    /// duplicating the mapping.
    static func planTitle(_ product: Product) -> String {
        switch product.id {
        case StoreService.yearlyID: return "Yearly"
        case StoreService.monthlyID: return "Monthly"
        default: return "Lifetime"
        }
    }

    /// The CTA label for a plan.
    ///
    /// Names the thing being started, never the transaction: "Subscribe"
    /// describes what the player gives up, while the trial length and the
    /// puzzle count describe what they get. The renewal terms are stated in
    /// full directly underneath either way — see `commitmentText`.
    ///
    /// Static, and shared, because the button sits outside this view on both
    /// surfaces and they had already ended up saying different things: the
    /// sheet named the puzzle count, onboarding said a flat "Unlock Premium",
    /// and neither could say "Unlock Lifetime" on the plan the other couldn't
    /// sell.
    ///
    /// "Try 7 days free" since 2026-10-24, as the design has it and as the
    /// upsell cards already said: the trial's length is the offer, and three
    /// words of it fit where "Start 7-day free trial" needed five.
    static func ctaTitle(for product: Product?, store: StoreService, puzzleCount: Int) -> String {
        guard let product else { return "Continue" }
        // What it costs to tap, as a number (2026-11-22). The trial's length
        // is on the plan card and in the terms under this button; said here
        // too ("Start my 3-day free trial") it was the page's third telling.
        if store.introOffer(for: product) != nil {
            return "Try for \(Decimal.zero.formatted(product.priceFormatStyle))"
        }
        if store.periodText(for: product) != nil { return "Unlock everything" }
        return "Unlock Lifetime"
    }

    /// The one-line disclosure under the CTA: exactly what the player is
    /// committing to, restated at the commit point where purchase anxiety
    /// peaks.
    ///
    /// Onboarding used to carry a shorter version of this that never said when
    /// money starts or that the charge repeats. Same offer, same words now.
    static func commitmentText(for product: Product?, store: StoreService) -> String? {
        guard let product else { return nil }
        let period = store.periodText(for: product) ?? ""
        // What App Review asks for at the buy button: when the charge starts,
        // the price, and that it renews. The reassurance that led this line
        // ("No charge for 3 days") sits above the button since 2026-11-22 —
        // see `PremiumReassurance` — so this is the terms alone.
        if let offer = store.introOffer(for: product) {
            return "\(offer.duration) free, then \(product.displayPrice)\(period). Renews automatically."
        }
        if !period.isEmpty {
            return "\(product.displayPrice)\(period). Renews automatically."
        }
        return "One-time purchase — yours forever."
    }

    /// The terms under the buy button on the paywall and onboarding's offer:
    /// `commitmentText`, plus where and when to cancel a subscription
    /// (2026-11-22, as the example paywall states it).
    static func buyTerms(for product: Product?, store: StoreService) -> String? {
        guard let terms = commitmentText(for: product, store: store) else { return nil }
        guard let product, store.periodText(for: product) != nil else { return terms }
        return terms + " Cancel anytime in Settings at least 24 hours before renewal."
    }

    /// The line under a plan's name: what it costs and when. Yearly with a
    /// trial says both halves of the offer — "$9.99 a year after 7 days free" —
    /// so the plan you're choosing states the trial where you choose it.
    /// The trial is the button's to say, so the rows carry the price — and
    /// the yearly row the deal, what it comes to a month.
    ///
    /// The billed amount leads, in primary ink; the per-month figure follows,
    /// secondary. Guideline 3.1.2: the amount actually charged must be the
    /// clearest price, a calculated monthly one subordinate to it.
    private func planSubtitle(_ product: Product) -> Text {
        let billed = Text("\(product.displayPrice) \(periodPhrase(product))")
        if product.id == StoreService.yearlyID {
            let perMonth = (product.price / 12).formatted(product.priceFormatStyle)
            return billed.foregroundStyle(.primary)
                + Text(" · \(perMonth)/month").foregroundStyle(.secondary)
        }
        return billed.foregroundStyle(.secondary)
    }

    /// Yearly against twelve months of Monthly, rounded down.
    private func savingsPercent(_ product: Product) -> Int? {
        guard product.id == StoreService.yearlyID,
              let monthly = store.products.first(where: { $0.id == StoreService.monthlyID }) else { return nil }
        let full = NSDecimalNumber(decimal: monthly.price * 12).doubleValue
        let paid = NSDecimalNumber(decimal: product.price).doubleValue
        guard full > 0, paid < full else { return nil }
        return Int((1 - paid / full) * 100)
    }

    /// "a year" / "a month", for a sentence rather than a price tag.
    private func periodPhrase(_ product: Product) -> String {
        switch product.id {
        case StoreService.yearlyID: "a year"
        case StoreService.monthlyID: "a month"
        default: ""
        }
    }
}



// MARK: - Chips

/// Lays chips out in a row and wraps to the next when the width runs out
/// (large text, a narrow cover screen).
private struct ChipFlow: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        return CGSize(width: rows.width, height: rows.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(subviews, width: bounds.width)
        for (subview, point) in zip(subviews, rows.points) {
            subview.place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y),
                          proposal: .unspecified)
        }
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> (points: [CGPoint], width: CGFloat, height: CGFloat) {
        var points: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            points.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return (points, widest, y + rowHeight)
    }
}

// MARK: - Reassurance

/// What the player is not committing to, said directly above the button that
/// commits them: nothing to pay today when the plan has a trial this Apple ID
/// can take, and that a subscription can be cancelled.
///
/// Both surfaces draw it over their own button, like `ctaTitle` and
/// `commitmentText`. Before 2026-11-22 "No charge for 3 days" was the opening
/// of the small grey terms line under the button, and cancelling wasn't said
/// at all (cut 2026-10-24, when it closed that line as "until you cancel").
/// Here it's a reassurance beside the action, not the last word of the terms.
///
/// Nothing for a one-time purchase: neither line is true of it.
struct PremiumReassurance: View {
    let product: Product?
    @Environment(StoreService.self) private var store

    var body: some View {
        if let product, store.periodText(for: product) != nil {
            // Side by side, or one under the other when the width or the
            // text size doesn't allow it.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Theme.Spacing.m) { items(product) }
                VStack(spacing: Theme.Spacing.xs) { items(product) }
            }
            .font(.footnote.weight(.medium))
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private func items(_ product: Product) -> some View {
        if store.introOffer(for: product) != nil {
            item("No payment now")
        }
        item("Cancel anytime")
    }

    private func item(_ text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "checkmark")
                .font(.caption.weight(.bold))
                .accessibilityHidden(true)
            Text(text)
        }
        .fixedSize()
    }
}

// MARK: - The offer button's shine

/// One light sweep across the offer's button after the page settles — a
/// glance toward the action, once, never a loop. Skipped under Reduce Motion.
private struct PremiumShine: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { proxy in
                    LinearGradient(
                        colors: [.clear, .white.opacity(0.32), .clear],
                        startPoint: .leading, endPoint: .trailing
                    )
                    .frame(width: proxy.size.width * 0.35)
                    .offset(x: phase * proxy.size.width * 1.4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .clipShape(.capsule)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            .task {
                guard !reduceMotion else { return }
                try? await Task.sleep(for: .seconds(1.2))
                withAnimation(.easeInOut(duration: 0.9)) { phase = 1 }
            }
    }
}

extension View {
    /// The offer button's one-time shine and its purchase-start haptic.
    func premiumOfferButton(purchasing: Bool) -> some View {
        modifier(PremiumShine())
            .controlSize(.large)
            .sensoryFeedback(.impact(weight: .medium), trigger: purchasing) { _, started in started }
    }
}
