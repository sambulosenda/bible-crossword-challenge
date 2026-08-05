//
//  ClueReferenceTests.swift
//  Bible Crossword ChallengeTests
//
//  Integrity of the per-clue scripture references in the bundled puzzles. The
//  generator checks these at authoring time, but puzzles.json is a shipped
//  artefact that can be hand-edited — and in a Bible app a citation that opens
//  an empty reader is a credibility problem, not a cosmetic one. So the bundle
//  itself is checked here too.
//

import Testing
import Foundation
@testable import Bible_Crossword_Challenge

struct ClueReferenceTests {

    /// Dailies, minis and pack exclusives — every clue that can be shown.
    private var allPuzzles: [Puzzle] {
        let provider = PuzzleProvider.shared
        let packed = provider.packs.flatMap { provider.puzzles(in: $0) }
        var seen = Set<String>()
        return (provider.puzzles + provider.minis + packed).filter { seen.insert($0.id).inserted }
    }

    @Test func everyClueReferenceParses() {
        for puzzle in allPuzzles {
            for clue in puzzle.clues {
                guard let reference = clue.reference else { continue }
                #expect(ScriptureRef(reference) != nil,
                        "\(puzzle.id) \(clue.number)\(clue.direction.rawValue): unparseable reference \"\(reference)\"")
            }
        }
    }

    @Test func everyClueReferenceOpensInTheReader() {
        let scripture = ScriptureProvider.shared
        for puzzle in allPuzzles {
            for clue in puzzle.clues {
                guard let reference = clue.reference, let ref = ScriptureRef(reference) else { continue }
                guard let (_, chapter) = scripture.chapter(ref) else {
                    Issue.record("\(puzzle.id) \(clue.answer): \"\(reference)\" names no chapter in the bundled Bible")
                    continue
                }
                if let verse = ref.verse {
                    #expect(chapter.verses.contains { $0.number == verse },
                            "\(puzzle.id) \(clue.answer): \"\(reference)\" is past the end of the chapter")
                }
            }
        }
    }

    /// A clue with no reference is valid and common — the guarantee is only that
    /// a blank string never stands in for one, which would render an empty
    /// tappable line.
    @Test func referencesAreAbsentRatherThanEmpty() {
        for puzzle in allPuzzles {
            for clue in puzzle.clues where clue.reference != nil {
                #expect(clue.reference?.trimmingCharacters(in: .whitespaces).isEmpty == false,
                        "\(puzzle.id) \(clue.answer): empty reference string")
            }
        }
    }

    /// The pilot batch: the free First Steps pack is where tap-rate is measured,
    /// so it losing its references silently would quietly end the experiment.
    @Test func firstStepsPuzzlesCarryReferences() {
        let provider = PuzzleProvider.shared
        guard let pack = provider.pack(id: "first-steps") else {
            Issue.record("first-steps pack missing")
            return
        }
        for puzzle in provider.puzzles(in: pack) {
            let referenced = puzzle.clues.filter { $0.reference != nil }.count
            #expect(referenced > 0, "\(puzzle.id) has no referenced clues")
        }
    }

    /// Absent in older JSON, so a puzzle authored before references existed must
    /// still decode and play.
    @Test func clueDecodesWithoutAReference() throws {
        let json = """
        {"number":1,"direction":"across","row":0,"col":0,"text":"Feline","answer":"CAT"}
        """
        let clue = try JSONDecoder().decode(ClueData.self, from: Data(json.utf8))
        #expect(clue.reference == nil)
        #expect(clue.answer == "CAT")
    }
}
