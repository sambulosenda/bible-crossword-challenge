//
//  ClueWidget.swift
//  BibleCrosswordWidget
//
//  Clue of the Day: an interactive widget (2026-11-10). One crossword clue a
//  day, answered on the Home Screen by tapping letter tiles; solving it shows
//  the verse of the day, and the streak and today's puzzle sit beside it.
//  The other widgets ask for a solve and got 0 opens in 30 days; this one
//  gives a small win first and then points at the real puzzle.
//
//  The app writes the clue (WidgetBridge.Key.clueDays). The play state lives
//  here, written by the intents below into the same app group, so a tap works
//  without launching the app. The clue comes from the verse-of-the-day
//  puzzle, never the day's daily, so it can't spoil today's grid.
//

import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Data (keys mirror WidgetBridge in the app)

struct ClueOfDay: Equatable {
    let clue: String
    /// Upper-case A–Z.
    let answer: String
    /// One letter each; progress is stored as indices into this.
    let tiles: [String]
    let clueReference: String?
    let verse: String
    let reference: String
}

struct ClueDay {
    let day: Date
    let dailyTitle: String?
    let puzzle: ClueOfDay?
}

/// The player's taps on one day's clue. Indices into `ClueOfDay.tiles`.
struct ClueProgress: Codable, Equatable {
    var day: Double = 0
    /// The answer these picks were made against. A content update that
    /// changes the day's clue mid-day must not leave picks pointing at
    /// another clue's tiles.
    var answer: String = ""
    var picks: [Int] = []
    var wrongAttempts = 0
    var solved = false
    var started = false

    func isWrong(_ clue: ClueOfDay) -> Bool {
        !solved && picks.count >= clue.answer.count
    }

    /// Letters given back after a wrong spelling: one per wrong attempt,
    /// never the whole word.
    func revealedCount(_ clue: ClueOfDay) -> Int {
        min(wrongAttempts, clue.answer.count - 1)
    }

    func letters(_ clue: ClueOfDay) -> [String] {
        picks.compactMap { clue.tiles.indices.contains($0) ? clue.tiles[$0] : nil }
    }

    /// Queued event names, in order, for the app to log later.
    enum Event { case started, solved }

    mutating func place(_ tile: Int, in clue: ClueOfDay) -> [Event] {
        guard !solved, picks.count < clue.answer.count,
              clue.tiles.indices.contains(tile), !picks.contains(tile)
        else { return [] }
        var events: [Event] = []
        if !started {
            started = true
            events.append(.started)
        }
        picks.append(tile)
        if picks.count == clue.answer.count {
            if letters(clue).joined() == clue.answer {
                solved = true
                events.append(.solved)
            } else {
                wrongAttempts += 1
            }
        }
        return events
    }

    mutating func deleteLast(in clue: ClueOfDay) {
        guard !solved, picks.count > revealedCount(clue) else { return }
        picks.removeLast()
    }

    /// Back to an empty answer, with the first letters filled in for each
    /// wrong attempt so far.
    mutating func retry(in clue: ClueOfDay) {
        guard !solved else { return }
        picks = []
        let answer = Array(clue.answer).map(String.init)
        for letter in answer.prefix(revealedCount(clue)) {
            guard let index = clue.tiles.indices.first(where: { clue.tiles[$0] == letter && !picks.contains($0) })
            else { break }
            picks.append(index)
        }
    }
}

enum ClueStore {
    static let daysKey = "widget.clueDays"
    static let progressKey = "widget.clueProgress"
    static let eventsKey = "widget.clueEvents"

    static var defaults: UserDefaults? { UserDefaults(suiteName: StreakSnapshot.appGroupID) }

    static func loadDays() -> [ClueDay] {
        let raw = defaults?.array(forKey: daysKey) as? [[String: Any]] ?? []
        return raw.compactMap { item in
            guard let interval = item["day"] as? Double else { return nil }
            var puzzle: ClueOfDay?
            if let clue = item["clue"] as? String,
               let answer = item["answer"] as? String,
               let tiles = item["tiles"] as? [String],
               let verse = item["verse"] as? String,
               let reference = item["reference"] as? String {
                puzzle = ClueOfDay(
                    clue: clue, answer: answer, tiles: tiles,
                    clueReference: item["clueReference"] as? String,
                    verse: verse, reference: reference
                )
            }
            return ClueDay(
                day: Date(timeIntervalSinceReferenceDate: interval),
                dailyTitle: item["dailyTitle"] as? String,
                puzzle: puzzle
            )
        }
    }

    static func day(_ date: Date, in days: [ClueDay], calendar: Calendar = .current) -> ClueDay? {
        days.first { calendar.isDate($0.day, inSameDayAs: date) }
    }

    /// The saved progress if it belongs to this day and clue, else a fresh one.
    static func progress(for clue: ClueOfDay, day: Date) -> ClueProgress {
        let interval = day.timeIntervalSinceReferenceDate
        if let data = defaults?.data(forKey: progressKey),
           let saved = try? JSONDecoder().decode(ClueProgress.self, from: data),
           saved.day == interval, saved.answer == clue.answer {
            return saved
        }
        return ClueProgress(day: interval, answer: clue.answer)
    }

    /// Loads the day's clue and progress, applies `change`, saves, and
    /// queues any events. A tap on a day the app hasn't published is a no-op.
    static func update(day interval: Double, _ change: (inout ClueProgress, ClueOfDay) -> [ClueProgress.Event]) {
        let date = Date(timeIntervalSinceReferenceDate: interval)
        guard let clue = day(date, in: loadDays())?.puzzle else { return }
        var state = progress(for: clue, day: date)
        let events = change(&state, clue)
        if let data = try? JSONEncoder().encode(state) {
            defaults?.set(data, forKey: progressKey)
        }
        guard !events.isEmpty, let defaults else { return }
        var queue = defaults.array(forKey: eventsKey) as? [[String: Any]] ?? []
        for event in events {
            queue.append([
                "event": event == .started ? "started" : "solved",
                "day": interval,
                "length": clue.answer.count,
                "wrong": state.wrongAttempts,
            ])
        }
        // Bounded in case the app isn't opened for a long while.
        defaults.set(Array(queue.suffix(60)), forKey: eventsKey)
    }
}

// MARK: - Intents (run in the widget extension, no app launch)

struct PlaceClueLetterIntent: AppIntent {
    static let title: LocalizedStringResource = "Place a Letter"
    static let isDiscoverable = false

    @Parameter(title: "Tile") var tile: Int
    @Parameter(title: "Day") var day: Double

    init() {}
    init(tile: Int, day: Double) {
        self.tile = tile
        self.day = day
    }

    func perform() async throws -> some IntentResult {
        ClueStore.update(day: day) { progress, clue in progress.place(tile, in: clue) }
        return .result()
    }
}

struct DeleteClueLetterIntent: AppIntent {
    static let title: LocalizedStringResource = "Delete a Letter"
    static let isDiscoverable = false

    @Parameter(title: "Day") var day: Double

    init() {}
    init(day: Double) { self.day = day }

    func perform() async throws -> some IntentResult {
        ClueStore.update(day: day) { progress, clue in
            progress.deleteLast(in: clue)
            return []
        }
        return .result()
    }
}

struct RetryClueIntent: AppIntent {
    static let title: LocalizedStringResource = "Try the Clue Again"
    static let isDiscoverable = false

    @Parameter(title: "Day") var day: Double

    init() {}
    init(day: Double) { self.day = day }

    func perform() async throws -> some IntentResult {
        ClueStore.update(day: day) { progress, clue in
            progress.retry(in: clue)
            return []
        }
        return .result()
    }
}

// MARK: - Entry and provider

struct ClueEntry: TimelineEntry {
    let date: Date
    let streak: StreakEntry
    let dailyTitle: String?
    let clue: ClueOfDay?
    var progress = ClueProgress()

    var dayInterval: Double { Calendar.current.startOfDay(for: date).timeIntervalSinceReferenceDate }

    static func make(at date: Date, snapshot: StreakSnapshot, days: [ClueDay]) -> ClueEntry {
        let streak = StreakEntry.make(from: snapshot, at: date)
        let start = Calendar.current.startOfDay(for: date)
        let day = ClueStore.day(start, in: days)
        let clue = day?.puzzle
        return ClueEntry(
            date: date,
            streak: streak,
            dailyTitle: day?.dailyTitle,
            clue: clue,
            progress: clue.map { ClueStore.progress(for: $0, day: start) } ?? ClueProgress()
        )
    }

    static let sample = ClueEntry(
        date: .now,
        streak: StreakEntry(date: .now, streak: 7, state: .streakAtStake),
        dailyTitle: "Shepherds and Kings",
        clue: ClueOfDay(
            clue: "Garden where Adam and Eve first lived",
            answer: "EDEN",
            tiles: ["N", "S", "E", "D", "A", "E"],
            clueReference: "Genesis 2:8",
            verse: "The Lord is my shepherd; I shall not want.",
            reference: "Psalm 23:1"
        )
    )
}

struct ClueProvider: TimelineProvider {
    func placeholder(in context: Context) -> ClueEntry { .sample }

    func getSnapshot(in context: Context, completion: @escaping (ClueEntry) -> Void) {
        if context.isPreview {
            completion(.sample)
        } else {
            completion(.make(at: Date(), snapshot: StreakSnapshot.load(), days: ClueStore.loadDays()))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ClueEntry>) -> Void) {
        let snapshot = StreakSnapshot.load()
        let days = ClueStore.loadDays()
        let calendar = Calendar.current
        let now = Date()
        // Now, then each of the next two midnights: a new clue and a fresh
        // board arrive overnight without the app.
        var entries = [ClueEntry.make(at: now, snapshot: snapshot, days: days)]
        var day = calendar.startOfDay(for: now)
        for _ in 0..<2 {
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
            entries.append(.make(at: next, snapshot: snapshot, days: days))
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

// MARK: - Views

struct ClueWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ClueEntry

    var body: some View {
        if let clue = entry.clue {
            switch family {
            case .accessoryRectangular: ClueLockScreenView(entry: entry, clue: clue)
            case .systemLarge: ClueLargeView(entry: entry, clue: clue)
            default: ClueBoardView(entry: entry, clue: clue, tileSize: 30)
            }
        } else {
            // Nothing published for today (first launch not yet done, or no
            // clue fits): still a doorway to today's puzzle.
            switch family {
            case .accessoryRectangular: RectangularStreakView(entry: entry.streak)
            default: MediumStreakView(entry: entry.streak)
            }
        }
    }
}

/// Header, clue, answer slots and tiles; or, once solved, the verse.
struct ClueBoardView: View {
    let entry: ClueEntry
    let clue: ClueOfDay
    let tileSize: CGFloat
    var verseLines = 2

    private var progress: ClueProgress { entry.progress }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            if progress.solved {
                solved
            } else {
                Text(clue.clue)
                    .font(.footnote.weight(.medium))
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                slots
                if progress.isWrong(clue) {
                    tryAgain
                } else {
                    tiles
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("CLUE OF THE DAY")
                .font(.caption2.weight(.semibold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            if entry.streak.streak > 0 {
                Label("\(entry.streak.streak)", systemImage: entry.streak.state == .solvedToday ? "flame.fill" : "flame")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(entry.streak.flameColor)
                    .widgetAccentable()
                    .accessibilityLabel("\(entry.streak.streak) day streak")
            }
        }
    }

    private var slots: some View {
        let letters = progress.letters(clue)
        let revealed = progress.revealedCount(clue)
        let wrong = progress.isWrong(clue)
        return HStack(spacing: 4) {
            ForEach(0..<clue.answer.count, id: \.self) { index in
                let letter = index < letters.count ? letters[index] : ""
                Text(letter)
                    .font(.system(size: tileSize * 0.52, weight: .bold, design: .rounded))
                    .foregroundStyle(wrong ? Color.red : (index < revealed ? Color.accentColor : Color.primary))
                    .frame(width: tileSize - 4, height: tileSize - 2)
                    .background {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(wrong ? Color.red.opacity(0.6) : Color.secondary.opacity(0.45), lineWidth: 1.5)
                    }
            }
            Spacer(minLength: 0)
            if !wrong, letters.count > revealed {
                Button(intent: DeleteClueLetterIntent(day: entry.dayInterval)) {
                    Image(systemName: "delete.left")
                        .font(.system(size: tileSize * 0.5))
                        .foregroundStyle(.secondary)
                        .frame(width: tileSize, height: tileSize - 2)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete last letter")
            }
        }
        .invalidatableContent()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(slotsLabel(letters))
    }

    private func slotsLabel(_ letters: [String]) -> String {
        let cells = (0..<clue.answer.count).map { $0 < letters.count ? letters[$0] : "blank" }
        return "Answer, \(clue.answer.count) letters: " + cells.joined(separator: ", ")
    }

    private var tiles: some View {
        HStack(spacing: 6) {
            ForEach(Array(clue.tiles.enumerated()), id: \.offset) { index, letter in
                if progress.picks.contains(index) {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(.fill.quaternary)
                        .frame(width: tileSize, height: tileSize)
                        .accessibilityHidden(true)
                } else {
                    Button(intent: PlaceClueLetterIntent(tile: index, day: entry.dayInterval)) {
                        Text(letter)
                            .font(.system(size: tileSize * 0.55, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(width: tileSize, height: tileSize)
                            .background(.tint, in: .rect(cornerRadius: 7, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Letter \(letter)")
                }
            }
        }
    }

    private var tryAgain: some View {
        HStack(spacing: 8) {
            Text("Not quite.")
                .font(.footnote.weight(.semibold))
            Spacer(minLength: 0)
            Button(intent: RetryClueIntent(day: entry.dayInterval)) {
                Label(
                    progress.revealedCount(clue) > 0 ? "Try again with a letter" : "Try again",
                    systemImage: "arrow.counterclockwise"
                )
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.tint, in: .capsule)
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
        .frame(height: tileSize)
    }

    private var solved: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(clue.answer)
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .tracking(2)
                if let reference = clue.clueReference {
                    Text(reference)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .accessibilityElement(children: .combine)
            Text("“\(clue.verse)”")
                .font(.system(.footnote, design: .serif))
                .lineLimit(verseLines)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 0)
            HStack {
                Text(clue.reference)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if !entry.streak.dayIsFinished {
                    Text(entry.streak.target == .mini ? "Play the Mini" : "Play today's puzzle")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.tint, in: .capsule)
                        .foregroundStyle(.white)
                }
            }
        }
    }
}

/// The board on top; the streak and today's puzzle underneath.
struct ClueLargeView: View {
    let entry: ClueEntry
    let clue: ClueOfDay

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ClueBoardView(entry: entry, clue: clue, tileSize: 34, verseLines: 5)
            Divider()
            HStack(spacing: 12) {
                VStack(spacing: 0) {
                    Image(systemName: "flame.fill")
                        .font(.title2)
                        .foregroundStyle(entry.streak.flameColor)
                        .widgetAccentable()
                    Text("\(entry.streak.streak)")
                        .font(.system(.title3, design: .rounded, weight: .bold))
                }
                .frame(minWidth: 44)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(entry.streak.streak) day streak")
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.streak.headline)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(todayLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if entry.streak.dayIsFinished {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.green)
                        .accessibilityLabel("Done for today")
                } else {
                    Text("Play")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.tint, in: .capsule)
                        .foregroundStyle(.white)
                }
            }
            .frame(height: 52)
        }
    }

    private var todayLine: String {
        switch entry.streak.target {
        case .daily: entry.dailyTitle.map { "Today: \($0)" } ?? entry.streak.subline
        case .mini: "Today's Mini is still open"
        case .home: "Come back tomorrow"
        }
    }
}

/// The clue to think about on the way past; answered on the Home Screen.
struct ClueLockScreenView: View {
    let entry: ClueEntry
    let clue: ClueOfDay

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            if entry.progress.solved {
                Label("\(clue.answer) · Solved", systemImage: "checkmark.circle")
                    .font(.headline)
                Text(clue.reference)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Clue of the day · \(clue.answer.count)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(clue.clue)
                    .font(.caption)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Widget

struct BibleCrosswordClueWidget: Widget {
    let kind = "BibleCrosswordClueWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ClueProvider()) { entry in
            ClueWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(entry.streak.deepLinkURL(widget: "clue"))
        }
        .configurationDisplayName("Clue of the Day")
        .description("Solve one clue a day right on your Home Screen, then see today's verse.")
        .supportedFamilies([.systemMedium, .systemLarge, .accessoryRectangular])
    }
}

// MARK: - Previews

private extension ClueEntry {
    func with(picks: [Int], wrong: Int = 0, solved: Bool = false) -> ClueEntry {
        var copy = self
        copy.progress = ClueProgress(
            day: dayInterval, answer: clue?.answer ?? "", picks: picks,
            wrongAttempts: wrong, solved: solved, started: !picks.isEmpty
        )
        return copy
    }
}

#Preview("Clue · medium", as: .systemMedium) {
    BibleCrosswordClueWidget()
} timeline: {
    ClueEntry.sample
    ClueEntry.sample.with(picks: [2, 3])
    ClueEntry.sample.with(picks: [2, 3, 0, 5], wrong: 1)
    ClueEntry.sample.with(picks: [2, 3, 5, 0], solved: true)
}

#Preview("Clue · large", as: .systemLarge) {
    BibleCrosswordClueWidget()
} timeline: {
    ClueEntry.sample.with(picks: [2])
    ClueEntry.sample.with(picks: [2, 3, 5, 0], solved: true)
}
