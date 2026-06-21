//
//  Persistence.swift
//  Bible Crossword Challenge
//
//  SwiftData models for the single local player profile and per-puzzle
//  progress, plus the streak/achievement rules that operate on them.
//  No authentication in v1 — everything is stored on device.
//

import Foundation
import SwiftData

// MARK: - Player profile (single row)

@Model
final class PlayerProfile {
    var username: String
    var currentStreak: Int
    var bestStreak: Int
    var totalPuzzlesCompleted: Int
    var lastCompletedDate: Date?
    var hintsUsedToday: Int
    var hintsDate: Date?
    var unlockedAchievementIDs: [String]
    var createdAt: Date

    init(
        username: String = "Friend",
        currentStreak: Int = 0,
        bestStreak: Int = 0,
        totalPuzzlesCompleted: Int = 0,
        lastCompletedDate: Date? = nil,
        hintsUsedToday: Int = 0,
        hintsDate: Date? = nil,
        unlockedAchievementIDs: [String] = [],
        createdAt: Date = Date()
    ) {
        self.username = username
        self.currentStreak = currentStreak
        self.bestStreak = bestStreak
        self.totalPuzzlesCompleted = totalPuzzlesCompleted
        self.lastCompletedDate = lastCompletedDate
        self.hintsUsedToday = hintsUsedToday
        self.hintsDate = hintsDate
        self.unlockedAchievementIDs = unlockedAchievementIDs
        self.createdAt = createdAt
    }
}

// MARK: - Per-puzzle progress / completion record

@Model
final class PuzzleRecord {
    @Attribute(.unique) var puzzleID: String
    var isCompleted: Bool
    var completedDate: Date?
    var elapsedSeconds: Int
    /// Encoded `[String: String]` of position storage-key -> letter, for resume.
    var entriesData: Data?
    var updatedAt: Date

    init(
        puzzleID: String,
        isCompleted: Bool = false,
        completedDate: Date? = nil,
        elapsedSeconds: Int = 0,
        entriesData: Data? = nil,
        updatedAt: Date = Date()
    ) {
        self.puzzleID = puzzleID
        self.isCompleted = isCompleted
        self.completedDate = completedDate
        self.elapsedSeconds = elapsedSeconds
        self.entriesData = entriesData
        self.updatedAt = updatedAt
    }

    var entries: [String: String] {
        get {
            guard let entriesData,
                  let decoded = try? JSONDecoder().decode([String: String].self, from: entriesData)
            else { return [:] }
            return decoded
        }
        set { entriesData = try? JSONEncoder().encode(newValue) }
    }
}

// MARK: - Hint helpers

extension PlayerProfile {
    static let freeHintLimit = 3

    func hintsRemaining(isPremium: Bool, now: Date = Date(), calendar: Calendar = .current) -> Int {
        if isPremium { return .max }
        let usedToday = calendar.isDate(hintsDate ?? .distantPast, inSameDayAs: now) ? hintsUsedToday : 0
        return max(0, Self.freeHintLimit - usedToday)
    }

    func consumeHint(now: Date = Date(), calendar: Calendar = .current) {
        if !calendar.isDate(hintsDate ?? .distantPast, inSameDayAs: now) {
            hintsUsedToday = 0
        }
        hintsUsedToday += 1
        hintsDate = now
    }
}

// MARK: - Streak rules

enum Streaks {
    /// Called on app launch: drops a stale streak to zero if a day was missed.
    static func normalize(_ p: PlayerProfile, now: Date = Date(), calendar: Calendar = .current) {
        guard let last = p.lastCompletedDate else {
            p.currentStreak = 0
            return
        }
        let today = calendar.startOfDay(for: now)
        let lastDay = calendar.startOfDay(for: last)
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else { return }
        if lastDay < yesterday {
            p.currentStreak = 0
        }
    }

    /// Called when a puzzle is completed. Returns true if the streak advanced today.
    @discardableResult
    static func registerCompletion(_ p: PlayerProfile, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        let today = calendar.startOfDay(for: now)
        var advanced = false

        if let last = p.lastCompletedDate {
            let lastDay = calendar.startOfDay(for: last)
            if lastDay == today {
                // Already completed a puzzle today — count the puzzle, leave the streak.
            } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: today), lastDay == yesterday {
                p.currentStreak += 1
                advanced = true
            } else {
                p.currentStreak = 1
                advanced = true
            }
        } else {
            p.currentStreak = 1
            advanced = true
        }

        if calendar.startOfDay(for: p.lastCompletedDate ?? .distantPast) != today {
            p.lastCompletedDate = today
        }
        p.totalPuzzlesCompleted += 1
        p.bestStreak = max(p.bestStreak, p.currentStreak)
        return advanced
    }
}

// MARK: - Achievements

struct Achievement: Identifiable, Hashable {
    enum Goal: Hashable {
        case puzzles(Int)
        case streak(Int)
    }

    let id: String
    let title: String
    let detail: String
    let symbol: String
    let goal: Goal

    func isUnlocked(by p: PlayerProfile) -> Bool {
        progress(for: p) >= 1.0
    }

    func progress(for p: PlayerProfile) -> Double {
        switch goal {
        case .puzzles(let target):
            return min(1.0, Double(p.totalPuzzlesCompleted) / Double(target))
        case .streak(let target):
            return min(1.0, Double(max(p.bestStreak, p.currentStreak)) / Double(target))
        }
    }

    /// e.g. "3 / 5" — current value over the goal target.
    func progressText(for p: PlayerProfile) -> String {
        switch goal {
        case .puzzles(let target):
            return "\(min(p.totalPuzzlesCompleted, target)) / \(target)"
        case .streak(let target):
            return "\(min(max(p.bestStreak, p.currentStreak), target)) / \(target)"
        }
    }
}

enum Achievements {
    static let all: [Achievement] = [
        Achievement(id: "bible-beginner", title: "Bible Beginner", detail: "Complete 5 puzzles", symbol: "book", goal: .puzzles(5)),
        Achievement(id: "disciple", title: "Disciple", detail: "Complete 25 puzzles", symbol: "figure.walk", goal: .puzzles(25)),
        Achievement(id: "scholar", title: "Scholar", detail: "Complete 100 puzzles", symbol: "graduationcap", goal: .puzzles(100)),
        Achievement(id: "evangelist", title: "Evangelist", detail: "Reach a 30 day streak", symbol: "flame", goal: .streak(30)),
        Achievement(id: "apostle", title: "Apostle", detail: "Reach a 100 day streak", symbol: "crown", goal: .streak(100)),
    ]

    /// Returns achievement IDs newly satisfied that aren't already recorded.
    static func newlyUnlocked(for p: PlayerProfile) -> [Achievement] {
        let already = Set(p.unlockedAchievementIDs)
        return all.filter { $0.isUnlocked(by: p) && !already.contains($0.id) }
    }
}
