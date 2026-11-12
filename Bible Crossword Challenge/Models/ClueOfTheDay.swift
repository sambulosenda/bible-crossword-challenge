//
//  ClueOfTheDay.swift
//  Bible Crossword Challenge
//
//  Clue of the Day (2026-11-12): one answer a day, up to four crossword
//  clues for it, hardest first. The result is how many clues it took. A
//  second, thirty-second reason to open the app, and crossword solving rather
//  than trivia: every clue is one already written for a grid.
//
//  The rules are plain values here, the same pattern as `ReviewAsk`, so the
//  day's pick and a round's play are testable without SwiftUI. The view owns
//  persistence and analytics.
//
//  Free for everyone, and it does not keep the streak: a thirty-second clue
//  that did would become the way to skip the crossword.
//

import Foundation

/// One day's round, from the bundled `clue_ladders.json`.
struct ClueRound: Codable, Identifiable, Equatable {
    /// Content-stable (`clue-001`): saved progress names it. Never renumber.
    let id: String
    /// Upper-case A–Z.
    let answer: String
    /// Hardest first, easiest last.
    let clues: [String]
    /// Where the closing verse is from, e.g. "Exodus 16:31".
    let reference: String
    /// The verse's text, written into the file when it is built so the round
    /// never has to decode the whole Bible to show one line.
    let verse: String
}

enum ClueOfTheDay {
    /// The bundled rounds, in file order. Empty if the file is missing, which
    /// hides the feature rather than crashing it.
    static let rounds: [ClueRound] = load(bundle: .main)

    static func load(bundle: Bundle) -> [ClueRound] {
        guard let url = bundle.url(forResource: "clue_ladders", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let rounds = try? JSONDecoder().decode([ClueRound].self, from: data)
        else {
            assertionFailure("clue_ladders.json missing or unreadable")
            return []
        }
        return rounds
    }

    /// The round for the day at `dayIndex` (whole days from the content
    /// epoch, as `PuzzleProvider.dayIndex` counts them): the same one for
    /// every player, walking the file in order and wrapping.
    ///
    /// `avoiding` is the answers in today's grids. A round whose answer the
    /// player is about to meet there would give it away, so that day takes
    /// the round half the file away instead: far enough that tomorrow's own
    /// pick is not the one borrowed today.
    static func round(dayIndex: Int, avoiding: Set<String> = [], in rounds: [ClueRound] = rounds) -> ClueRound? {
        guard !rounds.isEmpty else { return nil }
        let count = rounds.count
        let start = ((dayIndex % count) + count) % count
        if !avoiding.contains(rounds[start].answer) { return rounds[start] }
        for step in 0..<count {
            let candidate = rounds[(start + count / 2 + step) % count]
            if !avoiding.contains(candidate.answer) { return candidate }
        }
        return rounds[start]
    }

    /// Today's round, steering clear of the answers in today's daily and Mini.
    static func round(on day: Date, provider: PuzzleProvider = .shared, calendar: Calendar = .current) -> ClueRound? {
        let grids = [provider.dailyPuzzle(for: day, calendar: calendar), provider.dailyMini(for: day, calendar: calendar)]
        let answers = Set(grids.compactMap { $0 }.flatMap { $0.clues.map { $0.answer.uppercased() } })
        return round(dayIndex: provider.dayIndex(for: day, calendar: calendar), avoiding: answers)
    }

    /// What a finished round points at: today's crossword while it is
    /// unfinished, then the Mini, then nothing. The clue is the short way
    /// in; the grid is what the app is for.
    static func nextPuzzle(
        on day: Date,
        provider: PuzzleProvider = .shared,
        calendar: Calendar = .current,
        isFinishedToday: (Puzzle) -> Bool
    ) -> Puzzle? {
        [provider.dailyPuzzle(for: day, calendar: calendar), provider.dailyMini(for: day, calendar: calendar)]
            .compactMap { $0 }
            .first { !isFinishedToday($0) }
    }
}

/// Where a player stands in one day's round. Saved between visits.
struct ClueProgress: Codable, Equatable {
    enum Outcome: String, Codable {
        case solved
        /// The answer was shown after the last clue.
        case missed
    }

    /// Start of the day the round belongs to, as a reference-date interval.
    var day: Double
    var roundID: String
    /// How many clues are on screen, from 1.
    var cluesShown = 1
    /// Full wrong spellings so far.
    var wrongGuesses = 0
    var outcome: Outcome?

    func belongs(to round: ClueRound, on day: Date) -> Bool {
        roundID == round.id && self.day == day.timeIntervalSinceReferenceDate
    }
}

/// One round in play: the letters typed and what each key does to them.
struct ClueGame: Equatable {
    enum Result: Equatable {
        case solved
        case wrong
    }

    let round: ClueRound
    var progress: ClueProgress
    /// The letters typed so far, upper-case, at most the answer's length.
    private(set) var entry = ""
    /// The row is full and wrong. The next key starts it again.
    private(set) var isWrong = false

    init(round: ClueRound, day: Date, saved: ClueProgress? = nil) {
        self.round = round
        if let saved, saved.belongs(to: round, on: day) {
            progress = saved
        } else {
            progress = ClueProgress(day: day.timeIntervalSinceReferenceDate, roundID: round.id)
        }
        if progress.outcome != nil { entry = round.answer }
    }

    var isFinished: Bool { progress.outcome != nil }
    var visibleClues: ArraySlice<String> { round.clues.prefix(progress.cluesShown) }
    var hasEasierClue: Bool { progress.cluesShown < round.clues.count }

    /// Types a letter. A full row is checked at once, as a grid checks a
    /// finished word; nothing is returned until the row is full.
    mutating func type(_ character: Character) -> Result? {
        guard !isFinished else { return nil }
        let letter = String(character).uppercased()
        guard letter.count == 1, letter.unicodeScalars.allSatisfy({ ("A"..."Z").contains($0) }) else { return nil }
        if isWrong {
            entry = ""
            isWrong = false
        }
        guard entry.count < round.answer.count else { return nil }
        entry += letter
        guard entry.count == round.answer.count else { return nil }
        if entry == round.answer {
            progress.outcome = .solved
            return .solved
        }
        progress.wrongGuesses += 1
        isWrong = true
        return .wrong
    }

    mutating func delete() {
        guard !isFinished, !entry.isEmpty else { return }
        entry.removeLast()
        isWrong = false
    }

    /// Shows the next, easier clue. False when the last one is already up.
    mutating func revealClue() -> Bool {
        guard !isFinished, hasEasierClue else { return false }
        progress.cluesShown += 1
        return true
    }

    /// Shows the answer. Only once every clue has been seen.
    mutating func showAnswer() -> Bool {
        guard !isFinished, !hasEasierClue else { return false }
        progress.outcome = .missed
        entry = round.answer
        isWrong = false
        return true
    }
}

extension ClueProgress {
    /// The Today row's line for this state.
    func summary(clueCount: Int) -> String {
        switch outcome {
        case .solved: cluesShown == 1 ? "Solved in 1 clue" : "Solved in \(cluesShown) clues"
        case .missed: "Come back tomorrow for a new one"
        case nil: "Clue \(cluesShown) of \(clueCount)"
        }
    }
}
