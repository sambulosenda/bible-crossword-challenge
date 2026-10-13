//
//  PuzzleRecordLookup.swift
//  Bible Crossword Challenge
//
//  The one way to index puzzle records by puzzle id.
//
//  `puzzleID` is not unique in the store: CloudKit can land a second record
//  for a puzzle between the launch and foreground merges
//  (`mergeDuplicateRecords`), and `Dictionary(uniqueKeysWithValues:)` traps
//  on the duplicate — the Library crashed that way. Every screen builds its
//  lookup here, so the rule lives in one place.
//

extension Sequence where Element == PuzzleRecord {
    /// Records keyed by puzzle id. A duplicate keeps the first record seen,
    /// until the next merge folds them together.
    var byPuzzleID: [String: PuzzleRecord] {
        Dictionary(map { ($0.puzzleID, $0) }, uniquingKeysWith: { first, _ in first })
    }
}
