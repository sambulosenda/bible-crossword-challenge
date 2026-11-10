//
//  WidgetBridge.swift
//  Bible Crossword Challenge
//
//  Publishes a tiny snapshot of streak state into the shared app-group
//  defaults so the widget extension can render without touching the
//  SwiftData/CloudKit store. Keys are read by BibleCrosswordWidget — keep the
//  two sides in sync if they ever change.
//

import Foundation
import SwiftData
import WidgetKit

enum WidgetBridge {
    static let appGroupID = "group.com.sambulosendas1.Bible-Crossword-Challenge"

    enum Key {
        static let currentStreak = "widget.currentStreak"
        static let bestStreak = "widget.bestStreak"
        static let streakFreezes = "widget.streakFreezes"
        /// Start-of-day of the last completion, as timeIntervalSinceReferenceDate.
        /// 0 means never completed.
        static let lastCompletedDay = "widget.lastCompletedDay"
        static let totalCompleted = "widget.totalCompleted"
        /// Start-of-day the two per-pool flags below were computed for, as
        /// timeIntervalSinceReferenceDate. The widget trusts the flags only
        /// when this matches its entry's day, so a snapshot written yesterday
        /// can't claim today's puzzles are done after midnight.
        static let flagsDay = "widget.flagsDay"
        static let dailyCompletedToday = "widget.dailyCompletedToday"
        static let miniCompletedToday = "widget.miniCompletedToday"
        /// The verse of the day for today and the next few days, as
        /// `[["day": startOfDay interval, "text": …, "reference": …]]` — the
        /// same verse Today's header shows, so the widget and the app agree.
        /// Several days ahead because the widget's timeline runs past
        /// midnight without the app.
        static let verses = "widget.verses"
        /// Clue of the Day, for the same days as `verses`, as
        /// `[["day": interval, "dailyTitle": …, "clue": …, "answer": …,
        /// "tiles": [String], "clueReference": …?, "verse": …, "reference": …]]`.
        /// Written by the app; the interactive widget plays it. Every day has
        /// an entry for its daily's title even when no clue qualifies (then
        /// the clue keys are absent).
        static let clueDays = "widget.clueDays"
        /// The widget's own play state for the day's clue, as JSON. Written
        /// only by the widget's intents; the app never reads or clears it.
        static let clueProgress = "widget.clueProgress"
        /// Events the widget couldn't log itself (the extension has no
        /// analytics SDK): `[["event": "started" | "solved", "day": interval,
        /// "length": Int, "wrong": Int]]`. Appended by the widget, drained by
        /// the app at launch and on every return to the foreground.
        static let clueEvents = "widget.clueEvents"
    }

    /// Days of verses published ahead: today plus the widget timeline's
    /// two midnights, and one spare.
    static let verseDays = 4

    /// Mirrors the profile into shared defaults and asks WidgetKit to redraw.
    /// Call after any change to streak/completion state has been saved. The
    /// context is used to read the two records that decide which puzzle the
    /// widget's tap should open — `lastCompletedDay` alone can't tell a
    /// mini-only day from a daily-only one.
    static func publish(
        _ profile: PlayerProfile,
        context: ModelContext,
        provider: PuzzleProvider = .shared,
        calendar: Calendar = .current
    ) {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return }
        defaults.set(profile.currentStreak, forKey: Key.currentStreak)
        defaults.set(profile.bestStreak, forKey: Key.bestStreak)
        defaults.set(profile.streakFreezes, forKey: Key.streakFreezes)
        let lastDay = profile.lastCompletedDate.map {
            calendar.startOfDay(for: $0).timeIntervalSinceReferenceDate
        } ?? 0
        defaults.set(lastDay, forKey: Key.lastCompletedDay)
        defaults.set(profile.totalPuzzlesCompleted, forKey: Key.totalCompleted)

        let today = calendar.startOfDay(for: Date())
        defaults.set(today.timeIntervalSinceReferenceDate, forKey: Key.flagsDay)
        defaults.set(
            completedToday(provider.dailyPuzzle()?.id, context: context, on: today, calendar: calendar),
            forKey: Key.dailyCompletedToday
        )
        defaults.set(
            completedToday(provider.dailyMini()?.id, context: context, on: today, calendar: calendar),
            forKey: Key.miniCompletedToday
        )
        defaults.set(verses(from: today, provider: provider, calendar: calendar), forKey: Key.verses)
        defaults.set(clueDays(from: today, provider: provider, calendar: calendar), forKey: Key.clueDays)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private static func verses(from today: Date, provider: PuzzleProvider, calendar: Calendar) -> [[String: Any]] {
        (0..<verseDays).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let verse = provider.verseOfTheDay(
                      on: day, excluding: provider.dailyPuzzle(for: day, calendar: calendar)?.id, calendar: calendar
                  ),
                  !verse.verse.isEmpty
            else { return nil }
            return ["day": day.timeIntervalSinceReferenceDate, "text": verse.verse, "reference": verse.reference]
        }
    }

    private static func clueDays(from today: Date, provider: PuzzleProvider, calendar: Calendar) -> [[String: Any]] {
        (0..<verseDays).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { return nil }
            var item: [String: Any] = ["day": day.timeIntervalSinceReferenceDate]
            if let title = provider.dailyPuzzle(for: day, calendar: calendar)?.title {
                item["dailyTitle"] = title
            }
            if let clue = clueOfTheDay(on: day, provider: provider, calendar: calendar) {
                item["clue"] = clue.clue
                item["answer"] = clue.answer
                item["tiles"] = clue.tiles
                if let reference = clue.clueReference { item["clueReference"] = reference }
                item["verse"] = clue.verse
                item["reference"] = clue.reference
            }
            return item
        }
    }

    // MARK: Clue of the Day

    /// One clue a day for the interactive widget: answered by tapping letter
    /// tiles on the Home Screen, and solving it shows the day's verse.
    struct WidgetClue: Equatable {
        let clue: String
        /// Upper-case A–Z only.
        let answer: String
        /// The answer's letters plus `decoyCount` others, shuffled. One letter
        /// each. The order is fixed for the day, since the widget's progress
        /// is stored as indices into it.
        let tiles: [String]
        let clueReference: String?
        /// The verse of the day, and its reference: the clue comes from the
        /// same puzzle, so the verse it unlocks is the one Today shows.
        let verse: String
        let reference: String
    }

    static let clueLengths = 3...6
    /// Fits two lines of the medium widget.
    static let clueMaxLength = 70
    static let decoyCount = 2
    /// Common letters, so a decoy reads as a plausible wrong turn rather
    /// than an obvious throwaway Q or Z.
    private static let decoyLetters = Array("AEILNORSTDHMBGCPUWY").map(String.init)

    /// The day's clue, drawn from the verse-of-the-day puzzle. That puzzle is
    /// never the day's daily (see `verseOfTheDay`), so the widget can't give
    /// away an answer the player is about to meet in the full grid. Nil when
    /// none of its clues fit the widget.
    static func clueOfTheDay(
        on day: Date,
        provider: PuzzleProvider = .shared,
        calendar: Calendar = .current
    ) -> WidgetClue? {
        guard let source = provider.verseOfTheDay(
                  on: day, excluding: provider.dailyPuzzle(for: day, calendar: calendar)?.id, calendar: calendar
              ),
              !source.verse.isEmpty
        else { return nil }
        let candidates = source.clues.filter(fitsWidget)
        guard !candidates.isEmpty else { return nil }
        let seed = UInt64(truncatingIfNeeded: dayIndex(day, calendar: calendar))
        var rng = SeededGenerator(seed: seed)
        let pick = candidates[Int(rng.next() % UInt64(candidates.count))]
        let answer = pick.answer.uppercased()

        var tiles = answer.map(String.init)
        for _ in 0..<decoyCount {
            tiles.append(decoyLetters[Int(rng.next() % UInt64(decoyLetters.count))])
        }
        tiles.shuffle(using: &rng)
        // A shuffle that left the answer spelled out in the first tiles
        // would solve itself by tapping left to right.
        if tiles.prefix(answer.count).joined() == answer {
            tiles.append(tiles.removeFirst())
        }
        return WidgetClue(
            clue: pick.text,
            answer: answer,
            tiles: tiles,
            clueReference: pick.reference,
            verse: source.verse,
            reference: source.reference
        )
    }

    /// Short, letters only, and standing on its own: a clue that points at
    /// another ("See 5-Across") means nothing outside its grid.
    static func fitsWidget(_ clue: ClueData) -> Bool {
        let answer = clue.answer.uppercased()
        guard clueLengths.contains(answer.count),
              answer.allSatisfy({ ("A"..."Z").contains($0) }),
              clue.text.count <= clueMaxLength,
              !clue.text.isEmpty
        else { return false }
        let pointsElsewhere = clue.text.range(
            of: #"\d+\s*-?\s*(Across|Down)"#, options: [.regularExpression, .caseInsensitive]
        ) != nil
        return !pointsElsewhere
    }

    /// Counted from noon for the reason `verseOfTheDay` is.
    private static func dayIndex(_ day: Date, calendar: Calendar) -> Int {
        let noon = calendar.date(byAdding: .hour, value: 12, to: calendar.startOfDay(for: day)) ?? day
        return calendar.ordinality(of: .day, in: .era, for: noon) ?? 0
    }

    /// SplitMix64: the same tiles on every launch and every device for a
    /// day, which `SystemRandomNumberGenerator` can't give.
    struct SeededGenerator: RandomNumberGenerator {
        private var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    /// Takes the widget's queued events and empties the queue. `today` dates
    /// `daysLate`: the widget may be played for days before the app is next
    /// opened, and the event lands when it is.
    static func takeClueEvents(
        from defaults: UserDefaults? = UserDefaults(suiteName: appGroupID),
        today: Date,
        calendar: Calendar = .current
    ) -> [AnalyticsEvent] {
        guard let defaults,
              let raw = defaults.array(forKey: Key.clueEvents) as? [[String: Any]],
              !raw.isEmpty
        else { return [] }
        defaults.removeObject(forKey: Key.clueEvents)
        let start = calendar.startOfDay(for: today)
        return raw.compactMap { item in
            guard let event = item["event"] as? String,
                  let interval = item["day"] as? Double,
                  let length = item["length"] as? Int
            else { return nil }
            let day = calendar.startOfDay(for: Date(timeIntervalSinceReferenceDate: interval))
            let late = max(0, calendar.dateComponents([.day], from: day, to: start).day ?? 0)
            switch event {
            case "started":
                return .widgetClueStarted(answerLength: length, daysLate: late)
            case "solved":
                return .widgetClueSolved(answerLength: length, wrongAttempts: item["wrong"] as? Int ?? 0, daysLate: late)
            default:
                return nil
            }
        }
    }

    /// Whether `puzzleID`'s record was completed on `day`. Completed on an
    /// earlier rotation pass doesn't count — the widget's job is today's
    /// habit, and the rotation serving a puzzle solved months ago is exactly
    /// the repeat `DailyPresentation` warns about.
    private static func completedToday(
        _ puzzleID: String?,
        context: ModelContext,
        on day: Date,
        calendar: Calendar
    ) -> Bool {
        guard let puzzleID else { return false }
        let descriptor = FetchDescriptor<PuzzleRecord>(
            predicate: #Predicate { $0.puzzleID == puzzleID }
        )
        guard let record = try? context.fetch(descriptor).first,
              record.isCompleted,
              let completed = record.completedDate
        else { return false }
        return calendar.isDate(completed, inSameDayAs: day)
    }
}
