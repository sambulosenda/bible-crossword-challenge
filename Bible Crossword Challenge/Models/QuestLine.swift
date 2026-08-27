//
//  QuestLine.swift
//  Bible Crossword Challenge
//
//  Journey Quests: themed, *ordered* runs of existing puzzles, paced at one
//  step a day and sealed with a badge. A quest is packaging, not content —
//  every step is a puzzle that already ships in puzzles.json, so quests add
//  no puzzle tech and no new ids.
//
//  How a quest differs from a pack: a pack is a browsable collection (play in
//  any order), a quest is a sequence (steps unlock front to back, and the
//  screen frames one step per day). The pacing is deliberately soft — the
//  next step is *suggested* for tomorrow, never hard-locked, because hard
//  gates punish exactly the players who paid for everything.
//
//  Progress is derived from PuzzleRecords on every read, like PackProgress —
//  nothing about a quest's state is stored except the completion credit on
//  PlayerProfile.completedQuestIDs (which feeds the quest achievements, the
//  same shape as completedPackIDs).
//

import Foundation
import SwiftUI

/// One quest line, decoded from bundled `quests.json` (authored order in the
/// file is display order; the first quest is the free one).
struct QuestLine: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let blurb: String
    let coverSymbol: String
    let accentHex: String?
    let isPremium: Bool
    /// Ordered — step N is `puzzleIDs[N]`. The single source of membership.
    let puzzleIDs: [String]

    var accent: Color {
        guard let hex = accentHex, let color = Color(hex: hex) else { return Theme.accent }
        return color
    }
}

/// A quest's derived state: how far along, which step is next, and whether a
/// step was already played today (the soft-pacing signal the cards read).
struct QuestProgress: Hashable {
    let solved: Int
    let total: Int
    /// Index of the first unsolved step, nil once the quest is finished.
    /// Steps complete front to back for pacing, but the count is membership-
    /// based, so a puzzle solved earlier via the daily feed still counts.
    let currentIndex: Int?
    /// A step of this quest was first completed today — the card swaps its
    /// call to action for "back tomorrow" without ever locking the door.
    let steppedToday: Bool

    var isComplete: Bool { total > 0 && solved == total }
    var fraction: Double { total > 0 ? Double(solved) / Double(total) : 0 }

    init(
        quest: QuestLine,
        recordsByID: [String: PuzzleRecord],
        now: Date = Date(),
        calendar: Calendar = .current
    ) {
        let done = quest.puzzleIDs.map { recordsByID[$0]?.isCompleted == true }
        self.solved = done.filter { $0 }.count
        self.total = quest.puzzleIDs.count
        self.currentIndex = done.firstIndex(of: false)
        self.steppedToday = quest.puzzleIDs.contains { id in
            guard let date = recordsByID[id]?.completedDate else { return false }
            return calendar.isDate(date, inSameDayAs: now)
        }
    }
}

/// Credits finished quests on the profile, mirroring `PackCompletion`: runs at
/// solve time (so the badge lands on that completion screen) and again on
/// launch (reconciling solves that predate the feature or arrived by sync).
enum QuestCompletion {
    /// Appends any quest whose every step `isSolved` to
    /// `profile.completedQuestIDs`; returns the newly finished quests.
    @discardableResult
    static func record(
        quests: [QuestLine],
        profile: PlayerProfile,
        isSolved: (String) -> Bool
    ) -> [QuestLine] {
        var newlyCompleted: [QuestLine] = []
        for quest in quests {
            guard !quest.puzzleIDs.isEmpty,
                  !profile.completedQuestIDs.contains(quest.id),
                  quest.puzzleIDs.allSatisfy(isSolved) else { continue }
            profile.completedQuestIDs.append(quest.id)
            newlyCompleted.append(quest)
        }
        return newlyCompleted
    }
}
