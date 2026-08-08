//
//  PuzzleProvider.swift
//  Bible Crossword Challenge
//
//  Loads bundled puzzles and selects the daily puzzle. The bundled JSON keeps
//  the app fully offline. A Firestore-backed provider can conform to the same
//  shape later without touching the views.
//

import Foundation

final class PuzzleProvider {
    static let shared = PuzzleProvider()

    /// Full-size daily puzzles only — the pool the daily rotation and archive
    /// list draw from, unchanged by however many minis or pack-exclusive
    /// puzzles the bundle gains.
    let puzzles: [Puzzle]
    /// Quick 7×7 minis with their own daily rotation.
    let minis: [Puzzle]
    /// Curated collections, in display order, decoded from `packs.json`. Empty
    /// when the bundle omits the file, so the feature degrades to absent.
    let packs: [PuzzlePack]

    /// Everything in the bundle, including `pack-` exclusives that never enter
    /// the daily or Archive pools but must still resolve by id (pack rows,
    /// challenge links, deep links).
    private let allPuzzles: [Puzzle]

    /// Everything a Premium player can play: dailies, minis and pack
    /// exclusives. `puzzles` is only the daily/Archive pool, so it understates
    /// the library by the packs and minis when used in upgrade copy.
    var totalPuzzleCount: Int { allPuzzles.count }

    /// Reference date that maps day-index 0 to the first puzzle.
    private let epoch: Date

    /// puzzleID -> owning packID. First pack that lists a puzzle wins, so a
    /// puzzle shared across packs still resolves to a single "primary" pack for
    /// the in-game "next in pack" affordance.
    private let packByPuzzleID: [String: String]

    init(bundle: Bundle = .main) {
        let all = Self.loadBundledPuzzles(bundle: bundle)
        self.allPuzzles = all
        // Pack-exclusive puzzles ("pack-" ids) live only inside their pack:
        // keeping them out of this pool preserves the daily-rotation index for
        // every existing player (ids here are content-stable).
        self.puzzles = all.filter { !$0.isMini && !$0.id.hasPrefix("pack-") }
        self.minis = all.filter(\.isMini)
        let loadedPacks = Self.loadBundledPacks(bundle: bundle)
        self.packs = loadedPacks

        var reverse: [String: String] = [:]
        for pack in loadedPacks {
            for pid in pack.puzzleIDs where reverse[pid] == nil {
                reverse[pid] = pack.id
            }
        }
        self.packByPuzzleID = reverse

        var components = DateComponents()
        components.year = 2026
        components.month = 7
        components.day = 1
        self.epoch = Calendar.current.date(from: components) ?? Date()
    }

    private static func loadBundledPuzzles(bundle: Bundle) -> [Puzzle] {
        guard let url = bundle.url(forResource: "puzzles", withExtension: "json") else {
            assertionFailure("puzzles.json missing from bundle")
            return []
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([Puzzle].self, from: data)
        } catch {
            assertionFailure("Failed to decode puzzles.json: \(error)")
            return []
        }
    }

    /// Loads `packs.json` if present. A missing file is not an error — the packs
    /// feature simply stays absent (the app predates it).
    private static func loadBundledPacks(bundle: Bundle) -> [PuzzlePack] {
        guard let url = bundle.url(forResource: "packs", withExtension: "json") else {
            return []
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([PuzzlePack].self, from: data)
        } catch {
            assertionFailure("Failed to decode packs.json: \(error)")
            return []
        }
    }

    /// Deterministic daily puzzle: rotates through the bundled set by calendar day.
    func dailyPuzzle(for date: Date = Date(), calendar: Calendar = .current) -> Puzzle? {
        rotated(puzzles, for: date, calendar: calendar)
    }

    /// Today's Mini — the quick 7×7, rotating through its own pool.
    func dailyMini(for date: Date = Date(), calendar: Calendar = .current) -> Puzzle? {
        rotated(minis, for: date, calendar: calendar)
    }

    private func rotated(_ pool: [Puzzle], for date: Date, calendar: Calendar) -> Puzzle? {
        guard !pool.isEmpty else { return nil }
        return pool[index(in: pool.count, for: date, calendar: calendar)]
    }

    /// Whole days from the content epoch to `date`. Negative before the epoch;
    /// callers wrap it into a pool with `index(in:for:calendar:)`.
    func dayIndex(for date: Date = Date(), calendar: Calendar = .current) -> Int {
        let startToday = calendar.startOfDay(for: date)
        let startEpoch = calendar.startOfDay(for: epoch)
        return calendar.dateComponents([.day], from: startEpoch, to: startToday).day ?? 0
    }

    /// `dayIndex` wrapped into a pool of `count`, always non-negative.
    private func index(in count: Int, for date: Date, calendar: Calendar) -> Int {
        let days = dayIndex(for: date, calendar: calendar)
        return ((days % count) + count) % count
    }

    /// The `length` puzzles currently open in `pool`: today's, then the ones
    /// served before it, walking the rotation backwards and wrapping with it.
    ///
    /// Positions, not dates. The pool recurs every `pool.count` days, so no
    /// puzzle belongs to a calendar day — asking for "the last seven days of
    /// puzzles" only has an answer because the rotation says which seven are
    /// currently in play, and that answer stays defined after the pool wraps.
    func rotationWindow(
        _ pool: [Puzzle],
        for date: Date = Date(),
        calendar: Calendar = .current,
        length: Int
    ) -> [Puzzle] {
        guard !pool.isEmpty, length > 0 else { return [] }
        let today = dayIndex(for: date, calendar: calendar)
        // A window longer than the pool would repeat puzzles rather than widen.
        let span = min(length, pool.count)
        return (0..<span).map { offset in
            let i = (((today - offset) % pool.count) + pool.count) % pool.count
            return pool[i]
        }
    }

    func puzzle(id: String) -> Puzzle? {
        allPuzzles.first { $0.id == id }
    }

    // MARK: - Packs

    func pack(id: String) -> PuzzlePack? {
        packs.first { $0.id == id }
    }

    /// The pack a puzzle primarily belongs to, or `nil` if it's in none. Drives
    /// the in-game "next in pack" affordance.
    func pack(forPuzzle id: String) -> PuzzlePack? {
        packByPuzzleID[id].flatMap(pack(id:))
    }

    /// Every pack that lists this puzzle — a shared puzzle can complete more
    /// than one pack at once, so completion detection checks them all.
    func packs(containing puzzleID: String) -> [PuzzlePack] {
        packs.filter { $0.puzzleIDs.contains(puzzleID) }
    }

    /// A pack's puzzles resolved in authored order. Unknown ids are dropped (a
    /// DEBUG assertion flags authoring typos) so a stale reference never crashes.
    func puzzles(in pack: PuzzlePack) -> [Puzzle] {
        pack.puzzleIDs.compactMap { id in
            guard let puzzle = puzzle(id: id) else {
                assertionFailure("Pack \(pack.id) references missing puzzle \(id)")
                return nil
            }
            return puzzle
        }
    }

    /// Packs whose seasonal window includes `date` (non-seasonal always shown),
    /// preserving display order.
    func availablePacks(on date: Date = SeasonClock.now) -> [PuzzlePack] {
        packs.filter { $0.isAvailable(on: date) }
    }
}
