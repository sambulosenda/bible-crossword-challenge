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
    /// Fastest completed solve, in seconds (nil until the first completion).
    var bestSolveSeconds: Int?
    /// Count of puzzles first solved without using any hint.
    var noHintSolves: Int = 0
    /// Count of hard puzzles completed (first completion only).
    var hardCompleted: Int = 0
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
        bestSolveSeconds: Int? = nil,
        noHintSolves: Int = 0,
        hardCompleted: Int = 0,
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
        self.bestSolveSeconds = bestSolveSeconds
        self.noHintSolves = noHintSolves
        self.hardCompleted = hardCompleted
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
    /// True once any hint was revealed on this puzzle — survives resume, so a
    /// "no hints" solve stays accurate across sessions.
    var usedHint: Bool = false
    var updatedAt: Date

    init(
        puzzleID: String,
        isCompleted: Bool = false,
        completedDate: Date? = nil,
        elapsedSeconds: Int = 0,
        entriesData: Data? = nil,
        usedHint: Bool = false,
        updatedAt: Date = Date()
    ) {
        self.puzzleID = puzzleID
        self.isCompleted = isCompleted
        self.completedDate = completedDate
        self.elapsedSeconds = elapsedSeconds
        self.entriesData = entriesData
        self.usedHint = usedHint
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
        case fastSolve(maxSeconds: Int)
        case noHints(Int)
        case difficulty(PuzzleDifficulty, Int)
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
        case .fastSolve(let max):
            // Binary: achieved once any solve beats the target time.
            guard let best = p.bestSolveSeconds else { return 0 }
            return best <= max ? 1.0 : 0.0
        case .noHints(let target):
            return min(1.0, Double(p.noHintSolves) / Double(target))
        case .difficulty(let diff, let target):
            return min(1.0, Double(count(of: diff, in: p)) / Double(target))
        }
    }

    /// e.g. "3 / 5" — current value over the goal target.
    func progressText(for p: PlayerProfile) -> String {
        switch goal {
        case .puzzles(let target):
            return "\(min(p.totalPuzzlesCompleted, target)) / \(target)"
        case .streak(let target):
            return "\(min(max(p.bestStreak, p.currentStreak), target)) / \(target)"
        case .fastSolve(let max):
            return "< \(TimeFormat.clock(max))"
        case .noHints(let target):
            return "\(min(p.noHintSolves, target)) / \(target)"
        case .difficulty(let diff, let target):
            return "\(min(count(of: diff, in: p), target)) / \(target)"
        }
    }

    /// Completion count for a difficulty. Only hard is tracked today.
    private func count(of difficulty: PuzzleDifficulty, in p: PlayerProfile) -> Int {
        difficulty == .hard ? p.hardCompleted : 0
    }
}

enum Achievements {
    static let all: [Achievement] = [
        Achievement(id: "bible-beginner", title: "Bible Beginner", detail: "Complete 5 puzzles", symbol: "book", goal: .puzzles(5)),
        Achievement(id: "unaided", title: "Unaided", detail: "Solve a puzzle without hints", symbol: "hand.raised.slash", goal: .noHints(1)),
        Achievement(id: "quick-wit", title: "Quick Wit", detail: "Solve a puzzle in under 5 minutes", symbol: "bolt.fill", goal: .fastSolve(maxSeconds: 300)),
        Achievement(id: "disciple", title: "Disciple", detail: "Complete 25 puzzles", symbol: "figure.walk", goal: .puzzles(25)),
        Achievement(id: "lightning-round", title: "Lightning Round", detail: "Solve a puzzle in under 2 minutes", symbol: "bolt.horizontal.fill", goal: .fastSolve(maxSeconds: 120)),
        Achievement(id: "trial-by-fire", title: "Trial by Fire", detail: "Complete 5 hard puzzles", symbol: "mountain.2.fill", goal: .difficulty(.hard, 5)),
        Achievement(id: "purist", title: "Purist", detail: "Solve 10 puzzles without hints", symbol: "sparkles", goal: .noHints(10)),
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
