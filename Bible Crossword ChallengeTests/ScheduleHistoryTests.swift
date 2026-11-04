//
//  ScheduleHistoryTests.swift
//  Bible Crossword ChallengeTests
//
//  schedule.json took over from the `dayIndex % pool.count` rotation. Every
//  date it covers up to today must serve exactly what the modulo served, or a
//  player's past days (streak, "solved today", challenges) would point at a
//  different puzzle after the update.
//

import Testing
import Foundation
@testable import Bible_Crossword_Challenge

struct ScheduleHistoryTests {
    private let provider = PuzzleProvider()
    // Same calendar the provider builds its epoch from.
    private let calendar = Calendar.current

    private func noon(_ key: String) -> Date {
        let p = key.split(separator: "-").compactMap { Int($0) }
        return calendar.date(from: DateComponents(year: p[0], month: p[1], day: p[2], hour: 12))!
    }

    private func legacy(_ pool: [Puzzle], _ date: Date) -> String {
        let i = provider.dayIndex(for: date, calendar: calendar)
        return pool[((i % pool.count) + pool.count) % pool.count].id
    }

    /// Last day the original 248-puzzle bank served before the schedule.
    private let cutover = "2026-11-04"

    /// The pools as they shipped at the cutover. New puzzles append after
    /// them in file order, so history is the prefix: recomputing it with the
    /// grown pool would expect a rotation nobody was ever served.
    private var legacyDailies: [Puzzle] { Array(provider.puzzles.prefix(92)) }
    private var legacyMinis: [Puzzle] { Array(provider.minis.prefix(97)) }
    private var legacySundays: [Puzzle] { Array(provider.sundays.prefix(13)) }

    @Test func scheduleIsBundled() throws {
        let schedule = try #require(provider.schedule)
        #expect(schedule.daily["2026-07-01"] != nil)
        #expect(schedule.mini[cutover] != nil)
    }

    @Test func pastDailiesMatchTheLegacyRotation() throws {
        let schedule = try #require(provider.schedule)
        for key in schedule.daily.keys where key <= cutover {
            let date = noon(key)
            #expect(provider.dailyPuzzle(for: date, calendar: calendar)?.id == legacy(legacyDailies, date), "daily \(key)")
        }
    }

    @Test func pastMinisMatchTheLegacyRotation() throws {
        let schedule = try #require(provider.schedule)
        for key in schedule.mini.keys where key <= cutover {
            let date = noon(key)
            #expect(provider.dailyMini(for: date, calendar: calendar)?.id == legacy(legacyMinis, date), "mini \(key)")
        }
    }

    @Test func pastSundaysMatchTheLegacyRotation() throws {
        let schedule = try #require(provider.schedule)
        let pool = legacySundays
        for key in schedule.sunday.keys where key <= cutover {
            // Every day of the week serves the same Special.
            for offset in 0..<7 {
                let date = calendar.date(byAdding: .day, value: offset, to: noon(key))!
                let week = provider.weekIndex(for: date, calendar: calendar) - PuzzleProvider.sundayRotationOffset
                let expected = pool[((week % pool.count) + pool.count) % pool.count].id
                #expect(provider.sundaySpecial(for: date, calendar: calendar)?.id == expected, "sunday \(key)+\(offset)")
            }
        }
    }

    /// Adding dailies must not move the verse of the day: it is a modulo
    /// over its pool, so the pool stays the shipped 92.
    @Test func verseOfTheDayDrawsOnlyFromTheShippedDailies() {
        let shipped = Set(legacyDailies.map(\.id))
        for offset in 0..<200 {
            let date = calendar.date(byAdding: .day, value: offset, to: noon("2026-11-01"))!
            let verse = provider.verseOfTheDay(on: date, excluding: nil, calendar: calendar)
            #expect(verse.map { shipped.contains($0.id) } == true, "verse \(offset)")
        }
    }

    @Test func datesPastTheScheduleFallBackToTheRotation() {
        let far = noon("2030-01-01")
        #expect(provider.dailyPuzzle(for: far, calendar: calendar)?.id == legacy(provider.puzzles, far))
        #expect(provider.dailyMini(for: far, calendar: calendar)?.id == legacy(provider.minis, far))
    }
}
