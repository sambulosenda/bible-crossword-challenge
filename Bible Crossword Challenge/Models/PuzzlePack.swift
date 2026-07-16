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
    /// Seasonal gating as ISO "yyyy-MM-dd" (inclusive). `nil` means always available.
    let availableFrom: String?
    let availableTo: String?

    /// Resolved tint, honouring `accentHex` when it parses.
    var accent: Color {
        accentHex.flatMap(Color.init(hex:)) ?? Theme.accent
    }

    /// A pack is seasonal when it declares any availability window.
    var isSeasonal: Bool { availableFrom != nil || availableTo != nil }

    /// True when `date` falls within `[availableFrom, availableTo]`. Non-seasonal
    /// packs are always available. A malformed date is treated as no bound.
    func isAvailable(on date: Date = Date(), calendar: Calendar = .current) -> Bool {
        let day = calendar.startOfDay(for: date)
        if let from = Self.date(availableFrom, calendar: calendar),
           day < calendar.startOfDay(for: from) {
            return false
        }
        if let to = Self.date(availableTo, calendar: calendar),
           day > calendar.startOfDay(for: to) {
            return false
        }
        return true
    }

    private static func date(_ iso: String?, calendar: Calendar) -> Date? {
        guard let iso else { return nil }
        var f = DateComponents()
        let parts = iso.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        f.year = parts[0]; f.month = parts[1]; f.day = parts[2]
        return calendar.date(from: f)
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
    init?(hex: String) {
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
