//
//  FamilyBoardTests.swift
//  Bible Crossword ChallengeTests
//
//  The board is passed around as a link, so the rules that matter are the ones
//  that decide what happens when copies meet: the merge has to converge however
//  the link travelled, and a board link must never be mistaken for a one-to-one
//  challenge (they share a path).
//

import Testing
import Foundation
@testable import Bible_Crossword_Challenge

struct FamilyBoardTests {
    private func makeService(knownPuzzles: Set<String> = ["daily-042"]) -> FamilyBoardService {
        let suite = UserDefaults(suiteName: "family-board-tests-\(UUID().uuidString)")!
        return FamilyBoardService(
            defaults: suite,
            now: { Date(timeIntervalSinceReferenceDate: 0) },
            puzzleExists: { knownPuzzles.contains($0) }
        )
    }

    private func board(_ standings: [(String, Int)]) -> FamilyBoardService.Board {
        FamilyBoardService.Board(
            puzzleID: "daily-042",
            puzzleTitle: "Daily 42",
            standings: standings.map { FamilyBoardService.Standing(name: $0.0, seconds: $0.1) },
            updatedAt: Date(timeIntervalSinceReferenceDate: 0)
        )
    }

    // MARK: - Merging

    @Test func mergeRanksFastestFirst() {
        let merged = board([("Ann", 201)]).merged(with: [
            FamilyBoardService.Standing(name: "Sam", seconds: 154),
            FamilyBoardService.Standing(name: "Joe", seconds: 233),
        ])
        #expect(merged.map(\.name) == ["Sam", "Ann", "Joe"])
    }

    @Test func mergeKeepsTheLowestTimePerName() {
        let merged = board([("Sam", 154)]).merged(with: [
            FamilyBoardService.Standing(name: "Sam", seconds: 300)
        ])
        #expect(merged == [FamilyBoardService.Standing(name: "Sam", seconds: 154)])
    }

    /// Fold standings in one batch at a time, as forwarding a link does.
    private func fold(_ batches: [[(String, Int)]]) -> [FamilyBoardService.Standing] {
        var current = board([])
        for batch in batches {
            current.standings = current.merged(
                with: batch.map { FamilyBoardService.Standing(name: $0.0, seconds: $0.1) }
            )
        }
        return current.standings
    }

    /// The link criss-crosses a group in whatever order people forward it, so
    /// the merge has to land on the same board regardless of the path taken.
    @Test func mergeConvergesWhateverOrderCopiesMeet() {
        let ann = ("Ann", 201), sam = ("Sam", 154), joe = ("Joe", 233)

        let leftFirst = fold([[ann, sam], [joe]])
        let rightFirst = fold([[sam, joe], [ann]])
        let allAtOnce = fold([[joe, ann, sam]])

        #expect(leftFirst == rightFirst)
        #expect(leftFirst == allAtOnce)
        #expect(leftFirst.map(\.name) == ["Sam", "Ann", "Joe"])
    }

    @Test func mergeCapsTheBoardKeepingTheFastest() {
        let many = (1...(FamilyBoardService.maxStandings + 5)).map {
            FamilyBoardService.Standing(name: "P\($0)", seconds: 100 + $0)
        }
        let merged = board([]).merged(with: many)
        #expect(merged.count == FamilyBoardService.maxStandings)
        #expect(merged.first?.seconds == 101)
        #expect(merged.contains { $0.name == "P\(FamilyBoardService.maxStandings + 5)" } == false)
    }

    @Test func equalTimesRankAlphabeticallySoOrderIsStable() {
        let merged = board([]).merged(with: [
            FamilyBoardService.Standing(name: "Zoe", seconds: 154),
            FamilyBoardService.Standing(name: "Ann", seconds: 154),
        ])
        #expect(merged.map(\.name) == ["Ann", "Zoe"])
    }

    // MARK: - Recording own solve

    @Test func recordingAddsThisDeviceToTheBoard() {
        let service = makeService()
        let result = service.record(puzzleID: "daily-042", puzzleTitle: "Daily 42", name: "Sam", seconds: 154)
        #expect(result.standings == [FamilyBoardService.Standing(name: "Sam", seconds: 154)])
        #expect(service.board(for: "daily-042")?.standings.count == 1)
    }

    /// A replay knows every answer, so a second run must not improve a standing
    /// the first run earned.
    @Test func recordingDoesNotOverwriteAnExistingOwnTime() {
        let service = makeService()
        service.record(puzzleID: "daily-042", puzzleTitle: "Daily 42", name: "Sam", seconds: 154)
        let result = service.record(puzzleID: "daily-042", puzzleTitle: "Daily 42", name: "Sam", seconds: 10)
        #expect(result.standing(for: "Sam")?.seconds == 154)
    }

    @Test func acceptingFoldsAnIncomingBoardIntoTheLocalOne() {
        let service = makeService()
        service.record(puzzleID: "daily-042", puzzleTitle: "Daily 42", name: "Sam", seconds: 154)
        let result = service.accept(board([("Ann", 201)]))
        #expect(result.standings.map(\.name) == ["Sam", "Ann"])
    }

    // MARK: - Renaming

    /// You can join a board before picking a display name; the name is only
    /// asked for when the board is about to leave the device.
    @Test func renamingRelabelsTheRowRatherThanAddingOne() throws {
        let service = makeService()
        service.record(puzzleID: "daily-042", puzzleTitle: "Daily 42", name: "Friend", seconds: 201)
        service.accept(board([("Sam", 154)]))

        let renamed = try #require(service.rename(puzzleID: "daily-042", from: "Friend", to: "Ann"))
        #expect(renamed.standings.map(\.name) == ["Sam", "Ann"])
        #expect(renamed.standing(for: "Friend") == nil)
        #expect(renamed.standing(for: "Ann")?.seconds == 201)
    }

    /// The rename must drop the old row, not merge into it — a merge would keep
    /// the faster of the two and could resurrect a placeholder.
    @Test func renamingKeepsTheRenamedTimeNotTheFasterOne() throws {
        let service = makeService()
        service.record(puzzleID: "daily-042", puzzleTitle: "Daily 42", name: "Friend", seconds: 300)
        service.accept(board([("Ann", 100)]))

        let renamed = try #require(service.rename(puzzleID: "daily-042", from: "Friend", to: "Ann"))
        // One Ann, and she keeps the 100 already on the board — the placeholder
        // row is gone rather than having overwritten it.
        #expect(renamed.standings.count == 1)
        #expect(renamed.standing(for: "Ann")?.seconds == 100)
    }

    @Test func renamingAnAbsentRowChangesNothing() {
        let service = makeService()
        service.record(puzzleID: "daily-042", puzzleTitle: "Daily 42", name: "Sam", seconds: 154)
        let result = service.rename(puzzleID: "daily-042", from: "Nobody", to: "Ann")
        #expect(result?.standings.map(\.name) == ["Sam"])
    }

    // MARK: - URL round trip

    @Test func aBoardSurvivesTheRoundTripThroughItsLink() throws {
        let service = makeService()
        let original = board([("Sam", 154), ("Ann", 201)])
        let url = try #require(service.boardURL(original))

        #expect(url.absoluteString.contains("v=2"))
        guard case .valid(let parsed) = service.parse(url, title: { _ in "Daily 42" }) else {
            Issue.record("expected a valid board, got \(service.parse(url, title: { _ in nil }))")
            return
        }
        #expect(parsed.puzzleID == "daily-042")
        #expect(parsed.standings == original.standings)
    }

    /// Seconds lead so the name may contain anything after the first colon.
    @Test func namesMayContainColons() throws {
        let service = makeService()
        let url = try #require(service.boardURL(board([("Sam: the elder", 154)])))
        guard case .valid(let parsed) = service.parse(url, title: { _ in "Daily 42" }) else {
            Issue.record("expected a valid board")
            return
        }
        #expect(parsed.standings.first?.name == "Sam: the elder")
    }

    /// The board *is* the link, so a full one has to stay inside what messaging
    /// apps will carry intact. SMS is the tightest common limit at 160 chars per
    /// segment, but links are concatenated rather than truncated; the number
    /// that actually bites is the ~2000-char ceiling some clients impose on a
    /// URL before they stop linkifying it.
    @Test func aFullBoardStillFitsInASendableLink() throws {
        let service = makeService()
        let full = FamilyBoardService.Board(
            puzzleID: "daily-042",
            puzzleTitle: "Daily 42",
            // Worst realistic case: every row at the name cap, with spaces
            // (which percent-encode to three characters each).
            standings: (1...FamilyBoardService.maxStandings).map {
                FamilyBoardService.Standing(name: "Bartholomew Jones \($0)", seconds: 3599)
            },
            updatedAt: Date(timeIntervalSinceReferenceDate: 0)
        )
        let url = try #require(service.boardURL(full))
        #expect(url.absoluteString.count < 2000)

        // And it still round-trips at that size.
        guard case .valid(let parsed) = service.parse(url, title: { _ in "Daily 42" }) else {
            Issue.record("expected a valid board")
            return
        }
        #expect(parsed.standings.count == FamilyBoardService.maxStandings)
    }

    // MARK: - Telling the two payloads apart

    @Test func aOneToOneChallengeLinkIsNotABoard() {
        let service = makeService()
        let url = URL(string: "biblecrossword://challenge?v=1&p=daily-042&t=154&n=Sam")!
        #expect(service.parse(url, title: { _ in nil }) == .notABoard)
    }

    @Test func aBoardLinkIsNotAOneToOneChallenge() {
        let challenge = ChallengeService(
            defaults: UserDefaults(suiteName: "family-board-tests-\(UUID().uuidString)")!,
            puzzleExists: { _ in true }
        )
        let url = URL(string: "biblecrossword://challenge?v=2&p=daily-042&e=154:Sam")!
        // v=2 is beyond what the one-to-one parser understands, so an older
        // build shows "update the app" rather than silently doing nothing.
        #expect(challenge.parse(url) == .needsUpdate)
    }

    @Test func anUnrelatedURLIsNotABoard() {
        let service = makeService()
        let url = URL(string: "https://example.com/challenge/?v=2&p=daily-042&e=154:Sam")!
        #expect(service.parse(url, title: { _ in nil }) == .notABoard)
    }

    @Test func aBoardForAnUnknownPuzzleAsksForAnUpdate() {
        let service = makeService(knownPuzzles: [])
        let url = URL(string: "biblecrossword://challenge?v=2&p=daily-999&e=154:Sam")!
        #expect(service.parse(url, title: { _ in nil }) == .needsUpdate)
    }

    @Test func junkStandingsAreDropped() {
        let service = makeService()
        let url = URL(string: "biblecrossword://challenge?v=2&p=daily-042&e=abc:Sam&e=154:Ann&e=0:Zero")!
        guard case .valid(let parsed) = service.parse(url, title: { _ in "Daily 42" }) else {
            Issue.record("expected a valid board")
            return
        }
        // Non-numeric seconds and a zero time both fall out; Ann survives.
        #expect(parsed.standings == [FamilyBoardService.Standing(name: "Ann", seconds: 154)])
    }

    // MARK: - Share text

    @Test func shareTextRanksWithMedals() {
        let text = board([("Sam", 154), ("Ann", 201)]).shareText
        #expect(text.contains("🥇 Sam — 2:34"))
        #expect(text.contains("🥈 Ann — 3:21"))
        #expect(text.contains("Daily 42"))
    }
}
