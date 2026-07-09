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
}
