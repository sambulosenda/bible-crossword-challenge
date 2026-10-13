//
//  ProgressTests.swift
//  Bible Crossword ChallengeTests
//
//  Streaks, hint limits, achievements, and bundled-puzzle integrity.
//

import Testing
import Foundation
import SwiftData
@testable import Bible_Crossword_Challenge

private let utc: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(secondsFromGMT: 0)!
    return c
}()

private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
    utc.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
}

struct StreakTests {

    @Test func firstCompletionStartsStreak() {
        let p = PlayerProfile()
        let advanced = Streaks.registerCompletion(p, now: day(2026, 7, 1), calendar: utc)
        #expect(advanced)
        #expect(p.currentStreak == 1)
        #expect(p.bestStreak == 1)
        #expect(p.totalPuzzlesCompleted == 1)
    }

    @Test func consecutiveDaysIncrementStreak() {
        let p = PlayerProfile()
        Streaks.registerCompletion(p, now: day(2026, 7, 1), calendar: utc)
        Streaks.registerCompletion(p, now: day(2026, 7, 2), calendar: utc)
        Streaks.registerCompletion(p, now: day(2026, 7, 3), calendar: utc)
        #expect(p.currentStreak == 3)
        #expect(p.bestStreak == 3)
        #expect(p.totalPuzzlesCompleted == 3)
    }

    /// Two *different* puzzles on one day — the daily and the mini. The streak
    /// counts the day once; the solved count counts both.
    @Test func sameDayDoesNotDoubleCountStreak() {
        let p = PlayerProfile()
        Streaks.registerCompletion(p, now: day(2026, 7, 1), calendar: utc)
        let advanced = Streaks.registerCompletion(p, now: day(2026, 7, 1), calendar: utc)
        #expect(advanced == false)
        #expect(p.currentStreak == 1)
        #expect(p.totalPuzzlesCompleted == 2) // two puzzles, both count
    }

    /// Re-solving a puzzle already finished. The day counts — after the rotation
    /// wraps a replay is the only play available — but the solved count is
    /// distinct puzzles, so it stays put.
    @Test func aReplayAdvancesTheStreakWithoutCountingAsAPuzzle() {
        let p = PlayerProfile()
        Streaks.registerCompletion(p, now: day(2026, 7, 1), calendar: utc)
        #expect(p.totalPuzzlesCompleted == 1)

        let advanced = Streaks.registerCompletion(
            p, isReplay: true, now: day(2026, 7, 2), calendar: utc
        )
        #expect(advanced)
        #expect(p.currentStreak == 2)
        #expect(p.totalPuzzlesCompleted == 1, "a replay is not a new puzzle")
    }

    /// The wrap in miniature: a whole pool re-solved, day after day, must not
    /// re-run the player through the puzzle-count achievements.
    @Test func aWrappedWeekOfReplaysAddsNothingToTheSolvedCount() {
        let p = PlayerProfile(totalPuzzlesCompleted: 82)
        p.lastCompletedDate = day(2026, 9, 20)
        p.currentStreak = 82

        for d in 21...27 {
            Streaks.registerCompletion(p, isReplay: true, now: day(2026, 9, d), calendar: utc)
        }
        #expect(p.currentStreak == 89, "the streak survives the wrap")
        #expect(p.totalPuzzlesCompleted == 82, "no puzzle was solved that wasn't already")
    }

    /// A replay still earns a streak freeze at the seven-day milestone — the
    /// freeze rewards showing up, which a replay is.
    @Test func replaysStillEarnStreakFreezes() {
        let p = PlayerProfile()
        let freezesBefore = p.streakFreezes  // a new profile is given one
        for d in 1...7 {
            Streaks.registerCompletion(p, isReplay: true, now: day(2026, 7, d), calendar: utc)
        }
        #expect(p.currentStreak == 7)
        #expect(p.streakFreezes == freezesBefore + 1)
        #expect(p.totalPuzzlesCompleted == 0)
    }

    @Test func missedDayResetsStreak() {
        let p = PlayerProfile()
        Streaks.registerCompletion(p, now: day(2026, 7, 1), calendar: utc)
        Streaks.registerCompletion(p, now: day(2026, 7, 2), calendar: utc)
        // skip the 3rd, complete on the 4th
        Streaks.registerCompletion(p, now: day(2026, 7, 4), calendar: utc)
        #expect(p.currentStreak == 1)
        #expect(p.bestStreak == 2)
    }

    @Test func normalizeDropsStaleStreak() {
        let p = PlayerProfile()
        Streaks.registerCompletion(p, now: day(2026, 7, 1), calendar: utc)
        Streaks.normalize(p, now: day(2026, 7, 5), calendar: utc) // gap of days
        #expect(p.currentStreak == 0)
    }

    @Test func normalizeKeepsYesterdayStreak() {
        let p = PlayerProfile()
        Streaks.registerCompletion(p, now: day(2026, 7, 1), calendar: utc)
        Streaks.normalize(p, now: day(2026, 7, 2), calendar: utc)
        #expect(p.currentStreak == 1)
    }

    // MARK: - Streak freezes

    @Test func freezeBridgesSingleMissedDay() {
        let p = PlayerProfile() // starts with one freeze
        Streaks.registerCompletion(p, now: day(2026, 7, 1), calendar: utc)
        Streaks.normalize(p, now: day(2026, 7, 3), calendar: utc) // missed 7/2
        #expect(p.currentStreak == 1)        // preserved
        #expect(p.streakFreezes == 0)        // spent
        #expect(p.lastFreezeUsedDate != nil) // surfaces the one-time note
        // The next-day solve still continues the streak.
        Streaks.registerCompletion(p, now: day(2026, 7, 3), calendar: utc)
        #expect(p.currentStreak == 2)
    }

    @Test func missedDayWithoutFreezeResets() {
        let p = PlayerProfile(streakFreezes: 0)
        Streaks.registerCompletion(p, now: day(2026, 7, 1), calendar: utc)
        Streaks.normalize(p, now: day(2026, 7, 3), calendar: utc) // missed 7/2
        #expect(p.currentStreak == 0)
    }

    @Test func freezeDoesNotCoverTwoMissedDays() {
        let p = PlayerProfile() // one freeze
        Streaks.registerCompletion(p, now: day(2026, 7, 1), calendar: utc)
        Streaks.normalize(p, now: day(2026, 7, 4), calendar: utc) // missed 7/2 and 7/3
        #expect(p.currentStreak == 0)
        #expect(p.streakFreezes == 1) // not spent on an uncoverable gap
    }

    @Test func freezeSpentOncePerGap() {
        let p = PlayerProfile() // one freeze
        Streaks.registerCompletion(p, now: day(2026, 7, 1), calendar: utc)
        Streaks.normalize(p, now: day(2026, 7, 3), calendar: utc)
        Streaks.normalize(p, now: day(2026, 7, 3), calendar: utc) // second pass, same day
        #expect(p.streakFreezes == 0) // only one consumed
        #expect(p.currentStreak == 1)
    }

    // MARK: - Break detection (ticket 11)

    /// The comeback card is keyed on this outcome, so the freeze path must not
    /// report a break: the streak survived, and telling the player it ended
    /// would contradict the reassurance the streak card shows on the same
    /// launch.
    @Test func freezeSaveIsNotReportedAsABreak() {
        let p = PlayerProfile() // one freeze
        Streaks.registerCompletion(p, now: day(2026, 7, 1), calendar: utc)
        let outcome = Streaks.normalize(p, now: day(2026, 7, 3), calendar: utc)
        #expect(outcome == .freezeSaved)
        #expect(p.currentStreak == 1)
    }

    @Test func multiDayGapReportsBreakWithItsLength() {
        let p = PlayerProfile(streakFreezes: 0)
        for date in 1...5 {
            Streaks.registerCompletion(p, now: day(2026, 7, date), calendar: utc)
        }
        #expect(p.currentStreak == 5)
        let outcome = Streaks.normalize(p, now: day(2026, 7, 10), calendar: utc)
        #expect(outcome == .broken(previous: 5))
        #expect(p.currentStreak == 0)
    }

    /// The break is announced once. A second pass finds the streak already at
    /// zero and must stay quiet, or every launch would re-open the comeback
    /// card on a loss the player has already seen.
    @Test func breakIsReportedOnlyOnce() {
        let p = PlayerProfile(streakFreezes: 0)
        Streaks.registerCompletion(p, now: day(2026, 7, 1), calendar: utc)
        #expect(Streaks.normalize(p, now: day(2026, 7, 5), calendar: utc) == .broken(previous: 1))
        #expect(Streaks.normalize(p, now: day(2026, 7, 5), calendar: utc) == .unchanged)
        #expect(Streaks.normalize(p, now: day(2026, 7, 6), calendar: utc) == .unchanged)
    }

    /// A gap that a freeze covers, followed by a second gap it can't.
    @Test func breakAfterAFreezeCarriesTheSurvivingLength() {
        let p = PlayerProfile() // one freeze
        Streaks.registerCompletion(p, now: day(2026, 7, 1), calendar: utc)
        Streaks.registerCompletion(p, now: day(2026, 7, 2), calendar: utc)
        #expect(Streaks.normalize(p, now: day(2026, 7, 4), calendar: utc) == .freezeSaved)
        #expect(p.currentStreak == 2)
        // Freeze is spent, so the next gap breaks it.
        #expect(Streaks.normalize(p, now: day(2026, 7, 7), calendar: utc) == .broken(previous: 2))
    }

    @Test func currentStreakReportsUnchanged() {
        let p = PlayerProfile()
        Streaks.registerCompletion(p, now: day(2026, 7, 1), calendar: utc)
        #expect(Streaks.normalize(p, now: day(2026, 7, 1), calendar: utc) == .unchanged)
        #expect(Streaks.normalize(p, now: day(2026, 7, 2), calendar: utc) == .unchanged)
    }

    /// A profile that has never completed anything has no streak to lose.
    @Test func neverPlayedIsNotABreak() {
        let p = PlayerProfile()
        #expect(Streaks.normalize(p, now: day(2026, 7, 1), calendar: utc) == .unchanged)
    }

    /// The solve after a break restarts at 1 — what the completion screen calls
    /// "New streak — day 1".
    @Test func solveAfterBreakRestartsAtOne() {
        let p = PlayerProfile(streakFreezes: 0)
        Streaks.registerCompletion(p, now: day(2026, 7, 1), calendar: utc)
        Streaks.normalize(p, now: day(2026, 7, 5), calendar: utc)
        #expect(p.currentStreak == 0)
        Streaks.registerCompletion(p, now: day(2026, 7, 5), calendar: utc)
        #expect(p.currentStreak == 1)
    }

    @Test func milestoneGrantsFreeze() {
        let p = PlayerProfile() // starts with one
        for d in 1...7 {
            Streaks.registerCompletion(p, now: day(2026, 7, d), calendar: utc)
        }
        #expect(p.currentStreak == 7)
        #expect(p.streakFreezes == 2) // earned one crossing the 7-day mark
    }

    @Test func freezesCapAtMax() {
        let p = PlayerProfile() // starts with one
        for d in 1...21 {
            Streaks.registerCompletion(p, now: day(2026, 7, d), calendar: utc)
        }
        // Milestones at 7/14/21 would push to 4, but the cap holds it down.
        #expect(p.streakFreezes == PlayerProfile.maxStreakFreezes)
    }
}

struct HintTests {

    /// The quota arithmetic, tested at a pool of three so each step is
    /// visible. The shipped pool (one) is pinned in `HintQuotaTests`.
    static let pool = 3

    /// A profile past the learning window, where the daily quota applies.
    private func graduated() -> PlayerProfile {
        let p = PlayerProfile()
        p.totalPuzzlesCompleted = 3
        return p
    }

    @Test func freeUserGetsThreeHintsPerDay() {
        let p = graduated()
        #expect(p.hintsRemaining(isPremium: false, limit: Self.pool, now: day(2026, 7, 1), calendar: utc) == 3)
        p.consumeHint(now: day(2026, 7, 1), calendar: utc)
        p.consumeHint(now: day(2026, 7, 1), calendar: utc)
        #expect(p.hintsRemaining(isPremium: false, limit: Self.pool, now: day(2026, 7, 1), calendar: utc) == 1)
    }

    @Test func hintsResetNextDay() {
        let p = graduated()
        p.consumeHint(now: day(2026, 7, 1), calendar: utc)
        p.consumeHint(now: day(2026, 7, 1), calendar: utc)
        p.consumeHint(now: day(2026, 7, 1), calendar: utc)
        #expect(p.hintsRemaining(isPremium: false, limit: Self.pool, now: day(2026, 7, 1), calendar: utc) == 0)
        #expect(p.hintsRemaining(isPremium: false, limit: Self.pool, now: day(2026, 7, 2), calendar: utc) == 3)
    }

    @Test func premiumHasUnlimitedHints() {
        let p = graduated()
        #expect(p.hintsRemaining(isPremium: true, now: day(2026, 7, 1), calendar: utc) == Int.max)
    }

    @Test func wordHintCostsTwo() {
        let p = graduated()
        p.consumeHint(cost: HintType.word.cost, now: day(2026, 7, 1), calendar: utc)
        #expect(p.hintsRemaining(isPremium: false, limit: Self.pool, now: day(2026, 7, 1), calendar: utc) == 1)
    }

    @Test func learningWindowIsUnmetered() {
        // Inside the first three completions, hints are free: nothing counts
        // against the quota, and the remaining count never gates a reveal.
        let p = PlayerProfile()
        #expect(p.isStillLearning)
        #expect(p.hintsRemaining(isPremium: false, limit: Self.pool, now: day(2026, 7, 1), calendar: utc) == Int.max)
        p.consumeHint(cost: 3, now: day(2026, 7, 1), calendar: utc)
        #expect(p.hintsUsedToday == 0)
    }

    @Test func graduationRestoresTheFullBudget() {
        // Hints "spent" while learning cost nothing, so the third completion
        // hands the player an untouched daily budget, not a depleted one.
        let p = PlayerProfile()
        p.consumeHint(cost: 3, now: day(2026, 7, 1), calendar: utc)
        p.totalPuzzlesCompleted = 3
        #expect(!p.isStillLearning)
        #expect(p.hintsRemaining(isPremium: false, limit: Self.pool, now: day(2026, 7, 1), calendar: utc) == 3)
    }

    @Test func verseHintCostsNothing() {
        let p = graduated()
        p.consumeHint(cost: HintType.verse.cost, now: day(2026, 7, 1), calendar: utc)
        #expect(p.hintsRemaining(isPremium: false, limit: Self.pool, now: day(2026, 7, 1), calendar: utc) == 3)
        // A free hint must not stamp the date either.
        #expect(p.hintsDate == nil)
    }

    @Test func cannotAffordWordWithOneRemaining() {
        // Pins the `remaining >= cost` comparison the view uses.
        let p = graduated()
        p.consumeHint(cost: 2, now: day(2026, 7, 1), calendar: utc)
        let remaining = p.hintsRemaining(isPremium: false, limit: Self.pool, now: day(2026, 7, 1), calendar: utc)
        #expect(remaining >= HintType.letter.cost)
        #expect(!(remaining >= HintType.word.cost))
    }

    @Test func premiumAffordsEverything() {
        // Guards against "improving" the affordability check into subtraction,
        // which would overflow on premium's Int.max.
        let p = PlayerProfile()
        let remaining = p.hintsRemaining(isPremium: true, now: day(2026, 7, 1), calendar: utc)
        #expect(remaining >= HintType.word.cost)
    }
}

struct AchievementTests {

    @Test func puzzleThresholdsUnlock() {
        let p = PlayerProfile(totalPuzzlesCompleted: 5)
        let unlocked = Achievements.newlyUnlocked(for: p).map(\.id)
        #expect(unlocked.contains("bible-beginner"))
        #expect(!unlocked.contains("disciple"))
    }

    @Test func streakThresholdUnlocks() {
        let p = PlayerProfile(bestStreak: 30)
        #expect(Achievements.newlyUnlocked(for: p).map(\.id).contains("evangelist"))
    }

    @Test func alreadyUnlockedNotReturnedAgain() {
        let p = PlayerProfile(totalPuzzlesCompleted: 5, unlockedAchievementIDs: ["bible-beginner"])
        #expect(Achievements.newlyUnlocked(for: p).map(\.id).contains("bible-beginner") == false)
    }
}

struct SyncMergeTests {

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: PlayerProfile.self, PuzzleRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    @Test func profileMergeKeepsBestOfEverything() throws {
        let context = try makeContext()
        let old = PlayerProfile(
            username: "Friend", currentStreak: 2, bestStreak: 5, totalPuzzlesCompleted: 10,
            unlockedAchievementIDs: ["bible-beginner"], bestSolveSeconds: 200,
            streakFreezes: 1, createdAt: day(2026, 6, 1)
        )
        let new = PlayerProfile(
            username: "Sam", currentStreak: 7, bestStreak: 3, totalPuzzlesCompleted: 4,
            unlockedAchievementIDs: ["bible-beginner", "quick-wit"], bestSolveSeconds: 90,
            noHintSolves: 3, streakFreezes: 2, createdAt: day(2026, 6, 20)
        )
        context.insert(old)
        context.insert(new)

        let survivor = SyncMerge.mergeProfiles([new, old], context: context)

        #expect(survivor === old) // oldest profile wins
        #expect(old.username == "Sam") // real name beats the default
        #expect(old.currentStreak == 7)
        #expect(old.bestStreak == 5)
        #expect(old.totalPuzzlesCompleted == 10)
        #expect(Set(old.unlockedAchievementIDs) == ["bible-beginner", "quick-wit"])
        #expect(old.bestSolveSeconds == 90)
        #expect(old.noHintSolves == 3)
        #expect(old.streakFreezes == 2)
        let remaining = try context.fetch(FetchDescriptor<PlayerProfile>())
        #expect(remaining.count == 1)
    }

    @Test func profileMergeLatestHintDayOwnsTheCounter() throws {
        let context = try makeContext()
        let a = PlayerProfile(hintsUsedToday: 3, hintsDate: day(2026, 7, 1), createdAt: day(2026, 6, 1))
        let b = PlayerProfile(hintsUsedToday: 1, hintsDate: day(2026, 7, 2), createdAt: day(2026, 6, 2))
        context.insert(a)
        context.insert(b)

        SyncMerge.mergeProfiles([a, b], context: context)

        #expect(a.hintsUsedToday == 1)
        #expect(a.hintsDate == day(2026, 7, 2))
    }

    @Test func recordMergeCompletedBeatsInProgress() throws {
        let context = try makeContext()
        let done = PuzzleRecord(
            puzzleID: "daily-001", isCompleted: true, completedDate: day(2026, 7, 1),
            elapsedSeconds: 300, usedHint: false, updatedAt: day(2026, 7, 1)
        )
        let partial = PuzzleRecord(
            puzzleID: "daily-001", elapsedSeconds: 40, usedHint: true, updatedAt: day(2026, 7, 2)
        )
        context.insert(done)
        context.insert(partial)

        let survivor = SyncMerge.mergeRecords([partial, done], context: context)

        #expect(survivor === done) // completion outranks a newer partial save
        #expect(done.usedHint) // hint use on either device sticks
        let remaining = try context.fetch(FetchDescriptor<PuzzleRecord>())
        #expect(remaining.count == 1)
    }

    @Test func recordMergeKeepsEarliestCompletion() throws {
        let context = try makeContext()
        let first = PuzzleRecord(
            puzzleID: "daily-001", isCompleted: true, completedDate: day(2026, 7, 1),
            updatedAt: day(2026, 7, 1)
        )
        let second = PuzzleRecord(
            puzzleID: "daily-001", isCompleted: true, completedDate: day(2026, 7, 3),
            updatedAt: day(2026, 7, 3)
        )
        context.insert(first)
        context.insert(second)

        let survivor = SyncMerge.mergeRecords([first, second], context: context)

        #expect(survivor?.completedDate == day(2026, 7, 1))
    }

    @Test func storeSweepOnlyCollapsesDuplicates() throws {
        let context = try makeContext()
        context.insert(PuzzleRecord(puzzleID: "daily-001", updatedAt: day(2026, 7, 1)))
        context.insert(PuzzleRecord(puzzleID: "daily-001", updatedAt: day(2026, 7, 2)))
        context.insert(PuzzleRecord(puzzleID: "daily-002", updatedAt: day(2026, 7, 1)))

        SyncMerge.mergeDuplicateRecords(in: context)

        let remaining = try context.fetch(FetchDescriptor<PuzzleRecord>())
        #expect(remaining.count == 2)
        #expect(Set(remaining.map(\.puzzleID)) == ["daily-001", "daily-002"])
    }
}

struct PuzzleDataTests {

    @Test func bundledPuzzlesLoad() {
        let provider = PuzzleProvider.shared
        #expect(provider.puzzles.isEmpty == false)
    }

    @Test func everyClueMatchesItsGrid() {
        for puzzle in PuzzleProvider.shared.puzzles {
            let rows = puzzle.grid.map { Array($0.uppercased()) }
            #expect(puzzle.grid.count == puzzle.size)
            #expect(puzzle.clueCount >= 10 && puzzle.clueCount <= 20)
            for clue in puzzle.clues {
                let answer = Array(clue.answer.uppercased())
                for (i, pos) in clue.positions.enumerated() {
                    #expect(pos.row < puzzle.size && pos.col < puzzle.size)
                    #expect(rows[pos.row][pos.col] == answer[i],
                            "Mismatch in \(puzzle.id) clue \(clue.number)\(clue.direction.rawValue)")
                }
            }
        }
    }

    @Test func dailySelectionIsDeterministic() {
        let provider = PuzzleProvider.shared
        let a = provider.dailyPuzzle(for: day(2026, 7, 1), calendar: utc)
        let b = provider.dailyPuzzle(for: day(2026, 7, 1), calendar: utc)
        #expect(a?.id == b?.id)
        let next = provider.dailyPuzzle(for: day(2026, 7, 2), calendar: utc)
        #expect(next != nil)
    }
}
