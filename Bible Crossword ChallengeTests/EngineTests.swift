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

    @Test func verseHintChargesOncePerSlot() {
        let vm = GameViewModel(puzzle: makePuzzle())
        let slot = vm.acrossSlots[0]
        #expect(!vm.hasVerseHinted(slot))

        vm.markVerseHinted(slot)
        #expect(vm.hasVerseHinted(slot))
        #expect(vm.hintsUsed == 1)

        // Re-reading the same passage is free — no second charge.
        vm.markVerseHinted(slot)
        #expect(vm.hintsUsed == 1)

        // A different slot is a fresh charge.
        vm.markVerseHinted(vm.downSlots[0])
        #expect(vm.hintsUsed == 2)
    }

    @Test func verseHintTouchesNoCells() {
        let vm = GameViewModel(puzzle: makePuzzle())
        vm.markVerseHinted(vm.acrossSlots[0])
        for pos in vm.acrossSlots[0].positions {
            #expect(vm.cell(at: pos).entry == nil)
            #expect(!vm.cell(at: pos).isRevealed)
        }
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
}
