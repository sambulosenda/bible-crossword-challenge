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

    @Test func initialSelectionIsTheShortestAnswer() {
        // 4x4: LAMB across the top, AX down from its A — AX (2) beats LAMB (4),
        // so the session opens on the easiest foothold, not 1 Across.
        let vm = GameViewModel(puzzle: Puzzle(
            id: "test-easiest",
            title: "Tiny",
            difficulty: .easy,
            verse: "Test verse",
            reference: "Test 1:1",
            publishDate: "2026-07-01",
            size: 4,
            grid: ["LAMB", ".X..", "....", "...."],
            clues: [
                ClueData(number: 1, direction: .across, row: 0, col: 0, text: "Passover animal", answer: "LAMB"),
                ClueData(number: 2, direction: .down, row: 0, col: 1, text: "Chopping tool", answer: "AX"),
            ]
        ))
        #expect(vm.activeSlot?.answer == "AX")
        #expect(vm.selected == GridPos(row: 0, col: 1))
    }

    @Test func initialSelectionTiesGoAcross() {
        // CAT across vs COD down, both 3 letters — the tie keeps the
        // conventional 1-Across start.
        let vm = GameViewModel(puzzle: makePuzzle())
        #expect(vm.activeSlot?.answer == "CAT")
        #expect(vm.direction == .across)
    }

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

    // MARK: - Stall nudge
    //
    // The tiered rescue, each tier once per session on the active clock: at
    // ≥ 40% fill, `stallNudgeSeconds` idle fires the check tier; under 40%,
    // the shorter `earlyNudgeSeconds` idle fires the free-letter tier.
    // The fixture has 5 playable cells, so 4 filled = 80% and 1 filled = 20%.

    /// Advance the active clock by `seconds` of rendered ticks.
    private func idle(_ vm: GameViewModel, seconds: Int, from start: Int = 0) {
        let t0 = Date(timeIntervalSinceReferenceDate: Double(start))
        vm.tick(now: t0)
        for s in 1...seconds {
            vm.tick(now: t0.addingTimeInterval(Double(s)))
        }
    }

    private func fillFourOfFive(_ vm: GameViewModel) {
        vm.enter("C"); vm.enter("A"); vm.enter("T")
        vm.select(GridPos(row: 1, col: 0)); vm.enter("X")   // wrong on purpose
    }

    @Test func stallNudgeFiresOnceWhenIdleAtHighFill() {
        let vm = GameViewModel(puzzle: makePuzzle())
        vm.isAttachedToWindow = true
        fillFourOfFive(vm)
        #expect(!vm.isComplete)

        idle(vm, seconds: vm.stallNudgeSeconds + 1)
        #expect(vm.stallNudgeTick == 1)
        #expect(vm.stallNudgeKind == .checkAnswers)
        #expect(vm.isStallNudgeActive)

        // Keep idling: once per session, never a second nag.
        idle(vm, seconds: vm.stallNudgeSeconds + 1, from: 1000)
        #expect(vm.stallNudgeTick == 1)
    }

    @Test func lowFillIdleFiresTheFreeLetterTier() {
        let vm = GameViewModel(puzzle: makePuzzle())
        vm.isAttachedToWindow = true
        vm.enter("C")                                       // 1 of 5 = 20%
        idle(vm, seconds: vm.earlyNudgeSeconds + 1)
        #expect(vm.stallNudgeTick == 1)
        #expect(vm.stallNudgeKind == .freeLetter)
        #expect(vm.isStallNudgeActive)

        // Once per session for this tier too.
        idle(vm, seconds: vm.earlyNudgeSeconds + 1, from: 1000)
        #expect(vm.stallNudgeTick == 1)
    }

    @Test func earlyTierWaitsItsOwnThreshold() {
        let vm = GameViewModel(puzzle: makePuzzle())
        vm.isAttachedToWindow = true
        // Empty grid — even zero fill is eligible, but not before the idle.
        idle(vm, seconds: vm.earlyNudgeSeconds - 5)
        #expect(vm.stallNudgeTick == 0)
        idle(vm, seconds: 6, from: 1000)
        #expect(vm.stallNudgeTick == 1)
        #expect(vm.stallNudgeKind == .freeLetter)
    }

    @Test func eachTierFiresIndependently() {
        // Early tier at low fill, then the check tier after crossing 40% —
        // one session can be rescued twice, once per shape of stuck.
        let vm = GameViewModel(puzzle: makePuzzle())
        vm.isAttachedToWindow = true
        idle(vm, seconds: vm.earlyNudgeSeconds + 1)
        #expect(vm.stallNudgeTick == 1)

        fillFourOfFive(vm)                                  // 80%, clears the line
        #expect(!vm.isStallNudgeActive)
        idle(vm, seconds: vm.stallNudgeSeconds + 1, from: 1000)
        #expect(vm.stallNudgeTick == 2)
        #expect(vm.stallNudgeKind == .checkAnswers)
    }

    @Test func stallNudgeFiresAtThresholdFill() {
        let vm = GameViewModel(puzzle: makePuzzle())
        vm.isAttachedToWindow = true
        vm.enter("C"); vm.enter("A")                        // 2 of 5 = 40%, the gate
        idle(vm, seconds: vm.stallNudgeSeconds + 5)
        #expect(vm.stallNudgeTick == 1)
        #expect(vm.stallNudgeKind == .checkAnswers)
    }

    @Test func inputResetsTheStallClock() {
        let vm = GameViewModel(puzzle: makePuzzle())
        vm.isAttachedToWindow = true
        fillFourOfFive(vm)

        let half = vm.stallNudgeSeconds / 2
        idle(vm, seconds: half)
        vm.select(GridPos(row: 2, col: 0))                  // any deliberate action
        idle(vm, seconds: half + 5, from: 500)
        // Only ~half the threshold has passed since the selection.
        #expect(vm.stallNudgeTick == 0)
    }

    @Test func inputDismissesAnActiveNudge() {
        let vm = GameViewModel(puzzle: makePuzzle())
        vm.isAttachedToWindow = true
        fillFourOfFive(vm)
        idle(vm, seconds: vm.stallNudgeSeconds + 1)
        #expect(vm.isStallNudgeActive)

        vm.delete()
        #expect(!vm.isStallNudgeActive)
        #expect(vm.stallNudgeTick == 1)
    }

    @Test func resumingSeededTimeIsNotIdling() {
        let vm = GameViewModel(puzzle: makePuzzle())
        vm.isAttachedToWindow = true
        fillFourOfFive(vm)
        vm.seedElapsed(3600)
        // A couple of rendered ticks after resume must not read the carried
        // hour as a stall.
        idle(vm, seconds: 3, from: 5000)
        #expect(vm.stallNudgeTick == 0)
    }

    // MARK: - Starter word gift (first-session guaranteed win)

    @Test func giftFillsTheStarterWordWithoutSpendingAHint() {
        let vm = GameViewModel(puzzle: makePuzzle())
        let gifted = vm.giftStarterWord()
        // Initial selection is CAT (ties go across), so that's the gift.
        #expect(gifted?.answer == "CAT")
        #expect(vm.cell(at: GridPos(row: 0, col: 0)).entry == "C")
        #expect(vm.cell(at: GridPos(row: 0, col: 1)).entry == "A")
        #expect(vm.cell(at: GridPos(row: 0, col: 2)).entry == "T")
        #expect(vm.hintsUsed == 0)
        #expect(!vm.isComplete)
    }

    @Test func giftLocksItsCellsLikeAReveal() {
        let vm = GameViewModel(puzzle: makePuzzle())
        vm.giftStarterWord()
        // Locked: typing over a gifted cell skips it, deleting leaves it.
        vm.select(GridPos(row: 0, col: 1))
        vm.enter("X")
        #expect(vm.cell(at: GridPos(row: 0, col: 1)).entry == "A")
        vm.select(GridPos(row: 0, col: 1))
        vm.delete()
        #expect(vm.cell(at: GridPos(row: 0, col: 1)).entry == "A")
        // And it persists as a reveal (lowercase in the snapshot), so a
        // relaunch restores the gift still locked.
        #expect(vm.snapshot()["0,1"] == "a")
    }

    // MARK: - Next-word selection after a solve

    @Test func finishedWordAdvancesToItsCrossingWord() {
        // CAT across crossed by COW down, plus BEE across far below. The old
        // across-then-down wrap picked BEE (next across in order); the
        // crossing word — which already holds the C the player just typed —
        // is the natural foothold.
        let vm = GameViewModel(puzzle: Puzzle(
            id: "test-crossing",
            title: "Tiny",
            difficulty: .easy,
            verse: "Test verse",
            reference: "Test 1:1",
            publishDate: "2026-07-01",
            size: 5,
            grid: ["CAT..", "O....", "W....", ".....", "BEE.."],
            clues: [
                ClueData(number: 1, direction: .across, row: 0, col: 0, text: "Feline", answer: "CAT"),
                ClueData(number: 1, direction: .down, row: 0, col: 0, text: "Bovine", answer: "COW"),
                ClueData(number: 5, direction: .across, row: 4, col: 0, text: "Buzzer", answer: "BEE"),
            ]
        ))
        #expect(vm.activeSlot?.answer == "CAT")
        vm.enter("C"); vm.enter("A"); vm.enter("T")
        #expect(vm.activeSlot?.answer == "COW")
        #expect(vm.cell(at: vm.selected).entry == nil)
    }

    @Test func withNoCrossingWordTheNearestIncompleteWins() {
        // AX at the top-left touches nothing. BY sits three cells away, ZOO
        // five — the old wrap order (across before down) picked ZOO and
        // teleported the cursor across the grid.
        let vm = GameViewModel(puzzle: Puzzle(
            id: "test-nearest",
            title: "Tiny",
            difficulty: .easy,
            verse: "Test verse",
            reference: "Test 1:1",
            publishDate: "2026-07-01",
            size: 5,
            grid: ["AX..B", "....Y", ".....", ".....", "..ZOO"],
            clues: [
                ClueData(number: 1, direction: .across, row: 0, col: 0, text: "Tool", answer: "AX"),
                ClueData(number: 2, direction: .down, row: 0, col: 4, text: "Beside", answer: "BY"),
                ClueData(number: 3, direction: .across, row: 4, col: 2, text: "Animals", answer: "ZOO"),
            ]
        ))
        #expect(vm.activeSlot?.answer == "AX")
        vm.enter("A"); vm.enter("X")
        #expect(vm.activeSlot?.answer == "BY")
    }

    // MARK: - Locked-cell feedback

    @Test func typingOnALockedCellAnnouncesTheSkip() {
        let vm = GameViewModel(puzzle: makePuzzle())
        vm.giftStarterWord()                                // locks CAT
        vm.select(GridPos(row: 0, col: 1))
        vm.enter("X")
        #expect(vm.lockedEntryTick == 1)
        #expect(vm.lockedEntryPos == GridPos(row: 0, col: 1))
        #expect(vm.cell(at: GridPos(row: 0, col: 1)).entry == "A")
    }

    @Test func normalTypingNeverTicksLockedFeedback() {
        let vm = GameViewModel(puzzle: makePuzzle())
        vm.enter("C"); vm.enter("A")
        vm.delete()
        #expect(vm.lockedEntryTick == 0)
    }

    @Test func giftMovesSelectionToACrossingWord() {
        let vm = GameViewModel(puzzle: makePuzzle())
        vm.giftStarterWord()
        // The player should land on a word that still needs letters, not sit
        // on the solved gift.
        #expect(vm.activeSlot?.answer == "COD")
        #expect(vm.cell(at: vm.selected).entry == nil)
    }

    @Test func restoreSkipsAFilledOpeningSelection() {
        // Solve the opening word (CAT), save, and resume: the restored session
        // must not park the player on the done word — the gifted starter word
        // makes this the common first-resume shape.
        let vm = GameViewModel(puzzle: makePuzzle())
        vm.giftStarterWord()
        let snap = vm.snapshot()

        let vm2 = GameViewModel(puzzle: makePuzzle())
        vm2.restore(snap)
        #expect(vm2.activeSlot?.answer == "COD")
        #expect(vm2.cell(at: vm2.selected).entry == nil)
    }

    @Test func restoreKeepsAnUnfinishedOpeningSelection() {
        let vm = GameViewModel(puzzle: makePuzzle())
        vm.enter("C")
        let snap = vm.snapshot()

        // CAT still has empty cells, so the opening selection stands.
        let vm2 = GameViewModel(puzzle: makePuzzle())
        vm2.restore(snap)
        #expect(vm2.activeSlot?.answer == "CAT")
    }

    @Test func giftRefusesWhenTheGridHasAnyProgress() {
        let vm = GameViewModel(puzzle: makePuzzle())
        vm.enter("C")
        #expect(vm.giftStarterWord() == nil)
        // The typed letter (and everything else) is untouched.
        #expect(vm.cell(at: GridPos(row: 0, col: 1)).entry == nil)
    }
}
