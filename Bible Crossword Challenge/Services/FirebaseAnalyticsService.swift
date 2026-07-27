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

import Foundation
import FirebaseAnalytics

struct FirebaseAnalyticsService: AnalyticsService {
    static let shared = FirebaseAnalyticsService()

    func log(_ event: AnalyticsEvent) {
        Analytics.logEvent(event.name, parameters: event.parameters)
    }
}
