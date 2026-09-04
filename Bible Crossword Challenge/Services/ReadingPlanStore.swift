//
//  ReadingPlanStore.swift
//  Bible Crossword Challenge
//
//  A chapter a day through one book. The plan is the habit engine every
//  Bible app has and this one had none of: the Read tab's resume card was
//  passive, and reading had no mark of its own on Today.
//
//  Plans are content-free — a book and a title; the chapters are the book's.
//  Progress lives in UserDefaults for the reason `MemoryVerseStore` gives
//  (no CloudKit schema deploy for re-creatable state), and it records the
//  chapter count at start so nothing here, or on Today, needs the Bible
//  decoded to say "day 3 of 21".
//

import Foundation
import Observation
import os

struct ReadingPlan: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    /// The book read through, one chapter per day.
    let book: String
    let blurb: String

    static let all: [ReadingPlan] = [
        ReadingPlan(id: "john", title: "The Gospel of John", book: "John", blurb: "Who Jesus is, in his own words. Twenty-one days."),
        ReadingPlan(id: "mark", title: "The Gospel of Mark", book: "Mark", blurb: "The shortest gospel, and the fastest. Sixteen days."),
        ReadingPlan(id: "proverbs", title: "A Proverb a Day", book: "Proverbs", blurb: "One chapter for each day of the month."),
        ReadingPlan(id: "genesis", title: "Beginnings", book: "Genesis", blurb: "Creation to Joseph. Fifty days."),
        ReadingPlan(id: "psalms", title: "The Psalms", book: "Psalm", blurb: "The prayer book of the Bible. A hundred and fifty days."),
    ]

    static func named(_ id: String) -> ReadingPlan? { all.first { $0.id == id } }
}

@Observable
final class ReadingPlanStore {
    static let shared = ReadingPlanStore()

    struct Progress: Codable, Equatable {
        let planID: String
        let chapterCount: Int
        let startedAt: Date
        /// Days read, in order; day 1 is the book's first chapter. Sequential
        /// by construction — `markRead` only accepts the next day.
        var readDays: [Int]
        var lastReadAt: Date?
    }

    private let defaults: UserDefaults
    private let now: () -> Date
    private let calendar: Calendar
    private let storageKey = "read.plan"

    private(set) var progress: Progress?

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init, calendar: Calendar = .current) {
        self.defaults = defaults
        self.now = now
        self.calendar = calendar
        self.progress = Self.load(from: defaults, key: storageKey)
    }

    var activePlan: ReadingPlan? {
        progress.flatMap { ReadingPlan.named($0.planID) }
    }

    /// The next chapter to read, 1-based; nil with no plan or a finished one.
    var nextDay: Int? {
        guard let progress, !isComplete else { return nil }
        return progress.readDays.count + 1
    }

    var isComplete: Bool {
        guard let progress else { return false }
        return progress.readDays.count >= progress.chapterCount
    }

    /// Whether a chapter was marked read today.
    var readToday: Bool {
        guard let last = progress?.lastReadAt else { return false }
        return calendar.isDate(last, inSameDayAs: now())
    }

    /// Replaces any plan in progress.
    func start(_ plan: ReadingPlan, chapterCount: Int) {
        progress = Progress(
            planID: plan.id,
            chapterCount: chapterCount,
            startedAt: now(),
            readDays: [],
            lastReadAt: nil
        )
        persist()
    }

    func stop() {
        progress = nil
        persist()
    }

    /// Marks `day` read if it is the next one due. Reading ahead in a sitting
    /// is allowed — the plan says one a day, it doesn't police it — but a day
    /// can't be skipped or marked twice.
    @discardableResult
    func markRead(day: Int) -> Bool {
        guard var current = progress, day == current.readDays.count + 1,
              day <= current.chapterCount else { return false }
        current.readDays.append(day)
        current.lastReadAt = now()
        progress = current
        persist()
        return true
    }

    private func persist() {
        do {
            if let progress {
                defaults.set(try JSONEncoder().encode(progress), forKey: storageKey)
            } else {
                defaults.removeObject(forKey: storageKey)
            }
        } catch {
            Log.persistence.error("Failed to persist reading plan: \(error, privacy: .public)")
        }
    }

    private static func load(from defaults: UserDefaults, key: String) -> Progress? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Progress.self, from: data)
    }
}
