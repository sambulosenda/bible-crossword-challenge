//
//  QuestsTests.swift
//  Bible Crossword ChallengeTests
//
//  Journey Quests: bundle integrity, derived progress (including the
//  soft-pacing steppedToday signal), completion crediting, and sync merge.
//

import Testing
import Foundation
import SwiftData
@testable import Bible_Crossword_Challenge

/// Noon UTC on a fixed day, so day-boundary logic is deterministic.
private let utc: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}()

private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
    utc.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
}

private func record(_ id: String, completed: Bool, on date: Date? = nil) -> PuzzleRecord {
    let rec = PuzzleRecord(puzzleID: id)
    rec.isCompleted = completed
    rec.completedDate = date
    return rec
}

private extension QuestLine {
    static func fixture(
        id: String = "q1",
        isPremium: Bool = false,
        puzzleIDs: [String] = ["p1", "p2", "p3"]
    ) -> QuestLine {
        QuestLine(
            id: id, title: "Test Quest", blurb: "", coverSymbol: "map",
            accentHex: nil, isPremium: isPremium, puzzleIDs: puzzleIDs
        )
    }
}

struct QuestsTests {

    // MARK: - Bundle integrity

    @Test func questsLoadFromBundle() {
        #expect(!PuzzleProvider.shared.quests.isEmpty)
    }

    @Test func everyQuestReferencesRealPuzzles() {
        let provider = PuzzleProvider.shared
        for quest in provider.quests {
            for id in quest.puzzleIDs {
                #expect(provider.puzzle(id: id) != nil, "Quest \(quest.id) references missing \(id)")
            }
        }
    }

    @Test func exactlyOneFreeQuestAndItIsFirst() {
        let quests = PuzzleProvider.shared.quests
        #expect(quests.filter { !$0.isPremium }.count == 1)
        #expect(quests.first?.isPremium == false)
    }

    /// The free quest must be playable by a free player through the quest
    /// screen: `pack-` exclusives are hard-locked for non-premium everywhere.
    @Test func freeQuestHasNoPackExclusives() {
        for quest in PuzzleProvider.shared.quests where !quest.isPremium {
            #expect(quest.puzzleIDs.allSatisfy { !$0.hasPrefix("pack-") })
        }
    }

    @Test func questStepsHaveNoDuplicates() {
        for quest in PuzzleProvider.shared.quests {
            #expect(Set(quest.puzzleIDs).count == quest.puzzleIDs.count)
        }
    }

    @Test func questsResolveInAuthoredOrder() {
        let provider = PuzzleProvider.shared
        guard let quest = provider.quests.first else { return }
        #expect(provider.puzzles(in: quest).map(\.id) == quest.puzzleIDs)
    }

    @Test func questsContainingFindsOwners() {
        let provider = PuzzleProvider.shared
        guard let quest = provider.quests.first, let firstStep = quest.puzzleIDs.first else { return }
        #expect(provider.quests(containing: firstStep).contains { $0.id == quest.id })
        #expect(provider.quests(containing: "no-such-puzzle").isEmpty)
    }

    // MARK: - Progress

    @Test func progressCountsAndPointsAtFirstUnsolvedStep() {
        let quest = QuestLine.fixture()
        let records = ["p1": record("p1", completed: true)]
        let progress = QuestProgress(quest: quest, recordsByID: records, now: day(2026, 8, 27), calendar: utc)
        #expect(progress.solved == 1)
        #expect(progress.total == 3)
        #expect(progress.currentIndex == 1)
        #expect(!progress.isComplete)
    }

    @Test func aGapMidQuestIsTheCurrentStep() {
        // p2 solved via the daily feed before p1: the path resumes at p1.
        let quest = QuestLine.fixture()
        let records = ["p2": record("p2", completed: true)]
        let progress = QuestProgress(quest: quest, recordsByID: records, now: day(2026, 8, 27), calendar: utc)
        #expect(progress.solved == 1)
        #expect(progress.currentIndex == 0)
    }

    @Test func completeQuestHasNoCurrentStep() {
        let quest = QuestLine.fixture()
        let records = Dictionary(uniqueKeysWithValues: quest.puzzleIDs.map { ($0, record($0, completed: true)) })
        let progress = QuestProgress(quest: quest, recordsByID: records, now: day(2026, 8, 27), calendar: utc)
        #expect(progress.isComplete)
        #expect(progress.currentIndex == nil)
        #expect(progress.fraction == 1.0)
    }

    @Test func steppedTodayReadsTheCompletionDate() {
        let quest = QuestLine.fixture()
        let today = day(2026, 8, 27)
        let solvedToday = ["p1": record("p1", completed: true, on: today)]
        let solvedYesterday = ["p1": record("p1", completed: true, on: day(2026, 8, 26))]
        #expect(QuestProgress(quest: quest, recordsByID: solvedToday, now: today, calendar: utc).steppedToday)
        #expect(!QuestProgress(quest: quest, recordsByID: solvedYesterday, now: today, calendar: utc).steppedToday)
    }

    @Test func undatedCompletionIsNotToday() {
        // A record synced without its date can't claim today's step.
        let quest = QuestLine.fixture()
        let records = ["p1": record("p1", completed: true, on: nil)]
        #expect(!QuestProgress(quest: quest, recordsByID: records, now: day(2026, 8, 27), calendar: utc).steppedToday)
    }

    // MARK: - Completion crediting

    @Test func recordCreditsAFinishedQuestOnce() {
        let quest = QuestLine.fixture()
        let profile = PlayerProfile()
        let first = QuestCompletion.record(quests: [quest], profile: profile) { _ in true }
        #expect(first.map(\.id) == [quest.id])
        #expect(profile.completedQuestIDs == [quest.id])
        // Running again credits nothing new.
        let second = QuestCompletion.record(quests: [quest], profile: profile) { _ in true }
        #expect(second.isEmpty)
        #expect(profile.completedQuestIDs == [quest.id])
    }

    @Test func recordIgnoresPartialQuests() {
        let quest = QuestLine.fixture()
        let profile = PlayerProfile()
        let credited = QuestCompletion.record(quests: [quest], profile: profile) { $0 == "p1" }
        #expect(credited.isEmpty)
        #expect(profile.completedQuestIDs.isEmpty)
    }

    // MARK: - Achievements

    @Test func questAchievementCountsCompletedQuests() {
        let one = Achievement(id: "t1", title: "", detail: "", symbol: "", goal: .questsCompleted(1))
        let three = Achievement(id: "t3", title: "", detail: "", symbol: "", goal: .questsCompleted(3))
        let profile = PlayerProfile(completedQuestIDs: ["a"])
        #expect(one.isUnlocked(by: profile))
        #expect(!three.isUnlocked(by: profile))
        #expect(three.progressText(for: profile) == "1 / 3")
    }

    // MARK: - Sync merge

    @Test func mergeUnionsCompletedQuestIDs() throws {
        let container = try ModelContainer(
            for: PlayerProfile.self, PuzzleRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let old = PlayerProfile(completedQuestIDs: ["a"], createdAt: day(2026, 1, 1))
        let new = PlayerProfile(completedQuestIDs: ["a", "b"], createdAt: day(2026, 6, 1))
        context.insert(old)
        context.insert(new)
        let survivor = SyncMerge.mergeProfiles([old, new], context: context)
        #expect(survivor === old)
        #expect(Set(survivor?.completedQuestIDs ?? []) == ["a", "b"])
    }
}
