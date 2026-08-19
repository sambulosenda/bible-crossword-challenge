//
//  PurchaseFlowTests.swift
//  Bible Crossword ChallengeTests
//
//  End-to-end purchase through the real StoreService → RevenueCat → StoreKit
//  pipeline, against a local StoreKit test session built from the same
//  Products.storekit the scheme uses. This is the check that a bought yearly
//  trial actually comes back as the "pro" entitlement — the one seam a build
//  can't prove by compiling.
//
//  Runs on the simulator only (SKTestSession needs the test environment), and
//  reaches RevenueCat's sandbox over the network: a failure here can mean the
//  entitlement mapping is broken OR that connectivity is absent — read the
//  outcome value before blaming the code.
//

import Testing
import StoreKit
import StoreKitTest
@testable import Bible_Crossword_Challenge

@MainActor
struct PurchaseFlowTests {

    /// The scheme's StoreKit configuration, located from this file's own path
    /// so the test needs no bundle-membership changes for the .storekit file.
    private static var configurationURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Bible Crossword ChallengeTests/
            .deletingLastPathComponent() // repo root
            .appendingPathComponent("Bible Crossword Challenge/Products.storekit")
    }

    @Test func yearlyTrialPurchaseGrantsPremium() async throws {
        let session = try SKTestSession(contentsOf: Self.configurationURL)
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()

        let store = StoreService(analytics: ConsoleAnalyticsService.shared)
        await store.refresh()
        let yearly = try #require(store.yearly, "yearly product should load from the current offering")

        let outcome = await store.purchase(yearly, source: "purchase-flow-test")

        #expect(outcome == .purchased(isTrial: true), "trial purchase should complete and be recognised as a trial")
        #expect(store.isPremium, "the pro entitlement should be active after purchase")
    }
}
