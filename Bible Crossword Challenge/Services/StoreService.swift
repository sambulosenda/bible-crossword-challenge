//
//  StoreService.swift
//  Bible Crossword Challenge
//
//  Premium entitlement backed by StoreKit 2. Loads the non-consumable product,
//  runs purchases, restores via `AppStore.sync()`, and tracks ownership from
//  `Transaction.currentEntitlements`. A background task listens for
//  `Transaction.updates` so entitlements granted outside the app (Ask to Buy,
//  refunds, family sharing) are reflected automatically.
//
//  The matching product must exist in App Store Connect with the identifier in
//  `productID`. Local testing uses the bundled `Products.storekit` configuration.
//

import Foundation
import StoreKit
import Observation

@Observable
final class StoreService {
    /// Non-consumable IAP identifier. Must match App Store Connect and the
    /// `Products.storekit` test configuration.
    static let productID = "com.sambulosendas1.Bible-Crossword-Challenge.premium"

    private(set) var isPremium = false
    private(set) var product: Product?
    private(set) var purchaseInFlight = false

    /// Real localized price once the product loads; falls back until then.
    var displayPrice: String { product?.displayPrice ?? "£4.99" }

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

    /// Load the product and re-check entitlement. Safe to call repeatedly.
    func refresh() async {
        await loadProduct()
        await updateEntitlement()
    }

    func loadProduct() async {
        do {
            let products = try await Product.products(for: [Self.productID])
            product = products.first
        } catch {
            #if DEBUG
            print("⚠️ StoreKit: failed to load product — \(error)")
            #endif
        }
    }

    /// Start a purchase. Returns true when the user now owns premium.
    @discardableResult
    func purchase() async -> Bool {
        if product == nil { await loadProduct() }
        guard let product else { return false }

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
            case .userCancelled, .pending:
                return false
            @unknown default:
                return false
            }
        } catch {
            #if DEBUG
            print("⚠️ StoreKit: purchase failed — \(error)")
            #endif
            return false
        }
    }

    /// Restore prior purchases (StoreKit refreshes entitlements from the store).
    func restore() async {
        try? await AppStore.sync()
        await updateEntitlement()
    }

    private func updateEntitlement() async {
        var owned = false
        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result) else { continue }
            if transaction.productID == Self.productID, transaction.revocationDate == nil {
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

    #if DEBUG
    /// Quick UI reset for development. Note: this only clears the in-memory flag;
    /// the StoreKit transaction itself is cleared via Xcode's Transaction Manager
    /// (Debug ▸ StoreKit ▸ Manage Transactions) or by deleting it there.
    func resetForTesting() {
        isPremium = false
    }
    #endif
}
