//
//  PaywallView.swift
//  Bible Crossword Challenge
//
//  Premium upgrade screen. Offers a yearly subscription (with a free trial), a
//  monthly subscription, and a one-time lifetime unlock. Purchase/restore go
//  through StoreService (StoreKit 2).
//

import SwiftUI
import StoreKit
import Lottie

struct PaywallView: View {
    @Environment(StoreService.self) private var store
    @Environment(\.analytics) private var analytics
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var selectedID = StoreService.yearlyID

    private let benefits: [(symbol: String, title: String, detail: String)] = [
        ("nosign", "Remove Ads", "Enjoy a distraction-free experience"),
        ("lightbulb.fill", "Unlimited Hints", "Never get stuck on a tricky clue"),
        ("archivebox.fill", "Puzzle Archive", "Replay every past daily puzzle and Mini"),
        ("gift.fill", "Future Packs", "Get upcoming puzzle packs included"),
    ]

    private var selectedProduct: Product? {
        store.products.first { $0.id == selectedID }
    }

    /// Premium hero mark. Loops a gentle gold crown; falls back to the static
    /// crown symbol under Reduce Motion.
    @ViewBuilder private var crownMark: some View {
        if reduceMotion {
            Image(systemName: "crown.fill")
                .font(.system(size: 64))
                .foregroundStyle(.yellow)
                .accessibilityHidden(true)
        } else {
            LottieView(animation: .named("premium_crown"))
                .configure { $0.contentMode = .scaleAspectFit }
                .looping()
                .frame(width: 150, height: 150)
                .accessibilityHidden(true)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.l) {
                    crownMark
                        .padding(.top, Theme.Spacing.xl)

                    Text("Bible Crossword Premium")
                        .font(.largeTitle.bold())
                        .multilineTextAlignment(.center)

                    benefitsCard

                    if store.isPremium {
                        Label("You're Premium — thank you!", systemImage: "checkmark.seal.fill")
                            .font(.headline)
                            .foregroundStyle(.green)
                            .padding(.top, Theme.Spacing.m)
                    } else if store.products.isEmpty {
                        // Products haven't arrived (offline, App Store hiccup):
                        // never show an empty plan list with a dead button.
                        productsPlaceholder
                        restoreButton
                    } else {
                        plans
                        purchaseSection
                        legal
                    }
                }
                .padding(Theme.Spacing.l)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Premium")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
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
                .buttonStyle(.bordered)
            } else {
                ProgressView("Loading plans…")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.Spacing.xl)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: Theme.cornerRadius))
    }

    private var benefitsCard: some View {
        VStack(spacing: Theme.Spacing.m) {
            ForEach(benefits, id: \.title) { benefit in
                HStack(spacing: Theme.Spacing.m) {
                    Image(systemName: benefit.symbol)
                        .font(.title3)
                        .foregroundStyle(Theme.accent)
                        .frame(width: 32)
                    VStack(alignment: .leading) {
                        Text(benefit.title).font(.headline)
                        Text(benefit.detail).font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(Theme.Spacing.l)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: Theme.cornerRadius))
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
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.title2)
                    .foregroundStyle(selected ? Theme.accent : Color(.tertiaryLabel))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: Theme.Spacing.s) {
                        Text(planTitle(product)).font(.headline)
                        if product.id == StoreService.yearlyID {
                            Text("BEST VALUE").kicker(.green)
                        }
                    }
                    Text(planSubtitle(product))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(Theme.Spacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: Theme.cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.cornerRadius)
                    .strokeBorder(selected ? Theme.accent : .clear, lineWidth: 2)
            }
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

    private func planSubtitle(_ product: Product) -> String {
        if let trial = store.introOfferText(for: product) {
            return "\(trial), then \(product.displayPrice)\(store.periodText(for: product) ?? "")"
        }
        if let period = store.periodText(for: product) {
            return "\(product.displayPrice)\(period)"
        }
        return "\(product.displayPrice) one-time"
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
                        ProgressView()
                    } else {
                        Text(ctaTitle)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.extraLarge)
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

            restoreButton
        }
    }

    private var restoreButton: some View {
        Button("Restore Purchase") {
            Task { await store.restore() }
        }
        .font(.subheadline)
        .disabled(store.purchaseInFlight)
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
            HStack(spacing: Theme.Spacing.m) {
                Link("Terms of Use", destination: LegalLinks.terms)
                Link("Privacy Policy", destination: LegalLinks.privacy)
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
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
