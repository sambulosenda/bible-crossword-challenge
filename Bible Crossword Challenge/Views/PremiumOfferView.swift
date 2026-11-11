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

    @Environment(StoreService.self) private var store
    @Environment(\.puzzleProvider) private var puzzleProvider
    /// The preview card in view, for the page dots.
    @State private var previewID: String?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
            if dynamicTypeSize.isAccessibilitySize, let first = previews.first {
                // One card at its own height: the carousel's fixed height
                // cut the text off at these sizes.
                staggered(previewCard(first, fills: false, blurbLines: nil), delay: 0.07)
            } else if !previews.isEmpty {
                staggered(previewCarousel, delay: 0.07)
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
                    Text(PremiumCopy.sheetHeadline)
                        .font(.scripture(.largeTitle, weight: .semibold))
                        .tracking(-0.4)
                        .fixedSize(horizontal: false, vertical: true)
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
        }
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
    /// to two Premium packs (in-season first), as swipeable cards. Replaces
    /// the cropped cover fan (design pass, 2026-11).
    private struct Preview: Identifiable {
        let id: String
        let kicker: String
        let title: String
        let blurb: String
        let symbol: String
        let accent: Color
    }

    private var previews: [Preview] {
        var cards: [Preview] = []
        if let quest = puzzleProvider.quests.first(where: \.isPremium) {
            cards.append(Preview(id: "quest-\(quest.id)", kicker: "Journey · \(quest.puzzleIDs.count) steps",
                                 title: quest.title, blurb: quest.blurb,
                                 symbol: quest.coverSymbol, accent: quest.accent))
        }
        // Not a pack that ships as a Journey (Today's rule): Life of David
        // is both, and the card would show it twice.
        let packs = PuzzlePack.notShadowedByQuests(
            puzzleProvider.availablePacks(), quests: puzzleProvider.quests
        ).filter(\.isPremium)
        let ordered = packs.filter(\.isSeasonal) + packs.filter { !$0.isSeasonal }
        for pack in ordered.prefix(2) {
            cards.append(Preview(id: "pack-\(pack.id)", kicker: "Pack · \(pack.puzzleIDs.count) puzzles",
                                 title: pack.title, blurb: pack.blurb,
                                 symbol: pack.coverSymbol, accent: pack.accent))
        }
        return cards
    }

    private var previewCarousel: some View {
        // A paging scroll view, not a page-style TabView: that clipped the
        // cards' top edge and drew white dots on a white page. Width from a
        // GeometryReader, not containerRelativeFrame, which sticks at the
        // open width after an iPhone Duo fold.
        VStack(spacing: Theme.Spacing.s) {
            // The tallest card sets the height, at any text size: the cards
            // laid out unseen, the scroll view over them. A fixed 104/116 was
            // shorter than the card's own text in the compact layout, and the
            // scroll view cut all four corners off it (2026-11-11).
            ZStack {
                ForEach(previews) { card in
                    previewCard(card, fills: false)
                }
            }
            .hidden()
            .accessibilityHidden(true)
            .overlay {
                GeometryReader { proxy in
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: 0) {
                            ForEach(previews) { card in
                                previewCard(card)
                                    .frame(width: proxy.size.width, height: proxy.size.height)
                                    .id(card.id)
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollTargetBehavior(.paging)
                    .scrollIndicators(.hidden)
                    .scrollPosition(id: $previewID)
                }
            }
            if previews.count > 1 {
                HStack(spacing: 6) {
                    ForEach(previews) { card in
                        Circle()
                            .fill((previewID ?? previews.first?.id) == card.id ? Theme.ink : Color(.tertiaryLabel))
                            .frame(width: 6, height: 6)
                    }
                }
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)
            }
        }
    }

    /// `fills` stretches the card to the height it is given (the carousel's
    /// pages, so they match); without it the card takes its own height.
    /// `blurbLines` is nil only for the single card at accessibility sizes.
    private func previewCard(_ card: Preview, fills: Bool = true, blurbLines: Int? = 2) -> some View {
        HStack(spacing: Theme.Spacing.m) {
            Image(systemName: card.symbol)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 72, height: 72)
                .background(card.accent.gradient, in: .rect(cornerRadius: 18, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(card.kicker)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(card.title)
                    .font(.title3.weight(.semibold))
                Text(card.blurb)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(blurbLines)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Spacing.m)
        // 10pt in the compact layouts: the text then comes to the 104pt the
        // short page budgets for the card, with the cover still 16pt in.
        .padding(.vertical, compact ? Theme.Spacing.s + 2 : Theme.Spacing.m)
        .frame(maxWidth: .infinity, maxHeight: fills ? .infinity : nil, alignment: .leading)
        .background(Theme.surface, in: .rect(cornerRadius: Theme.cornerRadius, style: .continuous))
        .accessibilityElement(children: .combine)
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
    ]

    private var comparison: some View {
        Grid(alignment: .leading, horizontalSpacing: Theme.Spacing.m, verticalSpacing: Theme.Spacing.s + 2) {
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
    /// They were boxed once because, loose on the canvas, three wrapped
    /// two-line rows read as a wall of text. The rows are one line each now
    /// (see `PremiumBenefit`), and the box had become one of five on the page —
    /// so many that the two plan cards, the only things here you can choose,
    /// no longer stood out. Inset to the plan cards' content edge, so the page
    /// still has one left edge.
    ///
    /// Each row leads with the app's 36pt icon square in neutral (2026-10-24),
    /// as Today's lists draw theirs: bare glyphs of different weights read as
    /// an uneven column. Neutral, not tinted: blue means "you can tap this"
    /// and these are not.
    private var featureList: some View {
        // Tighter when the page is short: on a 17e sheet these gaps were part
        // of what the chip and the fan needed (2026-10-24, measured 5pt short).
        VStack(alignment: .leading, spacing: tight ? Theme.Spacing.s : (compact ? Theme.Spacing.s + 2 : Theme.Spacing.m)) {
            ForEach(PremiumBenefit.all) { benefit in
                HStack(spacing: Theme.Spacing.m) {
                    RowIcon(symbol: benefit.icon, tint: Theme.accent)
                    Text(benefit.title)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .environment(\.rowIconsNeutral, true)
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
            // One plan in focus: Yearly as the card, Monthly a quiet link
            // under it (design pass, 2026-11) — two equal cards made the
            // choice look even when the deal isn't.
            if let yearly = subscriptionProducts.first(where: { $0.id == StoreService.yearlyID }) {
                planRow(yearly)
            }
            if let monthly = subscriptionProducts.first(where: { $0.id == StoreService.monthlyID }) {
                monthlyLink(monthly)
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
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: Theme.Spacing.s) {
                        Text(planTitle(product))
                            .font(.headline)
                        if let save = savingsPercent(product) {
                            Text("Save \(save)%")
                                .font(.caption.weight(.bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .foregroundStyle(Theme.onInk)
                                .background(Theme.ink, in: .capsule)
                        }
                    }
                    planSubtitle(product)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .planChrome(selected: selected)
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    /// Lifetime, as a line under the plans rather than a third card. At about
    /// two years of the yearly plan it's a real choice, not a decoy — it stays
    /// selectable and keeps its own price — but few take it, and a third card
    /// asked everyone to rank three things before they could do anything.
    private func monthlyLink(_ product: Product) -> some View {
        let selected = product.id == selectedID
        return Button {
            selectedID = product.id
        } label: {
            HStack(spacing: Theme.Spacing.s) {
                if selected {
                    selectionMark(true)
                        .font(.subheadline)
                }
                Text("Or monthly — \(product.displayPrice) a month")
                    .font(.subheadline.weight(selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Color.primary : Color.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

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
        if selected {
            Image(systemName: "checkmark.circle.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(Theme.onInk, Theme.ink)
                .font(.title3)
        } else {
            Image(systemName: "circle")
                .foregroundStyle(.tertiary)
                .font(.title3)
        }
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
        // First person, naming the trial (design pass, 2026-11): the button
        // says what the player is starting, in their voice.
        if let offer = store.introOffer(for: product) { return "Start my \(offer.trialText)" }
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
        // the price, and that it renews. Nothing about cancelling (2026-10-24):
        // a line ending "until you cancel" read as an invitation to, and the
        // app sends no trial-ending reminder for the same reason.
        if let offer = store.introOffer(for: product) {
            // When the charge starts, the price, that it renews (App Review),
            // led by the reassurance rather than buried after the trial.
            return "No charge for \(offer.duration). Then \(product.displayPrice)\(period), renews automatically."
        }
        if !period.isEmpty {
            return "\(product.displayPrice)\(period). Renews automatically."
        }
        return "One-time purchase — yours forever."
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
            .sensoryFeedback(.impact(weight: .medium), trigger: purchasing) { _, started in started }
    }
}
