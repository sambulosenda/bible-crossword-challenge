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
        ("archivebox.fill", "Puzzle Archive", "Replay every past daily puzzle"),
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
        }
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
        .buttonStyle(.plain)
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

            Button("Restore Purchase") {
                Task { await store.restore() }
            }
            .font(.subheadline)
            .disabled(store.purchaseInFlight)
        }
    }

    private var ctaTitle: String {
        guard let product = selectedProduct else { return "Continue" }
        if store.introOfferText(for: product) != nil { return "Start Free Trial" }
        if store.periodText(for: product) != nil { return "Subscribe" }
        return "Unlock Lifetime"
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

/// External legal links shown on the paywall. Terms uses Apple's standard EULA.
enum LegalLinks {
    static let terms = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    static let privacy = URL(string: "https://biblecrosswordchallenge.com/privacy.html")!
}
