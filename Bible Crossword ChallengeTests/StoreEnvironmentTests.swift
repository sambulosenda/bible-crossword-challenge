//
//  StoreEnvironmentTests.swift
//  Bible Crossword ChallengeTests
//
//  The `store_environment` label PostHog filters on. A wrong mapping would
//  either keep App Review in the paywall numbers or, worse, drop real
//  players from them.
//

import Testing
import StoreKit
@testable import Bible_Crossword_Challenge

struct StoreEnvironmentTests {

    @Test func productionIsProduction() {
        #expect(StoreEnvironment.label(forRawValue: AppStore.Environment.production.rawValue) == "production")
    }

    /// App Review and TestFlight both buy in the sandbox: this is the value
    /// the filter drops.
    @Test func sandboxIsSandbox() {
        #expect(StoreEnvironment.label(forRawValue: AppStore.Environment.sandbox.rawValue) == "sandbox")
    }

    @Test func xcodeIsXcode() {
        #expect(StoreEnvironment.label(forRawValue: AppStore.Environment.xcode.rawValue) == "xcode")
    }

    /// An environment Apple adds later must never read as production.
    @Test func unknownPassesThroughLowercased() {
        #expect(StoreEnvironment.label(forRawValue: "Preview") == "preview")
    }

    @Test func propertyNameMatchesTheFilter() {
        #expect(StoreEnvironment.propertyName == "store_environment")
    }
}
