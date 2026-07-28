//
//  FirebaseAnalyticsService.swift
//  Bible Crossword Challenge
//
//  Production analytics backend. Forwards each `AnalyticsEvent`'s name and
//  parameters to Firebase Analytics. `FirebaseApp.configure()` must run first
//  (see Bible_Crossword_ChallengeApp.init). The DEBUG console mirror now lives
//  in `ConsoleAnalyticsService`, which `MultiAnalyticsService.production`
//  composes alongside this one — otherwise every event printed twice once
//  PostHog joined the fan-out.
//
//  `log` is unguarded on purpose: on the simulator `configure()` switches
//  collection off at the SDK, which also silences the events Firebase collects
//  by itself (`first_open`, `session_start`, …) — a guard here would not.
//

import Foundation
import FirebaseAnalytics

struct FirebaseAnalyticsService: AnalyticsService {
    static let shared = FirebaseAnalyticsService()

    /// Must run after `FirebaseApp.configure()`, which is what starts
    /// collection in the first place.
    static func configure() {
        #if targetEnvironment(simulator)
        // Firebase persists this flag across launches, so it has to be set
        // both ways rather than only when suppressing: a simulator that once
        // ran silenced would stay silenced, quietly defeating
        // `-analyticsAllowSimulator` on the next run. Guarded to the simulator
        // so device builds keep Firebase's own default untouched.
        Analytics.setAnalyticsCollectionEnabled(!AnalyticsEnvironment.isSuppressedSimulatorRun)
        #endif
    }

    func log(_ event: AnalyticsEvent) {
        Analytics.logEvent(event.name, parameters: event.parameters)
    }
}
