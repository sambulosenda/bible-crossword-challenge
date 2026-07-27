//
//  PurchaseAmountTests.swift
//  Bible Crossword ChallengeTests
//
//  Pins the price → minor-unit conversion that analytics revenue depends on.
//  A wrong exponent here doesn't crash or look broken; it silently reports
//  revenue off by a factor of 100, which is the kind of number a pricing
//  decision gets made on.
//

import Testing
import Foundation
@testable import Bible_Crossword_Challenge

struct PurchaseAmountTests {

    @Test func twoDecimalCurrenciesScaleByOneHundred() {
        #expect(StoreService.minorUnits(of: 29.99, currencyCode: "USD") == 2999)
        #expect(StoreService.minorUnits(of: 4.99, currencyCode: "GBP") == 499)
        #expect(StoreService.minorUnits(of: 10, currencyCode: "EUR") == 1000)
    }

    /// The case a hardcoded ×100 gets wrong: yen has no minor unit, so ¥500
    /// must stay 500 rather than becoming ¥50,000.
    @Test func zeroDecimalCurrenciesAreNotScaled() {
        #expect(StoreService.minorUnits(of: 500, currencyCode: "JPY") == 500)
        #expect(StoreService.minorUnits(of: 7000, currencyCode: "KRW") == 7000)
    }

    /// The opposite error: three-decimal currencies would be understated
    /// tenfold by a ×100 assumption.
    @Test func threeDecimalCurrenciesScaleByOneThousand() {
        #expect(StoreService.minorUnits(of: 2.999, currencyCode: "KWD") == 2999)
        #expect(StoreService.minorUnits(of: 1.5, currencyCode: "BHD") == 1500)
    }

    /// Prices arrive from StoreKit as exact `Decimal`s. The conversion must stay
    /// in decimal arithmetic — the same value via `Double` rounds to 811 here.
    @Test func decimalPrecisionSurvivesTheConversion() {
        #expect(StoreService.minorUnits(of: Decimal(string: "8.115")!, currencyCode: "USD") == 812)
        #expect(StoreService.minorUnits(of: Decimal(string: "0.01")!, currencyCode: "USD") == 1)
    }

    @Test func freeIsZeroNotNil() {
        #expect(StoreService.minorUnits(of: 0, currencyCode: "USD") == 0)
    }
}
