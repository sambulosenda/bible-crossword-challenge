import Foundation

/// The beginner journey uses ordinary puzzle records, including solves from
/// the daily rotation. No second progress store or calendar lock is needed.
enum BeginnerPath {
    static let questID = "first-week"

    static func contains(_ puzzle: Puzzle, provider: PuzzleProvider) -> Bool {
        provider.quest(id: questID)?.puzzleIDs.contains(puzzle.id) == true
    }

    static func next(provider: PuzzleProvider, recordsByID: [String: PuzzleRecord]) -> Puzzle? {
        guard let quest = provider.quest(id: questID) else { return nil }
        return provider.puzzles(in: quest).first { recordsByID[$0.id]?.isCompleted != true }
    }

    static func shouldFeature(totalCompleted: Int, progress: QuestProgress) -> Bool {
        !progress.isComplete && (totalCompleted < 7 || progress.solved > 0)
    }
}
