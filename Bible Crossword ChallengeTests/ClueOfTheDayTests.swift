//
//  ClueOfTheDayTests.swift
//  Bible Crossword ChallengeTests
//
//  The bundled rounds, the day's pick and one round's play.
//

import Foundation
import Testing
@testable import Bible_Crossword_Challenge

struct ClueOfTheDayTests {
    private let day = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func round(_ id: String, _ answer: String) -> ClueRound {
        ClueRound(id: id, answer: answer, clues: ["one", "two", "three", "four"], reference: "John 1:1", verse: "In the beginning")
    }

    // MARK: Content

    @Test func bundledRoundsAreWellFormed() {
        let rounds = ClueOfTheDay.rounds
        #expect(rounds.count >= 100)
        #expect(Set(rounds.map(\.id)).count == rounds.count)
        #expect(Set(rounds.map(\.answer)).count == rounds.count)
        for round in rounds {
            // 3–6 letters: what the Clue of the Day widget can lay out.
            #expect((3...6).contains(round.answer.count), "\(round.id)")
            #expect(round.answer.unicodeScalars.allSatisfy { ("A"..."Z").contains($0) }, "\(round.id)")
            #expect(round.clues.count == 4, "\(round.id)")
            #expect(Set(round.clues).count == 4, "\(round.id)")
            for clue in round.clues {
                #expect(!clue.uppercased().contains(round.answer), "\(round.id) gives its answer away: \(clue)")
            }
        }
    }

    /// The verse text is written into the file when it is built; it must
    /// still be the bundled Bible's.
    @Test func bundledVersesMatchTheBible() throws {
        let scripture = ScriptureProvider(bundle: .main)
        for round in ClueOfTheDay.rounds {
            let ref = try #require(ScriptureRef(round.reference), "\(round.id)")
            let chapter = try #require(scripture.chapter(ref)?.chapter, "\(round.id)")
            let verse = chapter.verses.first { $0.number == ref.verse }
            #expect(verse?.text == round.verse, "\(round.id) \(round.reference)")
        }
    }

    // MARK: The day's pick

    @Test func pickWalksTheFileAndWraps() {
        let rounds = (0..<6).map { round("clue-\($0)", "A\($0)") }
        #expect(ClueOfTheDay.round(dayIndex: 0, in: rounds)?.id == "clue-0")
        #expect(ClueOfTheDay.round(dayIndex: 5, in: rounds)?.id == "clue-5")
        #expect(ClueOfTheDay.round(dayIndex: 6, in: rounds)?.id == "clue-0")
        #expect(ClueOfTheDay.round(dayIndex: -1, in: rounds)?.id == "clue-5")
        #expect(ClueOfTheDay.round(dayIndex: 3, in: []) == nil)
    }

    @Test func pickStepsAsideForAnAnswerInTodaysGrids() {
        let rounds = (0..<6).map { round("clue-\($0)", "A\($0)") }
        // Half the file away, so tomorrow's own pick (clue-2) isn't borrowed.
        #expect(ClueOfTheDay.round(dayIndex: 1, avoiding: ["A1"], in: rounds)?.id == "clue-4")
        #expect(ClueOfTheDay.round(dayIndex: 1, avoiding: ["A1", "A4"], in: rounds)?.id == "clue-5")
        // Nothing left to step to: play the day's own rather than nothing.
        #expect(ClueOfTheDay.round(dayIndex: 1, avoiding: Set(rounds.map(\.answer)), in: rounds)?.id == "clue-1")
    }

    @Test func todaysRoundIsNotAnAnswerInTodaysGrids() throws {
        let provider = PuzzleProvider.shared
        let picked = try #require(ClueOfTheDay.round(on: day))
        let grids = [provider.dailyPuzzle(for: day), provider.dailyMini(for: day)].compactMap { $0 }
        let answers = Set(grids.flatMap { $0.clues.map { $0.answer.uppercased() } })
        #expect(!answers.contains(picked.answer))
    }

    @Test func aFinishedRoundPointsAtTheCrosswordThenTheMiniThenNothing() throws {
        let provider = PuzzleProvider.shared
        let daily = try #require(provider.dailyPuzzle(for: day))
        let mini = try #require(provider.dailyMini(for: day))
        #expect(ClueOfTheDay.nextPuzzle(on: day) { _ in false }?.id == daily.id)
        #expect(ClueOfTheDay.nextPuzzle(on: day) { $0.id == daily.id }?.id == mini.id)
        #expect(ClueOfTheDay.nextPuzzle(on: day) { _ in true } == nil)
    }

    // MARK: Play

    @Test func rightSpellingSolvesOnTheLastLetter() {
        var game = ClueGame(round: round("clue-1", "ARK"), day: day)
        do { let result = game.type("a"); #expect(result == nil) }
        do { let result = game.type("R"); #expect(result == nil) }
        do { let result = game.type("K"); #expect(result == .solved) }
        #expect(game.progress.outcome == .solved)
        #expect(game.progress.cluesShown == 1)
        // A finished round takes no more keys.
        do { let result = game.type("X"); #expect(result == nil) }
        game.delete()
        #expect(game.entry == "ARK")
    }

    @Test func wrongSpellingCountsAndTheNextKeyStartsAgain() {
        var game = ClueGame(round: round("clue-1", "ARK"), day: day)
        _ = game.type("A"); _ = game.type("R")
        do { let result = game.type("M"); #expect(result == .wrong) }
        #expect(game.isWrong)
        #expect(game.progress.wrongGuesses == 1)
        do { let result = game.type("A"); #expect(result == nil) }
        #expect(game.entry == "A")
        #expect(!game.isWrong)
    }

    @Test func deleteTakesBackOneLetterAndClearsTheWrongState() {
        var game = ClueGame(round: round("clue-1", "ARK"), day: day)
        "ARM".forEach { _ = game.type($0) }
        game.delete()
        #expect(game.entry == "AR")
        #expect(!game.isWrong)
        do { let result = game.type("K"); #expect(result == .solved) }
    }

    @Test func nonLettersAreIgnored() {
        var game = ClueGame(round: round("clue-1", "ARK"), day: day)
        do { let result = game.type("1"); #expect(result == nil) }
        do { let result = game.type(" "); #expect(result == nil) }
        #expect(game.entry.isEmpty)
    }

    @Test func cluesRevealOneAtATimeThenTheAnswer() {
        var game = ClueGame(round: round("clue-1", "ARK"), day: day)
        #expect(Array(game.visibleClues) == ["one"])
        // The answer isn't offered while an easier clue is left.
        do { let result = game.showAnswer(); #expect(!result) }
        do { let result = game.revealClue(); #expect(result) }
        do { let result = game.revealClue(); #expect(result) }
        do { let result = game.revealClue(); #expect(result) }
        #expect(game.progress.cluesShown == 4)
        do { let result = game.revealClue(); #expect(!result) }
        do { let result = game.showAnswer(); #expect(result) }
        #expect(game.progress.outcome == .missed)
        #expect(game.entry == "ARK")
    }

    // MARK: Saved progress

    @Test func savedProgressComesBackOnTheSameDayOnly() {
        let ark = round("clue-1", "ARK")
        var game = ClueGame(round: ark, day: day)
        _ = game.revealClue()
        let saved = game.progress

        #expect(ClueGame(round: ark, day: day, saved: saved).progress.cluesShown == 2)
        let tomorrow = day.addingTimeInterval(86_400)
        #expect(ClueGame(round: ark, day: tomorrow, saved: saved).progress.cluesShown == 1)
        #expect(ClueGame(round: round("clue-2", "OIL"), day: day, saved: saved).progress.cluesShown == 1)
    }

    @Test func aSolvedRoundReopensShowingItsAnswer() {
        let ark = round("clue-1", "ARK")
        var game = ClueGame(round: ark, day: day)
        "ARK".forEach { _ = game.type($0) }
        let reopened = ClueGame(round: ark, day: day, saved: game.progress)
        #expect(reopened.isFinished)
        #expect(reopened.entry == "ARK")
    }

    @Test func todayRowSummaries() {
        var progress = ClueProgress(day: 0, roundID: "clue-1")
        #expect(progress.summary(clueCount: 4) == "Clue 1 of 4")
        progress.cluesShown = 3
        progress.outcome = .solved
        #expect(progress.summary(clueCount: 4) == "Solved in 3 clues")
        progress.cluesShown = 1
        #expect(progress.summary(clueCount: 4) == "Solved in 1 clue")
    }
}
