import Testing
import Foundation
@testable import Bible_Crossword_Challenge

struct BeginnerPathTests {
    @Test func pathIsSevenDistinctEasyMinisWithScriptureHelp() throws {
        let provider = PuzzleProvider.shared
        let quest = try #require(provider.quest(id: BeginnerPath.questID))
        #expect(!quest.isPremium)
        #expect(Set(quest.puzzleIDs).count == 7)
        let puzzles = provider.puzzles(in: quest)
        #expect(puzzles.count == 7)
        for puzzle in puzzles {
            #expect(puzzle.isMini)
            #expect(puzzle.size == 7)
            #expect(puzzle.clues.allSatisfy { $0.reference != nil })
        }
    }

    @Test func pathResumesFirstUnfinishedAndFinishesWithoutRestarting() throws {
        let provider = PuzzleProvider.shared
        let quest = try #require(provider.quest(id: BeginnerPath.questID))
        var records: [String: PuzzleRecord] = [:]
        for id in quest.puzzleIDs {
            #expect(BeginnerPath.next(provider: provider, recordsByID: records)?.id == id)
            let record = PuzzleRecord(puzzleID: id)
            records[id] = record
            #expect(BeginnerPath.next(provider: provider, recordsByID: records)?.id == id)
            record.isCompleted = true
        }
        #expect(BeginnerPath.next(provider: provider, recordsByID: records) == nil)
        let progress = QuestProgress(quest: quest, recordsByID: records)
        #expect(!BeginnerPath.shouldFeature(totalCompleted: 7, progress: progress))
    }

    @Test func experiencedPlayersAreNotEnrolledUnlessTheyHaveStarted() throws {
        let provider = PuzzleProvider.shared
        let quest = try #require(provider.quest(id: BeginnerPath.questID))
        let empty = QuestProgress(quest: quest, recordsByID: [:])
        #expect(BeginnerPath.shouldFeature(totalCompleted: 0, progress: empty))
        #expect(!BeginnerPath.shouldFeature(totalCompleted: 40, progress: empty))
        let id = try #require(quest.puzzleIDs.last)
        let record = PuzzleRecord(puzzleID: id)
        record.isCompleted = true
        let started = QuestProgress(quest: quest, recordsByID: [id: record])
        #expect(BeginnerPath.shouldFeature(totalCompleted: 40, progress: started))
        #expect(BeginnerPath.next(provider: provider, recordsByID: [id: record])?.id == quest.puzzleIDs.first)
    }

    @Test func everyStepStaysFreeOutsideRotationWindow() throws {
        let provider = PuzzleProvider.shared
        let quest = try #require(provider.quest(id: BeginnerPath.questID))
        let access = PuzzleAccess(provider: provider, windowLength: 0)
        for puzzle in provider.puzzles(in: quest) {
            #expect(!access.isInWindow(puzzle))
            #expect(access.canPlay(puzzle, isPremium: false, hasProgress: false))
        }
    }
    @Test func stalledBeginnerGetsTheRelevantVerseBeforePaidHints() throws {
        let provider = PuzzleProvider.shared
        let puzzle = try #require(BeginnerPath.next(provider: provider, recordsByID: [:]))
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let vm = GameViewModel(puzzle: puzzle, learning: true, now: start, prefersVerseHelp: true)
        vm.tick(now: start)
        for second in 1...(vm.earlyNudgeSeconds + 1) {
            vm.tick(now: start.addingTimeInterval(Double(second)))
        }
        #expect(vm.isStallNudgeActive)
        #expect(vm.stallNudgeKind == .readVerse)
        #expect(vm.hintsUsed == 0)
    }

}
