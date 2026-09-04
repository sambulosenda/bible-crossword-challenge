//
//  ReadingPlanStoreTests.swift
//  Bible Crossword ChallengeTests
//
//  The chapter-a-day plan's bookkeeping: sequential days, "read today" on a
//  controllable clock, completion, switching, and the persistence round-trip.
//

import Testing
import Foundation
@testable import Bible_Crossword_Challenge

private func makeStore(start: Date = Date(timeIntervalSince1970: 1_700_000_000))
-> (store: ReadingPlanStore, advance: (TimeInterval) -> Void, defaults: UserDefaults) {
    let defaults = UserDefaults(suiteName: "plan-tests-\(UUID().uuidString)")!
    var current = start
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    let store = ReadingPlanStore(defaults: defaults, now: { current }, calendar: calendar)
    return (store, { current += $0 }, defaults)
}

struct ReadingPlanStoreTests {
    private let john = ReadingPlan.named("john")!

    @Test func startsAtDayOneWithNothingReadToday() {
        let (store, _, _) = makeStore()
        store.start(john, chapterCount: 21)
        #expect(store.activePlan == john)
        #expect(store.nextDay == 1)
        #expect(!store.readToday)
        #expect(!store.isComplete)
    }

    @Test func markReadAdvancesOnlyInOrder() {
        let (store, _, _) = makeStore()
        store.start(john, chapterCount: 21)
        #expect(!store.markRead(day: 2), "can't skip day 1")
        #expect(store.markRead(day: 1))
        #expect(!store.markRead(day: 1), "can't mark a day twice")
        #expect(store.nextDay == 2)
        #expect(store.readToday)
    }

    @Test func readTodayResetsOnTheNextCalendarDay() {
        let (store, advance, _) = makeStore()
        store.start(john, chapterCount: 21)
        store.markRead(day: 1)
        advance(24 * 60 * 60)
        #expect(!store.readToday)
        #expect(store.nextDay == 2, "the chapter waits; nothing is lost")
    }

    @Test func readingAheadInOneSittingIsAllowed() {
        let (store, _, _) = makeStore()
        store.start(john, chapterCount: 21)
        #expect(store.markRead(day: 1))
        #expect(store.markRead(day: 2))
        #expect(store.nextDay == 3)
    }

    @Test func completesAtTheLastChapter() {
        let (store, _, _) = makeStore()
        store.start(john, chapterCount: 3)
        for day in 1...3 { #expect(store.markRead(day: day)) }
        #expect(store.isComplete)
        #expect(store.nextDay == nil)
        #expect(!store.markRead(day: 4), "nothing past the last chapter")
    }

    @Test func switchingPlansDropsProgress() {
        let (store, _, _) = makeStore()
        store.start(john, chapterCount: 21)
        store.markRead(day: 1)
        let mark = ReadingPlan.named("mark")!
        store.start(mark, chapterCount: 16)
        #expect(store.activePlan == mark)
        #expect(store.nextDay == 1)
    }

    @Test func progressSurvivesRelaunch() {
        let (store, _, defaults) = makeStore()
        store.start(john, chapterCount: 21)
        store.markRead(day: 1)
        let reloaded = ReadingPlanStore(defaults: defaults)
        #expect(reloaded.activePlan == john)
        #expect(reloaded.nextDay == 2)
        #expect(reloaded.progress?.chapterCount == 21)
    }

    @Test func stopClearsEverything() {
        let (store, _, defaults) = makeStore()
        store.start(john, chapterCount: 21)
        store.stop()
        #expect(store.activePlan == nil)
        #expect(ReadingPlanStore(defaults: defaults).activePlan == nil)
    }

    @Test func everyPlanNamesABookInTheBundle() {
        let scripture = ScriptureProvider.shared
        for plan in ReadingPlan.all {
            #expect(scripture.book(named: plan.book) != nil, "\(plan.id) → \(plan.book)")
        }
    }
}
