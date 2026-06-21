//
//  StoreService.swift
//  Bible Crossword Challenge
//
//  Premium entitlement. This is a LOCAL PLACEHOLDER backed by UserDefaults so
//  the paywall and gating work end-to-end. Replace `purchase()` / `restore()`
//  with StoreKit 2 (`Product.products(for:)`, `product.purchase()`,
//  `Transaction.currentEntitlements`) before shipping the £4.99 IAP.
//

import Foundation
import Observation

@Observable
final class StoreService {
    private static let key = "premium.unlocked"

    private(set) var isPremium: Bool

    /// Display price — wire to the real StoreKit `Product.displayPrice` later.
    let displayPrice = "£4.99"

    var onPurchase: (() -> Void)?

    init() {
        isPremium = UserDefaults.standard.bool(forKey: Self.key)
    }

    /// Placeholder purchase. Real implementation must await StoreKit.
    func purchase() {
        isPremium = true
        UserDefaults.standard.set(true, forKey: Self.key)
        onPurchase?()
    }

    func restore() {
        isPremium = UserDefaults.standard.bool(forKey: Self.key)
    }

    #if DEBUG
    /// Test affordance to clear the entitlement.
    func resetForTesting() {
        isPremium = false
        UserDefaults.standard.set(false, forKey: Self.key)
    }
    #endif
}
