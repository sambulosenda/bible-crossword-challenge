//
//  EngagementCountersTests.swift
//  Bible Crossword ChallengeTests
//
//  `cellTaps` and `keyPresses` on `puzzle_abandoned` — the two numbers that
//  split the app's largest abandon bucket.
//
//  Install-day players who quit under 10% fill quit at exactly 0%: 148 of them
//  in the 45 days to 2026-09-08, median 4.5 seconds. Fill alone cannot say
//  whether they never touched the grid, tapped it and couldn't type, or typed
//  and cleared it — three causes with three different fixes. These count
//  attempts rather than effects, which is the only way the middle case is
//  visible at all, so the tests pin that: a key that changes nothing still
//  counts, and a tap on a block still counts.
//

import Testing
@testable import Bible_Crossword_Challenge

@MainActor
struct EngagementCountersTests {

    /// 3×3 with one across and one down, so there are blocks to tap.
    private func puzzle() -> Puzzle {
        Puzzle(
            id: "test-engagement",
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

    @Test("a fresh sitting starts at nothing")
    func startsAtZero() {
        let vm = GameViewModel(puzzle: puzzle())
        #expect(vm.cellTaps == 0)
        #expect(vm.keyPresses == 0)
    }

    @Test("tapping cells counts, typing does not inflate it")
    func tapsCount() {
        let vm = GameViewModel(puzzle: puzzle())
        vm.tapCell(GridPos(row: 0, col: 0))
        vm.tapCell(GridPos(row: 0, col: 1))
        #expect(vm.cellTaps == 2)
        #expect(vm.keyPresses == 0)
    }

    /// The case the whole thing exists for: a player who touched the grid and
    /// never managed to type. Tapping a block is still touching the grid, so it
    /// counts — a player poking at black squares is the clearest signal of all
    /// that the interaction isn't landing.
    @Test("a tap on a block still counts as touching the grid")
    func blockTapsCount() {
        let vm = GameViewModel(puzzle: puzzle())
        vm.tapCell(GridPos(row: 1, col: 1))   // block
        #expect(vm.cellTaps == 1)
        #expect(vm.keyPresses == 0)
    }

    @Test("keys count as attempts, so typing then clearing is not silence")
    func keyPressesCountAttempts() {
        let vm = GameViewModel(puzzle: puzzle())
        vm.tapCell(GridPos(row: 0, col: 0))
        vm.enter("C")
        vm.delete()
        // Back to an empty grid: fill is 0 and always will be for this player,
        // which is exactly why the counter and not the fill answers the
        // question.
        #expect(vm.filledPlayableCount == 0)
        #expect(vm.keyPresses == 2)
        #expect(vm.cellTaps == 1)
    }

    /// Hardware-keyboard cursor movement travels through `select`, not
    /// `tapCell`, so an iPad user arrowing around never looks like tapping.
    @Test("selection that isn't a tap doesn't count as one")
    func programmaticSelectionIsNotATap() {
        let vm = GameViewModel(puzzle: puzzle())
        vm.select(GridPos(row: 0, col: 1))
        #expect(vm.cellTaps == 0)
    }
}
