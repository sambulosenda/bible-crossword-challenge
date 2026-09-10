//
//  MemoryVerseStore.swift
//  Bible Crossword Challenge
//
//  Mastery state for memory-verse mode. Stored in UserDefaults for the same
//  reason the challenge ledger is (see `ChallengeHistory`) — a new synced model
//  would mean a CloudKit schema re-deploy, and mastery is low-stakes,
//  re-earnable state. The entries are Codable, so a later migration to a synced
//  model is additive.
//
//  Deliberately never writes a `PuzzleRecord`: those sync, feed streaks,
//  achievements and the access grandfather clause, and a `memory-` id in that
//  table would be bookkeeping pollution everywhere it's read.
//

import Foundation
import Observation
import os

@Observable
final class MemoryVerseStore {
    static let shared = MemoryVerseStore()

    struct Entry: Codable, Equatable, Hashable, Identifiable {
        /// Normalized reference (see `MemoryCloze.referenceKey`) — the identity
        /// a practice session is keyed on.
        let referenceKey: String
        let reference: String
        /// Denormalised: the verse as first met, so a row renders (and a grid
        /// builds) without a bundle lookup — and without drifting if the
        /// bundled text is ever edited mid-memorization.
        let verseText: String
        /// 1–4 are learning (each sets the blank fraction of the next session);
        /// 5 is mastered. See `MemoryCloze.blankFraction`.
        var level: Int
        var timesCompleted: Int
        var lastPracticedAt: Date?
        /// When the level last rose — the anti-grind clock.
        var lastLeveledUpAt: Date?
        let startedAt: Date

        var id: String { referenceKey }
        var isMastered: Bool { level >= MemoryVerseStore.masteredLevel }

        /// The level the next practice session builds its grid at. A mastered
        /// verse replays the full-recall grid.
        var playLevel: Int { min(level, MemoryVerseStore.masteredLevel - 1) }
    }

    /// What a completion did to the verse — the completion sheet's script.
    struct CompletionOutcome {
        let leveledUp: Bool
        let newLevel: Int
        var mastered: Bool { leveledUp && newLevel >= MemoryVerseStore.masteredLevel }
    }

    static let masteredLevel = 5

    /// Verses a free player can hold in active memorization. Practicing what
    /// was already started stays free forever — the wall is only in front of
    /// adding more.
    static let freeVerseLimit = 3

    /// A level-up must be at least this far from the previous one, so "mastered"
    /// can't be ground out in one sitting — the spacing is the memorization.
    static let levelUpSpacing: TimeInterval = 4 * 60 * 60

    /// Days until a verse at each level wants review. Sort key and badge only —
    /// nothing decays.
    private static let reviewDays: [Int: Int] = [1: 1, 2: 2, 3: 4, 4: 7, 5: 14]

    private let defaults: UserDefaults
    private let now: () -> Date
    private let storageKey = "memoryVerses.v1"

    private(set) var entries: [Entry] = []

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.now = now
        self.entries = Self.load(from: defaults, key: storageKey)
    }

    // MARK: - Reading

    func entry(for referenceKey: String) -> Entry? {
        entries.first { $0.referenceKey == referenceKey }
    }

    /// When this verse wants its next practice. Nil until first practiced.
    func dueDate(_ entry: Entry) -> Date? {
        guard let last = entry.lastPracticedAt else { return nil }
        let days = Self.reviewDays[min(max(entry.level, 1), Self.masteredLevel)] ?? 1
        return Calendar.current.date(byAdding: .day, value: days, to: last)
    }

    func isDue(_ entry: Entry) -> Bool {
        guard let due = dueDate(entry) else { return false }
        return due <= now()
    }

    var dueCount: Int { entries.count(where: isDue) }

    /// When a flawless round would next raise this verse's level, while the
    /// anti-grind spacing is still holding it. Nil once a level-up is
    /// available (or the verse is mastered). The practice sheet and the list
    /// row say the wait out loud: in the 60 days to 2026-09-10, 24 of 61
    /// rounds at levels 2–3 were hint-free and didn't count, and nothing told
    /// the player why or for how long.
    func levelUpAvailableAt(_ entry: Entry) -> Date? {
        guard !entry.isMastered, let last = entry.lastLeveledUpAt else { return nil }
        let at = last.addingTimeInterval(Self.levelUpSpacing)
        return at > now() ? at : nil
    }

    // MARK: - Gating

    /// Free players hold up to `freeVerseLimit` verses; mastered ones don't
    /// count against it — finishing a verse should open a slot, not close one.
    func canStartNewVerse(isPremium: Bool) -> Bool {
        isPremium || entries.count(where: { !$0.isMastered }) < Self.freeVerseLimit
    }

    // MARK: - Mutation

    /// Put a verse into memorization at level 1. Idempotent — starting an
    /// already-held verse returns its existing entry.
    @discardableResult
    func start(reference: String, verseText: String) -> Entry {
        let key = MemoryCloze.referenceKey(reference)
        if let existing = entry(for: key) { return existing }
        let entry = Entry(
            referenceKey: key,
            reference: reference,
            verseText: verseText,
            level: 1,
            timesCompleted: 0,
            lastPracticedAt: nil,
            lastLeveledUpAt: nil,
            startedAt: now()
        )
        entries.append(entry)
        persist()
        return entry
    }

    /// Record a finished practice session. A hint-free completion raises the
    /// level, but never twice within `levelUpSpacing` — the anti-grind rule.
    /// Hinted completions record practice without penalty.
    func recordCompletion(referenceKey: String, hintFree: Bool) -> CompletionOutcome {
        guard let index = entries.firstIndex(where: { $0.referenceKey == referenceKey }) else {
            return CompletionOutcome(leveledUp: false, newLevel: 1)
        }
        let at = now()
        entries[index].timesCompleted += 1
        entries[index].lastPracticedAt = at

        let spacingSatisfied = entries[index].lastLeveledUpAt
            .map { at.timeIntervalSince($0) >= Self.levelUpSpacing } ?? true
        let leveledUp = hintFree && spacingSatisfied && entries[index].level < Self.masteredLevel
        if leveledUp {
            entries[index].level += 1
            entries[index].lastLeveledUpAt = at
        }
        persist()
        return CompletionOutcome(leveledUp: leveledUp, newLevel: entries[index].level)
    }

    func remove(referenceKey: String) {
        entries.removeAll { $0.referenceKey == referenceKey }
        persist()
    }

    // MARK: - Candidates

    /// A verse the player has met but not yet started memorizing.
    struct Candidate: Identifiable, Hashable {
        let reference: String
        let verseText: String
        var id: String { MemoryCloze.referenceKey(reference) }
    }

    /// Verses "seen": the verse of every completed puzzle — derived on demand
    /// from what's already stored, the `BibleJourney` pattern. Deduped by
    /// normalized reference (first puzzle in bundle order wins), minus verses
    /// already in memorization, minus verses the layout can't hold.
    func candidates(completedPuzzleIDs: Set<String>, puzzles: [Puzzle]) -> [Candidate] {
        let held = Set(entries.map(\.referenceKey))
        var seen = Set<String>()
        var out: [Candidate] = []
        for puzzle in puzzles where completedPuzzleIDs.contains(puzzle.id) {
            let key = MemoryCloze.referenceKey(puzzle.reference)
            guard !key.isEmpty, !held.contains(key), seen.insert(key).inserted,
                  MemoryCloze.isEligible(verseText: puzzle.verse) else { continue }
            out.append(Candidate(reference: puzzle.reference, verseText: puzzle.verse))
        }
        return out
    }

    // MARK: - Persistence

    private func persist() {
        do {
            defaults.set(try JSONEncoder().encode(entries), forKey: storageKey)
        } catch {
            // Non-fatal: mastery just won't survive relaunch.
            Log.persistence.error("Failed to persist memory verses: \(error, privacy: .public)")
        }
    }

    private static func load(from defaults: UserDefaults, key: String) -> [Entry] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([Entry].self, from: data)) ?? []
    }
}
