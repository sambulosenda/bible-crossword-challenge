//
//  ChallengeHistory.swift
//  Bible Crossword Challenge
//
//  A device-local ledger of the friend-challenge loop: head-to-heads we played
//  and "beat my time" links we sent. Stored in UserDefaults for the same reason
//  pending challenges are (see `ChallengeService`) — a result has no
//  cross-device meaning, and a new synced model would mean a CloudKit schema
//  re-deploy before any of this could ship.
//
//  This is a brag sheet, not an audit log: newest first, capped, and one row per
//  matchup. A rematch marks the row it came from rather than adding a second
//  entry for the same opponent on the same puzzle — two rows reading "you vs
//  Sam on daily-042" is bookkeeping, not history.
//

import Foundation
import Observation
import os

@Observable
final class ChallengeHistory {
    static let shared = ChallengeHistory()

    struct Entry: Codable, Equatable, Hashable, Identifiable {
        /// Which side of the loop this row records.
        enum Kind: String, Codable {
            /// We played a friend's challenge — both times are known.
            case played
            /// We sent a "beat my time" and haven't heard back. A reply, when it
            /// comes, arrives as its own incoming challenge and its own row.
            case sent
        }

        enum Outcome { case won, lost, tied }

        /// Stable across edits, so `ForEach` identity outlives a rematch write.
        let id: UUID
        let kind: Kind
        let puzzleID: String
        /// Denormalised: the id is content-stable, but a row should still read
        /// correctly without a bundle lookup on every render.
        let puzzleTitle: String
        let mySeconds: Int
        /// Both nil for `.sent` — an outgoing link names no recipient.
        let opponentName: String?
        let opponentSeconds: Int?
        /// Last activity on this matchup — what the list is ordered by.
        var date: Date
        /// When a rematch link went out for this row, if it did.
        var rematchSentAt: Date?

        var outcome: Outcome? {
            guard let opponentSeconds else { return nil }
            if mySeconds == opponentSeconds { return .tied }
            return mySeconds < opponentSeconds ? .won : .lost
        }

        /// How much faster we were, in seconds. Negative when we lost.
        var margin: Int? {
            opponentSeconds.map { $0 - mySeconds }
        }
    }

    /// Enough to fill a history screen without letting UserDefaults grow
    /// unbounded.
    static let limit = 50

    private let defaults: UserDefaults
    private let now: () -> Date
    private let storageKey = "challengeHistory.v1"

    /// Newest first. Observable so Profile and Completion track writes.
    private(set) var entries: [Entry] = []

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.now = now
        self.entries = Self.load(from: defaults, key: storageKey)
    }

    // MARK: - Recording

    /// Record a head-to-head after playing a friend's challenge.
    ///
    /// Idempotent for an identical matchup: `CompletionView` guards against
    /// re-entry, but a screen that reappears shouldn't be able to double-count a
    /// single win.
    func recordPlayed(
        puzzleID: String,
        puzzleTitle: String,
        opponentName: String,
        opponentSeconds: Int,
        mySeconds: Int
    ) {
        let duplicate = entries.firstIndex {
            $0.kind == .played
                && $0.puzzleID == puzzleID
                && $0.opponentName == opponentName
                && $0.opponentSeconds == opponentSeconds
                && $0.mySeconds == mySeconds
        }
        if let duplicate {
            promote(duplicate)
            return
        }

        insert(Entry(
            id: UUID(),
            kind: .played,
            puzzleID: puzzleID,
            puzzleTitle: puzzleTitle,
            mySeconds: mySeconds,
            opponentName: opponentName,
            opponentSeconds: opponentSeconds,
            date: now(),
            rematchSentAt: nil
        ))
    }

    /// Record an outgoing "beat my time" for a puzzle we solved.
    ///
    /// Re-sharing the same solve refreshes the existing row rather than stacking
    /// — a player who cancels the share sheet and tries again sent one
    /// challenge, not two.
    func recordSent(puzzleID: String, puzzleTitle: String, mySeconds: Int) {
        let existing = entries.firstIndex {
            $0.kind == .sent && $0.puzzleID == puzzleID && $0.mySeconds == mySeconds
        }
        if let existing {
            entries[existing].date = now()
            promote(existing)
            return
        }

        insert(Entry(
            id: UUID(),
            kind: .sent,
            puzzleID: puzzleID,
            puzzleTitle: puzzleTitle,
            mySeconds: mySeconds,
            opponentName: nil,
            opponentSeconds: nil,
            date: now(),
            rematchSentAt: nil
        ))
    }

    /// Mark that a rematch went out for a puzzle, against the newest row that
    /// has one. Falls back to a plain outgoing row when there's nothing to link
    /// to — a rematch always implies a prior result, but the store shouldn't
    /// silently drop the send if that assumption ever breaks.
    func markRematchSent(puzzleID: String, puzzleTitle: String, mySeconds: Int) {
        guard let index = entries.firstIndex(where: { $0.puzzleID == puzzleID }) else {
            recordSent(puzzleID: puzzleID, puzzleTitle: puzzleTitle, mySeconds: mySeconds)
            return
        }
        entries[index].rematchSentAt = now()
        persist()
    }

    // MARK: - Reading

    /// The most recent named opponent on this puzzle — who Completion offers a
    /// rematch against. `.sent` rows name nobody, so they never match.
    func lastOpponent(for puzzleID: String) -> Entry? {
        entries.first { $0.puzzleID == puzzleID && $0.opponentName != nil }
    }

    // MARK: - Mutation helpers

    private func insert(_ entry: Entry) {
        entries.insert(entry, at: 0)
        if entries.count > Self.limit {
            entries.removeLast(entries.count - Self.limit)
        }
        persist()
    }

    /// Move an existing row to the front, keeping its identity.
    private func promote(_ index: Int) {
        guard index > 0 else {
            persist()
            return
        }
        let entry = entries.remove(at: index)
        entries.insert(entry, at: 0)
        persist()
    }

    // MARK: - Persistence

    private func persist() {
        do {
            defaults.set(try JSONEncoder().encode(entries), forKey: storageKey)
        } catch {
            // Non-fatal: the history just won't survive relaunch.
            Log.persistence.error("Failed to persist challenge history: \(error, privacy: .public)")
        }
    }

    private static func load(from defaults: UserDefaults, key: String) -> [Entry] {
        guard let data = defaults.data(forKey: key) else { return [] }
        let stored = (try? JSONDecoder().decode([Entry].self, from: data)) ?? []
        // Defensive: every write path already inserts newest-first, but the list
        // is ordered by date and nothing downstream re-sorts it.
        return stored.sorted { $0.date > $1.date }
    }
}
