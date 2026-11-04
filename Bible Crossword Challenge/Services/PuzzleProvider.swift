//
//  PuzzleProvider.swift
//  Bible Crossword Challenge
//
//  Loads bundled puzzles and selects the daily puzzle. The bundled JSON keeps
//  the app fully offline. A Firestore-backed provider can conform to the same
//  shape later without touching the views.
//

import Foundation

/// The "today" the daily rotation is measured against.
///
/// The rotation is deterministic from the calendar day, which is exactly right
/// in production and exactly wrong when capturing App Store screenshots: the
/// story the shot needs is served on whichever day the pool says, and most of
/// the catalogue is months away. In DEBUG a launch argument moves the day:
/// `-uiRotationDate 2026-10-04`. Same family as `-uiSeasonDate` and
/// `-uiSeedShowcase`.
///
/// Deliberately separate from `SeasonClock`: a seasonal pack window and the
/// daily rotation are independent axes, and a screenshot often needs to pin one
/// without disturbing the other.
enum RotationClock {
    nonisolated static var now: Date {
        #if DEBUG
        if let override { return override }
        #endif
        return Date()
    }

    #if DEBUG
    nonisolated static let override: Date? = {
        let args = ProcessInfo.processInfo.arguments
        guard let flag = args.firstIndex(of: "-uiRotationDate"), flag + 1 < args.count else {
            return nil
        }
        let parts = args[flag + 1].split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Calendar.current.date(
            from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12)
        )
    }()
    #endif
}

final class PuzzleProvider {
    static let shared = PuzzleProvider()

    /// Full-size daily puzzles only — the pool the daily rotation and archive
    /// list draw from, unchanged by however many minis or pack-exclusive
    /// puzzles the bundle gains.
    let puzzles: [Puzzle]
    /// Quick 7×7 minis with their own daily rotation.
    let minis: [Puzzle]
    /// Weekly 21×21 Sunday Specials, rotating by week rather than by day.
    let sundays: [Puzzle]
    /// Curated collections, in display order, decoded from `packs.json`. Empty
    /// when the bundle omits the file, so the feature degrades to absent.
    let packs: [PuzzlePack]

    /// Journey quest lines, in display order, decoded from `quests.json` —
    /// authored order is display order and the first quest is the free one.
    /// Empty when the bundle omits the file, like `packs`.
    let quests: [QuestLine]

    /// Everything in the bundle, including `pack-` exclusives that never enter
    /// the daily or Archive pools but must still resolve by id (pack rows,
    /// challenge links, deep links).
    ///
    /// Readable because the journey map counts across the whole catalogue: how
    /// much of a book exists is as much a part of that picture as how much of it
    /// has been solved.
    let allPuzzles: [Puzzle]

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

    /// Date → puzzle id, from `schedule.json` (built by
    /// `tools/build_schedule.py`). Pins each day to a puzzle so the pools can
    /// grow without moving history. Dates it doesn't cover fall back to the
    /// legacy `dayIndex % pool.count` rotation, which is also what every past
    /// entry was built from.
    let schedule: PuzzleSchedule?

    init(bundle: Bundle = .main) {
        let all = Self.loadBundledPuzzles(bundle: bundle)
        self.allPuzzles = all
        // Pack-exclusive puzzles ("pack-" ids) live only inside their pack, and
        // Sunday Specials rotate weekly in their own pool: keeping both out of
        // this pool preserves the daily-rotation index for every existing
        // player (ids here are content-stable).
        self.puzzles = all.filter { !$0.isMini && !$0.isSunday && !$0.id.hasPrefix("pack-") }
        self.minis = all.filter(\.isMini)
        self.sundays = all.filter(\.isSunday)
        let loadedPacks = Self.loadBundledPacks(bundle: bundle)
        self.packs = loadedPacks
        self.quests = Self.loadBundledQuests(bundle: bundle)
        self.schedule = Self.loadBundledSchedule(bundle: bundle)

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

    /// Loads `schedule.json` if present. Missing or broken → `nil`, and the
    /// rotation runs on the legacy modulo alone.
    private static func loadBundledSchedule(bundle: Bundle) -> PuzzleSchedule? {
        guard let url = bundle.url(forResource: "schedule", withExtension: "json") else {
            return nil
        }
        do {
            return try JSONDecoder().decode(PuzzleSchedule.self, from: Data(contentsOf: url))
        } catch {
            assertionFailure("Failed to decode schedule.json: \(error)")
            return nil
        }
    }

    /// Loads `quests.json` if present — same degrade-to-absent contract as
    /// `loadBundledPacks`.
    private static func loadBundledQuests(bundle: Bundle) -> [QuestLine] {
        guard let url = bundle.url(forResource: "quests", withExtension: "json") else {
            return []
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([QuestLine].self, from: data)
        } catch {
            assertionFailure("Failed to decode quests.json: \(error)")
            return []
        }
    }

    /// The longest verse Today opens on — three lines of body serif on a phone.
    static let verseOfTheDayMaxLength = 120

    /// The day's inspirational verse: a puzzle's verse, rotated by calendar
    /// day, from any puzzle but that day's daily — so it never spoils the
    /// daily's answers. Shared by Today's header and the daily reminder, so
    /// the notification quotes the verse the player then finds on Today.
    func verseOfTheDay(on day: Date, excluding dailyID: String?, calendar: Calendar = .current) -> Puzzle? {
        // Short verses only (2026-11-02): it opens Today, and a 190-character
        // verse ran five lines and pushed the day's puzzle down. 120 fits in
        // three lines without a clamp cutting it mid-word.
        // Whole sentences too: 13 verses open mid-sentence ("asking, …") and
        // read as fragments on their own. 162 pass both.
        // Falls back to every verse if a future set has too few.
        let others = puzzles.filter { $0.id != dailyID }
        let short = others.filter {
            $0.verse.count <= Self.verseOfTheDayMaxLength
                && $0.verse.first.map { !$0.isLowercase } ?? false
        }
        let pool = short.count >= 30 ? short : others
        guard !pool.isEmpty else { return nil }
        // Counted from noon, not from the day's start: at local midnight in
        // BST `ordinality(of: .day, in: .era)` still returns the previous
        // day's number, so midnight would shift the whole rotation back a
        // day. Noon is inside the right day in every time zone.
        let noon = calendar.date(byAdding: .hour, value: 12, to: calendar.startOfDay(for: day)) ?? day
        let index = calendar.ordinality(of: .day, in: .era, for: noon) ?? 0
        return pool[((index % pool.count) + pool.count) % pool.count]
    }

    /// Deterministic daily puzzle: rotates through the bundled set by calendar day.
    func dailyPuzzle(for date: Date = RotationClock.now, calendar: Calendar = .current) -> Puzzle? {
        scheduled(schedule?.daily, in: puzzles, on: date, calendar: calendar)
            ?? rotated(puzzles, for: date, calendar: calendar)
    }

    /// Today's Mini — the quick 7×7, rotating through its own pool.
    func dailyMini(for date: Date = RotationClock.now, calendar: Calendar = .current) -> Puzzle? {
        scheduled(schedule?.mini, in: minis, on: date, calendar: calendar)
            ?? rotated(minis, for: date, calendar: calendar)
    }

    /// This week's Sunday Special — the big 21×21, one per week. The card
    /// lingers Sunday through Saturday, so it rotates on `weekIndex`, not on
    /// the day.
    func sundaySpecial(for date: Date = RotationClock.now, calendar: Calendar = .current) -> Puzzle? {
        guard !sundays.isEmpty else { return nil }
        let start = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: start)
        if let sunday = calendar.date(byAdding: .day, value: -(weekday - 1), to: start),
           let puzzle = scheduled(schedule?.sunday, in: sundays, on: sunday, calendar: calendar) {
            return puzzle
        }
        let week = weekIndex(for: date, calendar: calendar) - Self.sundayRotationOffset
        let count = sundays.count
        return sundays[((week % count) + count) % count]
    }

    /// Weeks subtracted from the week index before it picks a Special.
    ///
    /// The pool is append-only (ids and positions are content-stable), so a
    /// plain `week % count` would, after a bank grows, replay the oldest
    /// Specials before it ever reached the new ones: with 5 banked, weeks 0–8
    /// served 001–005 and 001–004 again; adding 8 more without this would have
    /// sent weeks 13–17 back to 001–005 a third time while 006–009 sat unplayed.
    ///
    /// Re-derive whenever the bank grows: with the current week `w` serving
    /// index `i`, set this so `(w - offset) % newCount == i` — the week in
    /// progress keeps its Special and the following weeks walk forward through
    /// every puzzle once before wrapping. Set 2026-09-04 (week 8, index 3, 13
    /// banked): (8 - 5) % 13 == 3.
    static let sundayRotationOffset = 5

    /// Whole weeks from the content epoch, where a week begins on **Sunday**
    /// regardless of the player's locale — the Special is a Sunday tradition,
    /// not a "start of the local week" one. Two dates share an index exactly
    /// when they share a most-recent Sunday, so the served puzzle holds steady
    /// Sunday through Saturday and rolls at midnight into Sunday.
    func weekIndex(for date: Date = RotationClock.now, calendar: Calendar = .current) -> Int {
        let day = dayIndex(for: date, calendar: calendar)
        // Gregorian weekday: 1 = Sunday. Shift the day count so every date
        // inside a Sunday-week collapses to that week's Sunday before dividing.
        let weekday = calendar.component(.weekday, from: calendar.startOfDay(for: date))
        let sundayDay = day - (weekday - 1)
        // Floor division, so pre-epoch dates step backwards without doubling
        // up around zero the way truncating division would.
        return Int((Double(sundayDay) / 7.0).rounded(.down))
    }

    /// The puzzle `map` pins to `date`'s local calendar day, if it's in `pool`.
    /// An id outside the pool (a typo, or a puzzle this build doesn't carry)
    /// reads as unscheduled rather than serving the wrong kind of puzzle.
    private func scheduled(_ map: [String: String]?, in pool: [Puzzle], on date: Date, calendar: Calendar) -> Puzzle? {
        guard let map, let id = map[PuzzleSchedule.key(for: date, calendar: calendar)] else { return nil }
        return pool.first { $0.id == id }
    }

    private func rotated(_ pool: [Puzzle], for date: Date, calendar: Calendar) -> Puzzle? {
        guard !pool.isEmpty else { return nil }
        return pool[index(in: pool.count, for: date, calendar: calendar)]
    }

    /// Whole days from the content epoch to `date`. Negative before the epoch;
    /// callers wrap it into a pool with `index(in:for:calendar:)`.
    func dayIndex(for date: Date = RotationClock.now, calendar: Calendar = .current) -> Int {
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
        for date: Date = RotationClock.now,
        calendar: Calendar = .current,
        length: Int
    ) -> [Puzzle] {
        guard !pool.isEmpty, length > 0 else { return [] }
        // Scheduled pools walk back by date: the window is what the last
        // `length` days actually served. Falls back per day like the daily.
        let map: [String: String]? = pool.first.map { $0.isMini ? schedule?.mini : schedule?.daily } ?? nil
        if let map, !map.isEmpty, !pool.contains(where: \.isSunday) {
            let start = calendar.startOfDay(for: date)
            let today = dayIndex(for: date, calendar: calendar)
            // Walk back until the window holds `span` distinct puzzles: where
            // the schedule hands over to the modulo the two can name the same
            // puzzle on neighbouring days, and the window must not shrink.
            let span = min(length, pool.count)
            var seen = Set<String>()
            var window: [Puzzle] = []
            var offset = 0
            while window.count < span, offset < span * 2 + 7 {
                defer { offset += 1 }
                guard let day = calendar.date(byAdding: .day, value: -offset, to: start) else { continue }
                let i = (((today - offset) % pool.count) + pool.count) % pool.count
                let puzzle = scheduled(map, in: pool, on: day, calendar: calendar) ?? pool[i]
                if seen.insert(puzzle.id).inserted { window.append(puzzle) }
            }
            return window
        }
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

    // MARK: - Quests

    func quest(id: String) -> QuestLine? {
        quests.first { $0.id == id }
    }

    /// Every quest listing this puzzle — like packs, a puzzle solved in the
    /// daily feed can advance more than one quest at once.
    func quests(containing puzzleID: String) -> [QuestLine] {
        quests.filter { $0.puzzleIDs.contains(puzzleID) }
    }

    /// A quest's steps resolved in authored order — same drop-with-assertion
    /// contract as `puzzles(in pack:)`.
    func puzzles(in quest: QuestLine) -> [Puzzle] {
        quest.puzzleIDs.compactMap { id in
            guard let puzzle = puzzle(id: id) else {
                assertionFailure("Quest \(quest.id) references missing puzzle \(id)")
                return nil
            }
            return puzzle
        }
    }
}


/// `schedule.json`: local calendar date (`yyyy-MM-dd`) → puzzle id. Sundays are
/// keyed by the date of their week's Sunday.
struct PuzzleSchedule: Decodable, Sendable {
    let version: Int
    let daily: [String: String]
    let mini: [String: String]
    let sunday: [String: String]

    /// The local calendar day of `date`, as the schedule keys it.
    static func key(for date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
