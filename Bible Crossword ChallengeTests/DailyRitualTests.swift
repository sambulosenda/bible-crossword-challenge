//
//  DailyRitualTests.swift
//  Bible Crossword ChallengeTests
//
//  Pins Daily Bread: which beats count as done on a day, what beat two's
//  verse is, and which verse beat three reviews.
//

import Testing
import Foundation
@testable import Bible_Crossword_Challenge

/// 2023-11-14 12:00 UTC — midday, so an hour either way stays on the day.
private let noon = Date(timeIntervalSince1970: 1_699_963_200)
private let day: TimeInterval = 24 * 60 * 60

private let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

/// A store on an isolated suite whose clock the test moves.
private final class Clock {
    var now: Date
    init(_ now: Date) { self.now = now }
}

private func makeStore(at start: Date) -> (MemoryVerseStore, Clock) {
    let defaults = UserDefaults(suiteName: "ritual-tests-\(UUID().uuidString)")!
    let clock = Clock(start)
    return (MemoryVerseStore(defaults: defaults, now: { clock.now }), clock)
}

private let shortVerse = "The wolf will live with the lamb"

private func solve(_ reference: String, _ verse: String = shortVerse, at: Date = noon) -> DailyRitual.Solve {
    DailyRitual.Solve(reference: reference, verse: verse, completedAt: at)
}

struct DailyRitualTests {

    @Test func nothingDoneWaitsForTheFirstSolve() {
        let (store, _) = makeStore(at: noon)
        let ritual = DailyRitual.make(day: noon, calendar: utc, solvesToday: [], verseReadDay: nil, memory: store)
        #expect(ritual.done.isEmpty)
        #expect(ritual.verse == nil)
        #expect(ritual.review == .waitingForVerse)
        #expect(ritual.nextBeat == .puzzle)
    }

    @Test func aSolveDoesBeatOneAndOffersItsVerse() {
        let (store, _) = makeStore(at: noon)
        let ritual = DailyRitual.make(
            day: noon, calendar: utc,
            solvesToday: [solve("Isaiah 11:6", at: noon.addingTimeInterval(-3600)), solve("John 3:16", at: noon)],
            verseReadDay: nil, memory: store
        )
        #expect(ritual.done == [.puzzle])
        // The latest solve's verse: the one "it came from".
        #expect(ritual.verse?.reference == "John 3:16")
        #expect(ritual.review == .learn(DailyRitual.Verse(reference: "John 3:16", text: shortVerse)))
        #expect(ritual.nextBeat == .verse)
    }

    @Test func aVerseTheGridCantHoldOffersTheListInstead() {
        let (store, _) = makeStore(at: noon)
        let ritual = DailyRitual.make(
            day: noon, calendar: utc, solvesToday: [solve("John 11:35", "Wept")],
            verseReadDay: nil, memory: store
        )
        #expect(ritual.review == .choose)
    }

    @Test func theVerseBeatCountsOnlyOnItsDay() {
        let (store, _) = makeStore(at: noon)
        let today = DailyRitual.make(day: noon, calendar: utc, solvesToday: [solve("John 3:16")],
                                     verseReadDay: noon.addingTimeInterval(-3600), memory: store)
        #expect(today.done.contains(.verse))

        let yesterday = DailyRitual.make(day: noon, calendar: utc, solvesToday: [solve("John 3:16")],
                                         verseReadDay: noon.addingTimeInterval(-day), memory: store)
        #expect(!yesterday.done.contains(.verse))
    }

    @Test func aReadDayWithoutASolveDoesNotCount() {
        let (store, _) = makeStore(at: noon)
        let ritual = DailyRitual.make(day: noon, calendar: utc, solvesToday: [], verseReadDay: noon, memory: store)
        #expect(!ritual.done.contains(.verse))
    }

    @Test func practisingAnyVerseTodayClosesTheRing() {
        let (store, _) = makeStore(at: noon)
        let entry = store.start(reference: "John 3:16", verseText: shortVerse)
        _ = store.recordCompletion(referenceKey: entry.referenceKey, hintFree: true)
        let ritual = DailyRitual.make(day: noon, calendar: utc, solvesToday: [solve("John 3:16")],
                                      verseReadDay: noon, memory: store)
        #expect(ritual.isComplete)
        #expect(ritual.review == nil)
        #expect(ritual.nextBeat == nil)
    }

    @Test func yesterdaysPracticeLeavesTheReviewOpen() {
        let (store, clock) = makeStore(at: noon.addingTimeInterval(-day))
        let entry = store.start(reference: "John 3:16", verseText: shortVerse)
        _ = store.recordCompletion(referenceKey: entry.referenceKey, hintFree: true)
        clock.now = noon
        let ritual = DailyRitual.make(day: noon, calendar: utc, solvesToday: [], verseReadDay: nil, memory: store)
        #expect(!ritual.done.contains(.review))
        if case .practice(let key, _, _) = ritual.review {
            #expect(key == entry.referenceKey)
        } else {
            Issue.record("Expected a practice review, got \(String(describing: ritual.review))")
        }
    }

    // MARK: - Which verse beat three reviews

    @Test func aVerseStartedTodayComesBeforeADueOne() {
        let (store, clock) = makeStore(at: noon.addingTimeInterval(-3 * day))
        let old = store.start(reference: "Psalm 23:1", verseText: shortVerse)
        _ = store.recordCompletion(referenceKey: old.referenceKey, hintFree: true)
        clock.now = noon
        #expect(store.isDue(store.entry(for: old.referenceKey)!))
        #expect(DailyRitual.reviewPick(memory: store, day: noon, calendar: utc)?.referenceKey == old.referenceKey)

        let fresh = store.start(reference: "John 3:16", verseText: shortVerse)
        #expect(DailyRitual.reviewPick(memory: store, day: noon, calendar: utc)?.referenceKey == fresh.referenceKey)
    }

    @Test func anOlderUnpractisedVerseComesBeforeOneNotYetDue() {
        let (store, clock) = makeStore(at: noon.addingTimeInterval(-3 * day))
        let waiting = store.start(reference: "Psalm 23:1", verseText: shortVerse)
        clock.now = noon.addingTimeInterval(-day / 2)
        let recent = store.start(reference: "John 3:16", verseText: shortVerse)
        _ = store.recordCompletion(referenceKey: recent.referenceKey, hintFree: true)
        clock.now = noon
        #expect(DailyRitual.reviewPick(memory: store, day: noon, calendar: utc)?.referenceKey == waiting.referenceKey)
    }

    @Test func aLearningVerseComesBeforeAMasteredOne() {
        let (store, clock) = makeStore(at: noon.addingTimeInterval(-10 * day))
        let mastered = store.start(reference: "Psalm 23:1", verseText: shortVerse)
        for _ in 1...4 {
            clock.now = clock.now.addingTimeInterval(MemoryVerseStore.levelUpSpacing + 1)
            _ = store.recordCompletion(referenceKey: mastered.referenceKey, hintFree: true)
        }
        #expect(store.entry(for: mastered.referenceKey)?.isMastered == true)

        clock.now = noon.addingTimeInterval(-day / 2)
        let learning = store.start(reference: "John 3:16", verseText: shortVerse)
        _ = store.recordCompletion(referenceKey: learning.referenceKey, hintFree: true)
        clock.now = noon
        #expect(DailyRitual.reviewPick(memory: store, day: noon, calendar: utc)?.referenceKey == learning.referenceKey)
    }

    @Test func anEmptyShelfHasNothingToReview() {
        let (store, _) = makeStore(at: noon)
        #expect(DailyRitual.reviewPick(memory: store, day: noon, calendar: utc) == nil)
    }
}
