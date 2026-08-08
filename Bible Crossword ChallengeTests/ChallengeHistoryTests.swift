//
//  ChallengeHistoryTests.swift
//  Bible Crossword ChallengeTests
//
//  The challenge ledger's rules: what counts as one matchup, what a rematch
//  does to the row it answers, and that the list stays capped and ordered.
//

import Testing
import Foundation
@testable import Bible_Crossword_Challenge

@MainActor
struct ChallengeHistoryTests {
    /// A store over a throwaway suite, with a clock that advances a second per
    /// read so ordering assertions aren't at the mercy of timer resolution.
    private func makeHistory() -> ChallengeHistory {
        let suite = UserDefaults(suiteName: "challenge-history-tests-\(UUID().uuidString)")!
        var tick = 0
        return ChallengeHistory(defaults: suite, now: {
            tick += 1
            return Date(timeIntervalSinceReferenceDate: TimeInterval(tick))
        })
    }

    @Test func recordsAHeadToHeadWithItsOutcome() throws {
        let history = makeHistory()
        history.recordPlayed(
            puzzleID: "daily-042", puzzleTitle: "Daily 42",
            opponentName: "Sam", opponentSeconds: 154, mySeconds: 131
        )

        let entry = try #require(history.entries.first)
        #expect(history.entries.count == 1)
        #expect(entry.kind == .played)
        #expect(entry.outcome == .won)
        #expect(entry.margin == 23)
    }

    @Test func losingAndTyingAreDistinctOutcomes() {
        let history = makeHistory()
        history.recordPlayed(
            puzzleID: "daily-001", puzzleTitle: "One",
            opponentName: "Sam", opponentSeconds: 100, mySeconds: 140
        )
        history.recordPlayed(
            puzzleID: "daily-002", puzzleTitle: "Two",
            opponentName: "Sam", opponentSeconds: 100, mySeconds: 100
        )

        #expect(history.entries.first?.outcome == .tied)
        #expect(history.entries.last?.outcome == .lost)
        #expect(history.entries.last?.margin == -40)
    }

    @Test func anOutgoingChallengeHasNoOpponent() throws {
        let history = makeHistory()
        history.recordSent(puzzleID: "daily-042", puzzleTitle: "Daily 42", mySeconds: 131)

        let entry = try #require(history.entries.first)
        #expect(entry.kind == .sent)
        #expect(entry.opponentName == nil)
        #expect(entry.outcome == nil)
    }

    @Test func replayingTheSameMatchupDoesNotDuplicateIt() {
        let history = makeHistory()
        for _ in 0..<3 {
            history.recordPlayed(
                puzzleID: "daily-042", puzzleTitle: "Daily 42",
                opponentName: "Sam", opponentSeconds: 154, mySeconds: 131
            )
        }
        #expect(history.entries.count == 1)
    }

    @Test func resharingTheSameSolveRefreshesOneRow() {
        let history = makeHistory()
        history.recordSent(puzzleID: "daily-042", puzzleTitle: "Daily 42", mySeconds: 131)
        let first = history.entries[0]
        history.recordSent(puzzleID: "daily-042", puzzleTitle: "Daily 42", mySeconds: 131)

        #expect(history.entries.count == 1)
        // Same row, later timestamp — one challenge sent twice, not two sent.
        #expect(history.entries[0].id == first.id)
        #expect(history.entries[0].date > first.date)
    }

    @Test func aRematchMarksTheRowItAnswers() {
        let history = makeHistory()
        history.recordPlayed(
            puzzleID: "daily-042", puzzleTitle: "Daily 42",
            opponentName: "Sam", opponentSeconds: 154, mySeconds: 131
        )
        history.markRematchSent(puzzleID: "daily-042", puzzleTitle: "Daily 42", mySeconds: 131)

        #expect(history.entries.count == 1)
        #expect(history.entries[0].rematchSentAt != nil)
        #expect(history.entries[0].opponentName == "Sam")
    }

    @Test func aRematchWithNothingToAnswerBecomesAnOutgoingRow() {
        let history = makeHistory()
        history.markRematchSent(puzzleID: "daily-042", puzzleTitle: "Daily 42", mySeconds: 131)

        #expect(history.entries.count == 1)
        #expect(history.entries[0].kind == .sent)
    }

    @Test func lastOpponentIgnoresRowsThatNameNobody() {
        let history = makeHistory()
        history.recordPlayed(
            puzzleID: "daily-042", puzzleTitle: "Daily 42",
            opponentName: "Sam", opponentSeconds: 154, mySeconds: 131
        )
        history.recordSent(puzzleID: "daily-042", puzzleTitle: "Daily 42", mySeconds: 120)

        // The outgoing row is newer, but only a played row names an opponent.
        #expect(history.entries[0].kind == .sent)
        #expect(history.lastOpponent(for: "daily-042")?.opponentName == "Sam")
        #expect(history.lastOpponent(for: "daily-999") == nil)
    }

    @Test func theListIsCappedNewestFirst() {
        let history = makeHistory()
        for index in 0..<(ChallengeHistory.limit + 10) {
            history.recordSent(
                puzzleID: "daily-\(index)", puzzleTitle: "Daily \(index)", mySeconds: 100 + index
            )
        }

        #expect(history.entries.count == ChallengeHistory.limit)
        // The newest write is at the front; the oldest ten fell off the end.
        #expect(history.entries.first?.puzzleID == "daily-\(ChallengeHistory.limit + 9)")
        #expect(history.entries.contains { $0.puzzleID == "daily-0" } == false)
    }

    @Test func historySurvivesAReload() {
        let suite = UserDefaults(suiteName: "challenge-history-tests-\(UUID().uuidString)")!
        let history = ChallengeHistory(defaults: suite)
        history.recordPlayed(
            puzzleID: "daily-042", puzzleTitle: "Daily 42",
            opponentName: "Sam", opponentSeconds: 154, mySeconds: 131
        )

        let reloaded = ChallengeHistory(defaults: suite)
        #expect(reloaded.entries.count == 1)
        #expect(reloaded.entries.first?.opponentName == "Sam")
        #expect(reloaded.entries.first?.outcome == .won)
    }
}
