//
//  PaywallView.swift
//  Bible Crossword Challenge
//
//  Premium upgrade screen, in the app's native language: paper canvas, serif
//  hero, surface cards, the accent for selection and an ink CTA.
//
//  Order: promise, the player's own progress, benefits, then the named packs
//  they can't open yet — showing the content withheld rather than only the
//  content on offer. Then stacked plan cards (yearly with any free trial +
//  savings badge, monthly, and a one-time lifetime unlock), then the CTA and
//  its subtext. Purchase/restore go through StoreService (StoreKit 2).
//
//  Always presented as a sheet. Pushed onto a navigation stack it collides
//  with the back button and the tab bar.
//

import SwiftUI
import SwiftData
import StoreKit

struct PaywallView: View {
    /// Where this paywall was opened from (e.g. "archive", "hint_limit").
    /// Attributed on both `paywall_opened` and `premium_purchased` so each
    /// entry point's view → purchase conversion can be compared.
    let source: String

    @Environment(StoreService.self) private var store
    @Environment(\.analytics) private var analytics
    @Environment(\.puzzleProvider) private var puzzleProvider
    @Environment(\.dismiss) private var dismiss
    /// Filtered in the fetch rather than in Swift: the progress line only needs
    /// completions, and an unscoped query would materialise every record the
    /// player has ever touched to count a subset of them.
    @Query(filter: #Predicate<PuzzleRecord> { $0.isCompleted })
    private var completedRecords: [PuzzleRecord]

    @State private var selectedID = StoreService.yearlyID
    @State private var didLogOpen = false

    @ScaledMetric(relativeTo: .body) private var checkSize: CGFloat = 22
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var benefits: [PremiumBenefit] {
        PremiumBenefit.all(
            puzzleCount: puzzleProvider.totalPuzzleCount,
            packCount: premiumPackCount
        )
    }

    /// The trial as a headline rather than a footnote. When the yearly plan
    /// carries an introductory offer, the strongest thing this screen can say
    /// is that today costs nothing — so it goes directly under the promise
    /// instead of waiting until the plan row or the CTA subtext.
    ///
    /// Nil when no offer is configured or the player has already used theirs,
    /// in which case the page silently reads as a straight subscription pitch.
    private var trialHeadline: String? {
        guard let yearly = store.products.first(where: { $0.id == StoreService.yearlyID }),
              let trial = store.introOfferText(for: yearly)
        else { return nil }
        return trial
    }

    private var selectedProduct: Product? {
        store.products.first { $0.id == selectedID }
    }

    private var premiumPackCount: Int {
        puzzleProvider.packs.filter(\.isPremium).count
    }

    var body: some View {
        // A real navigation bar rather than a floating overlay: the header used
        // to scroll underneath the close and restore buttons and collide with
        // them. The system bar brings its own material on scroll, and drops the
        // magic 64pt top padding the overlay needed.
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.m) {
                    headline
                    featureList

                    if store.isPremium {
                        premiumBadge
                    } else if store.products.isEmpty {
                        productsPlaceholder
                    } else {
                        plans
                    }
                }
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.top, Theme.Spacing.s)
                .padding(.bottom, Theme.Spacing.l)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
            .background(Theme.background)
            // Pinned, not scrolled. Every addition to this page pushed the CTA
            // further down; on a 667pt screen it had fallen below the fold,
            // which means scrolling to find the primary action. Anchoring it
            // also means the page above can grow later without re-checking.
            .safeAreaInset(edge: .bottom) { pinnedPurchaseBar }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .bold))
                    }
                    .tint(.secondary)
                    .accessibilityLabel("Close")
                }
                // No Restore up here any more: it lives in the pinned footer
                // with the other housekeeping links, which never scrolls away,
                // so a second copy was only competing with the close button for
                // the top of the screen.
            }
            // Opaque, and in the page's own colour: the bar is transparent by
            // default, which put the serif hero underneath the close button as
            // soon as the content scrolled.
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Theme.background, for: .navigationBar)
        }
        .onAppear {
            // Every presentation logs exactly once, whatever the entry point.
            if !didLogOpen {
                didLogOpen = true
                analytics.log(.paywallOpened(source: source))
            }
            // Default to the trial plan; fall back to whatever loaded.
            if selectedProduct == nil, let first = store.products.first {
                selectedID = first.id
            }
        }
        .task {
            if store.products.isEmpty { await store.refresh() }
        }
        .onChange(of: store.products.count) { _, _ in
            if selectedProduct == nil, let first = store.products.first {
                selectedID = first.id
            }
        }
        .purchaseNoticeAlert(store)
    }

    // MARK: - Headline

    private var headline: some View {
        VStack(spacing: Theme.Spacing.s) {
            // The eyebrow carries the fact, the headline carries the reason.
            // Putting a number in both just says the same thing twice.
            Text("Premium · \(puzzleProvider.totalPuzzleCount) puzzles")
                .kicker()
            Text(headlineText)
                .font(.scripture(.largeTitle, weight: .semibold))
                .multilineTextAlignment(.center)

            if let trial = trialHeadline {
                // Shared with onboarding's premium page rather than restated —
                // see `PremiumCopy.trialSubhead`.
                PremiumCopy.trialSubhead(trial)
                    .font(.subheadline.weight(.medium))
                    .multilineTextAlignment(.center)
            }

            if let progress = progressLine {
                Text(progress)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    /// The entry points that get their own promise. Deliberately a failable
    /// `init(rawValue:)` rather than a match on bare strings: a source that is
    /// renamed, added, or mistyped falls through to the default line instead of
    /// leaving the largest text on the screen blank.
    private enum Entry: String {
        case hintLimit = "hint_limit"
        case completion
        case firstCompletion = "first_completion"
        case miniCompletion = "mini_completion"
        case streak3 = "streak_3"
        case packCompletion = "pack_completion"
        case packLocked = "pack_locked"
        case homeCard = "home_card"
        case archive
    }

    private static let defaultHeadline = PremiumCopy.promise

    /// The promise, chosen by where the player came from. Someone who just hit
    /// a hint wall and someone browsing from their profile are asking different
    /// questions, and `source` is already threaded through for attribution — so
    /// the copy can follow it without any new plumbing, and `premium_purchased`
    /// already carries the same value to judge it by later.
    private var headlineText: String {
        switch Entry(rawValue: source) {
        case .hintLimit:
            return "Never stuck for long."
        case .completion:
            return solvedTally ?? Self.defaultHeadline
        // The two auto-opens from `maybeAutoShowPaywall`, which fire once ever
        // at the highest-intent moments the app has. Both used to land on the
        // brand line — the largest text on the screen saying nothing about the
        // thing that had just happened.
        case .firstCompletion:
            return "That's your first. The rest are waiting."
        case .streak3:
            // Names the actual reason Premium matters *here*: the habit they've
            // just built runs on one puzzle a day, and that's all free gives.
            return "A habit needs more than one a day."
        case .miniCompletion:
            return "Two minutes was just the start."
        case .packCompletion:
            return "The rest of the pack is waiting."
        case .packLocked:
            return "The collections are waiting."
        case .homeCard:
            return "Make it part of the morning."
        case .archive:
            return PremiumCopy.archive
        // `profile` and anything added later. A player who hasn't hit a wall
        // needs telling what the app is for, not what it withholds. (Onboarding
        // never arrives here — its premium page is part of `OnboardingView`.)
        case nil:
            return Self.defaultHeadline
        }
    }

    /// "12 down. 165 to go." — the player's own two numbers, on the one screen
    /// where they've just finished something and the next one is the question.
    private var solvedTally: String? {
        let solved = completedRecords.count
        let remaining = puzzleProvider.totalPuzzleCount - solved
        guard solved > 0, remaining > 0 else { return nil }
        return "\(solved) down. \(remaining) to go."
    }

    /// The player's own gap, stated as a fact and nothing more. A personal
    /// number is a stronger reason to act now than a generic claim, and unlike
    /// social proof it's something the app can honestly know.
    ///
    /// Hidden at zero: "You've solved 0" is a discouragement, not a nudge.
    private var progressLine: String? {
        // Suppressed when the headline is already the tally — the two lines
        // carry identical numbers and reading them in sequence stutters.
        if Entry(rawValue: source) == .completion, solvedTally != nil { return nil }
        let solved = completedRecords.count
        guard solved > 0 else { return nil }
        return "You've solved \(solved) of \(puzzleProvider.totalPuzzleCount)."
    }

    // MARK: - Benefits

    /// The benefits, grouped into one surface rather than floating on the page.
    /// Four two-line rows loose on the canvas read as an unbroken wall of text;
    /// bounding them makes the list a single object the eye can skip past on
    /// the way to the price, and separates it from the locked packs below.
    private var featureList: some View {
        VStack(spacing: Theme.Spacing.m) {
            ForEach(benefits) { benefit in
                HStack(alignment: .top, spacing: Theme.Spacing.m) {
                    // Accent, not green: green means "solved" everywhere else
                    // in the app, and it shouldn't also mean "included".
                    // The disc scales with the label: at a fixed 22pt the glyph
                    // outgrew it at accessibility sizes and spilled over the edge.
                    Image(systemName: benefit.icon)
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(Theme.accent)
                        .frame(width: checkSize, height: checkSize)
                        .background(Theme.accent.opacity(0.12), in: .circle)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(benefit.title)
                            .font(.body.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                        Text(benefit.detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.m)
        .background(Theme.surface,
                    in: .rect(cornerRadius: Theme.cornerRadius, style: .continuous))
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
            // Two columns can't hold a price and a per-month figure once the
            // text gets large, so the same cards stack at accessibility sizes.
            // AnyLayout rather than a branch on the view itself, so selection
            // keeps its identity (and its animation) across the switch.
            let layout = dynamicTypeSize.isAccessibilitySize
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
                // The badge slot is always laid out, hidden when there's
                // nothing to say, so the two cards keep a common baseline
                // instead of one sitting a pill's height lower than the other.
                Text(badgeText(product) ?? "")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Theme.onInk)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Theme.ink, in: .capsule)
                    .opacity(badgeText(product) == nil ? 0 : 1)
                    .accessibilityHidden(badgeText(product) == nil)

                Text(planTitle(product))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
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
            .background(selected ? Theme.accent.opacity(0.12) : Theme.surface,
                        in: .rect(cornerRadius: Theme.cornerRadius, style: .continuous))
            .overlay {
                if selected {
                    RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                        .strokeBorder(Theme.accent, lineWidth: 2)
                }
            }
            // Without this the card only answers to taps that land on the
            // glyphs themselves: a SwiftUI button's hit area is its content,
            // and neither the padding nor the background extends it. Most of a
            // card this size is padding, so most of it was dead to the touch.
            .contentShape(.rect(cornerRadius: Theme.cornerRadius, style: .continuous))
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
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.subheadline)
                    .foregroundStyle(selected ? Theme.accent : Color(.separator))
                Text("Or pay once — \(product.displayPrice) forever")
                    .font(.subheadline.weight(selected ? .semibold : .regular))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.vertical, Theme.Spacing.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Theme.accent.opacity(0.12) : .clear,
                        in: .rect(cornerRadius: Theme.cornerRadius, style: .continuous))
            .overlay {
                if selected {
                    RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                        .strokeBorder(Theme.accent, lineWidth: 2)
                }
            }
            // As on the cards above — and it matters more here, because this
            // row is mostly empty space to the right of a short label.
            .contentShape(.rect(cornerRadius: Theme.cornerRadius, style: .continuous))
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private func planTitle(_ product: Product) -> String {
        switch product.id {
        case StoreService.yearlyID: return "Yearly"
        case StoreService.monthlyID: return "Monthly"
        default: return "Lifetime"
        }
    }

    /// The headline figure on a card: what leaves the account, and how often.
    private func planPrice(_ product: Product) -> String {
        product.displayPrice + (store.periodText(for: product) ?? "")
    }

    /// The line under the price, carrying whichever comparison makes that card
    /// legible on its own: the trial when there is one, the per-month figure on
    /// yearly, and on monthly the annual total — so the saving is a subtraction
    /// the reader can see rather than a percentage they have to trust.
    private func planFootnote(_ product: Product) -> String {
        if let trial = store.introOfferText(for: product) { return trial }
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

    // MARK: - Purchase

    /// The purchase bar as it sits in the bottom safe area: the CTA, the terms
    /// it commits you to, and the housekeeping links, in that order.
    ///
    /// The legal row is deliberately *outside* the "is there anything to buy"
    /// check. It carries Restore, and the state where that matters most is the
    /// one where products failed to load — a player who has already paid, on a
    /// bad connection, looking at a retry card. Gating it on a successful
    /// product fetch would take Restore away from exactly the person who needs
    /// it, and it is the only copy now that the toolbar button is gone.
    private var pinnedPurchaseBar: some View {
        VStack(spacing: Theme.Spacing.s) {
            if !store.isPremium && !store.products.isEmpty {
                purchaseSection
            }
            legal
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.top, Theme.Spacing.m)
        .padding(.bottom, Theme.Spacing.s)
        // The fill matches the canvas, so the bar reads continuous with
        // the page below it without needing to bleed into the safe area.
        .background(Theme.background)
        .overlay(alignment: .top) {
            // A hairline, because content scrolls underneath and the
            // bar needs an edge to read as a separate layer.
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 1)
        }
    }

    private var purchaseSection: some View {
        VStack(spacing: Theme.Spacing.m) {
            Button {
                guard let product = selectedProduct else { return }
                Task {
                    let plan = planTitle(product).lowercased()
                    // Before the sheet, not after: this is the only record that
                    // survives a player who backs out of Apple's dialog, which
                    // reports nothing at all.
                    analytics.log(.paywallCTATapped(
                        plan: plan,
                        source: source,
                        offersTrial: store.introOfferText(for: product) != nil
                    ))
                    // `premium_purchased` is emitted by StoreService, which sees
                    // every grant rather than only the ones that finish inside
                    // this call. Logging it here as well would double-count.
                    switch await store.purchase(product, source: source) {
                    case .purchased:
                        break
                    case .failed(let reason):
                        analytics.log(.purchaseFailed(plan: plan, source: source, reason: reason))
                    case .cancelled, .pending:
                        break
                    }
                }
            } label: {
                Group {
                    if store.purchaseInFlight {
                        ProgressView().tint(Theme.onInk)
                    } else {
                        Text(ctaTitle)
                    }
                }
            }
            .buttonStyle(.pillProminent)
            .disabled(store.purchaseInFlight || selectedProduct == nil)

            // Restate what happens right at the commit point — purchase anxiety
            // peaks here, and the trial/price detail otherwise only lives in the
            // plan row above.
            if let subtext = ctaSubtext {
                Text(subtext)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.top, Theme.Spacing.s)
    }

    /// Names the thing being started, never the transaction. "Subscribe"
    /// describes what the player gives up; the trial length and the puzzle
    /// count describe what they get, and the renewal terms are stated in full
    /// directly underneath either way.
    private var ctaTitle: String {
        guard let product = selectedProduct else { return "Continue" }
        // Shared with onboarding's premium page — see `PremiumCopy.trialCTA`.
        if let trial = store.introOfferText(for: product) { return PremiumCopy.trialCTA(trial) }
        if store.periodText(for: product) != nil {
            return "Unlock \(puzzleProvider.totalPuzzleCount) puzzles"
        }
        return "Unlock Lifetime"
    }

    /// One-line reassurance shown under the CTA: what the user is committing to.
    private var ctaSubtext: String? {
        guard let product = selectedProduct else { return nil }
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

    // MARK: - Legal

    /// Links only. The auto-renewal disclosure lives in `ctaSubtext`, right at
    /// the commit point where it carries the actual price — repeating it here
    /// as a vaguer sentence just made the footer say the same thing twice.
    private var legal: some View {
        HStack(spacing: Theme.Spacing.m) {
            Link("Terms of Use", destination: LegalLinks.terms)
            Link("Privacy Policy", destination: LegalLinks.privacy)
            // The only Restore on the screen since the toolbar copy went. A
            // player who can't find it reads the app as having charged them
            // twice, so it stays pinned rather than living in scrolled content.
            Button("Restore") { Task { await store.restore() } }
                .disabled(store.purchaseInFlight)
        }
        .font(.caption)
        .foregroundStyle(Theme.accent)
    }
}

extension View {
    /// Presents the store's pending `PurchaseNotice` (purchase failure, Ask to
    /// Buy pending, restore outcome) as an alert and clears it on dismiss.
    /// Attach to every screen that can start a purchase or restore.
    func purchaseNoticeAlert(_ store: StoreService) -> some View {
        alert(
            store.purchaseNotice?.title ?? "",
            isPresented: Binding(
                get: { store.purchaseNotice != nil },
                set: { if !$0 { store.purchaseNotice = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.purchaseNotice?.message ?? "")
        }
    }
}

/// Premium headlines that more than one screen makes.
///
/// Each of these was written twice before, in the two places that say it, and
/// the copies drifted — the app ended up making four different promises for one
/// product. A player who sees two of them reads two offers.
enum PremiumCopy {
    /// The promise itself, in the app's own register: what you'd be doing with
    /// the library rather than what's in it. Said by onboarding's premium page
    /// and by the paywall wherever the entry point has nothing more specific.
    static let promise = "Time in the Word, one clue at a time."

    /// The archive's promise. Shared because the Library locked state and the
    /// paywall it opens (`source: "archive"`) are one tap apart — a different
    /// headline on each made a single journey look like two pitches.
    static let archive = "Every puzzle, back to the first."

    /// The trial CTA, e.g. "Start 3-day free trial" — never a bare "Start Free
    /// Trial". The length is the most persuasive part of the offer and the
    /// store already hands it over, so spending the button on a generic phrase
    /// throws away the one number that closes.
    ///
    /// Pass `StoreService.introOfferText(for:)` straight in; the duration comes
    /// from StoreKit rather than any string written here, so a change to the
    /// configured offer can't leave the copy claiming the old length.
    static func trialCTA(_ trial: String) -> String { "Start \(trial)" }

    /// "Start with a 3-day free trial — pay nothing today", said above the fold
    /// on both surfaces that open the offer.
    ///
    /// The length carries the accent on its own so the offer survives a glance,
    /// the way a coloured word in a headline does — without tinting the whole
    /// line, which would read as a warning.
    static func trialSubhead(_ trial: String) -> Text {
        Text("Start with a ")
            + Text(trial).foregroundStyle(Theme.accent).bold()
            + Text(" — pay nothing today")
    }

    /// Said in the trial's place when there is no introductory offer — because
    /// the player has already used theirs, or none is configured. Without it
    /// the no-trial path has nothing above the fold about what costs nothing,
    /// and the free tier is the reason the ask can stay soft.
    static let freeDailyReassurance = "The daily puzzle stays free either way."
}

/// A premium benefit: what you get, then what that actually means.
///
/// The single-line version couldn't carry both, so each row had to choose
/// between being specific and being scannable. Splitting them means the bold
/// line reads on its own at a glance and the detail is there for anyone who
/// slows down.
struct PremiumBenefit: Identifiable {
    let icon: String
    let title: String
    let detail: String
    var id: String { title }

    /// The promise, written once for both places that make it.
    ///
    /// Onboarding's premium page and the paywall are the same offer at two
    /// moments, and while each kept its own copy they drifted: the paywall was
    /// rewritten to three outcome-led rows while onboarding still advertised
    /// four, including a "No ads, ever" the app can't really honour and a
    /// "whole library" that repeated the row above it. A player who saw both
    /// was reading two different products.
    ///
    /// Counts are passed in from the bundle rather than written as "100+" or
    /// "four", so no claim here can go stale as puzzles and packs are added.
    ///
    /// The first row says "not just today's" rather than "all N puzzles,
    /// unlocked". The free tier already gives a daily and a mini, so "unlocked"
    /// described a state the reader was not in — it invited them to check, find
    /// today's puzzle playable, and discount the other two rows with it. Naming
    /// the free tier in the same breath as the offer is the only version a
    /// daily player can't catch out. It also stopped the row from reaching for
    /// packs, which the third row already owns: one row for the archive and
    /// replay, one for hints, one for packs.
    ///
    /// Hint limits get their own row rather than sharing one with ads: they're
    /// the most-hit paywall trigger in the app, and pairing the strongest
    /// reason to subscribe with the weakest one buried it. "No ads" is gone
    /// entirely, and so is the ad scaffold behind it: the app serves no
    /// advertising, so there is nothing for Premium to remove. Add the row
    /// back only alongside a real ad integration.
    static func all(puzzleCount: Int, packCount: Int) -> [PremiumBenefit] {
        [
            PremiumBenefit(
                icon: "square.grid.3x3.fill",
                title: "\(puzzleCount) puzzles, not just today's",
                detail: "The whole archive, back to the very first — replay any of them, any time."
            ),
            PremiumBenefit(
                icon: "lightbulb.fill",
                title: "No hint limits",
                detail: "Every hint on every puzzle, for the moments you're properly stuck."
            ),
            PremiumBenefit(
                icon: "rectangle.stack.fill",
                title: "Every pack, now and later",
                detail: "\(packCount) themed collections today, plus every new one added after."
            ),
        ]
    }
}

/// External legal links shown on the paywall. Terms uses Apple's standard EULA.
enum LegalLinks {
    static let terms = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    static let privacy = URL(string: "https://biblecrosswordchallenge.com/privacy.html")!
}
