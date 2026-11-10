//
//  DailyRitual.swift
//  Bible Crossword Challenge
//
//  "Daily Bread": the three-minute ritual on Today — solve a puzzle, read the
//  verse it came from, review one memory verse — with one ring that closes
//  when all three are done. Growth & Award Plan, Bet 2 items 1–2.
//
//  Why: memory-verse players hold D7 near 50% against 8% for all installs,
//  but the mode sat behind a row in Keep going (35 players opened it in the
//  30 days to 2026-10-03). The ritual puts one review inside the daily loop
//  for everyone, and the solved puzzle's verse feeds the shelf for players
//  who have nothing on it yet.
//
//  Pure and derived, the `BibleJourney` pattern: beat one comes from today's
//  completed records, beat three from `MemoryVerseStore`, and only beat two
//  (reading the verse) needs a stored day — nothing else in the app records
//  that a verse was read. No `PuzzleRecord`, no CloudKit schema change.
//

import Foundation

struct DailyRitual: Equatable {

    enum Beat: String, CaseIterable, Sendable {
        case puzzle, verse, review
    }

    /// The verse of a puzzle solved today — beat two. Never today's unsolved
    /// verse: it would spoil the answers (see `TodayHeader`).
    struct Verse: Equatable, Hashable, Identifiable {
        let reference: String
        let text: String
        var id: String { MemoryCloze.referenceKey(reference) }
    }

    /// What beat three opens.
    enum Review: Equatable {
        /// A verse already on the shelf: due, new today, or the stalest.
        case practice(referenceKey: String, reference: String, isDue: Bool)
        /// Nothing on the shelf yet: today's verse becomes the first one.
        case learn(Verse)
        /// Nothing on the shelf and no verse to start from yet — beat three
        /// waits for beat one.
        case waitingForVerse
        /// Nothing on the shelf and today's verse doesn't fit the memory
        /// grid: the list's starter verses instead.
        case choose
    }

    let verse: Verse?
    let done: Set<Beat>
    /// Nil once beat three is done today.
    let review: Review?

    var isComplete: Bool { done.count == Beat.allCases.count }
    var doneCount: Int { done.count }
    /// The beat the card points at: the first one not yet done.
    var nextBeat: Beat? { Beat.allCases.first { !done.contains($0) } }

    // MARK: - Building

    /// A puzzle finished on the ritual's day: its verse and when.
    struct Solve {
        let reference: String
        let verse: String
        let completedAt: Date
    }

    /// The ritual for `day` (any moment in it).
    ///
    /// - Parameters:
    ///   - solvesToday: puzzles completed on `day`. The latest one's verse is
    ///     beat two — the verse "it came from".
    ///   - verseReadDay: the day beat two was last done, if ever.
    @MainActor
    static func make(
        day: Date,
        calendar: Calendar = .current,
        solvesToday: [Solve],
        verseReadDay: Date?,
        memory: MemoryVerseStore
    ) -> DailyRitual {
        let latest = solvesToday.max { $0.completedAt < $1.completedAt }
        let verse = latest.map { Verse(reference: $0.reference, text: $0.verse) }

        var done = Set<Beat>()
        if latest != nil { done.insert(.puzzle) }
        // Only with a verse to have read: a stored day without a solve can't
        // happen through the card, and mustn't close the ring if it did.
        if verse != nil, let read = verseReadDay, calendar.isDate(read, inSameDayAs: day) {
            done.insert(.verse)
        }
        let practicedToday = memory.entries.contains {
            $0.lastPracticedAt.map { calendar.isDate($0, inSameDayAs: day) } ?? false
        }
        if practicedToday { done.insert(.review) }

        let review: Review? = practicedToday ? nil : {
            if let pick = reviewPick(memory: memory, day: day, calendar: calendar) {
                return .practice(referenceKey: pick.referenceKey, reference: pick.reference,
                                 isDue: memory.isDue(pick))
            }
            guard let verse else { return .waitingForVerse }
            return MemoryCloze.isEligible(verseText: verse.text) ? .learn(verse) : .choose
        }()
        return DailyRitual(verse: verse, done: done, review: review)
    }

    /// The one verse beat three reviews. In order:
    /// 1. a verse started today and never practised — the player just pressed
    ///    "Learn it by heart" on beat two, and anything else would be a swap;
    /// 2. the most overdue verse due for review (spaced repetition);
    /// 3. an older verse never practised;
    /// 4. a learning verse, stalest first;
    /// 5. a mastered verse, stalest first — the occasional full-recall pass.
    /// Nil only when the shelf is empty.
    @MainActor
    static func reviewPick(memory: MemoryVerseStore, day: Date, calendar: Calendar = .current) -> MemoryVerseStore.Entry? {
        let entries = memory.entries
        guard !entries.isEmpty else { return nil }

        if let fresh = entries
            .filter({ $0.lastPracticedAt == nil && calendar.isDate($0.startedAt, inSameDayAs: day) })
            .max(by: { $0.startedAt < $1.startedAt }) {
            return fresh
        }
        if let due = entries
            .filter({ memory.isDue($0) })
            .min(by: { (memory.dueDate($0) ?? .distantPast) < (memory.dueDate($1) ?? .distantPast) }) {
            return due
        }
        if let unpracticed = entries
            .filter({ $0.lastPracticedAt == nil })
            .min(by: { $0.startedAt < $1.startedAt }) {
            return unpracticed
        }
        let stalest: (MemoryVerseStore.Entry, MemoryVerseStore.Entry) -> Bool = {
            ($0.lastPracticedAt ?? .distantPast) < ($1.lastPracticedAt ?? .distantPast)
        }
        return entries.filter { !$0.isMastered }.min(by: stalest)
            ?? entries.min(by: stalest)
    }
}
