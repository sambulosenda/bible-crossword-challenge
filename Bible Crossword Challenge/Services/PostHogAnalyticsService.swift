//
//  PostHogAnalyticsService.swift
//  Bible Crossword Challenge
//
//  Second production analytics backend, running alongside Firebase during the
//  migration overlap (see MultiAnalyticsService.production). PostHog is here for
//  the questions Firebase's console can't answer without a BigQuery export:
//  the onboarding funnel and paywall source → purchase conversion.
//
//  `configure()` must run before any `log`, and is a no-op until `apiKey` is a
//  real project key — so the app builds and runs fine before the PostHog
//  project exists, it just doesn't send anything.
//

import Foundation
import PostHog

struct PostHogAnalyticsService: AnalyticsService {
    static let shared = PostHogAnalyticsService()

    /// Project API key for PostHog project 137822. This is a write-only client
    /// key and is meant to ship in the binary; it is not a secret. It must stay
    /// the key for *this* project — a key from another project in the org would
    /// silently merge two unrelated event streams.
    private static let apiKey = "phc_sQnGkpXee9YHntnCRAWIMvjOng1iY7wau2AKtTUPG0A"

    /// EU cloud, matching where the account lives. A US-cloud key sent here
    /// fails silently, so these two travel together.
    private static let host = "https://eu.i.posthog.com"

    private static var isConfigured: Bool { apiKey.hasPrefix("phc_") }

    static func configure() {
        guard isConfigured else { return }

        let config = PostHogConfig(apiKey: apiKey, host: host)
        // Lifecycle capture stays on for `Application Installed` and
        // `Application Updated`: our own `app_open` fires on every launch and
        // so can't tell a first-ever open from the hundredth, which is exactly
        // what activation and new-vs-returning analysis need. `Application
        // Updated` carries previous_version/previous_build, which is how a
        // release's effect gets separated from the one before it. These are a
        // handful of events per install — the quota argument doesn't apply.
        // (It duplicates `app_open` slightly; that stays only for Firebase
        // parity during the overlap and can go once Firebase does.)
        config.captureApplicationLifecycleEvents = true
        // Screen views do stay off: one grid, one paywall and a few sheets
        // produce noise that restates what the explicit events already say.
        config.captureScreenViews = false
        // Off deliberately: replay burns event quota fast and tells us little
        // about a crossword grid. Revisit only for a specific stuck-user question.
        config.sessionReplay = false

        #if DEBUG
        // Logs each batch and its HTTP result, which is the only way to tell a
        // working key from a silently-dropped one — capture() never throws.
        config.debug = true
        #endif

        PostHogSDK.shared.setup(config)

        #if DEBUG
        // Stamps every dev/simulator event so a "filter internal and test
        // users" rule on `build_type` can exclude them. The rule has to be
        // added in project settings — this only supplies the property.
        PostHogSDK.shared.register(["build_type": "debug"])
        #endif

        // `personProfiles` stays at its `.identifiedOnly` default: the app has
        // no accounts and never calls `identify`, so every event is anonymous.
        // Funnels and retention still work off `distinct_id`, and anonymous
        // events bill at the cheaper rate.
    }

    func log(_ event: AnalyticsEvent) {
        guard Self.isConfigured else { return }
        PostHogSDK.shared.capture(event.name, properties: event.parameters)
    }
}
