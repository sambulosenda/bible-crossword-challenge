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

/// How a purchase attempt ended. A plain `Bool` collapsed "cancelled",
/// "awaiting approval", and "the payment failed" into one value, which made
/// `premium_purchased` the only thing analytics could ever see — every
/// non-purchase looked identical to never having tapped Buy.
enum PurchaseOutcome: Equatable {
    /// Premium is now owned. `isTrial` reflects what StoreKit actually applied
    /// to the transaction, not what the product advertises: a player who has
    /// already used the introductory offer is charged immediately, and their
    /// purchase must not be counted as a trial start.
    case purchased(isTrial: Bool)
    case cancelled
    /// Ask to Buy / deferred payment — no entitlement yet, may arrive later.
    case pending
    case failed(reason: String)
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

    private let analytics: any AnalyticsService

    /// Where the player was when they last tapped Buy. StoreKit knows nothing
    /// about paywalls, so a grant that arrives minutes later — Ask to Buy, or a
    /// sheet finished after the app was backgrounded — would otherwise lose the
    /// attribution the whole paywall-source analysis rests on.
    private var pendingSource: String?

    /// Transactions already reported. StoreKit deliberately hands the same
    /// transaction to both `Product.purchase()` and `Transaction.updates`, and
    /// re-delivers anything left unfinished on the next launch, so without this
    /// a single sale is counted two or three times.
    private var reportedTransactionIDs: Set<UInt64>

    private static let reportedIDsKey = "storekit.reportedTransactionIDs"
    /// Enough to cover any plausible backlog of unfinished transactions without
    /// letting the list grow for the lifetime of the install.
    private static let reportedIDsLimit = 100

    init(analytics: any AnalyticsService = MultiAnalyticsService.production) {
        self.analytics = analytics
        let stored = UserDefaults.standard.array(forKey: Self.reportedIDsKey) as? [NSNumber] ?? []
        self.reportedTransactionIDs = Set(stored.map { $0.uint64Value })

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

    /// Start a purchase for a specific plan. `source` is the paywall the tap
    /// came from; it is remembered for the whole attempt so a grant that lands
    /// out-of-band later is still attributed to the right entry point.
    @discardableResult
    func purchase(_ product: Product, source: String) async -> PurchaseOutcome {
        purchaseInFlight = true
        pendingSource = source
        defer { purchaseInFlight = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                let isTrial = transaction.offer?.type == .introductory
                await updateEntitlement()
                // Report before finishing: a crash between the two would
                // otherwise drop the sale entirely, whereas re-delivery of an
                // unfinished transaction is caught by the reported-ID set.
                report(transaction, acquisition: "in_app")
                await transaction.finish()
                // `isPremium` can still be false if the entitlement didn't land
                // (a revoked or superseded transaction), so report the failure
                // rather than claiming a sale.
                return isPremium
                    ? .purchased(isTrial: isTrial)
                    : .failed(reason: "entitlement_not_granted")
            case .userCancelled:
                // Nothing is coming, so drop the attribution rather than let it
                // sit and mislabel whatever grant happens to arrive next.
                pendingSource = nil
                return .cancelled
            case .pending:
                // Ask to Buy / deferred payment — without this the player sees
                // the button reset and assumes the purchase silently failed.
                // `pendingSource` deliberately survives: approval can be days
                // away, and this is the only record of where it started.
                purchaseNotice = PurchaseNotice(
                    title: "Purchase Pending",
                    message: "Your purchase is waiting for approval. Premium unlocks automatically once it's approved."
                )
                return .pending
            @unknown default:
                pendingSource = nil
                return .failed(reason: "unknown_result")
            }
        } catch {
            pendingSource = nil
            purchaseNotice = PurchaseNotice(
                title: "Purchase Failed",
                message: "The purchase didn't go through — you haven't been charged. Please try again.\n\n\(error.localizedDescription)"
            )
            #if DEBUG
            print("⚠️ StoreKit: purchase failed — \(error)")
            #endif
            return .failed(reason: Self.failureSlug(for: error))
        }
    }

    /// A stable, low-cardinality label for a purchase failure. Never the raw
    /// error text: that is localised and unbounded, so it would fragment into
    /// thousands of distinct analytics values that can't be grouped.
    private static func failureSlug(for error: Error) -> String {
        switch error {
        case is VerificationResult<Transaction>.VerificationError:
            return "verification_failed"
        case let storeKitError as StoreKitError:
            switch storeKitError {
            case .networkError: return "network"
            case .systemError: return "system"
            case .userCancelled: return "cancelled"
            case .notAvailableInStorefront: return "not_in_storefront"
            case .notEntitled: return "not_entitled"
            case .unknown: return "unknown"
            @unknown default: return "unknown"
            }
        case let purchaseError as Product.PurchaseError:
            switch purchaseError {
            case .invalidQuantity: return "invalid_quantity"
            case .productUnavailable: return "product_unavailable"
            case .purchaseNotAllowed: return "not_allowed"
            case .ineligibleForOffer: return "ineligible_for_offer"
            case .invalidOfferIdentifier: return "invalid_offer_id"
            case .invalidOfferPrice: return "invalid_offer_price"
            case .invalidOfferSignature: return "invalid_offer_signature"
            case .missingOfferParameters: return "missing_offer_params"
            @unknown default: return "purchase_error"
            }
        default:
            return "other"
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
        // Everything StoreKit grants without an in-app tap arrives here:
        // renewals, Ask to Buy approvals, family sharing, purchases made on
        // another device, and any sheet that finished while the app was away.
        report(transaction, acquisition: "external")
        await transaction.finish()
    }

    // MARK: - Purchase reporting

    /// Emit exactly one analytics event for a verified transaction, whichever
    /// path delivered it.
    ///
    /// This is the single choke point on purpose. The event used to be logged
    /// by the paywall views, which could only see purchases that completed
    /// inside one uninterrupted `await` — so renewals, deferred approvals and
    /// cross-device purchases were invisible, and PostHog disagreed with App
    /// Store Connect by an order of magnitude.
    private func report(_ transaction: Transaction, acquisition: String) {
        guard Self.allProductIDs.contains(transaction.productID) else { return }
        guard !reportedTransactionIDs.contains(transaction.id) else { return }
        markReported(transaction.id)

        let plan = Self.planName(for: transaction.productID)
        let isTrial = transaction.offer?.type == .introductory
        let amount = Self.amount(for: transaction)

        // A renewal is revenue but not a new customer. Keeping it out of
        // `premium_purchased` is what lets that event stay comparable to the
        // App Store Connect purchase count.
        if transaction.reason == .renewal {
            analytics.log(.subscriptionRenewed(plan: plan, isTrial: isTrial, amount: amount))
        } else {
            analytics.log(.premiumPurchased(
                plan: plan,
                // An out-of-band grant has no live paywall behind it; fall back
                // to the last one seen rather than inventing an entry point.
                source: pendingSource ?? acquisition,
                isTrial: isTrial,
                amount: amount,
                acquisition: acquisition
            ))
            pendingSource = nil
        }
    }

    private func markReported(_ id: UInt64) {
        reportedTransactionIDs.insert(id)
        var trimmed = Array(reportedTransactionIDs)
        if trimmed.count > Self.reportedIDsLimit {
            // Highest ids are the most recent, and only recent transactions can
            // still be re-delivered, so the oldest are safe to forget.
            trimmed = Array(trimmed.sorted(by: >).prefix(Self.reportedIDsLimit))
            reportedTransactionIDs = Set(trimmed)
        }
        UserDefaults.standard.set(trimmed.map { NSNumber(value: $0) }, forKey: Self.reportedIDsKey)
    }

    private static func planName(for productID: String) -> String {
        switch productID {
        case yearlyID: return "yearly"
        case monthlyID: return "monthly"
        case lifetimeID: return "lifetime"
        default: return "unknown"
        }
    }

    /// Price straight off the transaction. A renewal can arrive when no
    /// `Product` has been loaded — and at a price that has since changed — so
    /// the transaction is the only trustworthy source for what was charged.
    private static func amount(for transaction: Transaction) -> PurchaseAmount {
        let code = transaction.currency?.identifier ?? "USD"
        let price = transaction.price ?? 0
        return PurchaseAmount(
            minorUnits: minorUnits(of: price, currencyCode: code),
            currencyCode: code
        )
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error): throw error
        case .verified(let safe): return safe
        }
    }

    // MARK: - Analytics helpers

    /// A price in the form analytics should carry money: a whole number of the
    /// currency's minor unit. Never a `Double` — StoreKit hands us an exact
    /// `Decimal`, and converting to binary floating point at the last step
    /// reintroduces the drift that summing thousands of prices would compound.
    struct PurchaseAmount: Equatable {
        /// 2999 for $29.99, 500 for ¥500, 29990 for 29.990 KWD.
        let minorUnits: Int
        /// ISO 4217, e.g. "USD".
        let currencyCode: String
    }

    /// Scales a decimal price into whole minor units.
    ///
    /// The exponent is per-currency and *not* always 2: JPY and KRW have none,
    /// KWD and BHD have three. Hardcoding ×100 would inflate a ¥500 sale to
    /// ¥50,000 and understate a Kuwaiti one tenfold, so the count comes from
    /// ICU via `NumberFormatter` rather than an assumption.
    static func minorUnits(of price: Decimal, currencyCode: String) -> Int {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        let exponent = Int16(formatter.maximumFractionDigits)

        // All-decimal arithmetic: multiply then round half-up to a whole unit.
        let rounding = NSDecimalNumberHandler(
            roundingMode: .plain,
            scale: 0,
            raiseOnExactness: false,
            raiseOnOverflow: false,
            raiseOnUnderflow: false,
            raiseOnDivideByZero: false
        )
        return NSDecimalNumber(decimal: price)
            .multiplying(byPowerOf10: exponent)
            .rounding(accordingToBehavior: rounding)
            .intValue
    }

    // MARK: - Display helpers

    /// A free introductory offer in the two grammatical forms the UI needs.
    ///
    /// One string cannot serve both positions. "3-day free trial" is right in
    /// front of a noun; "Free for 3 days" is right after a preposition. The
    /// paywall used to derive the second from the first by trimming
    /// " free trial" off it, which shipped "Free for 3-days" against the real
    /// product and "Free for 7-day" against the local StoreKit config — wrong
    /// in both, differently.
    struct IntroOffer {
        /// Compound adjective, never pluralised: "3-day", "7-day", "1-month".
        /// The `s` belongs to `duration`; in front of a noun it is not English.
        let length: String
        /// Standalone duration, pluralised normally: "3 days", "1 month".
        let duration: String
        /// "3-day free trial" — the phrase the UI uses on its own.
        var trialText: String { "\(length) free trial" }
    }

    /// The product's free trial, or nil if it has no introductory free offer.
    func introOffer(for product: Product) -> IntroOffer? {
        guard let offer = product.subscription?.introductoryOffer,
              offer.paymentMode == .freeTrial else { return nil }
        let period = offer.period
        // A "P1W" trial reads more naturally in days than in weeks.
        let value = period.unit == .week ? period.value * 7 : period.value
        let unit = period.unit == .week ? "day" : unitLabel(period.unit)
        return IntroOffer(
            length: "\(value)-\(unit)",
            duration: "\(value) \(unit)\(value == 1 ? "" : "s")"
        )
    }

    /// e.g. "7-day free trial" when the product has a free introductory offer.
    func introOfferText(for product: Product) -> String? {
        introOffer(for: product)?.trialText
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
