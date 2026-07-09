//
//  PaywallView.swift
//  Bible Crossword Challenge
//
//  Premium upgrade screen. A dark, immersive paywall: a gold-glow hero, a clean
//  benefit checklist, stacked plan cards (yearly with a free trial + savings
//  badge, monthly, and a one-time lifetime unlock) and a prominent gradient CTA.
//  Purchase/restore go through StoreService (StoreKit 2). The screen forces a
//  dark scheme and paints its own colours so it reads the same in light or dark.
//

import SwiftUI
import StoreKit

/// Self-contained palette for the paywall's immersive dark look. Kept local so
/// the rest of the app's native, system-coloured language is untouched.
private enum Pay {
    static let gold = Color(red: 0.96, green: 0.80, blue: 0.42)
    static let ink = Color(red: 0.05, green: 0.06, blue: 0.12)

    static let card = Color.white.opacity(0.06)
    static let cardSelected = gold.opacity(0.14)
    static let hairline = Color.white.opacity(0.12)
    static let textSecondary = Color.white.opacity(0.64)

    static let cornerRadius: CGFloat = 18

    static let goldGradient = LinearGradient(
        colors: [Color(red: 0.99, green: 0.87, blue: 0.53), Color(red: 0.90, green: 0.70, blue: 0.31)],
        startPoint: .top, endPoint: .bottom
    )

    static let background = LinearGradient(
        colors: [
            Color(red: 0.11, green: 0.13, blue: 0.28),
            Color(red: 0.06, green: 0.07, blue: 0.16),
            Color(red: 0.03, green: 0.035, blue: 0.08),
        ],
        startPoint: .top, endPoint: .bottom
    )
}

struct PaywallView: View {
    @Environment(StoreService.self) private var store
    @Environment(\.analytics) private var analytics
    @Environment(\.dismiss) private var dismiss

    @State private var selectedID = StoreService.yearlyID

    private let benefits: [String] = [
        "Remove all ads",
        "Unlimited hints",
        "Full puzzle archive",
        "Every future pack included",
    ]

    private var selectedProduct: Product? {
        store.products.first { $0.id == selectedID }
    }

    var body: some View {
        ZStack(alignment: .top) {
            Pay.background.ignoresSafeArea()

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
                        purchaseSection
                        legal
                    }
                }
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.top, 64)          // clear the floating top bar
                .padding(.bottom, Theme.Spacing.l)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }

            topBar
        }
        .preferredColorScheme(.dark)
        .tint(Pay.gold)
        .onAppear {
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

    // MARK: - Top bar (floating close + restore)

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(.white.opacity(0.12), in: .circle)
            }
            .accessibilityLabel("Close")

            Spacer()

            Button("Restore") {
                Task { await store.restore() }
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(.white.opacity(0.12), in: .capsule)
            .disabled(store.purchaseInFlight)
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.top, Theme.Spacing.s)
    }

    // MARK: - Headline

    private var headline: some View {
        VStack(spacing: Theme.Spacing.s) {
            crownMark
            Text("Bible Crossword")
                .kicker(Pay.gold)
            Text("Unlock Premium")
                .font(.largeTitle.bold())
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
        }
    }

    /// Compact premium mark above the title — a small gold crown on a soft halo.
    /// Kept small so the plans and CTA fit without scrolling.
    private var crownMark: some View {
        Image(systemName: "crown.fill")
            .font(.system(size: 34))
            .foregroundStyle(Pay.goldGradient)
            .padding(14)
            .background {
                Circle()
                    .fill(RadialGradient(colors: [Pay.gold.opacity(0.30), .clear],
                                         center: .center, startRadius: 0, endRadius: 55))
                    .frame(width: 120, height: 120)
            }
            .accessibilityHidden(true)
    }

    // MARK: - Benefits

    private var featureList: some View {
        VStack(spacing: Theme.Spacing.m) {
            ForEach(benefits, id: \.self) { title in
                HStack(spacing: Theme.Spacing.m) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .black))
                        .foregroundStyle(Pay.ink)
                        .frame(width: 24, height: 24)
                        .background(Pay.goldGradient, in: .circle)
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Theme.Spacing.s)
    }

    private var premiumBadge: some View {
        Label("You're Premium — thank you!", systemImage: "checkmark.seal.fill")
            .font(.headline)
            .foregroundStyle(Pay.gold)
            .padding(.vertical, Theme.Spacing.l)
    }

    /// Loading spinner while products fetch; a retry card if the fetch failed.
    @ViewBuilder private var productsPlaceholder: some View {
        VStack(spacing: Theme.Spacing.m) {
            if store.productsLoadFailed {
                Label("Couldn't load plans", systemImage: "wifi.exclamationmark")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("Check your connection and try again.")
                    .font(.subheadline)
                    .foregroundStyle(Pay.textSecondary)
                Button("Retry") {
                    Task { await store.refresh() }
                }
                .font(.headline)
                .foregroundStyle(Pay.ink)
                .padding(.horizontal, Theme.Spacing.l)
                .frame(height: 44)
                .background(Pay.goldGradient, in: .capsule)
            } else {
                ProgressView("Loading plans…")
                    .foregroundStyle(Pay.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.Spacing.xl)
        .background(Pay.card, in: .rect(cornerRadius: Pay.cornerRadius, style: .continuous))
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
                            .foregroundStyle(.white)
                        if let badge = badgeText(product) {
                            Text(badge)
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(Pay.ink)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Pay.goldGradient, in: .capsule)
                        }
                    }
                    Text(planSubtitle(product))
                        .font(.subheadline)
                        .foregroundStyle(Pay.textSecondary)
                }
                Spacer(minLength: 0)
                radio(selected: selected)
            }
            .padding(Theme.Spacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Pay.cardSelected : Pay.card,
                        in: .rect(cornerRadius: Pay.cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Pay.cornerRadius, style: .continuous)
                    .strokeBorder(selected ? Pay.gold : Pay.hairline, lineWidth: selected ? 2 : 1)
            }
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private func radio(selected: Bool) -> some View {
        ZStack {
            Circle()
                .strokeBorder(selected ? Color.clear : Pay.hairline, lineWidth: 1.5)
            if selected {
                Circle().fill(Pay.goldGradient)
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .black))
                    .foregroundStyle(Pay.ink)
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
            return "\(product.displayPrice)\(period)"
        }
        return "\(product.displayPrice) one-time"
    }

    /// Gold pill on the yearly plan — the computed saving vs. paying monthly, or
    /// a "BEST VALUE" fallback when monthly isn't available to compare against.
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

    private var purchaseSection: some View {
        VStack(spacing: Theme.Spacing.m) {
            Button {
                guard let product = selectedProduct else { return }
                Task {
                    if await store.purchase(product) {
                        analytics.log(.premiumPurchased(plan: planTitle(product).lowercased()))
                    }
                }
            } label: {
                Group {
                    if store.purchaseInFlight {
                        ProgressView().tint(Pay.ink)
                    } else {
                        Text(ctaTitle).font(.headline)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .foregroundStyle(Pay.ink)
                .background(Pay.goldGradient, in: .rect(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(PressableCardStyle())
            .disabled(store.purchaseInFlight || selectedProduct == nil)

            // Restate what happens right at the commit point — purchase anxiety
            // peaks here, and the trial/price detail otherwise only lives in the
            // plan row above.
            if let subtext = ctaSubtext {
                Text(subtext)
                    .font(.footnote)
                    .foregroundStyle(Pay.textSecondary)
                    .multilineTextAlignment(.center)
            }
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
            return "Auto-renews at \(product.displayPrice)\(period). Cancel anytime."
        }
        return "One-time purchase — yours forever."
    }

    // MARK: - Legal

    private var legal: some View {
        VStack(spacing: Theme.Spacing.s) {
            Text("Subscriptions auto-renew unless cancelled at least 24 hours before the end of the period. Manage or cancel anytime in Settings. Payment is charged to your Apple Account.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.45))
            HStack(spacing: Theme.Spacing.m) {
                Link("Terms of Use", destination: LegalLinks.terms)
                Link("Privacy Policy", destination: LegalLinks.privacy)
            }
            .foregroundStyle(Pay.gold.opacity(0.9))
        }
        .font(.caption2)
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
