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
    /// The promise, chosen by the surface presenting it.
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

    /// Onboarding's hero, in its own tiles: the word the player just solved,
    /// so the ask continues the solve instead of interrupting it. The sheet
    /// draws `PremiumCoverFan` instead — see `offerHeader`.
    var heroTiles: [[MiniTile]] = MiniCrossword.faithHopeLove
    /// Cells of `heroTiles` to draw with the gold rim — the solved word.
    var heroCelebrated: Set<MiniPoint> = []


    /// Drops the decoration — the tiles and the kicker — for a screen the
    /// whole offer doesn't fit. Each surface offers both sizes to a
    /// `ViewThatFits` and lets layout pick: on a 667pt iPhone SE the full page
    /// pushed the prices and the timeline behind the purchase button, and the
    /// price is the one thing that must be on screen when the button is.
    /// Nothing that describes the offer is ever dropped, only what decorates it.
    var compact: Bool = false

    /// Keeps a smaller hero in the compact layout. The sheet offers it as a
    /// middle size: on a 6.3" phone the full hero missed by a few dozen points
    /// and the compact page left that room empty above the headline.
    var keepsSmallHero: Bool = false

    /// Onboarding's version of the offer: no kicker and no hints row. The
    /// solved word in gold already names the page, and a first-run player has
    /// never been refused a hint — see `PremiumBenefit.all`. Median time on
    /// that page is five seconds, so each cut block is one the headline and
    /// the plans no longer compete with.
    var firstRun: Bool = false

    @Environment(StoreService.self) private var store
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion


    var body: some View {
        // Three groups, spaced as groups: what this is, what you get, what
        // you pay. Tight inside each, open between them — one uniform gap
        // made every block on the page look equally related to every other.
        // A step tighter in the compact layout: on a 667pt iPhone SE the
        // group gaps were the ~24pt that left the trial timeline's last line
        // under the pinned button.
        VStack(alignment: .leading, spacing: compact && !keepsSmallHero ? Theme.Spacing.l : Theme.Spacing.xl) {
            if firstRun {
                VStack(spacing: Theme.Spacing.m) {
                    if !compact || keepsSmallHero {
                        staggered(hero, delay: 0)
                    }
                    staggered(headlineBlock, delay: 0.05)
                }
                .frame(maxWidth: .infinity)
            } else {
                staggered(offerHeader, delay: 0)
            }
            staggered(featureList, delay: 0.14)

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

    // MARK: - Hero

    /// Until this view had one, the page that asks for money was the only
    /// onboarding page with no tiles on it — five boxes of text straight after
    /// the solved word glowing gold. Small, so it costs the page less than the
    /// benefits card it replaced did.
    ///
    /// Cascades in on the sheet, which has no entrance of its own; onboarding's
    /// stagger already carries it there, and both at once would double up.
    private var hero: some View {
        MiniCrossword(
            layout: heroTiles,
            celebrated: heroCelebrated,
            animatesIn: entranceActive == nil,
            tileSide: heroTileSide
        )
        .padding(.top, Theme.Spacing.xs)
    }

    /// One footprint whichever fragment is drawn: the three-row solve gets
    /// bigger tiles than the four-row FAITH/HOPE/LOVE, so both stand about
    /// 105–125pt tall and neither page gives the hero more room than the
    /// other.
    private var heroTileSide: CGFloat {
        if compact && keepsSmallHero { return heroTiles.count > 3 ? 20 : 24 }
        return heroTiles.count > 3 ? 28 : 32
    }

    // MARK: - Header

    /// The sheet's header, as the design canvas draws it (2026-10-24): the
    /// gold chip over a large serif promise on the left, a fan of locked pack
    /// covers on the right, one line under both. Left-aligned on the page's
    /// one edge, like every other screen; the centred stack it replaced was
    /// the only centred page in the app.
    ///
    /// The fan is what Premium opens, where the FAITH/HOPE/LOVE tiles were
    /// decoration. It goes in the tightest layout and at accessibility sizes,
    /// where the promise needs the width.
    private var offerHeader: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s + Theme.Spacing.xs) {
            HStack(alignment: .bottom, spacing: Theme.Spacing.s) {
                VStack(alignment: .leading, spacing: Theme.Spacing.s + Theme.Spacing.xs) {
                    if !compact || keepsSmallHero {
                        PremiumChip()
                    }
                    Text(headline)
                        .font(.scripture(.largeTitle, weight: .semibold))
                        .tracking(-0.4)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                }
                Spacer(minLength: 0)
                if (!compact || keepsSmallHero) && !dynamicTypeSize.isAccessibilitySize {
                    PremiumCoverFan(leadingPackID: highlightedPackID, scale: compact ? 0.8 : 1)
                }
            }
            // The same line with or without a trial: it says what Premium is
            // for, and "after today's puzzle" already tells a player the daily
            // stays free.
            Text(PremiumCopy.subhead)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Onboarding's headline: centred under the solved word.
    private var headlineBlock: some View {
        VStack(spacing: Theme.Spacing.s) {
            // `.title`, not `.largeTitle`: with the tiles above it the
            // headline is no longer the only thing announcing the page, and
            // at the larger size it ran to three heavy lines that pushed the
            // plans toward the button.
            Text(headline)
                .font(.scripture(.title, weight: .semibold))
                .multilineTextAlignment(.center)

            // Only the no-trial path gets a subhead. When a trial exists the
            // page already states it three times — the timeline, the CTA and
            // the commitment line — and the fourth copy up here was the
            // weakest of them: an adjective ("3-day free trial") where the
            // timeline below answers the actual question, which is when money
            // starts. A player with no trial left still needs something above
            // the fold about what costs nothing, so the free tier keeps its
            // line.
            if trialText == nil {
                Text(PremiumCopy.freeDailyReassurance)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
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
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            ForEach(PremiumBenefit.all(firstRun: firstRun)) { benefit in
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
        VStack(spacing: Theme.Spacing.s + 2) {
            ForEach(subscriptionProducts, id: \.id) { product in
                planRow(product)
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
                    Text(planTitle(product))
                        .font(.headline)
                    Text(planSubtitle(product))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
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
        if let offer = store.introOffer(for: product) { return "Try \(offer.duration) free" }
        if store.periodText(for: product) != nil { return "Unlock \(puzzleCount) puzzles" }
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
        if store.introOffer(for: product) != nil {
            // "Nothing charged today" leads (design canvas, 2026-10-24): it is
            // the question a trial-sceptic is asking at the button. Only ever
            // on this path — a player whose trial is spent is charged today.
            // The rest keeps what App Review asks for at the buy button: the
            // price after the trial, that it renews, and how to stop it. The
            // trial's length is on the button and the selected plan's row.
            return "Nothing charged today. Then \(product.displayPrice)\(period) until you cancel in Settings."
        }
        if !period.isEmpty {
            return "Auto-renews at \(product.displayPrice)\(period) until cancelled. Cancel anytime in Settings."
        }
        return "One-time purchase — yours forever."
    }

    /// The line under a plan's name: what it costs and when. Yearly with a
    /// trial says both halves of the offer — "$9.99 a year after 7 days free" —
    /// so the plan you're choosing states the trial where you choose it.
    private func planSubtitle(_ product: Product) -> String {
        let price = "\(product.displayPrice) \(periodPhrase(product))"
        if let offer = store.introOffer(for: product) {
            return "\(price) after \(offer.duration) free"
        }
        return price
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

