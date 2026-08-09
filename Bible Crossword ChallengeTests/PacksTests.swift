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

    @Test func annualSeasonRespectsWindow() {
        let advent = PuzzlePack.fixture(
            id: "advent", puzzleIDs: ["daily-019"],
            season: .annual(from: "12-01", to: "12-26")
        )
        #expect(advent.isAvailable(on: day(2026, 11, 30), calendar: utc) == false)
        #expect(advent.isAvailable(on: day(2026, 12, 1), calendar: utc))   // inclusive start
        #expect(advent.isAvailable(on: day(2026, 12, 26), calendar: utc))  // inclusive end
        #expect(advent.isAvailable(on: day(2026, 12, 27), calendar: utc) == false)
    }

    /// The reason `.annual` exists: the same window has to come back next year
    /// without anyone editing packs.json.
    @Test func annualSeasonReturnsEveryYear() {
        let advent = PuzzlePack.fixture(
            id: "advent", puzzleIDs: ["daily-019"],
            season: .annual(from: "12-01", to: "12-26")
        )
        for year in [2026, 2027, 2030, 2041] {
            #expect(advent.isAvailable(on: day(year, 12, 10), calendar: utc),
                    "Advent should run in \(year)")
            #expect(advent.isAvailable(on: day(year, 7, 10), calendar: utc) == false)
        }
    }

    @Test func annualSeasonCanWrapTheNewYear() {
        // Christmastide: 26 December → 6 January.
        let season = PackSeason.annual(from: "12-26", to: "01-06")
        #expect(season.contains(day(2026, 12, 26), calendar: utc))
        #expect(season.contains(day(2026, 12, 31), calendar: utc))
        #expect(season.contains(day(2027, 1, 1), calendar: utc))
        #expect(season.contains(day(2027, 1, 6), calendar: utc))
        #expect(season.contains(day(2027, 1, 7), calendar: utc) == false)
        #expect(season.contains(day(2026, 12, 25), calendar: utc) == false)
    }

    /// An expired one-off window stays expired — the confirmed policy is that a
    /// finished seasonal pack is hidden, not teased.
    @Test func oneOffSeasonExpiresForGood() {
        let launch = PackSeason.dates(from: "2026-07-01", to: "2026-07-07")
        #expect(launch.contains(day(2026, 7, 3), calendar: utc))
        #expect(launch.contains(day(2027, 7, 3), calendar: utc) == false)
        #expect(launch.nextStart(onOrAfter: day(2026, 8, 1), calendar: utc) == nil)
    }

    @Test func availablePacksFiltersByDate() {
        let provider = PuzzleProvider.shared
        let inSeason = provider.availablePacks(on: day(2026, 12, 10))
        let offSeason = provider.availablePacks(on: day(2026, 6, 1))
        // Evergreen packs appear in both; any seasonal pack only in its window.
        #expect(inSeason.count >= offSeason.count)
    }

    // MARK: - Easter

    /// Known Western Easter Sundays. The algorithm is the only reason a Lent or
    /// Easter pack can be authored once and open on the right day every year,
    /// so it's pinned against dates that can be checked against a calendar.
    @Test(arguments: [
        (2024, 3, 31), (2025, 4, 20), (2026, 4, 5), (2027, 3, 28),
        (2028, 4, 16), (2029, 4, 1), (2030, 4, 21), (2038, 4, 25),
    ])
    func easterSundayMatchesKnownDates(year: Int, month: Int, dayOfMonth: Int) {
        let easter = PackSeason.easterSunday(year: year, calendar: utc)
        #expect(easter == utc.startOfDay(for: day(year, month, dayOfMonth)))
    }

    @Test func lentTracksEasterAcrossYears() {
        // Ash Wednesday → Easter Eve is Easter minus 46 to minus 1.
        let lent = PuzzlePack.fixture(
            id: "lent", puzzleIDs: ["a"], season: .easter(from: -46, to: -1)
        )
        // 2026: Easter 5 April → Lent runs 18 Feb … 4 April.
        #expect(lent.isAvailable(on: day(2026, 2, 18), calendar: utc))
        #expect(lent.isAvailable(on: day(2026, 4, 4), calendar: utc))
        #expect(lent.isAvailable(on: day(2026, 4, 5), calendar: utc) == false)  // Easter itself
        #expect(lent.isAvailable(on: day(2026, 2, 17), calendar: utc) == false)
        // 2027: Easter 28 March → the whole window shifts a week earlier.
        #expect(lent.isAvailable(on: day(2027, 2, 10), calendar: utc))
        #expect(lent.isAvailable(on: day(2027, 3, 27), calendar: utc))
        #expect(lent.isAvailable(on: day(2027, 3, 28), calendar: utc) == false)
        // The 2026 window's dates are emphatically not the 2027 window's.
        #expect(lent.isAvailable(on: day(2027, 4, 4), calendar: utc) == false)
    }

    @Test func easterWeekWindowSpansTheFeast() {
        let easterWeek = PackSeason.easter(from: -7, to: 7)
        #expect(easterWeek.contains(day(2026, 3, 29), calendar: utc))   // Palm Sunday
        #expect(easterWeek.contains(day(2026, 4, 5), calendar: utc))    // Easter Sunday
        #expect(easterWeek.contains(day(2026, 4, 12), calendar: utc))   // +7
        #expect(easterWeek.contains(day(2026, 4, 13), calendar: utc) == false)
    }

    // MARK: - Countdown

    @Test func daysRemainingCountsInclusiveOfToday() {
        let advent = PuzzlePack.fixture(
            id: "advent", puzzleIDs: ["a"], season: .annual(from: "12-01", to: "12-26")
        )
        #expect(advent.daysRemaining(on: day(2026, 12, 26), calendar: utc) == 0)  // last day
        #expect(advent.daysRemaining(on: day(2026, 12, 25), calendar: utc) == 1)
        #expect(advent.daysRemaining(on: day(2026, 12, 1), calendar: utc) == 25)
        #expect(advent.daysRemaining(on: day(2026, 11, 30), calendar: utc) == nil)
    }

    @Test func evergreenPackHasNoCountdown() {
        #expect(PuzzlePack.fixtureEvergreen.daysRemaining(on: day(2026, 12, 25), calendar: utc) == nil)
        #expect(PuzzlePack.fixtureEvergreen.seasonEnd(on: day(2026, 12, 25), calendar: utc) == nil)
    }

    @Test func badgeOnlyShowsInTheClosingStretch() {
        #expect(SeasonBadge.text(daysRemaining: 0) == "Last day")
        #expect(SeasonBadge.text(daysRemaining: 1) == "1 day left")
        #expect(SeasonBadge.text(daysRemaining: 9) == "9 days left")
    }

    // MARK: - Openings

    @Test func openingsFindSeasonsStartingInsideTheHorizon() {
        let advent = PuzzlePack.fixture(
            id: "advent", puzzleIDs: ["a"], season: .annual(from: "12-01", to: "12-26")
        )
        let evergreen = PuzzlePack.fixtureEvergreen
        let packs = [evergreen, advent]

        let soon = PuzzlePack.openings(
            in: packs, from: day(2026, 11, 25), within: 14, calendar: utc
        )
        #expect(soon.map(\.pack.id) == ["advent"])
        #expect(soon.first?.opensOn == utc.startOfDay(for: day(2026, 12, 1)))

        // Far out: nothing to announce yet.
        #expect(PuzzlePack.openings(in: packs, from: day(2026, 10, 1), within: 14, calendar: utc).isEmpty)
    }

    /// The rule that makes "announce it once" need no stored flag: a season
    /// already under way is not an upcoming opening.
    @Test func openingsIgnoreSeasonsAlreadyRunning() {
        let advent = PuzzlePack.fixture(
            id: "advent", puzzleIDs: ["a"], season: .annual(from: "12-01", to: "12-26")
        )
        // Opening day itself still counts — that's the day the notice fires.
        #expect(PuzzlePack.openings(in: [advent], from: day(2026, 12, 1), within: 14, calendar: utc).count == 1)
        // A day into the window, there is nothing left to announce.
        #expect(PuzzlePack.openings(in: [advent], from: day(2026, 12, 2), within: 14, calendar: utc).isEmpty)
    }

    @Test func openingsAreSortedByDate() {
        let advent = PuzzlePack.fixture(
            id: "advent", puzzleIDs: ["a"], season: .annual(from: "12-01", to: "12-26")
        )
        let stir = PuzzlePack.fixture(
            id: "stir-up", puzzleIDs: ["b"], season: .annual(from: "11-22", to: "11-28")
        )
        let openings = PuzzlePack.openings(
            in: [advent, stir], from: day(2026, 11, 20), within: 30, calendar: utc
        )
        #expect(openings.map(\.pack.id) == ["stir-up", "advent"])
    }

    // MARK: - Season decoding

    @Test func seasonRoundTripsThroughJSON() throws {
        let seasons: [PackSeason] = [
            .dates(from: "2026-07-01", to: "2026-07-07"),
            .annual(from: "12-01", to: "12-26"),
            .easter(from: -46, to: -1),
        ]
        for season in seasons {
            let data = try JSONEncoder().encode(season)
            #expect(try JSONDecoder().decode(PackSeason.self, from: data) == season)
        }
    }

    @Test func everySeasonInTheBundleResolvesAWindow() {
        for pack in PuzzleProvider.shared.packs {
            guard let season = pack.season else { continue }
            // A mistyped month/day silently resolves to nothing, which would
            // read as "this pack never opens" rather than as a bug.
            let resolved = (2026...2030).contains {
                season.window(anchoredTo: $0, calendar: utc) != nil
            }
            #expect(resolved, "Pack \(pack.id) has a season that never resolves")
        }
    }

    // MARK: - Progress

    @Test func progressCountsOnlyCompleted() {
        let pack = PuzzlePack.fixture(id: "p", puzzleIDs: ["a", "b", "c"])
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
        let pack = PuzzlePack.fixture(id: "p", puzzleIDs: ["a", "b"])
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

/// The "New" badge window. Date arithmetic gated on a shipped constant, which
/// is the shape of bug this file exists to catch.
struct NewPackBadgeTests {
    private func pack(addedOn: String?) -> PuzzlePack {
        .fixture(id: "p", puzzleIDs: ["x"], addedOn: addedOn)
    }

    @Test func aPackWithNoAddedDateIsNeverNew() {
        // Every pack that shipped before the field existed. Backfilling would
        // announce the whole back catalogue at once.
        #expect(pack(addedOn: nil).isNew(on: day(2026, 8, 9), calendar: utc) == false)
    }

    @Test func aPackIsNewOnTheDayItShips() {
        #expect(pack(addedOn: "2026-08-09").isNew(on: day(2026, 8, 9), calendar: utc))
    }

    @Test func aPackIsStillNewOnTheLastDayOfTheWindow() {
        // 14-day window, counted from day 0, so day 13 is the last one.
        #expect(pack(addedOn: "2026-08-09").isNew(on: day(2026, 8, 22), calendar: utc))
    }

    @Test func aPackStopsBeingNewWhenTheWindowLapses() {
        #expect(pack(addedOn: "2026-08-09").isNew(on: day(2026, 8, 23), calendar: utc) == false)
    }

    @Test func aFutureDateIsNotYetNewRatherThanNewForever() {
        // A mistyped year must not pin the badge on permanently.
        #expect(pack(addedOn: "2027-08-09").isNew(on: day(2026, 8, 9), calendar: utc) == false)
    }

    @Test func anUnparseableDateIsIgnored() {
        #expect(pack(addedOn: "not-a-date").isNew(on: day(2026, 8, 9), calendar: utc) == false)
    }

    @Test func closingBeatsNewWhenBothApply() {
        // A seasonal pack shipped part-way through its own window is both. The
        // row holds one badge, and the one that stops being actionable wins.
        let seasonal = PuzzlePack.fixture(
            id: "s", puzzleIDs: ["x"],
            season: .annual(from: "08-01", to: "08-15"), addedOn: "2026-08-09"
        )
        let badge = PackBadge.forPack(seasonal, on: day(2026, 8, 9))
        if case .closing = badge {} else {
            Issue.record("expected closing to win, got \(String(describing: badge))")
        }
    }
}

private extension PuzzlePack {
    static let fixtureEvergreen = PuzzlePack.fixture(id: "e", puzzleIDs: ["x"])

    static func fixture(
        id: String, puzzleIDs: [String], season: PackSeason? = nil, addedOn: String? = nil
    ) -> PuzzlePack {
        PuzzlePack(
            id: id, title: id, blurb: "", coverSymbol: "star", accentHex: nil,
            isPremium: false, puzzleIDs: puzzleIDs, season: season, addedOn: addedOn
        )
    }
}
