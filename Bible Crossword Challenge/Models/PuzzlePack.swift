//
//  PuzzlePack.swift
//  Bible Crossword Challenge
//
//  A curated collection of related puzzles ("The Life of David", "Advent"),
//  decoded from the bundled `packs.json`. Packs are a curation layer over the
//  flat puzzle pool: membership + ordering + editorial metadata live here, while
//  per-puzzle progress rides the existing `PuzzleRecord`s (already CloudKit
//  synced), so packs add no new synced state.
//

import SwiftUI

// MARK: - Clock

/// "Now", for anything gated on a season.
///
/// A seasonal surface is visible a few weeks a year, which makes it the hardest
/// thing in the app to look at and the easiest to ship broken — the countdown
/// badge, the paywall's named pack and the opening notice are all unreachable
/// on an ordinary August afternoon. In DEBUG a launch argument moves the clock:
/// `-uiSeasonDate 2026-12-20`. Same family as `-uiSeedShowcase`.
enum SeasonClock {
    nonisolated static var now: Date {
        #if DEBUG
        if let override { return override }
        #endif
        return Date()
    }

    #if DEBUG
    nonisolated static let override: Date? = {
        let args = ProcessInfo.processInfo.arguments
        guard let flag = args.firstIndex(of: "-uiSeasonDate"), flag + 1 < args.count else {
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

// MARK: - Season

/// When a pack is in season.
///
/// The obvious way to gate a seasonal pack is a pair of absolute dates, and it
/// is almost always wrong: an Advent pack dated 2026-12-01…2026-12-26 is gone
/// for good on Boxing Day 2026, silently, with nothing in the app to say so —
/// and Easter can't be written down that way at all, because it moves. A feast
/// is a *rule*, not an event, so the recurring cases store the rule and resolve
/// a concrete window for whichever year is being asked about.
enum PackSeason: Hashable, Codable {
    /// A genuinely one-off window — ISO "yyyy-MM-dd", inclusive both ends.
    /// This one *does* expire permanently, which is the point: a launch event
    /// or an anniversary happens once.
    case dates(from: String, to: String)

    /// The same calendar days every year — "MM-dd", inclusive both ends. A
    /// window may wrap the new year ("12-26" → "01-06").
    case annual(from: String, to: String)

    /// Days relative to Easter Sunday, which moves between 22 March and
    /// 25 April. Lent is `-46 ... -1`, Holy Week `-7 ... 0`, Eastertide `0 ... 7`.
    case easter(from: Int, to: Int)
}

extension PackSeason {
    // JSON shape: {"kind": "annual", "from": "12-01", "to": "12-26"}. A
    // discriminator rather than a shape-sniffing decoder, so a typo in an
    // authored pack fails loudly at decode instead of quietly never opening.
    private enum CodingKeys: String, CodingKey { case kind, from, to }
    private enum Kind: String, Codable { case dates, annual, easter }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .dates:
            self = .dates(from: try container.decode(String.self, forKey: .from),
                          to: try container.decode(String.self, forKey: .to))
        case .annual:
            self = .annual(from: try container.decode(String.self, forKey: .from),
                           to: try container.decode(String.self, forKey: .to))
        case .easter:
            self = .easter(from: try container.decode(Int.self, forKey: .from),
                           to: try container.decode(Int.self, forKey: .to))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .dates(from, to):
            try container.encode(Kind.dates, forKey: .kind)
            try container.encode(from, forKey: .from)
            try container.encode(to, forKey: .to)
        case let .annual(from, to):
            try container.encode(Kind.annual, forKey: .kind)
            try container.encode(from, forKey: .from)
            try container.encode(to, forKey: .to)
        case let .easter(from, to):
            try container.encode(Kind.easter, forKey: .kind)
            try container.encode(from, forKey: .from)
            try container.encode(to, forKey: .to)
        }
    }
}

extension PackSeason {
    /// The window this season resolves to when anchored on `year`, or `nil` when
    /// it resolves to none there (a `.dates` season belonging to another year,
    /// or an unparseable value). `.annual` and `.easter` anchor on the year the
    /// window *starts*, so a wrapping window belongs to its opening year.
    func window(anchoredTo year: Int, calendar: Calendar) -> ClosedRange<Date>? {
        switch self {
        case let .dates(from, to):
            guard let start = Self.day(iso: from, calendar: calendar),
                  let end = Self.day(iso: to, calendar: calendar),
                  calendar.component(.year, from: start) == year,
                  start <= end
            else { return nil }
            return start...end

        case let .annual(from, to):
            guard let open = Self.monthDay(from), let close = Self.monthDay(to),
                  let start = Self.day(year: year, monthDay: open, calendar: calendar)
            else { return nil }
            // An end that falls earlier in the calendar than the start wraps
            // into the next year (Christmastide: 12-26 → 01-06).
            let closingYear = close < open ? year + 1 : year
            guard let end = Self.day(year: closingYear, monthDay: close, calendar: calendar)
            else { return nil }
            return start...end

        case let .easter(from, to):
            guard from <= to,
                  let easter = Self.easterSunday(year: year, calendar: calendar),
                  let start = calendar.date(byAdding: .day, value: from, to: easter),
                  let end = calendar.date(byAdding: .day, value: to, to: easter)
            else { return nil }
            return calendar.startOfDay(for: start)...calendar.startOfDay(for: end)
        }
    }

    /// The window running on `date`, or `nil` when the season is off that day.
    func window(containing date: Date, calendar: Calendar) -> ClosedRange<Date>? {
        let day = calendar.startOfDay(for: date)
        let year = calendar.component(.year, from: day)
        // A running window can have opened last year (Christmastide) or, for a
        // date in late December, next year — so check the neighbours too.
        for anchor in [year - 1, year, year + 1] {
            if let window = window(anchoredTo: anchor, calendar: calendar), window.contains(day) {
                return window
            }
        }
        return nil
    }

    func contains(_ date: Date, calendar: Calendar) -> Bool {
        window(containing: date, calendar: calendar) != nil
    }

    /// The first day of the next window that opens on or after `date`, or `nil`
    /// when the season will never run again — which only a `.dates` season can
    /// be, since the recurring ones always come back around.
    func nextStart(onOrAfter date: Date, calendar: Calendar) -> Date? {
        let day = calendar.startOfDay(for: date)
        let year = calendar.component(.year, from: day)
        return (0...2)
            .compactMap { window(anchoredTo: year + $0, calendar: calendar)?.lowerBound }
            .filter { $0 >= day }
            .min()
    }

    /// Western (Gregorian) Easter Sunday — the anonymous Gregorian algorithm
    /// (Meeus/Jones/Butcher). Pure arithmetic valid for any Gregorian year, so
    /// the one moveable feast in the calendar needs no table to keep up to date.
    static func easterSunday(year: Int, calendar: Calendar) -> Date? {
        let a = year % 19
        let b = year / 100
        let c = year % 100
        let d = b / 4
        let e = b % 4
        let f = (b + 8) / 25
        let g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30
        let i = c / 4
        let k = c % 4
        let l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let month = (h + l - 7 * m + 114) / 31
        let day = ((h + l - 7 * m + 114) % 31) + 1
        return Self.day(year: year, monthDay: (month, day), calendar: calendar)
    }

    private static func day(iso: String, calendar: Calendar) -> Date? {
        let parts = iso.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return day(year: parts[0], monthDay: (parts[1], parts[2]), calendar: calendar)
    }

    private static func day(year: Int, monthDay: (Int, Int), calendar: Calendar) -> Date? {
        calendar.date(from: DateComponents(year: year, month: monthDay.0, day: monthDay.1))
            .map { calendar.startOfDay(for: $0) }
    }

    /// "12-01" → (12, 1). Rejects anything that isn't a plausible month/day, so
    /// a mistyped season is caught by the packs.json integrity test.
    private static func monthDay(_ value: String) -> (Int, Int)? {
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 2, (1...12).contains(parts[0]), (1...31).contains(parts[1]) else {
            return nil
        }
        return (parts[0], parts[1])
    }
}

// MARK: - Pack

struct PuzzlePack: Codable, Identifiable, Hashable {
    /// Stable slug, e.g. "life-of-david". Used for analytics and reverse lookup.
    let id: String
    let title: String
    let blurb: String
    /// SF Symbol shown on the pack's cover tile.
    let coverSymbol: String
    /// Optional per-pack tint (hex "#RRGGBB"); `nil` falls back to `Theme.accent`.
    let accentHex: String?
    /// Free "taster" packs are `false`; everything else unlocks with Premium.
    let isPremium: Bool
    /// Ordered puzzle ids — the single source of truth for membership.
    let puzzleIDs: [String]
    /// When the pack is in season. `nil` for an evergreen collection, which is
    /// always available.
    let season: PackSeason?

    /// The day this collection first shipped, ISO "yyyy-MM-dd". Drives the
    /// "New" badge for a fortnight and nothing else.
    ///
    /// Optional because every pack that shipped before the field existed has no
    /// honest answer to give — and backfilling one would announce four packs as
    /// new to everybody at once. A pack without it is simply never new.
    ///
    /// Deliberately not derived from `publishDate` on the member puzzles:
    /// `tools/README.md` calls that field cosmetic and free to shift, so a
    /// regeneration could quietly re-announce a two-year-old collection.
    let addedOn: String?

    /// Resolved tint, honouring `accentHex` when it parses.
    var accent: Color {
        accentHex.flatMap(Color.init(hex:)) ?? Theme.accent
    }

    /// A pack is seasonal when it declares a season at all.
    var isSeasonal: Bool { season != nil }

    /// Whether the pack shows on `date`. Out-of-window seasonal packs are hidden
    /// outright rather than teased — a locked "returns in December" row is a
    /// dead end on every surface that would carry it.
    func isAvailable(on date: Date = SeasonClock.now, calendar: Calendar = .current) -> Bool {
        guard let season else { return true }
        return season.contains(date, calendar: calendar)
    }

    /// The last day of the window the pack is in right now; `nil` when it's
    /// evergreen or out of season.
    func seasonEnd(on date: Date = SeasonClock.now, calendar: Calendar = .current) -> Date? {
        season?.window(containing: date, calendar: calendar)?.upperBound
    }

    /// Whole days left in the current window, counting today — `0` on the last
    /// day. `nil` when the pack is evergreen or out of season.
    func daysRemaining(on date: Date = SeasonClock.now, calendar: Calendar = .current) -> Int? {
        guard let end = seasonEnd(on: date, calendar: calendar) else { return nil }
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: end).day
    }

    /// How long a pack wears the "New" badge. A fortnight: long enough that
    /// someone who plays weekly still catches it, short enough that "new" keeps
    /// meaning it. Matched to `SeasonBadge.noticeDays` so the two badges live on
    /// the same clock.
    static let newDays = 14

    /// Whether the collection shipped inside the last `newDays`.
    ///
    /// A player installing the app long after a pack landed never sees the
    /// badge, which is right — everything is new to them, so nothing is.
    func isNew(on date: Date = SeasonClock.now, calendar: Calendar = .current) -> Bool {
        guard let addedOn, let added = Self.day(iso: addedOn, calendar: calendar) else {
            return false
        }
        let today = calendar.startOfDay(for: date)
        guard let days = calendar.dateComponents([.day], from: added, to: today).day else {
            return false
        }
        // A future date reads as not-yet-new rather than new for ever, so a
        // typo'd year can't pin the badge on permanently.
        return (0..<Self.newDays).contains(days)
    }

    /// ISO "yyyy-MM-dd" → that day at midnight. Same shape as `PackSeason`'s
    /// own parser, which is private to it.
    private static func day(iso: String, calendar: Calendar) -> Date? {
        let parts = iso.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
            .map { calendar.startOfDay(for: $0) }
    }

    /// The next day this pack opens, on or after `date`. A pack already weeks
    /// into its season reports next year's opening, not today's — callers ask
    /// this to find *upcoming* openings, and one already under way isn't news.
    func nextOpening(onOrAfter date: Date = SeasonClock.now, calendar: Calendar = .current) -> Date? {
        season?.nextStart(onOrAfter: date, calendar: calendar)
    }
}

// MARK: - Openings

/// A seasonal pack and the day its window opens. Drives the one-off "the season
/// has begun" notification.
struct PackOpening: Hashable {
    let pack: PuzzlePack
    let opensOn: Date
}

extension PuzzlePack {
    /// The packs among `packs` whose season opens between `date` and `days`
    /// later (inclusive), earliest first.
    ///
    /// Kept as pure date arithmetic so the scheduling rule is testable without
    /// standing up a notification centre.
    static func openings(
        in packs: [PuzzlePack],
        from date: Date = SeasonClock.now,
        within days: Int,
        calendar: Calendar = .current
    ) -> [PackOpening] {
        let start = calendar.startOfDay(for: date)
        guard days >= 0, let horizon = calendar.date(byAdding: .day, value: days, to: start) else {
            return []
        }
        return packs
            .compactMap { pack -> PackOpening? in
                guard let opensOn = pack.nextOpening(onOrAfter: start, calendar: calendar),
                      opensOn <= horizon
                else { return nil }
                return PackOpening(pack: pack, opensOn: opensOn)
            }
            .sorted { $0.opensOn < $1.opensOn }
    }
}

// MARK: - Shadowing

extension PuzzlePack {
    /// `packs` with any collection a Journey already covers removed.
    ///
    /// A Journey and a pack can be the same collection under two names:
    /// `life-of-david` and `parables-of-jesus` each ship as both, with the
    /// same id, the same title and the same nine puzzles. On the Packs tab
    /// that put one collection on screen twice — once under Journeys, again
    /// under All Collections, both crowned — which reads as two things to buy
    /// rather than one, and makes the catalogue look twice the size it is.
    ///
    /// The Journey wins. An ordered, paced run is the stronger daily-return
    /// pitch (it is why the Journeys section sits first), and the pack is
    /// still reachable everywhere else that links one directly.
    ///
    /// The match is exact and on content, not just id: the pack is dropped
    /// only while it holds precisely the puzzles the Journey holds. Let the
    /// two memberships diverge and the collection is genuinely a second thing
    /// again, so it comes back on its own rather than staying hidden by a
    /// rule nobody remembers writing.
    static func notShadowedByQuests(_ packs: [PuzzlePack], quests: [QuestLine]) -> [PuzzlePack] {
        let questContents = Dictionary(
            quests.map { ($0.id, Set($0.puzzleIDs)) },
            uniquingKeysWith: { first, _ in first }
        )
        return packs.filter { pack in
            guard let steps = questContents[pack.id] else { return true }
            return steps != Set(pack.puzzleIDs)
        }
    }
}

// MARK: - Progress

/// Play-through progress for a pack, derived from the player's saved records.
/// Computed in views (which own `@Query` records), not the stateless provider.
struct PackProgress: Hashable {
    let solved: Int
    let total: Int

    var fraction: Double { total == 0 ? 0 : Double(solved) / Double(total) }
    var isComplete: Bool { total > 0 && solved == total }

    init(pack: PuzzlePack, recordsByID: [String: PuzzleRecord]) {
        total = pack.puzzleIDs.count
        solved = pack.puzzleIDs.filter { recordsByID[$0]?.isCompleted == true }.count
    }
}

// MARK: - Completion recording

/// Marks packs as completed on the player's profile the moment their last
/// member puzzle is solved. Separated from the views so the same rule runs at
/// solve time (game screen) and on launch (reconciling solves that predate
/// `completedPackIDs`, or that finished a pack from another device).
enum PackCompletion {
    /// Appends any of `packs` whose every puzzle satisfies `isSolved` and that
    /// aren't already on the profile. Returns the newly completed packs.
    @discardableResult
    static func record(
        packs: [PuzzlePack],
        profile: PlayerProfile,
        isSolved: (String) -> Bool
    ) -> [PuzzlePack] {
        let finished = packs.filter { pack in
            !profile.completedPackIDs.contains(pack.id)
                && !pack.puzzleIDs.isEmpty
                && pack.puzzleIDs.allSatisfy(isSolved)
        }
        profile.completedPackIDs.append(contentsOf: finished.map(\.id))
        return finished
    }
}

// MARK: - Hex colour

extension Color {
    /// Parses "#RRGGBB" (or "RRGGBB"); returns `nil` on malformed input.
    ///
    /// `nonisolated` because the module defaults to `@MainActor`, and this is
    /// passed as a function value to `flatMap`, which wants a plain one.
    nonisolated init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let value = UInt32(s, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
