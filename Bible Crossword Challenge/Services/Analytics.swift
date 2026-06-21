//
//  Analytics.swift
//  Bible Crossword Challenge
//
//  Analytics abstraction. The console implementation is used by default; a
//  FirebaseAnalyticsService can conform to `AnalyticsService` and forward
//  `event.name` / `event.parameters` to Firebase once the SDK is added.
//

import Foundation

enum AnalyticsEvent {
    case appOpen
    case dailyPuzzleStarted(puzzleID: String)
    case dailyPuzzleCompleted(puzzleID: String, seconds: Int)
    case hintUsed(type: String)
    case streakUpdated(streak: Int)
    case achievementUnlocked(id: String)
    case premiumPurchased

    var name: String {
        switch self {
        case .appOpen: return "app_open"
        case .dailyPuzzleStarted: return "daily_puzzle_started"
        case .dailyPuzzleCompleted: return "daily_puzzle_completed"
        case .hintUsed: return "hint_used"
        case .streakUpdated: return "streak_updated"
        case .achievementUnlocked: return "achievement_unlocked"
        case .premiumPurchased: return "premium_purchased"
        }
    }

    var parameters: [String: Any] {
        switch self {
        case .appOpen, .premiumPurchased:
            return [:]
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
