//
//  StoreService.swift
//  Bible Crossword Challenge
//
//  Premium entitlement backed by StoreKit 2. Premium can be obtained three ways,
//  all sharing one entitlement: an auto-renewable monthly or yearly subscription
//  (yearly carries a free trial), or a one-time lifetime unlock (non-consumable).
//  Ownership is derived from `Transaction.currentEntitlements`, which only yields
//  active subscriptions (incl. an in-progress trial) plus the lifetime purchase.
//  A background task listens for `Transaction.updates` so entitlements granted or
//  revoked outside the app (renewals, Ask to Buy, refunds, family sharing) are
//  reflected automatically.
//
//  The matching products must exist in App Store Connect with these identifiers.
//  Local testing uses the bundled `Products.storekit` configuration (referenced
//  by the scheme).
//

import Foundation
import StoreKit
import Observation

/// A user-facing alert for a purchase/restore outcome the player must know
/// about (failure, pending approval, restore result). Nil means nothing to say.
struct PurchaseNotice: Equatable {
    let title: String
    let message: String
}

@Observable
final class StoreService {
    static let monthlyID = "com.sambulosendas1.biblecrossword.premium.monthly"
    static let yearlyID = "com.sambulosendas1.biblecrossword.premium.yearly"
    /// The original non-consumable, now offered as the lifetime tier.
    static let lifetimeID = "com.sambulosendas1.biblecrossword.premium"
    static let allProductIDs = [yearlyID, monthlyID, lifetimeID]

    private(set) var isPremium = false
    private(set) var products: [Product] = []
    private(set) var purchaseInFlight = false
    /// True when the last product load ended with nothing to show — drives the
    /// paywall's "couldn't load plans / retry" state instead of a blank screen.
    private(set) var productsLoadFailed = false
    /// Set whenever a purchase or restore ends in a way the player would
    /// otherwise only discover by nothing happening. Views present it as an
    /// alert and clear it back to nil.
    var purchaseNotice: PurchaseNotice?

    var yearly: Product? { products.first { $0.id == Self.yearlyID } }
    var monthly: Product? { products.first { $0.id == Self.monthlyID } }
    var lifetime: Product? { products.first { $0.id == Self.lifetimeID } }

    /// Representative single price for compact "Unlock Premium" spots.
    var displayPrice: String { lifetime?.displayPrice ?? yearly?.displayPrice ?? "£19.99" }

    /// Yearly subscription price for callers that can't import StoreKit.
    var yearlyPriceText: String { yearly?.displayPrice ?? "£9.99" }

    private var updatesTask: Task<Void, Never>?

    init() {
        // Reflect entitlement changes that happen outside an explicit purchase.
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                await self?.handle(update)
            }
        }
        Task { await refresh() }
    }

    deinit { updatesTask?.cancel() }

    /// Load products and re-check entitlement. Safe to call repeatedly.
    func refresh() async {
        await loadProducts()
        await updateEntitlement()
    }

    func loadProducts() async {
        do {
            let loaded = try await Product.products(for: Self.allProductIDs)
            // Keep a stable display order: yearly, monthly, lifetime.
            products = Self.allProductIDs.compactMap { id in loaded.first { $0.id == id } }
            productsLoadFailed = products.isEmpty
        } catch {
            // Keep any previously loaded products; only flag failure when the
            // paywall would otherwise have nothing to sell.
            productsLoadFailed = products.isEmpty
            #if DEBUG
            print("⚠️ StoreKit: failed to load products — \(error)")
            #endif
        }
    }

    /// Start a purchase for a specific plan. Returns true when premium is owned.
    @discardableResult
    func purchase(_ product: Product) async -> Bool {
        purchaseInFlight = true
        defer { purchaseInFlight = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await updateEntitlement()
                await transaction.finish()
                return isPremium
            case .userCancelled:
                return false
            case .pending:
                // Ask to Buy / deferred payment — without this the player sees
                // the button reset and assumes the purchase silently failed.
                purchaseNotice = PurchaseNotice(
                    title: "Purchase Pending",
                    message: "Your purchase is waiting for approval. Premium unlocks automatically once it's approved."
                )
                return false
            @unknown default:
                return false
            }
        } catch {
            purchaseNotice = PurchaseNotice(
                title: "Purchase Failed",
                message: "The purchase didn't go through — you haven't been charged. Please try again.\n\n\(error.localizedDescription)"
            )
            #if DEBUG
            print("⚠️ StoreKit: purchase failed — \(error)")
            #endif
            return false
        }
    }

    /// Restore prior purchases (StoreKit refreshes entitlements from the store).
    /// Always ends in a `purchaseNotice` telling the player what happened,
    /// unless they cancelled the App Store sign-in themselves.
    func restore() async {
        do {
            try await AppStore.sync()
            await updateEntitlement()
            purchaseNotice = isPremium
                ? PurchaseNotice(title: "Purchases Restored", message: "Welcome back — Premium is active.")
                : PurchaseNotice(title: "Nothing to Restore", message: "No previous purchases were found for this Apple Account.")
        } catch StoreKitError.userCancelled {
            // Player dismissed the App Store sign-in — not an error.
            await updateEntitlement()
        } catch {
            await updateEntitlement()
            purchaseNotice = PurchaseNotice(
                title: "Restore Failed",
                message: "Couldn't reach the App Store. Check your connection and try again."
            )
        }
    }

    private func updateEntitlement() async {
        var owned = false
        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result) else { continue }
            if Self.allProductIDs.contains(transaction.productID), transaction.revocationDate == nil {
                owned = true
            }
        }
        isPremium = owned
    }

    private func handle(_ result: VerificationResult<Transaction>) async {
        guard let transaction = try? checkVerified(result) else { return }
        await updateEntitlement()
        await transaction.finish()
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error): throw error
        case .verified(let safe): return safe
        }
    }

    // MARK: - Display helpers

    /// e.g. "7-day free trial" when the product has a free introductory offer.
    func introOfferText(for product: Product) -> String? {
        guard let offer = product.subscription?.introductoryOffer,
              offer.paymentMode == .freeTrial else { return nil }
        let period = offer.period
        // A "P1W" trial reads more naturally as "7-day".
        if period.unit == .week { return "\(period.value * 7)-day free trial" }
        let unit = unitLabel(period.unit)
        return "\(period.value)-\(unit)\(period.value > 1 ? "s" : "") free trial"
    }

    /// e.g. "/month", "/year" for a subscription product; nil otherwise.
    func periodText(for product: Product) -> String? {
        guard let period = product.subscription?.subscriptionPeriod else { return nil }
        switch period.unit {
        case .day: return "/day"
        case .week: return "/week"
        case .month: return "/month"
        case .year: return "/year"
        @unknown default: return nil
        }
    }

    private func unitLabel(_ unit: Product.SubscriptionPeriod.Unit) -> String {
        switch unit {
        case .day: return "day"
        case .week: return "week"
        case .month: return "month"
        case .year: return "year"
        @unknown default: return "day"
        }
    }

    #if DEBUG
    /// Force the premium entitlement on for development, so premium-gated screens
    /// can be exercised without a StoreKit purchase. Sticks for the session;
    /// DEBUG builds only.
    func grantForTesting() {
        isPremium = true
    }

    /// Quick UI reset for development. Clears only the in-memory flag; the
    /// StoreKit transaction is cleared via Xcode's Transaction Manager.
    func resetForTesting() {
        isPremium = false
    }
    #endif
}
