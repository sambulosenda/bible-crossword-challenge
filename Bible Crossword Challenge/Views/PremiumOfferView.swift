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
    /// The shared look of a thing you can pick on this page: a tinted, accented
    /// card when it's the one, an outline on bare paper when it isn't.
    ///
    /// Unselected plans used to be filled with `Theme.surface` — the same white
    /// as the benefits card directly above them. Two blocks in the same material
    /// read as two blocks of the same kind, so the monthly card looked like more
    /// information rather than the other half of a choice. Outlining them
    /// instead leaves exactly one white card on the page (the benefits) and
    /// makes every bordered thing below it something you can tap.
    func planChrome(selected: Bool) -> some View {
        background(selected ? Theme.accent.opacity(0.12) : .clear,
                   in: .rect(cornerRadius: Theme.cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .strokeBorder(selected ? Theme.accent : Color(.separator),
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

    /// The player's own progress, when the surface has any worth stating.
    ///
    /// Nil during onboarding: the most they can have solved by then is the
    /// tutorial clue, and a tally of one reads as a tally of nothing.
    var progressLine: String? = nil

    /// Which plan is selected.
    ///
    /// Owned by the caller because on both surfaces the CTA that acts on it
    /// sits outside this view — pinned to the sheet's bottom edge, or down in
    /// onboarding's shared controls row.
    @Binding var selectedID: String

    /// When non-nil, the blocks fade in on a stagger, as onboarding's other
    /// pages do. Nil on the sheet, which is already an animated presentation.
    var entranceActive: Bool? = nil

    @Environment(StoreService.self) private var store
    @Environment(\.puzzleProvider) private var puzzleProvider
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ScaledMetric(relativeTo: .body) private var checkSize: CGFloat = 22

    var body: some View {
        VStack(spacing: Theme.Spacing.m) {
            staggered(headlineBlock, delay: 0.05)
            staggered(featureList, delay: 0.14)

            if store.isPremium {
                premiumBadge
            } else if store.products.isEmpty {
                productsPlaceholder
            } else {
                staggered(plans, delay: 0.20)
                staggered(trialTimeline, delay: 0.26)
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

    // MARK: - Headline

    private var headlineBlock: some View {
        VStack(spacing: Theme.Spacing.s) {
            // The eyebrow carries the fact, the headline carries the reason.
            // Putting a number in both just says the same thing twice.
            Text("Premium · \(puzzleProvider.totalPuzzleCount) puzzles")
                .kicker()
            Text(headline)
                .font(.scripture(.largeTitle, weight: .semibold))
                .multilineTextAlignment(.center)

            // The offer above the benefits, not only down on the button: a
            // player deciding whether to read on shouldn't have to look at the
            // CTA to find out that today costs nothing.
            //
            // The no-trial path states what stays free instead. That fallback
            // used to be onboarding's alone, and the sheet had nothing at all
            // above the fold for a player who'd already used their trial — the
            // free tier is the reason the ask can stay soft, so it's worth
            // saying on both.
            Group {
                if let trial = trialText {
                    PremiumCopy.trialSubhead(trial)
                } else {
                    Text(PremiumCopy.freeDailyReassurance)
                        .foregroundStyle(.secondary)
                }
            }
            .font(.subheadline.weight(.medium))
            .multilineTextAlignment(.center)

            if let progressLine {
                Text(progressLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    /// The yearly plan's introductory offer, when there is one and the player
    /// hasn't already used theirs.
    private var trialText: String? {
        guard let yearly = store.yearly else { return nil }
        return store.introOfferText(for: yearly)
    }

    // MARK: - Benefits

    /// The benefits, grouped into one surface rather than floating on the page.
    /// Loose on the canvas they read as an unbroken wall of text; bounding them
    /// makes the list a single object the eye can skip past on the way to the
    /// price.
    ///
    /// One line per row — see `PremiumBenefit`. `.top` alignment stays for the
    /// accessibility sizes where a row does wrap, so the disc sits beside the
    /// first line rather than floating in the middle of two.
    private var featureList: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            ForEach(PremiumBenefit.all(
                puzzleCount: puzzleProvider.totalPuzzleCount,
                packCount: puzzleProvider.packs.filter(\.isPremium).count
            )) { benefit in
                HStack(alignment: .top, spacing: Theme.Spacing.m) {
                    // Accent, not green: green means "solved" everywhere else
                    // in the app, and it shouldn't also mean "included".
                    // The disc scales with the label: at a fixed size the glyph
                    // outgrew it at accessibility sizes and spilled over.
                    Image(systemName: benefit.icon)
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(Theme.accent)
                        .frame(width: checkSize, height: checkSize)
                        .background(Theme.accent.opacity(0.12), in: .circle)
                    Text(benefit.title)
                        .font(.body.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.m)
        .elevatedCard()
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

    /// The two subscriptions side by side, with the lifetime unlock demoted to
    /// a line beneath them.
    ///
    /// Three equal-weight rows made the player rank three things before they
    /// could do anything, and pushed the price itself below the fold. Two
    /// columns turn it into one comparison — which is the only question most
    /// people are actually asking — and lifetime stays reachable for the few
    /// who want it without competing for the same attention.
    private var plans: some View {
        VStack(spacing: Theme.Spacing.s) {
            // AnyLayout rather than a branch on the view itself, so selection
            // keeps its identity (and its animation) across the switch.
            let layout = stacksPlans
                ? AnyLayout(VStackLayout(spacing: Theme.Spacing.s))
                : AnyLayout(HStackLayout(alignment: .top, spacing: Theme.Spacing.s))
            layout {
                ForEach(subscriptionProducts, id: \.id) { product in
                    planCard(product)
                }
            }
            if let lifetime = store.products.first(where: { $0.id == StoreService.lifetimeID }) {
                lifetimeRow(lifetime)
            }
        }
        // Room for the savings pill, which straddles the yearly card's top edge
        // rather than sitting inside it. Without this it would ride up into the
        // benefits card above. Stacked, the pill is back in the flow and there
        // is nothing hanging over the edge to make room for.
        .padding(.top, stacksPlans ? 0 : 10)
        // Spring the selection between plans instead of snapping.
        .animation(.snappy(duration: 0.2), value: selectedID)
    }

    /// Yearly and monthly, in that order — never lifetime, which has its own row.
    private var subscriptionProducts: [Product] {
        store.products.filter { $0.id != StoreService.lifetimeID }
    }

    private func planCard(_ product: Product) -> some View {
        let selected = product.id == selectedID
        return Button {
            selectedID = product.id
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                // Stacked, the badge is just the card's first line. It costs a
                // row, but only on the card that has one to show — full-width
                // cards don't share a baseline, so monthly needs no phantom
                // copy to stay level with yearly.
                if stacksPlans, let text = badgeText(product) {
                    savingsPill(text)
                }
                // The same mark the lifetime row below has always used. The two
                // used to speak different languages — cards signalled selection
                // with a tint and a border, the row with a radio — so one screen
                // asked the player to learn "selected" twice.
                HStack(spacing: 6) {
                    selectionMark(selected)
                    Text(planTitle(product))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                Text(planPrice(product))
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(planFootnote(product))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.m)
            .planChrome(selected: selected)
            // The pill straddles the top edge instead of occupying a row inside
            // the card. As a row it had to be laid out on *both* cards — an
            // invisible copy on monthly — just to keep their baselines level,
            // which cost each card a line to say nothing on one of them. On the
            // border it costs no height at all, and the cards match by default.
            .overlay(alignment: .top) { straddlingBadge(product) }
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    /// Lifetime, priced against the subscription rather than presented as a
    /// peer of it. At roughly two years of the yearly plan it's a real choice,
    /// not a decoy — so it stays selectable and keeps its own price.
    private func lifetimeRow(_ product: Product) -> some View {
        let selected = product.id == selectedID
        return Button {
            selectedID = product.id
        } label: {
            HStack(spacing: Theme.Spacing.s) {
                selectionMark(selected)
                Text("Or pay once — \(product.displayPrice) forever")
                    .font(.subheadline.weight(selected ? .semibold : .regular))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.vertical, Theme.Spacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Same chrome as the cards above. Unselected it used to be bare
            // paper with no edge at all, so until you tapped it the third option
            // read as a caption about the other two rather than a third choice.
            .planChrome(selected: selected)
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    /// The one mark every option on this page uses to say "this is the one".
    private func selectionMark(_ selected: Bool) -> some View {
        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
            .font(.subheadline)
            .foregroundStyle(selected ? Theme.accent : Color(.separator))
    }

    /// The savings pill itself.
    private func savingsPill(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .foregroundStyle(Theme.onInk)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Theme.ink, in: .capsule)
    }

    /// The pill straddling the card's top edge — the side-by-side layout only.
    ///
    /// Straddling costs the card no height, which is the whole reason the badge
    /// left the card: side by side, a pill that takes a row has to take one on
    /// *both* cards (invisibly on monthly) or the two stop lining up.
    ///
    /// It can only hang over the edge while it's shorter than the card's own top
    /// padding, and at accessibility text sizes it isn't: the pill grows with
    /// the label until its lower half reaches down over "Yearly". Stacked, the
    /// cards are full width and no longer share a baseline, so nothing is gained
    /// by keeping the badge out of the flow — see `planCard`.
    @ViewBuilder
    private func straddlingBadge(_ product: Product) -> some View {
        if !stacksPlans, let text = badgeText(product) {
            savingsPill(text)
                // Centres the pill *on* the edge rather than below it.
                .alignmentGuide(.top) { $0[VerticalAlignment.center] }
        }
    }

    /// Whether the plans stack instead of sitting side by side. Two columns
    /// can't hold a price and a per-month figure once the text gets large.
    private var stacksPlans: Bool { dynamicTypeSize.isAccessibilitySize }

    // MARK: - Trial timeline

    /// What actually happens if they tap the button: access today, money on a
    /// named day. The trial is stated four times on this page already, but only
    /// ever as an adjective — "3-day free trial" says how long it lasts, not
    /// what arrives at the end of it, and the unanswered version of that
    /// question is the one that stops a purchase.
    ///
    /// Two steps, not the three this pattern usually has. The middle step is
    /// normally "we'll remind you before it ends", and this app cannot honestly
    /// make that promise: `NotificationService` schedules the daily reminder,
    /// season openings and the streak nudge, and nothing for a trial — and
    /// notification permission is optional here, so even once something is
    /// scheduled the claim would be false for everyone who declined. Add the
    /// step when there is a real reminder behind it, and only for players who
    /// granted notifications.
    ///
    /// Keyed to the *selected* plan rather than to yearly: monthly carries no
    /// introductory offer, so leaving a trial timeline on screen while monthly
    /// is selected would describe an offer the CTA isn't making.
    @ViewBuilder
    private var trialTimeline: some View {
        if let product = selectedProduct, let offer = store.introOffer(for: product) {
            VStack(alignment: .leading, spacing: 0) {
                timelineStep(
                    icon: "lock.open.fill",
                    title: "Today",
                    detail: "Full access to all \(puzzleProvider.totalPuzzleCount) puzzles. You pay nothing.",
                    isLast: false
                )
                timelineStep(
                    icon: "creditcard.fill",
                    title: "In \(offer.duration)",
                    // The price and period come from the same product the CTA
                    // will buy, so this line cannot drift from the button.
                    detail: "\(product.displayPrice)\(store.periodText(for: product) ?? "") begins, unless you cancel first.",
                    isLast: true
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.m)
            .elevatedCard()
        }
    }

    private func timelineStep(icon: String, title: String, detail: String, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
            // The rail is drawn by the step above it, filling whatever height
            // the text beside it turns out to need — so it still joins the two
            // discs when a detail line wraps at large text sizes.
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: checkSize, height: checkSize)
                    .background(Theme.accent.opacity(0.12), in: .circle)
                if !isLast {
                    Rectangle()
                        .fill(Theme.accent.opacity(0.2))
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, isLast ? 0 : Theme.Spacing.m)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
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
    static func ctaTitle(for product: Product?, store: StoreService, puzzleCount: Int) -> String {
        guard let product else { return "Continue" }
        if let trial = store.introOfferText(for: product) { return PremiumCopy.trialCTA(trial) }
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
        if let offer = store.introOffer(for: product) {
            // Says when money starts, not just that a trial exists — the
            // question a trial-sceptic is actually asking at this point.
            // `duration`, not the trial phrase with " free trial" trimmed off
            // it: after "Free for" the length needs its plural back.
            return "Free for \(offer.duration), then \(product.displayPrice)\(period), renewing until cancelled. Cancel anytime."
        }
        if !period.isEmpty {
            return "Auto-renews at \(product.displayPrice)\(period) until cancelled. Cancel anytime in Settings."
        }
        return "One-time purchase — yours forever."
    }

    /// The headline figure on a card: what leaves the account, and how often.
    private func planPrice(_ product: Product) -> String {
        product.displayPrice + (store.periodText(for: product) ?? "")
    }

    /// The line under the price: the same price read the other way round, so
    /// each card is legible on its own — the per-month figure on yearly, the
    /// annual total on monthly. That makes the saving a subtraction the reader
    /// can see rather than a percentage they have to trust.
    ///
    /// The trial does not appear here, and used to be all that did: this
    /// returned the introductory offer early, so whenever one existed the
    /// yearly card read "3-day free trial" and the per-month figure appeared
    /// *nowhere on the screen*. The cheapest way to read this price was the one
    /// number the page never showed.
    ///
    /// The trial is already stated three times — the subhead, the CTA, and the
    /// commitment line — and it reads as attached to yearly because yearly is
    /// preselected: choosing monthly changes the CTA away from "Start 3-day
    /// free trial", which says it more plainly than a fourth caption would.
    /// Adding it back here only cost the card a second line, and left the two
    /// plans at visibly different heights.
    private func planFootnote(_ product: Product) -> String {
        switch product.id {
        case StoreService.yearlyID:
            return yearlyPerMonthText.map { "\($0)/month" } ?? ""
        case StoreService.monthlyID:
            return monthlyPerYearText.map { "\($0) a year" } ?? ""
        default:
            return "one-time"
        }
    }

    /// The monthly plan's price over twelve months, in the product's own
    /// currency — the number the yearly plan is quietly being compared against.
    private var monthlyPerYearText: String? {
        guard let monthly = store.products.first(where: { $0.id == StoreService.monthlyID })
        else { return nil }
        return (monthly.price * 12).formatted(monthly.priceFormatStyle)
    }

    /// The yearly plan's price divided by twelve, formatted in the product's
    /// own currency and locale rather than hand-built from the display string.
    private var yearlyPerMonthText: String? {
        guard let yearly = store.products.first(where: { $0.id == StoreService.yearlyID })
        else { return nil }
        let perMonth = yearly.price / 12
        return perMonth.formatted(yearly.priceFormatStyle)
    }

    /// Tinted pill on the yearly plan — the computed saving vs. paying monthly,
    /// or a "BEST VALUE" fallback when monthly isn't available to compare against.
    private func badgeText(_ product: Product) -> String? {
        guard product.id == StoreService.yearlyID else { return nil }
        if let pct = yearlySavingsPercent { return "SAVE \(pct)%" }
        return "BEST VALUE"
    }

    private var yearlySavingsPercent: Int? {
        guard
            let yearly = store.products.first(where: { $0.id == StoreService.yearlyID }),
            let monthly = store.products.first(where: { $0.id == StoreService.monthlyID })
        else { return nil }
        let monthlyAnnual = monthly.price * 12
        guard monthlyAnnual > 0 else { return nil }
        let saved = (monthlyAnnual - yearly.price) / monthlyAnnual
        let pct = Int((NSDecimalNumber(decimal: saved).doubleValue * 100).rounded())
        return pct > 0 ? pct : nil
    }
}
