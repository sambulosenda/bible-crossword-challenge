//
//  FirebaseAnalyticsService.swift
//  Bible Crossword Challenge
//
//  Production analytics backend. Forwards each `AnalyticsEvent`'s name and
//  parameters to Firebase Analytics. `FirebaseApp.configure()` must run first
//  (see Bible_Crossword_ChallengeApp.init). In DEBUG it also mirrors to the
//  console so events are visible while developing.
//

import Foundation
import FirebaseAnalytics

struct FirebaseAnalyticsService: AnalyticsService {
    static let shared = FirebaseAnalyticsService()

    func log(_ event: AnalyticsEvent) {
        #if DEBUG
        print("📊 \(event.name) \(event.parameters)")
        #endif
        Analytics.logEvent(event.name, parameters: event.parameters)
    }
}
