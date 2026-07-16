//
//  PacksTests.swift
//  Bible Crossword ChallengeTests
//
//  Themed-pack resolution, seasonal gating, reverse lookup, and progress —
//  plus integrity of the bundled packs.json against the bundled puzzles.
//

import Testing
import Foundation
import SwiftUI
import SwiftData
@testable import Bible_Crossword_Challenge

private let utc: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(secondsFromGMT: 0)!
    return c
}()

private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
    utc.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
}

struct PacksTests {

    // MARK: - Integrity

    @Test func packsLoadFromBundle() {
        #expect(PuzzleProvider.shared.packs.isEmpty == false)
    }

    @Test func everyPackReferencesRealPuzzles() {
        let provider = PuzzleProvider.shared
        for pack in provider.packs {
            #expect(pack.puzzleIDs.isEmpty == false, "Pack \(pack.id) is empty")
            for id in pack.puzzleIDs {
                #expect(provider.puzzle(id: id) != nil,
                        "Pack \(pack.id) references missing puzzle \(id)")
            }
        }
    }

    @Test func exactlyOneFreeStarterPack() {
        let free = PuzzleProvider.shared.packs.filter { !$0.isPremium }
        #expect(free.count == 1)
    }

    // MARK: - Resolution

    @Test func puzzlesInPackPreserveAuthoredOrder() {
        let provider = PuzzleProvider.shared
        guard let pack = provider.packs.first else { return }
        let resolved = provider.puzzles(in: pack)
        #expect(resolved.map(\.id) == pack.puzzleIDs)
    }

    @Test func reverseLookupFindsOwningPack() {
        let provider = PuzzleProvider.shared
        guard let pack = provider.packs.first, let first = pack.puzzleIDs.first else { return }
        #expect(provider.pack(forPuzzle: first)?.id == pack.id)
    }

    @Test func puzzleInNoPackHasNoOwner() {
        let provider = PuzzleProvider.shared
        let owned = Set(provider.packs.flatMap(\.puzzleIDs))
        let orphan = provider.puzzles.first { !owned.contains($0.id) }
        if let orphan {
            #expect(provider.pack(forPuzzle: orphan.id) == nil)
        }
    }

    // MARK: - Seasonal gating

    @Test func nonSeasonalPacksAlwaysAvailable() {
        let evergreen = PuzzlePack.fixtureEvergreen
        #expect(evergreen.isAvailable(on: day(2026, 3, 1), calendar: utc))
        #expect(evergreen.isAvailable(on: day(2026, 12, 25), calendar: utc))
    }

    @Test func seasonalPackRespectsWindow() {
        let advent = PuzzlePack(
            id: "advent", title: "Advent", blurb: "", coverSymbol: "sparkles",
            accentHex: nil, isPremium: true, puzzleIDs: ["daily-019"],
            availableFrom: "2026-12-01", availableTo: "2026-12-26"
        )
        #expect(advent.isAvailable(on: day(2026, 11, 30), calendar: utc) == false)
        #expect(advent.isAvailable(on: day(2026, 12, 1), calendar: utc))   // inclusive start
        #expect(advent.isAvailable(on: day(2026, 12, 26), calendar: utc))  // inclusive end
        #expect(advent.isAvailable(on: day(2026, 12, 27), calendar: utc) == false)
    }

    @Test func availablePacksFiltersByDate() {
        let provider = PuzzleProvider.shared
        let inSeason = provider.availablePacks(on: day(2026, 12, 10))
        let offSeason = provider.availablePacks(on: day(2026, 6, 1))
        // Evergreen packs appear in both; any seasonal pack only in its window.
        #expect(inSeason.count >= offSeason.count)
    }

    // MARK: - Progress

    @Test func progressCountsOnlyCompleted() {
        let pack = PuzzlePack(
            id: "p", title: "P", blurb: "", coverSymbol: "star", accentHex: nil,
            isPremium: false, puzzleIDs: ["a", "b", "c"],
            availableFrom: nil, availableTo: nil
        )
        let byID: [String: PuzzleRecord] = [
            "a": record(id: "a", completed: true),
            "b": record(id: "b", completed: false),
            "c": record(id: "c", completed: true),
        ]
        let progress = PackProgress(pack: pack, recordsByID: byID)
        #expect(progress.total == 3)
        #expect(progress.solved == 2)
        #expect(progress.isComplete == false)
    }

    @Test func fullyCompletedPackIsComplete() {
        let pack = PuzzlePack(
            id: "p", title: "P", blurb: "", coverSymbol: "star", accentHex: nil,
            isPremium: false, puzzleIDs: ["a", "b"],
            availableFrom: nil, availableTo: nil
        )
        let byID = ["a": record(id: "a", completed: true),
                    "b": record(id: "b", completed: true)]
        #expect(PackProgress(pack: pack, recordsByID: byID).isComplete)
    }

    // MARK: - Pack-exclusive puzzles (Phase 2)

    /// The daily and mini pools must never contain a pack-exclusive puzzle —
    /// their membership drives the rotation index, which is content-stable.
    @Test func poolsExcludePackExclusives() {
        let provider = PuzzleProvider.shared
        #expect(provider.puzzles.allSatisfy { $0.id.hasPrefix("daily-") })
        #expect(provider.minis.allSatisfy { $0.id.hasPrefix("mini-") })
    }

    @Test func packExclusivesStillResolveByID() {
        let provider = PuzzleProvider.shared
        let exclusiveIDs = provider.packs.flatMap(\.puzzleIDs).filter { $0.hasPrefix("pack-") }
        #expect(exclusiveIDs.isEmpty == false, "expected at least one pack-exclusive puzzle in the bundle")
        for id in exclusiveIDs {
            #expect(provider.puzzle(id: id) != nil, "\(id) must resolve even though it's outside the pools")
        }
    }

    @Test func packsContainingFindsOwners() {
        let provider = PuzzleProvider.shared
        guard let pack = provider.packs.first, let first = pack.puzzleIDs.first else { return }
        #expect(provider.packs(containing: first).contains(pack))
        #expect(provider.packs(containing: "no-such-puzzle").isEmpty)
    }

    // MARK: - Completion recording

    @Test func recordCreditsFullySolvedPack() {
        let profile = PlayerProfile()
        let pack = PuzzlePack.fixture(id: "p", puzzleIDs: ["a", "b"])
        let newly = PackCompletion.record(packs: [pack], profile: profile) { _ in true }
        #expect(newly.map(\.id) == ["p"])
        #expect(profile.completedPackIDs == ["p"])
    }

    @Test func recordSkipsPartialAndAlreadyRecorded() {
        let profile = PlayerProfile(completedPackIDs: ["done"])
        let done = PuzzlePack.fixture(id: "done", puzzleIDs: ["a"])
        let partial = PuzzlePack.fixture(id: "partial", puzzleIDs: ["a", "unsolved"])
        let newly = PackCompletion.record(packs: [done, partial], profile: profile) { $0 == "a" }
        #expect(newly.isEmpty)
        #expect(profile.completedPackIDs == ["done"])
    }

    @Test func recordIgnoresEmptyPack() {
        let profile = PlayerProfile()
        let empty = PuzzlePack.fixture(id: "empty", puzzleIDs: [])
        #expect(PackCompletion.record(packs: [empty], profile: profile) { _ in true }.isEmpty)
        #expect(profile.completedPackIDs.isEmpty)
    }

    // MARK: - Pack achievements

    @Test func packsCompletedAchievementProgress() {
        let profile = PlayerProfile(completedPackIDs: ["first-steps"])
        let pathfinder = Achievement(
            id: "t1", title: "", detail: "", symbol: "", goal: .packsCompleted(1)
        )
        let collector = Achievement(
            id: "t3", title: "", detail: "", symbol: "", goal: .packsCompleted(3)
        )
        #expect(pathfinder.isUnlocked(by: profile))
        #expect(collector.isUnlocked(by: profile) == false)
        #expect(collector.progressText(for: profile) == "1 / 3")
    }

    // MARK: - Sync merge

    @Test func profileMergeUnionsCompletedPacks() throws {
        let container = try ModelContainer(
            for: PlayerProfile.self, PuzzleRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let old = PlayerProfile(completedPackIDs: ["first-steps"], createdAt: day(2026, 6, 1))
        let new = PlayerProfile(completedPackIDs: ["first-steps", "psalm-23"], createdAt: day(2026, 6, 20))
        context.insert(old)
        context.insert(new)
        let survivor = SyncMerge.mergeProfiles([new, old], context: context)
        #expect(survivor === old)
        #expect(Set(old.completedPackIDs) == ["first-steps", "psalm-23"])
    }

    // MARK: - Colour parsing

    @Test func hexColourParsing() {
        #expect(Color(hex: "#8A6D3B") != nil)
        #expect(Color(hex: "8A6D3B") != nil)
        #expect(Color(hex: "nope") == nil)
        #expect(Color(hex: "#FFF") == nil)   // wrong length
    }

    // MARK: - Helpers

    private func record(id: String, completed: Bool) -> PuzzleRecord {
        PuzzleRecord(puzzleID: id, isCompleted: completed)
    }
}

private extension PuzzlePack {
    static let fixtureEvergreen = PuzzlePack(
        id: "e", title: "E", blurb: "", coverSymbol: "star", accentHex: nil,
        isPremium: false, puzzleIDs: ["x"], availableFrom: nil, availableTo: nil
    )

    static func fixture(id: String, puzzleIDs: [String]) -> PuzzlePack {
        PuzzlePack(
            id: id, title: id, blurb: "", coverSymbol: "star", accentHex: nil,
            isPremium: false, puzzleIDs: puzzleIDs, availableFrom: nil, availableTo: nil
        )
    }
}
