//
//  EngineTests.swift
//  Bible Crossword ChallengeTests
//
//  Exercises the crossword engine on a tiny, hand-built puzzle.
//

import Testing
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
        vm.onWordCompleted = { completed.append($0) }

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
        #expect(vm.hasVisibleErrors == true)
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
        var fired = false
        vm.onWordCompleted = { _ in fired = true }
        vm.select(GridPos(row: 1, col: 0))  // down COD: C filled, O/D empty
        vm.enter("O"); vm.enter("D")        // finishes COD; CAT was seeded silently
        #expect(fired == true)  // COD fires
        // CAT must not re-fire — only one event total.
        var count = 0
        vm.onWordCompleted = { _ in count += 1 }
        vm.select(GridPos(row: 0, col: 0))
        vm.enter("C")  // retyping an already-correct, already-tracked letter
        #expect(count == 0)
    }

    @Test func showErrorsFlagsWrongEntries() {
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

    @Test func advanceClueWrapsBetweenSlots() {
        let vm = GameViewModel(puzzle: makePuzzle())
        #expect(vm.activeSlot?.answer == "CAT")
        vm.advanceClue(by: 1)
        #expect(vm.activeSlot?.answer == "COD")
        vm.advanceClue(by: 1) // wrap back
        #expect(vm.activeSlot?.answer == "CAT")
    }
}
