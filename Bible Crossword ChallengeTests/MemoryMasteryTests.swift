//
//  MemoryMasteryTests.swift
//  Bible Crossword ChallengeTests
//
//  Pins the mastery ladder: level-up gating (hints, spacing), the mastered
//  cap, review due dates, the free-tier limit, and persistence round-trip.
//

import Testing
import Foundation
@testable import Bible_Crossword_Challenge

/// A store on an isolated suite with a controllable clock.
private func makeStore(start: Date = Date(timeIntervalSince1970: 1_700_000_000))
-> (store: MemoryVerseStore, advance: (TimeInterval) -> Void, suiteName: String) {
    let suiteName = "memory-tests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    var current = start
    let store = MemoryVerseStore(defaults: defaults, now: { current })
    return (store, { current += $0 }, suiteName)
}

struct MemoryMasteryTests {

    @Test func startIsIdempotentAndBeginsAtLevelOne() {
        let (store, _, _) = makeStore()
        let first = store.start(reference: "John 3:16", verseText: "For God so loved")
        let second = store.start(reference: "John 3:16", verseText: "different text ignored")
        #expect(first.level == 1)
        #expect(store.entries.count == 1)
        #expect(second.verseText == "For God so loved")
    }

    @Test func hintFreeCompletionLevelsUp() {
        let (store, _, _) = makeStore()
        let entry = store.start(reference: "John 3:16", verseText: "For God so loved")
        let outcome = store.recordCompletion(referenceKey: entry.referenceKey, hintFree: true)
        #expect(outcome.leveledUp)
        #expect(outcome.newLevel == 2)
        #expect(store.entry(for: entry.referenceKey)?.timesCompleted == 1)
    }

    @Test func hintedCompletionRecordsPracticeWithoutLevelUp() {
        let (store, _, _) = makeStore()
        let entry = store.start(reference: "John 3:16", verseText: "For God so loved")
        let outcome = store.recordCompletion(referenceKey: entry.referenceKey, hintFree: false)
        #expect(!outcome.leveledUp)
        #expect(outcome.newLevel == 1)
        #expect(store.entry(for: entry.referenceKey)?.lastPracticedAt != nil)
    }

    @Test func levelUpRespectsSpacing() {
        let (store, advance, _) = makeStore()
        let entry = store.start(reference: "John 3:16", verseText: "For God so loved")
        #expect(store.recordCompletion(referenceKey: entry.referenceKey, hintFree: true).leveledUp)

        // A second flawless run minutes later practices but doesn't level.
        advance(60)
        let ground = store.recordCompletion(referenceKey: entry.referenceKey, hintFree: true)
        #expect(!ground.leveledUp)
        #expect(ground.newLevel == 2)

        // After the spacing window it levels again.
        advance(MemoryVerseStore.levelUpSpacing)
        let spaced = store.recordCompletion(referenceKey: entry.referenceKey, hintFree: true)
        #expect(spaced.leveledUp)
        #expect(spaced.newLevel == 3)
    }

    @Test func masteryCapsAtFiveAndFlagsTheMoment() {
        let (store, advance, _) = makeStore()
        let entry = store.start(reference: "John 3:16", verseText: "For God so loved")
        var lastOutcome = MemoryVerseStore.CompletionOutcome(leveledUp: false, newLevel: 1)
        for _ in 1...4 {
            advance(MemoryVerseStore.levelUpSpacing + 1)
            lastOutcome = store.recordCompletion(referenceKey: entry.referenceKey, hintFree: true)
        }
        #expect(lastOutcome.mastered)
        #expect(lastOutcome.newLevel == 5)
        #expect(store.entry(for: entry.referenceKey)?.isMastered == true)
        #expect(store.entry(for: entry.referenceKey)?.playLevel == 4)

        // Beyond mastered: practice records, level holds.
        advance(MemoryVerseStore.levelUpSpacing + 1)
        let after = store.recordCompletion(referenceKey: entry.referenceKey, hintFree: true)
        #expect(!after.leveledUp)
        #expect(after.newLevel == 5)
    }

    @Test func dueDateFollowsLevelLadder() {
        let (store, _, _) = makeStore()
        let entry = store.start(reference: "John 3:16", verseText: "For God so loved")
        #expect(store.dueDate(entry) == nil)
        #expect(!store.isDue(entry))

        _ = store.recordCompletion(referenceKey: entry.referenceKey, hintFree: false)
        let updated = store.entry(for: entry.referenceKey)!
        let due = store.dueDate(updated)!
        let expected = Calendar.current.date(byAdding: .day, value: 1, to: updated.lastPracticedAt!)!
        #expect(due == expected)
    }

    @Test func overdueVerseIsDue() {
        let (store, advance, _) = makeStore()
        let entry = store.start(reference: "John 3:16", verseText: "For God so loved")
        _ = store.recordCompletion(referenceKey: entry.referenceKey, hintFree: false)
        #expect(store.dueCount == 0)
        advance(2 * 24 * 60 * 60)
        #expect(store.dueCount == 1)
    }

    @Test func freeTierLimitIgnoresMasteredVerses() {
        let (store, advance, _) = makeStore()
        for i in 1...MemoryVerseStore.freeVerseLimit {
            store.start(reference: "Ref \(i):1", verseText: "verse \(i)")
        }
        #expect(!store.canStartNewVerse(isPremium: false))
        #expect(store.canStartNewVerse(isPremium: true))

        // Mastering one frees a slot.
        let key = MemoryCloze.referenceKey("Ref 1:1")
        for _ in 1...4 {
            advance(MemoryVerseStore.levelUpSpacing + 1)
            _ = store.recordCompletion(referenceKey: key, hintFree: true)
        }
        #expect(store.canStartNewVerse(isPremium: false))
    }

    @Test func entriesSurviveReload() {
        let suiteName = "memory-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let store = MemoryVerseStore(defaults: defaults, now: Date.init)
        store.start(reference: "John 3:16", verseText: "For God so loved")
        _ = store.recordCompletion(referenceKey: "john-3:16", hintFree: true)

        let reloaded = MemoryVerseStore(defaults: defaults, now: Date.init)
        #expect(reloaded.entries.count == 1)
        #expect(reloaded.entry(for: "john-3:16")?.level == 2)
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test func candidatesDedupeAndExcludeHeldOrIneligible() {
        let (store, _, _) = makeStore()
        func puzzle(_ id: String, _ reference: String, _ verse: String) -> Puzzle {
            Puzzle(
                id: id, title: reference, difficulty: .easy, verse: verse,
                reference: reference, publishDate: "", size: 3, grid: ["..."], clues: []
            )
        }
        let puzzles = [
            puzzle("daily-001", "John 3:16", "For God so loved the world"),
            puzzle("daily-002", "John 3:16", "duplicate reference, different text"),
            puzzle("daily-003", "Psalm 23:1", "The Lord is my shepherd"),
            puzzle("daily-004", "Job 3:2", "Said"),               // 1 word: ineligible
            puzzle("daily-005", "Luke 1:1", "Never completed"),
        ]
        store.start(reference: "Psalm 23:1", verseText: "The Lord is my shepherd")

        let candidates = store.candidates(
            completedPuzzleIDs: ["daily-001", "daily-002", "daily-003", "daily-004"],
            puzzles: puzzles
        )
        #expect(candidates.map(\.reference) == ["John 3:16"])
        #expect(candidates.first?.verseText == "For God so loved the world")
    }
}
