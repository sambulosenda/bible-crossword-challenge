//
//  EngineTests.swift
//  Bible Crossword ChallengeTests
//
//  Exercises the crossword engine on a tiny, hand-built puzzle.
//

import Testing
import Foundation
@testable import Bible_Crossword_Challenge

private func makePuzzle() -> Puzzle {
    // 3x3:  C A T  /  O . .  /  D . .
    // Across 1 = CAT, Down 1 = COD, sharing the C at (0,0).
    Puzzle(
        id: "test-1",
        title: "Tiny",
        difficulty: .easy,
        verse: "Test verse",
        reference: "Test 1:1",
        publishDate: "2026-07-01",
        size: 3,
        grid: ["CAT", "O..", "D.."],
        clues: [
            ClueData(number: 1, direction: .across, row: 0, col: 0, text: "Feline", answer: "CAT"),
            ClueData(number: 1, direction: .down, row: 0, col: 0, text: "A fish", answer: "COD"),
        ]
    )
}

struct EngineTests {

    @Test func buildsGridAndSlots() {
        let vm = GameViewModel(puzzle: makePuzzle())
        #expect(vm.acrossSlots.count == 1)
        #expect(vm.downSlots.count == 1)
        #expect(vm.cell(at: GridPos(row: 0, col: 0)).solution == "C")
        #expect(vm.cell(at: GridPos(row: 0, col: 0)).number == 1)
        #expect(vm.cell(at: GridPos(row: 1, col: 1)).isBlock)
        #expect(!vm.cell(at: GridPos(row: 2, col: 0)).isBlock)
    }

    @Test func initialSelectionIsFirstAcross() {
        let vm = GameViewModel(puzzle: makePuzzle())
        #expect(vm.selected == GridPos(row: 0, col: 0))
        #expect(vm.direction == .across)
        #expect(vm.activeSlot?.answer == "CAT")
    }

    @Test func entryAutoAdvancesToNextEmptyCell() {
        let vm = GameViewModel(puzzle: makePuzzle())
        vm.enter("C")
        #expect(vm.selected == GridPos(row: 0, col: 1))
        vm.enter("A")
        #expect(vm.selected == GridPos(row: 0, col: 2))
        #expect(vm.cell(at: GridPos(row: 0, col: 1)).entry == "A")
    }

    @Test func tappingSelectedCellTogglesDirection() {
        let vm = GameViewModel(puzzle: makePuzzle())
        #expect(vm.direction == .across)
        vm.select(GridPos(row: 0, col: 0)) // same cell → toggle
        #expect(vm.direction == .down)
        #expect(vm.activeSlot?.answer == "COD")
    }

    @Test func deleteClearsThenStepsBack() {
        let vm = GameViewModel(puzzle: makePuzzle())
        vm.enter("C") // (0,0)=C, selected→(0,1)
        vm.enter("A") // (0,1)=A, selected→(0,2)
        vm.delete()   // (0,2) empty → step back and clear (0,1)
        #expect(vm.cell(at: GridPos(row: 0, col: 1)).entry == nil)
        #expect(vm.selected == GridPos(row: 0, col: 1))
    }

    @Test func completingAllCellsFiresCompletion() {
        let vm = GameViewModel(puzzle: makePuzzle())
        var completedSeconds: Int? = nil
        vm.onComplete = { completedSeconds = $0 }

        vm.enter("C"); vm.enter("A"); vm.enter("T")     // CAT
        #expect(vm.isComplete == false)
        vm.select(GridPos(row: 1, col: 0))              // down COD
        #expect(vm.direction == .down)
        vm.enter("O"); vm.enter("D")                    // O,D (C shared)

        #expect(vm.isComplete == true)
        #expect(completedSeconds != nil)
    }

    @Test func completingAWordFiresWordCompletedOnce() {
        let vm = GameViewModel(puzzle: makePuzzle())
        var completed: [[GridPos]] = []
        vm.onWordCompleted = { completed.append($0.positions) }

        vm.enter("C"); vm.enter("A")     // CAT not finished yet
        #expect(completed.isEmpty)
        vm.enter("T")                    // CAT now complete → fires once
        #expect(completed.count == 1)
        #expect(Set(completed[0]) == Set([
            GridPos(row: 0, col: 0), GridPos(row: 0, col: 1), GridPos(row: 0, col: 2),
        ]))
    }

    @Test func wrongWordDoesNotFireWordCompleted() {
        let vm = GameViewModel(puzzle: makePuzzle())
        var fired = false
        vm.onWordCompleted = { _ in fired = true }
        vm.enter("C"); vm.enter("A"); vm.enter("X")  // CAX is wrong
        #expect(fired == false)
        // The full word auto-advanced selection to the next slot — come back
        // to CAT before judging it.
        vm.select(GridPos(row: 0, col: 2))
        #expect(vm.check(.word) == 1)                // the X is checkably wrong
    }

    @Test func finalWordDoesNotDoubleFireWithCompletion() {
        let vm = GameViewModel(puzzle: makePuzzle())
        var wordEvents = 0
        vm.onWordCompleted = { _ in wordEvents += 1 }
        vm.enter("C"); vm.enter("A"); vm.enter("T")  // CAT completes → 1 event
        vm.select(GridPos(row: 1, col: 0))
        vm.enter("O"); vm.enter("D")                 // COD completes the puzzle
        // The puzzle-completing word defers to onComplete, not a word flash.
        #expect(wordEvents == 1)
        #expect(vm.isComplete)
    }

    @Test func restoredWordsDoNotFlashOnNextKeystroke() {
        let vm = GameViewModel(puzzle: makePuzzle())
        vm.restore(["0,0": "C", "0,1": "A", "0,2": "T"])  // CAT already solved
        var count = 0
        vm.onWordCompleted = { _ in count += 1 }
        vm.select(GridPos(row: 1, col: 0))  // down COD: C filled, O/D empty
        vm.enter("O"); vm.enter("D")        // finishes COD; CAT was seeded silently

        // This fixture only has two words, so COD is also the last one: it
        // defers to onComplete rather than firing a word flash, which
        // `finalWordDoesNotDoubleFireWithCompletion` pins down. `isComplete`
        // is what proves the keystrokes landed at all.
        #expect(vm.isComplete)
        #expect(count == 0)

        // The real subject of this test. Retyping a letter that is already
        // correct touches both CAT and COD; if `restore` hadn't seeded CAT as
        // solved, it would be announced here as though it had just been solved.
        vm.select(GridPos(row: 0, col: 0))
        vm.enter("C")
        #expect(count == 0)
    }

    @Test func wrongEntryIsNotCorrect() {
        let vm = GameViewModel(puzzle: makePuzzle())
        vm.enter("X") // wrong at (0,0)
        let cell = vm.cell(at: GridPos(row: 0, col: 0))
        #expect(cell.entry == "X")
        #expect(cell.isCorrect == false)
    }

    @Test func revealWordFillsActiveSlotCorrectly() {
        let vm = GameViewModel(puzzle: makePuzzle())
        let ok = vm.revealWord()
        #expect(ok)
        #expect(vm.cell(at: GridPos(row: 0, col: 0)).entry == "C")
        #expect(vm.cell(at: GridPos(row: 0, col: 1)).entry == "A")
        #expect(vm.cell(at: GridPos(row: 0, col: 2)).entry == "T")
        #expect(vm.hintsUsed == 1)
    }

    @Test func revealLetterFillsSelectedCell() {
        let vm = GameViewModel(puzzle: makePuzzle())
        vm.select(GridPos(row: 2, col: 0))
        let ok = vm.revealLetter()
        #expect(ok)
        #expect(vm.cell(at: GridPos(row: 2, col: 0)).entry == "D")
    }

    @Test func snapshotAndRestoreRoundTrips() {
        let vm = GameViewModel(puzzle: makePuzzle())
        vm.enter("C"); vm.enter("A")
        let snap = vm.snapshot()
        #expect(snap["0,0"] == "C")
        #expect(snap["0,1"] == "A")

        let vm2 = GameViewModel(puzzle: makePuzzle())
        vm2.restore(snap)
        #expect(vm2.cell(at: GridPos(row: 0, col: 0)).entry == "C")
        #expect(vm2.cell(at: GridPos(row: 0, col: 1)).entry == "A")
    }

    @Test func verseHintBumpsSessionCounter() {
        let vm = GameViewModel(puzzle: makePuzzle())
        // Free rung, no per-clue dedupe: every open counts toward the
        // session counter that feeds abandonment analytics.
        vm.noteVerseHint()
        vm.noteVerseHint()
        #expect(vm.hintsUsed == 2)
    }

    @Test func hintTypeCosts() {
        #expect(HintType.verse.cost == 0)
        #expect(HintType.letter.cost == 1)
        #expect(HintType.word.cost == 2)
    }

    @Test func suppressedTimerAccruesNothing() {
        let vm = GameViewModel(puzzle: makePuzzle())
        vm.isAttachedToWindow = true
        let t0 = Date(timeIntervalSinceReferenceDate: 0)
        vm.tick(now: t0)
        vm.tick(now: t0.addingTimeInterval(1))
        #expect(vm.elapsed() == 1)

        // Reader sheet up: ticks keep arriving (the grid stays attached under
        // a sheet) but none of the covered time may count.
        vm.isTimerSuppressed = true
        vm.tick(now: t0.addingTimeInterval(2))
        vm.tick(now: t0.addingTimeInterval(30))
        #expect(vm.elapsed() == 1)

        // Sheet dismissed: the first tick only re-baselines, so the covered
        // gap still counts for nothing; the next one resumes the clock.
        vm.isTimerSuppressed = false
        vm.tick(now: t0.addingTimeInterval(31))
        vm.tick(now: t0.addingTimeInterval(32))
        #expect(vm.elapsed() == 2)
    }

    @Test func advanceClueWrapsBetweenSlots() {
        let vm = GameViewModel(puzzle: makePuzzle())
        #expect(vm.activeSlot?.answer == "CAT")
        vm.advanceClue(by: 1)
        #expect(vm.activeSlot?.answer == "COD")
        vm.advanceClue(by: 1) // wrap back
        #expect(vm.activeSlot?.answer == "CAT")
    }

    // MARK: - Pencil mode

    @Test func pencilEntryNeverCompletesAnything() {
        let vm = GameViewModel(puzzle: makePuzzle())
        var completedWords = 0
        vm.onWordCompleted = { _ in completedWords += 1 }

        vm.isPencilMode = true
        // Fill the entire grid correctly — but all in pencil.
        vm.enter("C"); vm.enter("A"); vm.enter("T")
        vm.select(GridPos(row: 1, col: 0)); vm.enter("O")
        vm.select(GridPos(row: 2, col: 0)); vm.enter("D")

        #expect(vm.cell(at: GridPos(row: 0, col: 0)).isPencil)
        #expect(!vm.isComplete)
        #expect(completedWords == 0)
        #expect(vm.remainingClueCount == 2)
    }

    @Test func penOverwriteCommitsAPencilledLetter() {
        let vm = GameViewModel(puzzle: makePuzzle())
        vm.isPencilMode = true
        vm.enter("C")
        #expect(vm.cell(at: GridPos(row: 0, col: 0)).isPencil)

        vm.isPencilMode = false
        vm.select(GridPos(row: 0, col: 0))
        vm.enter("C")
        let cell = vm.cell(at: GridPos(row: 0, col: 0))
        #expect(!cell.isPencil)
        #expect(cell.isCorrect)
    }

    @Test func penningTheLastPencilCompletesThePuzzle() {
        let vm = GameViewModel(puzzle: makePuzzle())
        vm.isPencilMode = true
        vm.enter("C"); vm.enter("A"); vm.enter("T")
        vm.select(GridPos(row: 1, col: 0)); vm.enter("O")
        vm.select(GridPos(row: 2, col: 0)); vm.enter("D")
        #expect(!vm.isComplete)

        // Commit each pencilled letter in pen.
        vm.isPencilMode = false
        for pos in [GridPos(row: 0, col: 0), GridPos(row: 0, col: 1), GridPos(row: 0, col: 2),
                    GridPos(row: 1, col: 0), GridPos(row: 2, col: 0)] {
            vm.select(pos)
            vm.enter(vm.cell(at: pos).entry!)
        }
        #expect(vm.isComplete)
    }

    @Test func revealConvertsPencilToLockedPen() {
        let vm = GameViewModel(puzzle: makePuzzle())
        vm.isPencilMode = true
        vm.enter("C") // correct letter, but pencilled
        vm.select(GridPos(row: 0, col: 0))

        vm.isPencilMode = false
        #expect(vm.revealLetter())
        let cell = vm.cell(at: GridPos(row: 0, col: 0))
        #expect(!cell.isPencil)
        #expect(cell.isRevealed)
        #expect(cell.entry == "C")
    }

    @Test func snapshotSeparatesPenFromPencil() {
        let vm = GameViewModel(puzzle: makePuzzle())
        vm.enter("C")                       // pen
        vm.isPencilMode = true
        vm.enter("X")                       // pencil at (0,1)
        #expect(vm.snapshot() == ["0,0": "C"])
        #expect(vm.pencilSnapshot() == ["0,1": "X"])

        let vm2 = GameViewModel(puzzle: makePuzzle())
        vm2.restore(vm.snapshot(), pencil: vm.pencilSnapshot())
        #expect(vm2.cell(at: GridPos(row: 0, col: 0)).entry == "C")
        #expect(!vm2.cell(at: GridPos(row: 0, col: 0)).isPencil)
        #expect(vm2.cell(at: GridPos(row: 0, col: 1)).entry == "X")
        #expect(vm2.cell(at: GridPos(row: 0, col: 1)).isPencil)
    }

    /// Pins the entries encoding: lowercase means hint-revealed (locked).
    /// The case of the stored value is load-bearing — see `snapshot()`.
    @Test func lowercaseSnapshotValueMarksRevealedCell() {
        let vm = GameViewModel(puzzle: makePuzzle())
        vm.enter("C")
        #expect(vm.revealLetter()) // reveals A at (0,1)
        let snap = vm.snapshot()
        #expect(snap["0,0"] == "C")
        #expect(snap["0,1"] == "a")

        let vm2 = GameViewModel(puzzle: makePuzzle())
        vm2.restore(snap)
        #expect(!vm2.cell(at: GridPos(row: 0, col: 0)).isRevealed)
        #expect(vm2.cell(at: GridPos(row: 0, col: 1)).isRevealed)
    }

    // MARK: - Granular check

    @Test func checkWordMarksOnlyInScopeWrongCells() {
        let vm = GameViewModel(puzzle: makePuzzle())
        vm.enter("C"); vm.enter("X")                     // CAT: C right, X wrong
        vm.select(GridPos(row: 1, col: 0)); vm.enter("Z") // COD: Z wrong, other word
        vm.select(GridPos(row: 0, col: 0))
        vm.direction = .across

        var reported: (correct: Int, wrong: Int)?
        vm.onCheckResult = { correct, wrong in reported = (correct.count, wrong) }
        #expect(vm.check(.word) == 1)

        #expect(vm.cell(at: GridPos(row: 0, col: 1)).isCheckedWrong)
        #expect(!vm.cell(at: GridPos(row: 0, col: 0)).isCheckedWrong)
        // The wrong letter in the other word is out of scope.
        #expect(!vm.cell(at: GridPos(row: 1, col: 0)).isCheckedWrong)
        #expect(reported?.correct == 1)
        #expect(reported?.wrong == 1)
    }

    @Test func editingAMarkedCellClearsTheMark() {
        let vm = GameViewModel(puzzle: makePuzzle())
        vm.enter("X")
        vm.select(GridPos(row: 0, col: 0))
        _ = vm.check(.letter)
        #expect(vm.cell(at: GridPos(row: 0, col: 0)).isCheckedWrong)

        vm.enter("C")
        #expect(!vm.cell(at: GridPos(row: 0, col: 0)).isCheckedWrong)
    }

    @Test func checkNeverTouchesTheHintEconomy() {
        let vm = GameViewModel(puzzle: makePuzzle())
        vm.enter("X"); vm.enter("A")
        _ = vm.check(.puzzle)
        #expect(vm.hintsUsed == 0)
        // Nothing revealed, nothing filled in.
        #expect(vm.cell(at: GridPos(row: 0, col: 0)).entry == "X")
        #expect(!vm.cell(at: GridPos(row: 0, col: 0)).isRevealed)
    }

    @Test func checkWithNothingFilledReturnsNil() {
        let vm = GameViewModel(puzzle: makePuzzle())
        #expect(vm.check(.puzzle) == nil)
        #expect(vm.check(.letter) == nil)
    }

    // MARK: - Reveal puzzle

    @Test func revealPuzzleCompletesAndLocks() {
        let vm = GameViewModel(puzzle: makePuzzle())
        vm.enter("C")          // player's own correct pen letter
        vm.isPencilMode = true
        vm.enter("X")          // wrong pencil at (0,1)

        #expect(vm.revealPuzzle())
        #expect(vm.isComplete)
        #expect(vm.hintsUsed == 1)
        // The player's own correct letter stays unlocked; everything the
        // reveal touched (including the pencil cell) is locked pen.
        #expect(!vm.cell(at: GridPos(row: 0, col: 0)).isRevealed)
        let fixed = vm.cell(at: GridPos(row: 0, col: 1))
        #expect(fixed.entry == "A")
        #expect(fixed.isRevealed)
        #expect(!fixed.isPencil)
    }

    @Test func revealPuzzleRefusesWhenAlreadySolved() {
        let vm = GameViewModel(puzzle: makePuzzle())
        vm.enter("C"); vm.enter("A"); vm.enter("T")
        vm.select(GridPos(row: 1, col: 0)); vm.enter("O")
        vm.select(GridPos(row: 2, col: 0)); vm.enter("D")
        #expect(vm.isComplete)
        #expect(!vm.revealPuzzle())
        #expect(vm.hintsUsed == 0)
    }
}
