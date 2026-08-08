//
//  Persistence.swift
//  Bible Crossword Challenge
//
//  SwiftData models for the single local player profile and per-puzzle
//  progress, plus the streak/achievement rules that operate on them.
//  Synced across the player's devices via CloudKit (private database).
//  CloudKit requires every attribute to be optional or defaulted and forbids
//  unique constraints, so duplicates from sync races are collapsed by the
//  SyncMerge helpers below.
//

import Foundation
import SwiftData
import os

/// App-wide loggers. Persistence failures especially must never be silent —
/// a dropped save is invisible progress loss, so it at least lands in the
/// unified log (visible in Console.app and sysdiagnose) in all builds.
enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "BibleCrossword"
    static let persistence = Logger(subsystem: subsystem, category: "persistence")
}

extension ModelContext {
    /// Save that shields the caller from throwing but records the failure —
    /// used where there is no meaningful recovery UI (backgrounding, launch
    /// normalisation) and the old `try?` pattern was hiding data loss.
    func saveLogged(_ what: StaticString) {
        do {
            try save()
        } catch {
            Log.persistence.error("Save failed (\(what, privacy: .public)): \(error, privacy: .public)")
        }
    }
}

// MARK: - Player profile (single row)

@Model
final class PlayerProfile {
    var username: String = "Friend"
    var currentStreak: Int = 0
    var bestStreak: Int = 0
    /// **Distinct puzzles solved**, not completions — a replay of a puzzle
    /// already finished doesn't count, matching `noHintSolves`, `hardCompleted`
    /// and pack completion, which have always been once-per-puzzle.
    ///
    /// This is the definition Profile's "Solved" tile shows and the one the
    /// puzzle-count achievements are measured against, so the two cannot
    /// disagree. It is never recomputed downward: counts inflated by replays
    /// before this rule existed are left alone, because recalculating would
    /// retroactively take back achievements players have already been shown.
    var totalPuzzlesCompleted: Int = 0
    var lastCompletedDate: Date?
    var hintsUsedToday: Int = 0
    var hintsDate: Date?
    var unlockedAchievementIDs: [String] = []
    /// Fastest completed solve, in seconds (nil until the first completion).
    var bestSolveSeconds: Int?
    /// Count of puzzles first solved without using any hint.
    var noHintSolves: Int = 0
    /// Count of hard puzzles completed (first completion only).
    var hardCompleted: Int = 0
    /// Packs the player has fully solved, by pack id. Recorded at the moment
    /// the last member puzzle completes (and reconciled on launch for solves
    /// that predate this field) — drives the pack achievements.
    var completedPackIDs: [String] = []
    /// Streak freezes on hand — each auto-forgives a single missed day. Every
    /// player starts with one; more are earned at streak milestones.
    var streakFreezes: Int = 1
    /// The day a freeze was last spent, used to show a one-time "saved" note.
    var lastFreezeUsedDate: Date? = nil
    var createdAt: Date = Date()

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
        completedPackIDs: [String] = [],
        streakFreezes: Int = 1,
        lastFreezeUsedDate: Date? = nil,
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
        self.completedPackIDs = completedPackIDs
        self.streakFreezes = streakFreezes
        self.lastFreezeUsedDate = lastFreezeUsedDate
        self.createdAt = createdAt
    }
}

// MARK: - Per-puzzle progress / completion record

@Model
final class PuzzleRecord {
    var puzzleID: String = ""
    var isCompleted: Bool = false
    var completedDate: Date?
    var elapsedSeconds: Int = 0
    /// Encoded `[String: String]` of position storage-key -> letter, for resume.
    var entriesData: Data?
    /// True once any hint was revealed on this puzzle — survives resume, so a
    /// "no hints" solve stays accurate across sessions.
    var usedHint: Bool = false
    var updatedAt: Date = Date()

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

// MARK: - CloudKit duplicate merging

/// CloudKit can't enforce uniqueness, so two devices syncing for the first
/// time can each contribute a profile, or in-flight solves can land as
/// duplicate records for the same puzzle. Merging always keeps the most
/// generous value of each progress field so sync never costs the player
/// anything they earned on either device.
enum SyncMerge {
    /// Collapses all profiles into the oldest one and deletes the rest.
    /// Returns the surviving profile (nil only if the list is empty).
    @discardableResult
    static func mergeProfiles(_ profiles: [PlayerProfile], context: ModelContext) -> PlayerProfile? {
        guard let primary = profiles.min(by: { $0.createdAt < $1.createdAt }) else { return nil }
        for other in profiles where other !== primary {
            if primary.username == "Friend", other.username != "Friend" {
                primary.username = other.username
            }
            primary.currentStreak = max(primary.currentStreak, other.currentStreak)
            primary.bestStreak = max(primary.bestStreak, other.bestStreak)
            primary.totalPuzzlesCompleted = max(primary.totalPuzzlesCompleted, other.totalPuzzlesCompleted)
            if let d = other.lastCompletedDate, d > (primary.lastCompletedDate ?? .distantPast) {
                primary.lastCompletedDate = d
            }
            // The device that spent hints most recently owns today's count.
            if (other.hintsDate ?? .distantPast) > (primary.hintsDate ?? .distantPast) {
                primary.hintsDate = other.hintsDate
                primary.hintsUsedToday = other.hintsUsedToday
            }
            for id in other.unlockedAchievementIDs where !primary.unlockedAchievementIDs.contains(id) {
                primary.unlockedAchievementIDs.append(id)
            }
            for id in other.completedPackIDs where !primary.completedPackIDs.contains(id) {
                primary.completedPackIDs.append(id)
            }
            if let best = other.bestSolveSeconds, best < (primary.bestSolveSeconds ?? .max) {
                primary.bestSolveSeconds = best
            }
            primary.noHintSolves = max(primary.noHintSolves, other.noHintSolves)
            primary.hardCompleted = max(primary.hardCompleted, other.hardCompleted)
            primary.streakFreezes = min(
                max(primary.streakFreezes, other.streakFreezes),
                PlayerProfile.maxStreakFreezes
            )
            if let d = other.lastFreezeUsedDate, d > (primary.lastFreezeUsedDate ?? .distantPast) {
                primary.lastFreezeUsedDate = d
            }
            context.delete(other)
        }
        return primary
    }

    /// Collapses duplicate records for one puzzle into the most advanced
    /// (completed beats in-progress, then most recently updated) and deletes
    /// the rest. Returns the survivor (nil only if the list is empty).
    @discardableResult
    static func mergeRecords(_ records: [PuzzleRecord], context: ModelContext) -> PuzzleRecord? {
        guard let primary = records.max(by: {
            ($0.isCompleted ? 1 : 0, $0.updatedAt) < ($1.isCompleted ? 1 : 0, $1.updatedAt)
        }) else { return nil }
        for other in records where other !== primary {
            // The earliest completion is the historically accurate one.
            if let d = other.completedDate, d < (primary.completedDate ?? .distantFuture) {
                primary.completedDate = d
            }
            primary.usedHint = primary.usedHint || other.usedHint
            context.delete(other)
        }
        return primary
    }

    /// Sweeps the whole store for duplicate puzzle records — run on launch
    /// and when returning to the foreground, after sync may have landed.
    static func mergeDuplicateRecords(in context: ModelContext) {
        let all: [PuzzleRecord]
        do {
            all = try context.fetch(FetchDescriptor<PuzzleRecord>())
        } catch {
            Log.persistence.error("Duplicate-record sweep fetch failed: \(error, privacy: .public)")
            return
        }
        for (_, dupes) in Dictionary(grouping: all, by: \.puzzleID) where dupes.count > 1 {
            mergeRecords(dupes, context: context)
        }
    }
}

// MARK: - Hint helpers

extension PlayerProfile {
    static let freeHintLimit = 3
    /// Most freezes a player can hold at once, so milestone rewards don't stack
    /// into an indefinite safety net.
    static let maxStreakFreezes = 3

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
    /// What a `normalize` pass did, so the caller can react without inferring it
    /// from the profile afterwards.
    ///
    /// `broken` carries the length that was lost and is reported **only** on the
    /// pass that actually resets it. A second pass the same day finds the streak
    /// already at zero and reports `unchanged`, which is what keeps the comeback
    /// card from re-firing on every launch.
    enum Outcome: Equatable {
        case unchanged
        case freezeSaved
        case broken(previous: Int)
    }

    /// Called on app launch: drops a stale streak to zero if a day was missed,
    /// unless a single missed day can be bridged by spending a streak freeze.
    @discardableResult
    static func normalize(_ p: PlayerProfile, now: Date = Date(), calendar: Calendar = .current) -> Outcome {
        guard let last = p.lastCompletedDate else {
            p.currentStreak = 0
            return .unchanged
        }
        let today = calendar.startOfDay(for: now)
        let lastDay = calendar.startOfDay(for: last)
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else { return .unchanged }
        // Solved today or yesterday — streak is current, nothing to do.
        if lastDay >= yesterday { return .unchanged }

        // At least one full day was missed. A freeze can bridge exactly one
        // missed day (last solve was the day before yesterday). Larger gaps
        // reset regardless of freezes.
        let dayBeforeYesterday = calendar.date(byAdding: .day, value: -2, to: today)
        if lastDay == dayBeforeYesterday, p.currentStreak > 0, p.streakFreezes > 0 {
            p.streakFreezes -= 1
            // Fill the gap so the streak is treated as current and later
            // same-day normalize passes don't spend another freeze.
            p.lastCompletedDate = yesterday
            p.lastFreezeUsedDate = today
            return .freezeSaved
        }
        // Only a streak that was actually running can break. Reporting the reset
        // of an already-zero streak would re-announce the same loss on every
        // launch until they solved something.
        guard p.currentStreak > 0 else { return .unchanged }
        let previous = p.currentStreak
        p.currentStreak = 0
        return .broken(previous: previous)
    }

    /// Called when a puzzle is completed. Returns true if the streak advanced today.
    ///
    /// `isReplay` marks a puzzle the player had already finished. The streak
    /// still advances — a replay is a real day's play, and after the rotation
    /// wraps it is the *only* play available — but it doesn't add to the solved
    /// count, which counts distinct puzzles. Without this the wrap would have
    /// the whole cohort re-solve the whole pool and every puzzle-count
    /// achievement would unlock again on the way through.
    @discardableResult
    static func registerCompletion(
        _ p: PlayerProfile,
        isReplay: Bool = false,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
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
        if !isReplay { p.totalPuzzlesCompleted += 1 }
        p.bestStreak = max(p.bestStreak, p.currentStreak)

        // Reward sustained streaks: a freeze each time the streak crosses a
        // 7-day milestone, capped so it can't grow without bound.
        if advanced && p.currentStreak % 7 == 0 {
            p.streakFreezes = min(p.streakFreezes + 1, PlayerProfile.maxStreakFreezes)
        }
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
        case packsCompleted(Int)
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
        case .packsCompleted(let target):
            return min(1.0, Double(p.completedPackIDs.count) / Double(target))
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
        case .packsCompleted(let target):
            return "\(min(p.completedPackIDs.count, target)) / \(target)"
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
        Achievement(id: "pathfinder", title: "Pathfinder", detail: "Complete a puzzle pack", symbol: "square.stack.3d.up.fill", goal: .packsCompleted(1)),
        Achievement(id: "collector", title: "Collector", detail: "Complete 3 puzzle packs", symbol: "books.vertical.fill", goal: .packsCompleted(3)),
    ]

    /// Returns achievement IDs newly satisfied that aren't already recorded.
    static func newlyUnlocked(for p: PlayerProfile) -> [Achievement] {
        let already = Set(p.unlockedAchievementIDs)
        return all.filter { $0.isUnlocked(by: p) && !already.contains($0.id) }
    }
}
