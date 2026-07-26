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
//  savings badge, monthly, and a one-time lifetime unlock), the CTA, and a
//  plain reminder that the daily puzzle stays free. Purchase/restore go
//  through StoreService (StoreKit 2).
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

    /// Outcome first, proof second. The previous list was an inventory ("All
    /// 117 puzzles / The full archive / Unlimited hints") — accurate, but it
    /// described the box rather than what the box does for you.
    ///
    /// Counts come from the bundle rather than a written "100+", so the claim
    /// can't drift out of date as packs are added. `totalPuzzleCount`, not
    /// `puzzles.count` — the latter is the daily/Archive pool only and would
    /// undersell the library by every mini and pack exclusive.
    private var benefits: [String] {
        [
            "The whole archive — never miss a day",
            "Every pack, the four below and every one after",
            "No ads and no hint limits, ever",
        ]
    }

    private var selectedProduct: Product? {
        store.products.first { $0.id == selectedID }
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
                        lockedPacks
                        plans
                        legal
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
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Restore") {
                        Task { await store.restore() }
                    }
                    .disabled(store.purchaseInFlight)
                }
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
            Text("Premium · \(puzzleProvider.totalPuzzleCount) puzzles")
                .kicker()
            // Same line as onboarding's premium page: one promise, worded once.
            Text("Play the whole library.")
                .font(.scripture(.largeTitle, weight: .semibold))
                .multilineTextAlignment(.center)

            if let progress = progressLine {
                Text(progress)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    /// The player's own gap, stated as a fact and nothing more. A personal
    /// number is a stronger reason to act now than a generic claim, and unlike
    /// social proof it's something the app can honestly know.
    ///
    /// Hidden at zero: "You've solved 0" is a discouragement, not a nudge.
    private var progressLine: String? {
        let solved = completedRecords.count
        guard solved > 0 else { return nil }
        return "You've solved \(solved) of \(puzzleProvider.totalPuzzleCount)."
    }

    // MARK: - Benefits

    private var featureList: some View {
        VStack(spacing: Theme.Spacing.m) {
            ForEach(benefits, id: \.self) { title in
                HStack(spacing: Theme.Spacing.m) {
                    // Accent, not green: green means "solved" everywhere else
                    // in the app, and it shouldn't also mean "included".
                    // The disc scales with the label: at a fixed 22pt the glyph
                    // outgrew it at accessibility sizes and spilled over the edge.
                    Image(systemName: "checkmark")
                        .font(.footnote.weight(.black))
                        .foregroundStyle(Theme.accent)
                        .frame(width: checkSize, height: checkSize)
                        .background(Theme.accent.opacity(0.12), in: .circle)
                    Text(title)
                        .font(.body.weight(.medium))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Theme.Spacing.s)
    }

    // MARK: - Locked packs
    //
    // Named, countable things the player can't open yet. The library band at the
    // top shows what's on offer; this shows it withheld, which is the half a
    // paywall usually forgets. Real packs from the bundle, so it can't describe
    // content that doesn't exist.

    @ViewBuilder private var lockedPacks: some View {
        let packs = puzzleProvider.packs.filter(\.isPremium)
        if !packs.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Text("Locked right now")
                    .kicker()
                HStack(alignment: .top, spacing: Theme.Spacing.s) {
                    ForEach(packs) { pack in
                        lockedPackTile(pack)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, Theme.Spacing.xs)
        }
    }

    private func lockedPackTile(_ pack: PuzzlePack) -> some View {
        VStack(spacing: 6) {
            // Tiles divide the width they're given rather than taking a fixed
            // size, so four of them can't overflow a narrow screen.
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(pack.accent.opacity(0.12))
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    Image(systemName: pack.coverSymbol)
                        .font(.title3)
                        .foregroundStyle(pack.accent.opacity(0.5))
                }
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "lock.fill")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Theme.onInk)
                        .padding(4)
                        .background(Theme.ink.opacity(0.85), in: .circle)
                        .padding(4)
                }

            Text(pack.title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(pack.title), locked. \(pack.puzzleIDs.count) puzzles.")
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

    private var plans: some View {
        VStack(spacing: Theme.Spacing.s) {
            ForEach(store.products, id: \.id) { product in
                planRow(product)
            }
        }
        // Spring the selection ring/radio between plans instead of snapping.
        .animation(.snappy(duration: 0.2), value: selectedID)
    }

    private func planRow(_ product: Product) -> some View {
        let selected = product.id == selectedID
        return Button {
            selectedID = product.id
        } label: {
            HStack(spacing: Theme.Spacing.m) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: Theme.Spacing.s) {
                        Text(planTitle(product))
                            .font(.headline)
                        if let badge = badgeText(product) {
                            // Ink fill rather than a tinted wash: accent on
                            // accent-15% is about 2.8:1, well under AA for
                            // caption text, and this is the one label on the
                            // screen that should be impossible to miss.
                            Text(badge)
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(Theme.onInk)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Theme.ink, in: .capsule)
                        }
                    }
                    Text(planSubtitle(product))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                radio(selected: selected)
            }
            .padding(Theme.Spacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Theme.accent.opacity(0.12) : Theme.surface,
                        in: .rect(cornerRadius: Theme.cornerRadius, style: .continuous))
            .overlay {
                if selected {
                    RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                        .strokeBorder(Theme.accent, lineWidth: 2)
                }
            }
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private func radio(selected: Bool) -> some View {
        ZStack {
            Circle()
                .strokeBorder(selected ? Color.clear : Color(.separator), lineWidth: 1.5)
            if selected {
                Circle().fill(Theme.accent)
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .black))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 26, height: 26)
    }

    private func planTitle(_ product: Product) -> String {
        switch product.id {
        case StoreService.yearlyID: return "Yearly"
        case StoreService.monthlyID: return "Monthly"
        default: return "Lifetime"
        }
    }

    private func planSubtitle(_ product: Product) -> String {
        if let trial = store.introOfferText(for: product) {
            return "\(trial), then \(product.displayPrice)\(store.periodText(for: product) ?? "")"
        }
        if let period = store.periodText(for: product) {
            // The yearly price also gets a per-month figure — otherwise the
            // reader has to divide in their head to compare it with monthly.
            if product.id == StoreService.yearlyID, let monthly = yearlyPerMonthText {
                return "\(product.displayPrice)\(period) · \(monthly)/month"
            }
            return "\(product.displayPrice)\(period)"
        }
        return "\(product.displayPrice) one-time"
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

    /// The purchase bar as it sits in the bottom safe area. Empty in the two
    /// states that have nothing to buy, so the inset collapses rather than
    /// leaving a floating strip.
    @ViewBuilder private var pinnedPurchaseBar: some View {
        if !store.isPremium && !store.products.isEmpty {
            purchaseSection
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
    }

    private var purchaseSection: some View {
        VStack(spacing: Theme.Spacing.m) {
            Button {
                guard let product = selectedProduct else { return }
                Task {
                    if await store.purchase(product) {
                        analytics.log(.premiumPurchased(plan: planTitle(product).lowercased(), source: source))
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

            // Said plainly, because it's true and because a paywall that looks
            // like it's taking something away breeds resentment. Nothing here
            // removes the free daily puzzle.
            Text("The daily puzzle stays free — always.")
                .font(.footnote.weight(.semibold))
                .multilineTextAlignment(.center)
        }
        .padding(.top, Theme.Spacing.s)
    }

    private var ctaTitle: String {
        guard let product = selectedProduct else { return "Continue" }
        if store.introOfferText(for: product) != nil { return "Start Free Trial" }
        if store.periodText(for: product) != nil { return "Subscribe" }
        return "Unlock Lifetime"
    }

    /// One-line reassurance shown under the CTA: what the user is committing to.
    private var ctaSubtext: String? {
        guard let product = selectedProduct else { return nil }
        let period = store.periodText(for: product) ?? ""
        if let trial = store.introOfferText(for: product) {
            return "\(trial), then \(product.displayPrice)\(period). Cancel anytime."
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

/// External legal links shown on the paywall. Terms uses Apple's standard EULA.
enum LegalLinks {
    static let terms = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    static let privacy = URL(string: "https://biblecrosswordchallenge.com/privacy.html")!
}
