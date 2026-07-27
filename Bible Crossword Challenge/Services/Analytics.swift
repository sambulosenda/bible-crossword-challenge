//
//  Analytics.swift
//  Bible Crossword Challenge
//
//  Analytics abstraction. `FirebaseAnalyticsService` is the production backend
//  (the environment default — see AppEnvironment). `ConsoleAnalyticsService`
//  remains for previews/tests that want no network side effects.
//

import Foundation

enum AnalyticsEvent {
    case appOpen
    // First-run funnel. `onboardingStep` fires on every entry to a page, so
    // count distinct users per step rather than raw events; the other two fire
    // once each. Together they answer the question the redesign was a bet on:
    // does solving a clue up front make people finish onboarding?
    case onboardingStep(index: Int, name: String)
    case onboardingFirstSolve(solved: Bool, attempts: Int)
    case onboardingCompleted(solvedFirstClue: Bool)
    case dailyPuzzleStarted(puzzleID: String)
    case dailyPuzzleCompleted(puzzleID: String, seconds: Int)
    case hintUsed(type: String)
    case streakUpdated(streak: Int)
    case achievementUnlocked(id: String)
    // Purchases. `isTrial` is what StoreKit actually applied, so a trial start
    // and a paid conversion are never counted as the same thing — the yearly
    // plan carries a free trial and is the default selection, so without this
    // nearly every "purchase" is really a trial that may still churn.
    case premiumPurchased(plan: String, source: String, isTrial: Bool, price: Decimal, currency: String)
    /// Fires when a purchase attempt ends without an entitlement for a reason
    /// other than the player simply cancelling, so "opened the paywall and
    /// didn't buy" can be split from "tried to buy and it broke".
    case purchaseFailed(plan: String, source: String, reason: String)
    case paywallOpened(source: String)
    case notificationPermission(granted: Bool)
    case reminderSettingChanged(enabled: Bool)
    case packOpened(id: String)
    case packCompleted(id: String)
    case challengeSent(puzzleID: String)
    case challengeOpened(puzzleID: String)
    case challengeCompleted(puzzleID: String, won: Bool, deltaSeconds: Int)
    case challengeRematchSent(puzzleID: String)

    var name: String {
        switch self {
        case .appOpen: return "app_open"
        case .onboardingStep: return "onboarding_step"
        case .onboardingFirstSolve: return "onboarding_first_solve"
        case .onboardingCompleted: return "onboarding_completed"
        case .dailyPuzzleStarted: return "daily_puzzle_started"
        case .dailyPuzzleCompleted: return "daily_puzzle_completed"
        case .hintUsed: return "hint_used"
        case .streakUpdated: return "streak_updated"
        case .achievementUnlocked: return "achievement_unlocked"
        case .premiumPurchased: return "premium_purchased"
        case .purchaseFailed: return "purchase_failed"
        case .paywallOpened: return "paywall_opened"
        case .notificationPermission: return "notification_permission"
        case .reminderSettingChanged: return "reminder_setting_changed"
        case .packOpened: return "pack_opened"
        case .packCompleted: return "pack_completed"
        case .challengeSent: return "challenge_sent"
        case .challengeOpened: return "challenge_opened"
        case .challengeCompleted: return "challenge_completed"
        case .challengeRematchSent: return "challenge_rematch_sent"
        }
    }

    var parameters: [String: Any] {
        switch self {
        case .appOpen:
            return [:]
        case .onboardingStep(let index, let name):
            return ["step_index": index, "step_name": name]
        case .onboardingFirstSolve(let solved, let attempts):
            return ["solved": solved, "attempts": attempts]
        case .onboardingCompleted(let solvedFirstClue):
            return ["solved_first_clue": solvedFirstClue]
        case .premiumPurchased(let plan, let source, let isTrial, let price, let currency):
            return [
                "plan": plan,
                "source": source,
                "is_trial": isTrial,
                // The plan's list price, always — what the player will pay.
                "price": NSDecimalNumber(decimal: price).doubleValue,
                // What was charged *now*, so summing this across a source gives
                // real money rather than the notional value of free trials.
                "revenue": isTrial ? 0 : NSDecimalNumber(decimal: price).doubleValue,
                "currency": currency,
            ]
        case .purchaseFailed(let plan, let source, let reason):
            return ["plan": plan, "source": source, "reason": reason]
        case .paywallOpened(let source):
            return ["source": source]
        case .dailyPuzzleStarted(let id):
            return ["puzzle_id": id]
        case .dailyPuzzleCompleted(let id, let seconds):
            return ["puzzle_id": id, "seconds": seconds]
        case .hintUsed(let type):
            return ["type": type]
        case .streakUpdated(let streak):
            return ["streak": streak]
        case .achievementUnlocked(let id):
            return ["achievement_id": id]
        case .notificationPermission(let granted):
            return ["granted": granted]
        case .reminderSettingChanged(let enabled):
            return ["enabled": enabled]
        case .packOpened(let id):
            return ["pack_id": id]
        case .packCompleted(let id):
            return ["pack_id": id]
        case .challengeSent(let id):
            return ["puzzle_id": id]
        case .challengeOpened(let id):
            return ["puzzle_id": id]
        case .challengeCompleted(let id, let won, let delta):
            return ["puzzle_id": id, "won": won, "delta_seconds": delta]
        case .challengeRematchSent(let id):
            return ["puzzle_id": id]
        }
    }
}

protocol AnalyticsService {
    func log(_ event: AnalyticsEvent)
}

struct ConsoleAnalyticsService: AnalyticsService {
    static let shared = ConsoleAnalyticsService()

    func log(_ event: AnalyticsEvent) {
        #if DEBUG
        print("📊 \(event.name) \(event.parameters)")
        #endif
    }
}

/// Sends each event to every backend. Order is the order given; a slow or
/// misconfigured backend can't stop the others, because none of them throw.
struct MultiAnalyticsService: AnalyticsService {
    let services: [any AnalyticsService]

    init(_ services: [any AnalyticsService]) {
        self.services = services
    }

    func log(_ event: AnalyticsEvent) {
        for service in services {
            service.log(event)
        }
    }
}

extension MultiAnalyticsService {
    /// The production sink for the Firebase → PostHog overlap. Both backends
    /// collect everything so the two can be reconciled before Firebase is
    /// dropped; the Firebase half exists to keep the paywall-source history
    /// that started on 2026-07-19 continuous through the switch.
    static let production = MultiAnalyticsService([
        ConsoleAnalyticsService.shared,
        FirebaseAnalyticsService.shared,
        PostHogAnalyticsService.shared,
    ])
}
