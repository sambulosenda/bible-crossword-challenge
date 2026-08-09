//
//  RotationWrapTests.swift
//  Bible Crossword ChallengeTests
//
//  The daily is `daysSinceEpoch % pool.count`, so it wraps. These tests pin the
//  two things that make the wrap survivable: that the rotation really does come
//  back to the first puzzle on the dates the roadmap claims, and that a puzzle
//  solved on an earlier day is never presented as today's finished work.
//

import Testing
import Foundation
@testable import Bible_Crossword_Challenge

struct RotationWrapTests {
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }()

    private func day(_ y: Int, _ m: Int, _ d: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: hour))!
    }

    private func record(completedOn date: Date?, seconds: Int = 272) -> PuzzleRecord {
        let r = PuzzleRecord(puzzleID: "daily-001")
        r.isCompleted = true
        r.completedDate = date
        r.elapsedSeconds = seconds
        return r
    }

    // MARK: - The wrap itself
    //
    // These use `Calendar.current` throughout rather than a fixed UTC one,
    // because `PuzzleProvider` builds its epoch from `Calendar.current` too.
    // Pinning the date in UTC while the provider counts in local time puts the
    // index one day out — which is worth knowing in itself: the exact wrap date
    // is the device's, not a universal one.

    /// Days after the 2026-07-01 epoch, counted the way the provider counts.
    private func epochPlus(_ days: Int) -> Date {
        let calendar = Calendar.current
        let epoch = calendar.date(from: DateComponents(year: 2026, month: 7, day: 1))!
        return calendar.date(byAdding: .day, value: days, to: epoch)!
    }

    /// The dates epic 13 is scheduled against. If content is added these move
    /// later, and this is the test that says so out loud.
    @Test func theDailyPoolWrapsAfterItsOwnLength() {
        let provider = PuzzleProvider.shared
        let pool = provider.puzzles
        #expect(pool.count == 92, "daily pool changed — the wrap date has moved")

        #expect(provider.dailyPuzzle(for: epochPlus(pool.count))?.id == pool.first?.id)
        #expect(provider.dailyPuzzle(for: epochPlus(pool.count - 1))?.id != pool.first?.id)
    }

    /// The pool length turned into the calendar date the roadmap plans around.
    /// It was 21 September at 82 dailies; ten more moved it to 1 October, and
    /// every daily added from here moves it another day.
    @Test func theDailyWrapLandsOn1October2026() {
        let wrap = epochPlus(PuzzleProvider.shared.puzzles.count)
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: wrap)
        #expect(parts.year == 2026)
        #expect(parts.month == 10)
        #expect(parts.day == 1)
    }

    @Test func theMiniPoolWrapsAfterItsOwnLength() {
        let provider = PuzzleProvider.shared
        let pool = provider.minis
        #expect(pool.count == 90, "mini pool changed — the wrap date has moved")

        #expect(provider.dailyMini(for: epochPlus(pool.count))?.id == pool.first?.id)
        #expect(provider.dailyMini(for: epochPlus(pool.count - 1))?.id != pool.first?.id)
    }

    @Test func theMiniWrapLandsOn29September2026() {
        let wrap = epochPlus(PuzzleProvider.shared.minis.count)
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: wrap)
        #expect(parts.year == 2026)
        #expect(parts.month == 9)
        #expect(parts.day == 29)
    }

    /// The wrap is a repeat, not a new puzzle — the whole problem in one line.
    @Test func theWrappedDailyIsTheOneServedOnDayOne() {
        let provider = PuzzleProvider.shared
        let firstDay = provider.dailyPuzzle(for: epochPlus(0))
        let wrapDay = provider.dailyPuzzle(for: epochPlus(provider.puzzles.count))
        #expect(firstDay?.id == wrapDay?.id)
    }

    // MARK: - Telling a repeat from today's work

    @Test func aPuzzleSolvedTodayStillCelebrates() {
        let today = day(2026, 9, 21)
        let presentation = DailyPresentation.of(
            record: record(completedOn: today), on: today, calendar: calendar
        )
        #expect(presentation == .solvedToday(seconds: 272))
    }

    /// The case that breaks streaks: solved in July, served again in September.
    @Test func aPuzzleSolvedOnAnEarlierDayIsARepeat() {
        let presentation = DailyPresentation.of(
            record: record(completedOn: day(2026, 7, 1)),
            on: day(2026, 9, 21),
            calendar: calendar
        )
        #expect(presentation == .playedBefore(previousSeconds: 272))
    }

    /// Same calendar day, different clock time — still today's work.
    @Test func earlierTheSameDayIsNotARepeat() {
        let presentation = DailyPresentation.of(
            record: record(completedOn: day(2026, 9, 21, hour: 1)),
            on: day(2026, 9, 21, hour: 23),
            calendar: calendar
        )
        #expect(presentation == .solvedToday(seconds: 272))
    }

    @Test func yesterdayIsARepeatEvenByAnHour() {
        let presentation = DailyPresentation.of(
            record: record(completedOn: day(2026, 9, 20, hour: 23)),
            on: day(2026, 9, 21, hour: 1),
            calendar: calendar
        )
        #expect(presentation == .playedBefore(previousSeconds: 272))
    }

    @Test func anUnsolvedPuzzleIsJustPlayable() {
        #expect(
            DailyPresentation.of(record: nil, on: day(2026, 9, 21), calendar: calendar)
                == .play(.start)
        )

        let started = PuzzleRecord(puzzleID: "daily-001")
        started.entries = ["0,0": "A"]
        #expect(
            DailyPresentation.of(record: started, on: day(2026, 9, 21), calendar: calendar)
                == .play(.inProgress)
        )
    }

    /// Undated completions err toward playable: a needless replay costs nothing,
    /// a false "done" costs a streak.
    @Test func aCompletedRecordWithNoDateIsTreatedAsARepeat() {
        let presentation = DailyPresentation.of(
            record: record(completedOn: nil), on: day(2026, 9, 21), calendar: calendar
        )
        #expect(presentation == .playedBefore(previousSeconds: 272))
    }

    @Test func aZeroTimeIsNotOfferedAsATimeToBeat() {
        let presentation = DailyPresentation.of(
            record: record(completedOn: day(2026, 7, 1), seconds: 0),
            on: day(2026, 9, 21),
            calendar: calendar
        )
        #expect(presentation == .playedBefore(previousSeconds: nil))
    }

    // MARK: - Streak

    /// The mechanism was never the problem — only the card that discouraged the
    /// replay. Worth asserting, since the whole fix rests on it.
    @Test func solvingARepeatStillAdvancesTheStreak() {
        let profile = PlayerProfile()
        profile.currentStreak = 82
        profile.lastCompletedDate = day(2026, 9, 20)

        _ = Streaks.registerCompletion(profile, now: day(2026, 9, 21), calendar: calendar)
        #expect(profile.currentStreak == 83)
    }
}
