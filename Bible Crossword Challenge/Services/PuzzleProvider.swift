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
    /// list draw from, unchanged by however many minis the bundle gains.
    let puzzles: [Puzzle]
    /// Quick 7×7 minis with their own daily rotation.
    let minis: [Puzzle]

    /// Reference date that maps day-index 0 to the first puzzle.
    private let epoch: Date

    init(bundle: Bundle = .main) {
        let all = Self.loadBundledPuzzles(bundle: bundle)
        self.puzzles = all.filter { !$0.isMini }
        self.minis = all.filter(\.isMini)
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
        let startToday = calendar.startOfDay(for: date)
        let startEpoch = calendar.startOfDay(for: epoch)
        let days = calendar.dateComponents([.day], from: startEpoch, to: startToday).day ?? 0
        let index = ((days % pool.count) + pool.count) % pool.count
        return pool[index]
    }

    func puzzle(id: String) -> Puzzle? {
        (puzzles + minis).first { $0.id == id }
    }
}
