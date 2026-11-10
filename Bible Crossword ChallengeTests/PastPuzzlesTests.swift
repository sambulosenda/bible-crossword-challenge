//
//  PastPuzzlesTests.swift
//  Bible Crossword ChallengeTests
//
//  The calendar's one promise is that a day names a puzzle and a puzzle
//  names a day. These pin that, and the grid arithmetic around it.
//

import Testing
import Foundation
@testable import Bible_Crossword_Challenge

struct PastPuzzlesTests {
    private let provider = PuzzleProvider()
    // Same calendar the provider builds its epoch from.
    private let calendar = Calendar.current

    private func noon(_ year: Int, _ month: Int, _ day: Int, in calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    @Test(arguments: PastPuzzleKind.allCases)
    func theSpanStartsTodayAndNeverRepeatsAPuzzle(kind: PastPuzzleKind) throws {
        let today = noon(2026, 11, 10, in: calendar)
        let days = PastPuzzles.days(kind, provider: provider, today: today, calendar: calendar)
        let pool = kind == .daily ? provider.puzzles : provider.minis

        let first = try #require(days.first)
        #expect(first.date == calendar.startOfDay(for: today))
        let served = kind == .daily
            ? provider.dailyPuzzle(for: today, calendar: calendar)
            : provider.dailyMini(for: today, calendar: calendar)
        #expect(first.puzzle.id == served?.id)

        #expect(Set(days.map(\.puzzle.id)).count == days.count)
        #expect(days.count <= pool.count)
        // A span shorter than the free window would leave nothing to unlock.
        #expect(days.count > PuzzleAccess.windowLength)
    }

    @Test(arguments: PastPuzzleKind.allCases)
    func theSpanWalksBackOneDayAtATime(kind: PastPuzzleKind) {
        let today = noon(2026, 11, 10, in: calendar)
        let days = PastPuzzles.days(kind, provider: provider, today: today, calendar: calendar)
        for (offset, day) in days.enumerated() {
            let expected = calendar.date(byAdding: .day, value: -offset, to: calendar.startOfDay(for: today))
            #expect(day.date == expected)
        }
    }

    @Test func everyDayLandsInExactlyOneMonthNewestFirst() {
        let today = noon(2026, 11, 10, in: calendar)
        let days = PastPuzzles.days(.daily, provider: provider, today: today, calendar: calendar)
        let months = PastPuzzles.months(days, calendar: calendar)

        #expect(months.flatMap(\.days).map(\.date).sorted() == days.map(\.date).sorted())
        #expect(months.map(\.start) == months.map(\.start).sorted(by: >))
        #expect(months.first?.start == calendar.dateInterval(of: .month, for: today)?.start)
    }

    @Test func aMonthIsPaddedToItsFirstWeekday() throws {
        var sundayFirst = Calendar(identifier: .gregorian)
        sundayFirst.firstWeekday = 1
        var mondayFirst = sundayFirst
        mondayFirst.firstWeekday = 2

        let puzzle = try #require(provider.puzzles.first)
        // 1 October 2026 is a Thursday.
        func october(_ calendar: Calendar) -> PastPuzzleMonth? {
            let days = [15, 1].map {
                PastPuzzleDay(date: calendar.startOfDay(for: noon(2026, 10, $0, in: calendar)), puzzle: puzzle)
            }
            return PastPuzzles.months(days, calendar: calendar).first
        }
        func leadingBlanks(_ month: PastPuzzleMonth?) -> Int {
            month?.cells.prefix { if case .blank = $0 { true } else { false } }.count ?? -1
        }

        #expect(leadingBlanks(october(sundayFirst)) == 4)
        #expect(leadingBlanks(october(mondayFirst)) == 3)
        // Only the weeks the span touches are kept: the 1st's and the 15th's.
        #expect(october(sundayFirst)?.cells.count == 14)
        #expect(october(sundayFirst)?.days.count == 2)
    }

    @Test func weekdayInitialsFollowTheFirstWeekday() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US")
        calendar.firstWeekday = 1
        #expect(PastPuzzles.weekdaySymbols(calendar: calendar) == ["S", "M", "T", "W", "T", "F", "S"])
        calendar.firstWeekday = 2
        #expect(PastPuzzles.weekdaySymbols(calendar: calendar) == ["M", "T", "W", "T", "F", "S", "S"])
    }
}
