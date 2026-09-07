//
//  PuzzleAccessTests.swift
//  Bible Crossword ChallengeTests
//
//  The free-tier soft gate: the rolling window, the grandfather clause for
//  started puzzles, and the boundaries where either could quietly go wrong.
//

import Testing
import Foundation
@testable import Bible_Crossword_Challenge

private let utc: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(secondsFromGMT: 0)!
    return c
}()

private func day(_ y: Int, _ m: Int, _ d: Int, hour: Int = 12) -> Date {
    utc.date(from: DateComponents(year: y, month: m, day: d, hour: hour))!
}

/// The content epoch: day-index 0, the first puzzle in the rotation.
private let epochDay = day(2026, 7, 1)

private func access(on date: Date, windowLength: Int = PuzzleAccess.windowLength) -> PuzzleAccess {
    PuzzleAccess(provider: .shared, date: date, calendar: utc, windowLength: windowLength)
}

struct PuzzleAccessTests {

    // MARK: - Pending challenges

    @Test func aPendingChallengeOpensThePuzzleItNamesAndNothingElse() throws {
        let provider = PuzzleProvider.shared
        let today = day(2026, 8, 8)
        let old = try #require(provider.dailyPuzzle(for: day(2026, 7, 2), calendar: utc))
        let plain = access(on: today)
        #expect(!plain.canPlay(old, isPremium: false, hasProgress: false),
                "a daily from five weeks ago is outside the window")

        let challenged = PuzzleAccess(provider: provider, date: today, calendar: utc, challengedIDs: [old.id])
        #expect(challenged.canPlay(old, isPremium: false, hasProgress: false))
        // Playable, but not framed as part of this week's free window.
        #expect(!challenged.isInWindow(old))
        // The exception is per puzzle, not a general unlock.
        let otherOld = try #require(provider.dailyPuzzle(for: day(2026, 7, 9), calendar: utc))
        #expect(!challenged.canPlay(otherOld, isPremium: false, hasProgress: false))
    }

    // MARK: - Window membership

    @Test func todaysDailyAndMiniAreFree() {
        let provider = PuzzleProvider.shared
        let gate = access(on: day(2026, 8, 8))

        let daily = provider.dailyPuzzle(for: day(2026, 8, 8), calendar: utc)
        let mini = provider.dailyMini(for: day(2026, 8, 8), calendar: utc)

        #expect(daily != nil)
        #expect(mini != nil)
        #expect(gate.canPlay(daily!, isPremium: false, hasProgress: false))
        #expect(gate.canPlay(mini!, isPremium: false, hasProgress: false))
    }

    /// The whole point of the window: the last seven days of dailies open, the
    /// eighth shut. Guards against an off-by-one making it six or eight.
    @Test func windowCoversSevenDaysAndStopsAtTheEighth() {
        let provider = PuzzleProvider.shared
        let today = day(2026, 8, 8)
        let gate = access(on: today)

        for back in 0..<7 {
            let date = utc.date(byAdding: .day, value: -back, to: today)!
            let puzzle = provider.dailyPuzzle(for: date, calendar: utc)!
            #expect(gate.canPlay(puzzle, isPremium: false, hasProgress: false),
                    "daily from \(back) day(s) ago should be free")
        }

        let eighth = provider.dailyPuzzle(
            for: utc.date(byAdding: .day, value: -7, to: today)!, calendar: utc
        )!
        #expect(!gate.canPlay(eighth, isPremium: false, hasProgress: false),
                "the eighth day back should be locked")
    }

    @Test func windowHoldsSevenDistinctPuzzlesPerPool() {
        let provider = PuzzleProvider.shared
        let window = provider.rotationWindow(
            provider.puzzles, for: day(2026, 8, 8), calendar: utc, length: 7
        )
        #expect(window.count == 7)
        #expect(Set(window.map(\.id)).count == 7, "window must not repeat a puzzle")
    }

    /// Dailies and minis rotate through differently sized pools, so each needs
    /// its own window. If minis were sliced off the daily index the two would
    /// drift and Library would lock a mini that Home is serving free today.
    @Test func poolsGetIndependentWindows() {
        let provider = PuzzleProvider.shared
        // Walk a stretch of dates rather than trusting one: the two pools only
        // disagree once their day counts diverge.
        for offset in 0..<30 {
            let date = utc.date(byAdding: .day, value: offset, to: epochDay)!
            let gate = access(on: date)
            let mini = provider.dailyMini(for: date, calendar: utc)!
            #expect(gate.canPlay(mini, isPremium: false, hasProgress: false),
                    "today's mini must be free on day \(offset)")
        }
    }

    // MARK: - Wrap-around

    /// The window's leading edge is always whatever Home is serving. Asserted on
    /// its own because everything else here depends on it, and because it is the
    /// invariant that ties the gate to the rotation.
    @Test func windowStartsAtTodaysDaily() {
        let provider = PuzzleProvider.shared
        for offset in 0..<40 {
            let date = utc.date(byAdding: .day, value: offset, to: epochDay)!
            let window = provider.rotationWindow(
                provider.puzzles, for: date, calendar: utc, length: 7
            )
            #expect(window.first?.id == provider.dailyPuzzle(for: date, calendar: utc)?.id,
                    "window should lead with day \(offset)'s daily")
        }
    }

    /// The daily pool recurs every `puzzles.count` days. At the pool's first
    /// puzzle the window has to reach backwards past index 0 and wrap to the end
    /// rather than clamping or trapping on a negative index.
    @Test func windowWrapsBackwardsAtTheStartOfThePool() {
        let provider = PuzzleProvider.shared
        // Found rather than assumed: `PuzzleProvider` builds its epoch in the
        // device calendar, so a UTC test calendar can sit a day either side of
        // it and `epochDay` is not reliably rotation-index 0.
        let start = (0..<provider.puzzles.count)
            .map { utc.date(byAdding: .day, value: $0, to: epochDay)! }
            .first { provider.dailyPuzzle(for: $0, calendar: utc)?.id == provider.puzzles.first?.id }

        #expect(start != nil, "the pool's first puzzle should come round within one lap")
        guard let start else { return }

        let window = provider.rotationWindow(
            provider.puzzles, for: start, calendar: utc, length: 7
        )
        #expect(window.count == 7)
        #expect(Set(window.map(\.id)).count == 7)
        #expect(window.first?.id == provider.puzzles.first?.id)
        #expect(window.last?.id == provider.puzzles[provider.puzzles.count - 6].id)
    }

    /// A device clock set before the content epoch yields a negative day index.
    /// It must still resolve to a real puzzle rather than crash on a negative
    /// array subscript.
    @Test func windowSurvivesDatesBeforeTheEpoch() {
        let provider = PuzzleProvider.shared
        let before = utc.date(byAdding: .day, value: -3, to: epochDay)!
        let window = provider.rotationWindow(
            provider.puzzles, for: before, calendar: utc, length: 7
        )
        #expect(window.count == 7)
        #expect(Set(window.map(\.id)).count == 7)
    }

    /// After one full lap the same day-of-rotation opens the same seven, so the
    /// gate keeps working once the pool starts repeating.
    @Test func windowRepeatsAfterAFullRotation() {
        let provider = PuzzleProvider.shared
        let lap = provider.puzzles.count
        let first = provider.rotationWindow(
            provider.puzzles, for: day(2026, 8, 8), calendar: utc, length: 7
        )
        let second = provider.rotationWindow(
            provider.puzzles,
            for: utc.date(byAdding: .day, value: lap, to: day(2026, 8, 8))!,
            calendar: utc,
            length: 7
        )
        #expect(first.map(\.id) == second.map(\.id))
    }

    @Test func windowNeverExceedsItsPool() {
        let provider = PuzzleProvider.shared
        let huge = provider.rotationWindow(
            provider.puzzles, for: epochDay, calendar: utc, length: provider.puzzles.count + 50
        )
        #expect(huge.count == provider.puzzles.count)
        #expect(Set(huge.map(\.id)).count == provider.puzzles.count)
    }

    // MARK: - Day boundary

    /// The rotation advances at local midnight. Two instants either side of it
    /// must not resolve to the same window, or a player's free set would lag a
    /// day behind the daily Home is serving.
    @Test func windowTurnsOverAtMidnight() {
        let provider = PuzzleProvider.shared
        let lateTonight = day(2026, 8, 8, hour: 23)
        let earlyTomorrow = day(2026, 8, 9, hour: 0)

        let tonight = access(on: lateTonight)
        let tomorrow = access(on: earlyTomorrow)

        let tomorrowsDaily = provider.dailyPuzzle(for: earlyTomorrow, calendar: utc)!
        #expect(!tonight.canPlay(tomorrowsDaily, isPremium: false, hasProgress: false),
                "tomorrow's puzzle must not be free tonight")
        #expect(tomorrow.canPlay(tomorrowsDaily, isPremium: false, hasProgress: false))
    }

    /// 11:50pm and 12:10am sit in different rotation days, per the ticket's test
    /// plan. Same assertion as above from the player's side: the free set they
    /// had before bed is not the one they have after midnight.
    @Test func lateNightAndAfterMidnightDisagree() {
        let provider = PuzzleProvider.shared
        let before = utc.date(from: DateComponents(year: 2026, month: 8, day: 8, hour: 23, minute: 50))!
        let after = utc.date(from: DateComponents(year: 2026, month: 8, day: 9, hour: 0, minute: 10))!
        #expect(provider.dailyPuzzle(for: before, calendar: utc)?.id
                != provider.dailyPuzzle(for: after, calendar: utc)?.id)
    }

    // MARK: - Grandfather clause

    /// The window slides. A puzzle started inside it has to stay open once it
    /// falls out, or the gate takes back work the player already did.
    @Test func startedPuzzleStaysFreeAfterLeavingTheWindow() {
        let provider = PuzzleProvider.shared
        let today = day(2026, 8, 8)
        let gate = access(on: today)

        let longAgo = provider.dailyPuzzle(
            for: utc.date(byAdding: .day, value: -30, to: today)!, calendar: utc
        )!
        #expect(!gate.canPlay(longAgo, isPremium: false, hasProgress: false))
        #expect(gate.canPlay(longAgo, isPremium: false, hasProgress: true))
    }

    // MARK: - Entitlement and packs

    @Test func premiumPlaysEverything() {
        let provider = PuzzleProvider.shared
        let gate = access(on: day(2026, 8, 8))
        for puzzle in provider.puzzles + provider.minis {
            #expect(gate.canPlay(puzzle, isPremium: true, hasProgress: false))
        }
    }

    /// Pack exclusives are sold with their pack and must not leak through the
    /// archive gate — not via the window, and not via a lapsed subscriber's
    /// leftover progress.
    @Test func packExclusivesStayGated() {
        let provider = PuzzleProvider.shared
        let gate = access(on: day(2026, 8, 8))
        let packOnly = provider.packs
            .flatMap(\.puzzleIDs)
            .filter { $0.hasPrefix("pack-") }
            .compactMap { provider.puzzle(id: $0) }

        #expect(!packOnly.isEmpty, "fixture should contain pack exclusives")
        for puzzle in packOnly {
            #expect(!gate.canPlay(puzzle, isPremium: false, hasProgress: false))
            #expect(!gate.canPlay(puzzle, isPremium: false, hasProgress: true),
                    "progress must not unlock a pack exclusive")
            #expect(gate.canPlay(puzzle, isPremium: true, hasProgress: false))
        }
    }

    /// Pack exclusives are kept out of the rotation pools entirely, so they can
    /// never land in a window in the first place.
    @Test func packExclusivesAreNotInTheRotation() {
        let provider = PuzzleProvider.shared
        #expect(!provider.puzzles.contains { $0.id.hasPrefix("pack-") })
        #expect(!provider.minis.contains { $0.id.hasPrefix("pack-") })
    }

    // MARK: - Sunday Specials

    /// The Sunday pool's window is one puzzle wide: this week's Special is
    /// free every day of its week, last week's belongs to Premium's shelf.
    @Test func thisWeeksSundaySpecialIsFreeAllWeek() {
        let provider = PuzzleProvider.shared
        // 2026-08-16 is a Sunday; walk its whole week.
        for offset in 0..<7 {
            let date = utc.date(byAdding: .day, value: offset, to: day(2026, 8, 16))!
            let gate = access(on: date)
            let special = provider.sundaySpecial(for: date, calendar: utc)!
            #expect(gate.canPlay(special, isPremium: false, hasProgress: false),
                    "the week's Special must be free on day \(offset)")
        }
    }

    @Test func lastWeeksSundaySpecialIsLocked() {
        let provider = PuzzleProvider.shared
        let today = day(2026, 8, 19)
        let gate = access(on: today)
        let lastWeek = provider.sundaySpecial(
            for: utc.date(byAdding: .day, value: -7, to: today)!, calendar: utc
        )!
        #expect(lastWeek.id != provider.sundaySpecial(for: today, calendar: utc)!.id)
        #expect(!gate.canPlay(lastWeek, isPremium: false, hasProgress: false))
        #expect(gate.canPlay(lastWeek, isPremium: false, hasProgress: true),
                "a started Special stays yours, like any windowed puzzle")
        #expect(gate.canPlay(lastWeek, isPremium: true, hasProgress: false))
    }

    /// Sundays rotate weekly in their own pool — never in the daily index.
    @Test func sundaySpecialsAreNotInTheDailyRotation() {
        let provider = PuzzleProvider.shared
        #expect(!provider.puzzles.contains { $0.id.hasPrefix("sunday-") })
        #expect(!provider.minis.contains { $0.id.hasPrefix("sunday-") })
        #expect(!provider.sundays.isEmpty)
    }
}
