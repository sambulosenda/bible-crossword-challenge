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
//  project exists, it just doesn't send anything. It is also a no-op on the
//  simulator (see `isEnabled`).
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

    private static var isEnabled: Bool {
        apiKey.hasPrefix("phc_") && !AnalyticsEnvironment.isSuppressedSimulatorRun
    }

    static func configure() {
        guard isEnabled else { return }

        let config = PostHogConfig(projectToken: apiKey, host: host)
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
        // On by default, and wrong for this app: it flags 3 taps landing within
        // 30pt and 1s of each other as `$rageclick`. On a grid whose cells are
        // smaller than that threshold, filling three neighbouring squares at a
        // normal solving pace trips it. Frustration and fluency would be
        // indistinguishable, and every fast solver would look furious.
        config.rageClickConfig.enabled = false

        #if DEBUG
        // Logs each batch and its HTTP result, which is the only way to tell a
        // working key from a silently-dropped one — capture() never throws.
        config.debug = true
        #endif

        PostHogSDK.shared.setup(config)

        #if DEBUG
        // Simulator runs no longer get this far, so what's left is a debug
        // build on a real device — our own phones. Stamped so the project's
        // "filter internal and test users" rules can exclude them.
        //
        // Those rules now exist (project 137822, set 2026-08-09):
        // `build_type is_not debug` and `$device_model is_not arm64`, with
        // new insights defaulting to applying them.
        //
        // Both are needed, and the second is not redundant. `register` can
        // only run *after* `setup`, and the SDK captures `Application
        // Installed` during setup — so that one event escapes without this
        // property. In the recorded history that is 13 of 14 simulator
        // installs carrying no `build_type` at all; only `$device_model`
        // catches them.
        PostHogSDK.shared.register(["build_type": "debug"])
        #endif

        // `personProfiles` stays at its `.identifiedOnly` default: the app has
        // no accounts and never calls `identify`, so every event is anonymous.
        // Funnels and retention still work off `distinct_id`, and anonymous
        // events bill at the cheaper rate.
    }

    func log(_ event: AnalyticsEvent) {
        guard Self.isEnabled else { return }
        PostHogSDK.shared.capture(event.name, properties: event.parameters)
    }
}
