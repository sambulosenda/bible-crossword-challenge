//
//  ProgressTests.swift
//  Bible Crossword ChallengeTests
//
//  Streaks, hint limits, achievements, and bundled-puzzle integrity.
//

import Testing
import Foundation
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

    @Test func sameDayDoesNotDoubleCountStreak() {
        let p = PlayerProfile()
        Streaks.registerCompletion(p, now: day(2026, 7, 1), calendar: utc)
        let advanced = Streaks.registerCompletion(p, now: day(2026, 7, 1), calendar: utc)
        #expect(advanced == false)
        #expect(p.currentStreak == 1)
        #expect(p.totalPuzzlesCompleted == 2) // puzzle still counts
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
}

struct HintTests {

    @Test func freeUserGetsThreeHintsPerDay() {
        let p = PlayerProfile()
        #expect(p.hintsRemaining(isPremium: false, now: day(2026, 7, 1), calendar: utc) == 3)
        p.consumeHint(now: day(2026, 7, 1), calendar: utc)
        p.consumeHint(now: day(2026, 7, 1), calendar: utc)
        #expect(p.hintsRemaining(isPremium: false, now: day(2026, 7, 1), calendar: utc) == 1)
    }

    @Test func hintsResetNextDay() {
        let p = PlayerProfile()
        p.consumeHint(now: day(2026, 7, 1), calendar: utc)
        p.consumeHint(now: day(2026, 7, 1), calendar: utc)
        p.consumeHint(now: day(2026, 7, 1), calendar: utc)
        #expect(p.hintsRemaining(isPremium: false, now: day(2026, 7, 1), calendar: utc) == 0)
        #expect(p.hintsRemaining(isPremium: false, now: day(2026, 7, 2), calendar: utc) == 3)
    }

    @Test func premiumHasUnlimitedHints() {
        let p = PlayerProfile()
        #expect(p.hintsRemaining(isPremium: true, now: day(2026, 7, 1), calendar: utc) == Int.max)
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
