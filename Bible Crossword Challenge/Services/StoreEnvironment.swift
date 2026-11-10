//
//  StoreEnvironment.swift
//  Bible Crossword Challenge
//
//  Which App Store the running copy of the app talks to — the real one, or
//  Apple's sandbox — stamped on every PostHog event as `store_environment`
//  so the project's internal-and-test filter can drop the sandbox.
//
//  Why: App Review tests every build with sandbox purchases and walks the
//  onboarding offer each time. In Sep 26 – Nov 9, 2026, 8 of the 34
//  onboarding `purchase_cancelled` events were reviewers (Apple-internal
//  hardware, a cancel in under 100 ms, one short session minutes after the
//  build first appeared), which turned a 62% real back-out rate into a
//  reported 68% and made "never reopened the app" look far worse than it
//  was. They are indistinguishable from players in every other field.
//  TestFlight installs are sandbox too, which is what we want filtered.
//
//  A super property, like `build_type`: the app never calls `identify`, so
//  there are no person profiles to hold it (see `FeatureFlags.registerVariant`).
//

import Foundation
import StoreKit

enum StoreEnvironment {
    /// The PostHog super property, and the key the PostHog filter names.
    static let propertyName = "store_environment"

    /// The last resolved value, so a later launch is tagged from its first
    /// event rather than from whenever `AppTransaction` answers.
    static let cacheKey = "analytics.storeEnvironment"

    /// The analytics value for a StoreKit environment: "production",
    /// "sandbox" (TestFlight and App Review) or "xcode" (a local StoreKit
    /// configuration). Takes the raw value so it is testable without a
    /// signed app; anything Apple adds later passes through lowercased
    /// rather than being mislabelled production.
    static func label(forRawValue raw: String) -> String {
        switch raw {
        case AppStore.Environment.production.rawValue: "production"
        case AppStore.Environment.sandbox.rawValue: "sandbox"
        case AppStore.Environment.xcode.rawValue: "xcode"
        default: raw.lowercased()
        }
    }

    /// The environment this copy of the app was installed from, or nil when
    /// StoreKit can't say yet. `shared`, never `refresh()`: refresh can put
    /// an App Store sign-in in front of a player at launch. An unverified
    /// transaction still names its environment correctly, and this is only
    /// an analytics label, so both cases are read.
    static func resolve() async -> String? {
        guard let result = try? await AppTransaction.shared else { return nil }
        let transaction: AppTransaction
        switch result {
        case .verified(let value), .unverified(let value, _):
            transaction = value
        }
        return label(forRawValue: transaction.environment.rawValue)
    }
}
