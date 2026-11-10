//
//  WidgetClueTests.swift
//  Bible Crossword ChallengeTests
//
//  Pins the Clue of the Day the app publishes for the interactive widget:
//  which clue a day gets, the tiles it's played with, and the events the
//  widget queues for the app to log.
//

import Testing
import Foundation
@testable import Bible_Crossword_Challenge

struct WidgetClueTests {
    private let provider = PuzzleProvider()
    private let calendar = Calendar.current

    private var start: Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 12))!
    }

    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: start)!
    }

    @Test func nearlyEveryDayHasAClue() {
        let days = (0..<120).map(day)
        let withClue = days.filter { WidgetBridge.clueOfTheDay(on: $0, provider: provider, calendar: calendar) != nil }
        #expect(withClue.count >= 108, "\(withClue.count) of 120 days have a clue")
    }

    /// The widget must not hand out an answer from the grid the player is
    /// about to open: the clue is never one of the day's daily's.
    @Test func clueNeverComesFromTheDaysDaily() {
        for offset in 0..<120 {
            let date = day(offset)
            guard let clue = WidgetBridge.clueOfTheDay(on: date, provider: provider, calendar: calendar),
                  let daily = provider.dailyPuzzle(for: date, calendar: calendar)
            else { continue }
            let dailyClues = daily.clues.map { "\($0.text)|\($0.answer.uppercased())" }
            #expect(!dailyClues.contains("\(clue.clue)|\(clue.answer)"), "day \(offset)")
        }
    }

    /// Solving shows the verse of the day, the one Today's header shows.
    @Test func clueUnlocksTheVerseOfTheDay() throws {
        for offset in 0..<30 {
            let date = day(offset)
            guard let clue = WidgetBridge.clueOfTheDay(on: date, provider: provider, calendar: calendar) else { continue }
            let verse = try #require(provider.verseOfTheDay(
                on: date, excluding: provider.dailyPuzzle(for: date, calendar: calendar)?.id, calendar: calendar
            ))
            #expect(clue.verse == verse.verse)
            #expect(clue.reference == verse.reference)
            #expect(verse.clues.contains { $0.text == clue.clue && $0.answer.uppercased() == clue.answer })
        }
    }

    @Test func tilesHoldTheAnswerAndTwoDecoys() {
        for offset in 0..<120 {
            guard let clue = WidgetBridge.clueOfTheDay(on: day(offset), provider: provider, calendar: calendar) else { continue }
            #expect(WidgetBridge.clueLengths.contains(clue.answer.count))
            #expect(clue.tiles.count == clue.answer.count + WidgetBridge.decoyCount)
            #expect(clue.tiles.allSatisfy { $0.count == 1 })
            var pool = clue.tiles
            for letter in clue.answer.map(String.init) {
                let index = pool.firstIndex(of: letter)
                #expect(index != nil, "day \(offset): \(letter) missing from \(clue.tiles)")
                if let index { pool.remove(at: index) }
            }
            // Tapping left to right must not spell it.
            #expect(clue.tiles.prefix(clue.answer.count).joined() != clue.answer, "day \(offset)")
        }
    }

    /// Progress is stored as tile indices, so the same day must give the
    /// same tiles on every publish.
    @Test func sameDaySameClueAndTiles() {
        for offset in 0..<20 {
            let a = WidgetBridge.clueOfTheDay(on: day(offset), provider: provider, calendar: calendar)
            let b = WidgetBridge.clueOfTheDay(
                on: calendar.date(byAdding: .hour, value: 9, to: calendar.startOfDay(for: day(offset)))!,
                provider: provider, calendar: calendar
            )
            #expect(a == b)
        }
    }

    @Test func onlyShortStandaloneLetterCluesFit() {
        func clue(_ text: String, _ answer: String) -> ClueData {
            ClueData(number: 1, direction: .across, row: 0, col: 0, text: text, answer: answer)
        }
        #expect(WidgetBridge.fitsWidget(clue("Garden of the first man", "EDEN")))
        #expect(WidgetBridge.fitsWidget(clue("Ark builder", "noah")))
        #expect(!WidgetBridge.fitsWidget(clue("Too short", "OX")))
        #expect(!WidgetBridge.fitsWidget(clue("Too long for tiles", "JERUSALEM")))
        #expect(!WidgetBridge.fitsWidget(clue("See 5-Across", "MOSES")))
        #expect(!WidgetBridge.fitsWidget(clue("With 12 Down, a prophet", "ELIJAH")))
        #expect(!WidgetBridge.fitsWidget(clue("Two words", "RED SEA")))
        #expect(!WidgetBridge.fitsWidget(clue(String(repeating: "x", count: 71), "LAMB")))
    }

    @Test func queuedWidgetEventsAreLoggedOnceWithTheirLateness() {
        let defaults = UserDefaults(suiteName: "widget-clue-tests-\(UUID().uuidString)")!
        let today = calendar.startOfDay(for: start)
        let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: today)!
        defaults.set([
            ["event": "started", "day": twoDaysAgo.timeIntervalSinceReferenceDate, "length": 4, "wrong": 0],
            ["event": "solved", "day": today.timeIntervalSinceReferenceDate, "length": 5, "wrong": 2],
            ["event": "bogus", "day": today.timeIntervalSinceReferenceDate, "length": 5, "wrong": 0],
        ], forKey: WidgetBridge.Key.clueEvents)

        let events = WidgetBridge.takeClueEvents(from: defaults, today: start, calendar: calendar)
        #expect(events.map(\.name) == ["widget_clue_started", "widget_clue_solved"])
        #expect(events.first?.parameters["days_late"] as? Int == 2)
        #expect(events.last?.parameters["wrong_attempts"] as? Int == 2)
        #expect(events.last?.parameters["days_late"] as? Int == 0)

        #expect(WidgetBridge.takeClueEvents(from: defaults, today: start, calendar: calendar).isEmpty)
    }
}
