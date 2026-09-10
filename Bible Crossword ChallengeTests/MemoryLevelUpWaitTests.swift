//
//  MemoryLevelUpWaitTests.swift
//  Bible Crossword ChallengeTests
//
//  The anti-grind wait, said out loud: `levelUpAvailableAt` and the countdown
//  string the practice sheet and the list row print from it.
//

import Testing
import Foundation
@testable import Bible_Crossword_Challenge

struct MemoryLevelUpWaitTests {
    private func makeStore() -> (store: MemoryVerseStore, advance: (TimeInterval) -> Void) {
        let defaults = UserDefaults(suiteName: "memory-wait-tests-\(UUID().uuidString)")!
        var current = Date(timeIntervalSince1970: 1_700_000_000)
        let store = MemoryVerseStore(defaults: defaults, now: { current })
        return (store, { current += $0 })
    }

    @Test func noWaitBeforeTheFirstLevelUp() {
        let (store, _) = makeStore()
        let entry = store.start(reference: "John 3:16", verseText: "For God so loved the world")
        #expect(store.levelUpAvailableAt(entry) == nil)
    }

    @Test func waitRunsFromTheLastLevelUpForTheSpacing() {
        let (store, advance) = makeStore()
        let entry = store.start(reference: "John 3:16", verseText: "For God so loved the world")
        _ = store.recordCompletion(referenceKey: entry.referenceKey, hintFree: true)
        let leveled = store.entry(for: entry.referenceKey)!
        #expect(store.levelUpAvailableAt(leveled)
                == leveled.lastLeveledUpAt!.addingTimeInterval(MemoryVerseStore.levelUpSpacing))

        advance(MemoryVerseStore.levelUpSpacing - 1)
        #expect(store.levelUpAvailableAt(leveled) != nil)
        advance(1)
        #expect(store.levelUpAvailableAt(leveled) == nil)
    }

    @Test func hintedRoundsDoNotStartAWait() {
        let (store, _) = makeStore()
        let entry = store.start(reference: "John 3:16", verseText: "For God so loved the world")
        _ = store.recordCompletion(referenceKey: entry.referenceKey, hintFree: false)
        #expect(store.levelUpAvailableAt(store.entry(for: entry.referenceKey)!) == nil)
    }

    @Test func masteredVersesHaveNoWait() {
        let (store, advance) = makeStore()
        let entry = store.start(reference: "John 3:16", verseText: "For God so loved the world")
        for level in 1..<MemoryVerseStore.masteredLevel {
            let outcome = store.recordCompletion(referenceKey: entry.referenceKey, hintFree: true)
            #expect(outcome.newLevel == level + 1)
            // Stay inside the spacing after the final level-up.
            if level + 1 < MemoryVerseStore.masteredLevel { advance(MemoryVerseStore.levelUpSpacing) }
        }
        let mastered = store.entry(for: entry.referenceKey)!
        #expect(mastered.isMastered)
        #expect(store.levelUpAvailableAt(mastered) == nil)
    }
}

struct CountdownFormatTests {
    @Test func roundsUpToTheMinute() {
        #expect(TimeFormat.countdown(59) == "under a minute")
        #expect(TimeFormat.countdown(60) == "1m")
        #expect(TimeFormat.countdown(61) == "2m")
        #expect(TimeFormat.countdown(45 * 60) == "45m")
    }

    @Test func hoursAndMinutes() {
        #expect(TimeFormat.countdown(3600) == "1h")
        #expect(TimeFormat.countdown(3 * 3600 + 40 * 60) == "3h 40m")
        #expect(TimeFormat.countdown(3 * 3600 + 39 * 60 + 1) == "3h 40m")
    }

    @Test func aWaitAlreadyOverReadsAsNow() {
        #expect(TimeFormat.countdown(-5) == "under a minute")
    }
}
