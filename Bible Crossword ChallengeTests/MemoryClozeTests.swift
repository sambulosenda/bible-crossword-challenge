//
//  MemoryClozeTests.swift
//  Bible Crossword ChallengeTests
//
//  Pins the memory-verse grid builder: tokenization, layout, blank nesting,
//  and — most load-bearing — the round trip through the real engine, since the
//  whole design rests on `GameViewModel` needing no changes.
//

import Testing
import Foundation
@testable import Bible_Crossword_Challenge

private let johnVerse = "For God so loved the world that He gave His one and only Son"
private let johnRef = "John 3:16"

struct MemoryClozeTests {

    // MARK: - Tokenization

    @Test func tokenizeStripsPunctuationAndKeepsOrder() {
        let words = MemoryCloze.tokenize("Jesus wept.")
        #expect(words == ["JESUS", "WEPT"])
    }

    @Test func tokenizeDropsApostrophesAndSplitsHyphens() {
        #expect(MemoryCloze.tokenize("God's") == ["GODS"])
        #expect(MemoryCloze.tokenize("self-control, and love") == ["SELF", "CONTROL", "AND", "LOVE"])
    }

    @Test func tokenizeKeepsDuplicates() {
        let words = MemoryCloze.tokenize("Rejoice always, again I say rejoice")
        #expect(words.filter { $0 == "REJOICE" }.count == 2)
    }

    // MARK: - Layout

    @Test func layoutPlacesEveryWordWithGaps() throws {
        let words = MemoryCloze.tokenize(johnVerse)
        let layout = try #require(MemoryCloze.layout(words: words))
        #expect(layout.starts.count == words.count)
        #expect(layout.size <= 15)
        #expect(layout.grid.count == layout.size)
        #expect(layout.grid.allSatisfy { $0.count == layout.size })

        // Each word sits at its start, and the cell before each start (if on
        // the same row) is a block.
        let rows = layout.grid.map(Array.init)
        for (i, word) in layout.words.enumerated() {
            let start = layout.starts[i]
            let slice = String(rows[start.row][start.col..<(start.col + word.count)])
            #expect(slice == word)
            if start.col > 0 {
                #expect(rows[start.row][start.col - 1] == ".")
            }
        }
    }

    @Test func layoutIsDeterministic() {
        let words = MemoryCloze.tokenize(johnVerse)
        let a = MemoryCloze.layout(words: words)
        let b = MemoryCloze.layout(words: words)
        #expect(a?.grid == b?.grid)
        #expect(a?.starts == b?.starts)
    }

    @Test func layoutHandlesTwoWordVerse() throws {
        let layout = try #require(MemoryCloze.layout(words: ["JESUS", "WEPT"]))
        #expect(layout.starts.count == 2)
    }

    @Test func layoutRejectsOutOfRangeVerses() {
        #expect(MemoryCloze.layout(words: ["AMEN"]) == nil)
        let long = Array(repeating: "WORD", count: 41)
        #expect(MemoryCloze.layout(words: long) == nil)
        #expect(MemoryCloze.layout(words: ["A", "SIXTEENLETTERWORDX"]) == nil)
    }

    // MARK: - Blanking

    @Test func blanksAlwaysAtLeastOne() {
        let blanked = MemoryCloze.blankedWordIndices(words: ["JESUS", "WEPT"], level: 1)
        #expect(!blanked.isEmpty)
    }

    @Test func blanksNestAcrossLevels() {
        let words = MemoryCloze.tokenize(johnVerse)
        var previous: Set<Int> = []
        for level in 1...4 {
            let blanked = MemoryCloze.blankedWordIndices(words: words, level: level)
            #expect(previous.isSubset(of: blanked), "level \(level) must include level \(level - 1)'s blanks")
            previous = blanked
        }
        #expect(previous.count == words.count, "top level blanks everything")
    }

    @Test func blanksPreferContentWordsFirst() {
        let words = MemoryCloze.tokenize(johnVerse)
        let blanked = MemoryCloze.blankedWordIndices(words: words, level: 1)
        // At the lowest level no glue word may be blanked while content words
        // remain revealed — LOVED/WORLD outrank THE/AND.
        for index in blanked {
            #expect(!["THE", "AND", "SO", "HE", "HIS", "THAT", "FOR"].contains(words[index]))
        }
    }

    // MARK: - Build

    @Test func buildProducesMemoryNamespacedPuzzle() throws {
        let built = try #require(MemoryCloze.build(reference: johnRef, verseText: johnVerse, level: 1))
        #expect(built.puzzle.id == "memory-john-3:16")
        #expect(built.puzzle.clues.allSatisfy { $0.direction == .across })
        #expect(built.puzzle.clues.count == built.wordCount)
        // Prefill covers exactly the non-blanked words' letters, lowercased.
        let prefillCells = built.prefill.count
        let blankedLetters = built.blankedWordIndices
            .map { MemoryCloze.tokenize(johnVerse)[$0].count }.reduce(0, +)
        let totalLetters = MemoryCloze.tokenize(johnVerse).map(\.count).reduce(0, +)
        #expect(prefillCells == totalLetters - blankedLetters)
        #expect(built.prefill.values.allSatisfy { $0 == $0.lowercased() })
    }

    @Test func referenceKeyNormalizes() {
        #expect(MemoryCloze.referenceKey(" 1 John 4:19 ") == "1-john-4:19")
        #expect(MemoryCloze.referenceKey("1 John 4:19") == MemoryCloze.referenceKey("1  john 4:19"))
    }

    // MARK: - Engine round trip (the design's load-bearing claim)

    @Test func engineAcceptsBuiltGridAndLocksPrefill() throws {
        let built = try #require(MemoryCloze.build(reference: johnRef, verseText: johnVerse, level: 1))
        let vm = GameViewModel(puzzle: built.puzzle)

        var completedWords: [String] = []
        vm.onWordCompleted = { completedWords.append($0.answer) }
        vm.restore(built.prefill)

        // Restore must not complete the puzzle or flash pre-filled words.
        #expect(!vm.isComplete)
        #expect(completedWords.isEmpty)

        // Every prefilled cell is locked; every blanked cell is empty.
        for row in vm.grid {
            for cell in row where !cell.isBlock {
                if built.prefill[cell.pos.storageKey] != nil {
                    #expect(cell.isRevealed)
                    #expect(cell.entry == cell.solution)
                } else {
                    #expect(cell.entry == nil)
                }
            }
        }
    }

    @Test func typingOnlyBlankedWordsCompletesPuzzle() throws {
        let built = try #require(MemoryCloze.build(reference: johnRef, verseText: johnVerse, level: 2))
        let vm = GameViewModel(puzzle: built.puzzle)
        vm.restore(built.prefill)

        var completed = false
        vm.onComplete = { _ in completed = true }

        let blankedSlots = vm.acrossSlots.filter { built.blankedWordIndices.contains($0.number - 1) }
        for slot in blankedSlots {
            vm.select(slot: slot)
            for letter in slot.answer where vm.cell(at: vm.selected).entry == nil {
                vm.enter(letter)
            }
        }
        #expect(completed)
        #expect(vm.isComplete)
    }

    @Test func typingSkipsLockedCells() throws {
        let built = try #require(MemoryCloze.build(reference: johnRef, verseText: johnVerse, level: 1))
        let vm = GameViewModel(puzzle: built.puzzle)
        vm.restore(built.prefill)

        // Select a prefilled (locked) word's first cell: typing must not
        // overwrite the locked letter.
        let locked = try #require(vm.acrossSlots.first { !built.blankedWordIndices.contains($0.number - 1) })
        vm.select(locked.positions[0])
        vm.direction = .across
        let before = vm.cell(at: locked.positions[0]).entry
        vm.enter("Z")
        #expect(vm.cell(at: locked.positions[0]).entry == before)
    }
}
