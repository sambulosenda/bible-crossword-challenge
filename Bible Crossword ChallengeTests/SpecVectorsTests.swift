//
//  SpecVectorsTests.swift
//  Bible Crossword ChallengeTests
//
//  The executable contract between the iOS app and the Android port.
//
//  Every rule that drives revenue or retention — the hint quota, streaks and
//  freezes, achievements, the free-tier window, the three asks, sync merging,
//  challenge links, and the crossword engine itself — is a deterministic
//  function over plain values. This test evaluates each one across a corpus of
//  inputs and writes the results as JSON to `spec/vectors/` at the repo root.
//  The Android test suite reads the same files and asserts its Kotlin port
//  produces the same outputs.
//
//  That is the whole point: there is no shared code between the platforms, so
//  there is shared *data* instead. When a rule changes here, the vector changes
//  in the same commit, and Android goes red until it follows. Two
//  implementations, one specification.
//
//  Mechanics: each family is regenerated on every run and compared to the
//  checked-in file. A difference rewrites the file and FAILS the test, so the
//  change shows up in `git diff` and has to be committed on purpose. The first
//  run creates them all (and fails once, by design).
//
//  Determinism rules for the corpus — every case must reproduce on either
//  platform, in any time zone, on any day:
//    - No absolute dates in outputs. Time is expressed as day offsets from an
//      unemitted fixed "now" (`daysAgo`), evaluated on a UTC calendar.
//    - No `Date()`, no bundle-specific paths, no randomness.
//    - Inputs that are calendar dates (rotation and access lookups) are
//      emitted as ISO day strings and evaluated on the *local* calendar —
//      `PuzzleProvider` builds its epoch as local midnight on 2026-07-01, so
//      date and epoch must share a zone for "day 0 = July 1" to hold. Same
//      zone on both sides makes the result zone-independent; evaluating in
//      UTC on a UTC+1 machine shifted day 0 to June 30.
//

import Testing
import Foundation
import SwiftData
@testable import Bible_Crossword_Challenge

// MARK: - Harness

/// Where the vectors live: `<repo>/spec/vectors/`. Derived from this file's
/// own path so no environment variable or scheme setting is needed.
private let vectorsDir: URL = URL(filePath: #filePath)
    .deletingLastPathComponent()   // Bible Crossword ChallengeTests/
    .deletingLastPathComponent()   // <repo>/
    .appending(path: "spec/vectors", directoryHint: .isDirectory)

private let utc: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(secondsFromGMT: 0)!
    c.locale = Locale(identifier: "en_US_POSIX")
    return c
}()

/// The fixed "now" every relative-date case is evaluated against. Never
/// emitted — only offsets from it are.
private let fixedNow = utc.date(from: DateComponents(year: 2026, month: 8, day: 8, hour: 12))!

private func daysAgo(_ n: Int) -> Date {
    utc.date(byAdding: .day, value: -n, to: fixedNow)!
}

/// Whole days between `date` and `fixedNow` on the UTC calendar, so a date
/// produced by a rule can be emitted as an offset rather than an instant.
private func daysAgoOf(_ date: Date?) -> Any {
    guard let date else { return NSNull() }
    let a = utc.startOfDay(for: date)
    let b = utc.startOfDay(for: fixedNow)
    return utc.dateComponents([.day], from: a, to: b).day ?? 0
}

/// The calendar the rotation is evaluated on — see the header note. Locale is
/// pinned so weekday numbering can't drift with the machine's region.
private let local: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.locale = Locale(identifier: "en_US_POSIX")
    return c
}()

/// A calendar day at local noon, as the rotation sees it.
private func isoDay(_ y: Int, _ m: Int, _ d: Int) -> (String, Date) {
    let date = local.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    return (String(format: "%04d-%02d-%02d", y, m, d), date)
}

private struct VectorCase {
    let name: String
    let given: [String: Any]
    let expect: [String: Any]

    var json: [String: Any] { ["name": name, "given": given, "expect": expect] }
}

private struct VectorFile {
    let family: String
    let description: String
    /// The Swift the vectors were derived from, so a reader on the Android
    /// side knows where to look when a case surprises them.
    let source: [String]
    var constants: [String: Any] = [:]
    var cases: [VectorCase] = []

    var json: [String: Any] {
        var out: [String: Any] = [
            "family": family,
            "description": description,
            "source": source,
            "cases": cases.map(\.json),
        ]
        if !constants.isEmpty { out["constants"] = constants }
        return out
    }
}

/// Serialise, compare with the checked-in file, rewrite on change.
///
/// Records an `Issue` (fails the test) when the file changed, naming it, so
/// the diff is reviewed rather than absorbed. A missing file is created and
/// reported the same way.
private func emit(_ file: VectorFile) throws {
    let data = try JSONSerialization.data(
        withJSONObject: file.json,
        options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    )
    let text = String(decoding: data, as: UTF8.self) + "\n"
    let url = vectorsDir.appending(path: "\(file.family).json")
    let existing = try? String(contentsOf: url, encoding: .utf8)
    guard existing != text else { return }
    try FileManager.default.createDirectory(at: vectorsDir, withIntermediateDirectories: true)
    try text.write(to: url, atomically: true, encoding: .utf8)
    let verb = existing == nil ? "created" : "changed"
    let message = "spec/vectors/\(file.family).json \(verb) — review `git diff spec/vectors` and commit it. The Android port reads this file."
    Issue.record(Comment(rawValue: message))
}

// MARK: - Tests

@MainActor
struct SpecVectorsTests {

    // MARK: Constants

    /// Every magic number a port has to get right, in one place. Not a rule
    /// evaluation — a pin, so a Kotlin `const val` typo shows up as a diff
    /// here rather than as a quota that is off by one in production.
    @Test func constants() throws {
        var file = VectorFile(
            family: "constants",
            description: "Named constants the rules depend on. Kotlin should assert equality against each at test time.",
            source: [
                "Models/Persistence.swift", "ViewModels/GameViewModel.swift",
                "Models/ReminderAsk.swift", "Models/ReviewAsk.swift", "Models/TrialReoffer.swift",
                "Services/PuzzleAccess.swift", "Services/PuzzleProvider.swift", "Services/FeatureFlags.swift",
                "Services/ChallengeService.swift", "Models/PaywallSource.swift",
            ]
        )
        file.constants = [
            "hints": [
                "freeHintLimit": PlayerProfile.freeHintLimit,
                "learningWindowCompletions": 3,
                "costs": [
                    HintType.verse.rawValue: HintType.verse.cost,
                    HintType.letter.rawValue: HintType.letter.cost,
                    HintType.word.rawValue: HintType.word.cost,
                    HintType.puzzle.rawValue: HintType.puzzle.cost,
                ],
                "titles": [
                    HintType.verse.rawValue: HintType.verse.title,
                    HintType.letter.rawValue: HintType.letter.title,
                    HintType.word.rawValue: HintType.word.title,
                    HintType.puzzle.rawValue: HintType.puzzle.title,
                ],
                "checkScopes": [CheckScope.letter.rawValue, CheckScope.word.rawValue, CheckScope.puzzle.rawValue],
            ],
            "streaks": [
                "maxStreakFreezes": PlayerProfile.maxStreakFreezes,
                "freezeMilestoneEveryDays": 7,
                "startingFreezes": PlayerProfile().streakFreezes,
            ],
            "stallNudge": [
                "standardStallNudgeSeconds": GameViewModel.standardStallNudgeSeconds,
                "learningStallNudgeSeconds": GameViewModel.learningStallNudgeSeconds,
                "earlyNudgeCap": GameViewModel.earlyNudgeCap,
                "learningEarlyNudgeSeconds": GameViewModel.learningEarlyNudgeSeconds,
                "maxMidSolveNudges": GameViewModel.maxMidSolveNudges,
                "midSolveFillThreshold": 0.40,
                "kinds": [
                    GameViewModel.StallNudgeKind.checkAnswers.rawValue,
                    GameViewModel.StallNudgeKind.readVerse.rawValue,
                    GameViewModel.StallNudgeKind.freeLetter.rawValue,
                ],
            ],
            "timer": ["maxTickDeltaSeconds": 1.5],
            "starterGift": ["letterIntervalMilliseconds": 170],
            "reminderAsk": [
                "maxCompletionAsks": ReminderAsk.maxCompletionAsks,
                "surfaces": [
                    ReminderAsk.Surface.completion.rawValue,
                    ReminderAsk.Surface.streakCard.rawValue,
                    ReminderAsk.Surface.returnDaySheet.rawValue,
                ],
                "streakCardFloor": 2,
            ],
            "reviewAsk": [
                "milestones": ReviewAsk.milestones,
                "streakFloor": ReviewAsk.streakFloor,
                "versionFloor": ReviewAsk.versionFloor,
                "minimumGapDays": ReviewAsk.minimumGap / 86_400,
                "minimumInstallAgeDays": ReviewAsk.minimumInstallAge / 86_400,
            ],
            "trialReoffer": [
                "windowDays": TrialReoffer.window / 86_400,
                "paywallSource": TrialReoffer.source.rawValue,
            ],
            "puzzleAccess": [
                "windowLength": PuzzleAccess.windowLength,
                "packExclusivePrefix": "pack-",
            ],
            "rotation": [
                "epochDay": "2026-07-01",
                "sundayRotationOffset": PuzzleProvider.sundayRotationOffset,
                "poolCounts": [
                    "daily": PuzzleProvider.shared.puzzles.count,
                    "mini": PuzzleProvider.shared.minis.count,
                    "sunday": PuzzleProvider.shared.sundays.count,
                    "all": PuzzleProvider.shared.allPuzzles.count,
                ],
            ],
            "challengeLinks": [
                "scheme": ChallengeService.scheme,
                "host": ChallengeService.host,
                "webHost": ChallengeService.webHost,
                "webPath": ChallengeService.webPath,
                "currentVersion": ChallengeService.currentVersion,
                "placeholderName": ChallengeService.placeholderName,
            ],
            "paywallSources": PaywallSource.allCases.map(\.rawValue),
            "achievements": Achievements.all.map { a -> [String: Any] in
                var goal: [String: Any]
                switch a.goal {
                case .puzzles(let n): goal = ["type": "puzzles", "target": n]
                case .streak(let n): goal = ["type": "streak", "target": n]
                case .fastSolve(let s): goal = ["type": "fastSolve", "maxSeconds": s]
                case .noHints(let n): goal = ["type": "noHints", "target": n]
                case .difficulty(let d, let n): goal = ["type": "difficulty", "difficulty": d.rawValue, "target": n]
                case .packsCompleted(let n): goal = ["type": "packsCompleted", "target": n]
                case .questsCompleted(let n): goal = ["type": "questsCompleted", "target": n]
                }
                return ["id": a.id, "title": a.title, "detail": a.detail, "symbol": a.symbol, "goal": goal]
            },
        ]
        try emit(file)
    }

    // MARK: Analytics vocabulary

    /// The event names and parameter keys, exactly as iOS emits them.
    ///
    /// This is the one family that protects something already live: the
    /// PostHog and Firebase projects are **shared with the iOS app**. An
    /// Android build emitting `daily_puzzle_completed` with a different
    /// parameter spelling doesn't merely fail to measure Android — it pollutes
    /// dashboards, saved insights, and the arms of the running experiments.
    ///
    /// Every case is constructed rather than parsed, so the names and keys are
    /// whatever the shipping code actually produces.
    @Test func analyticsVocabulary() throws {
        var file = VectorFile(
            family: "analytics",
            description: "AnalyticsEvent names and parameter keys. Kotlin must emit the same name and the same key set for each, plus a platform property.",
            source: ["Services/Analytics.swift", "Services/FeatureFlags.swift"]
        )
        let amount = StoreService.PurchaseAmount(minorUnits: 1299, currencyCode: "USD")
        let events: [AnalyticsEvent] = [
        AnalyticsEvent.appOpen,
        .onboardingStep(index: 1, name: "welcome"),
        .onboardingFirstSolve(solved: true, attempts: 2),
        .onboardingCompleted(solvedFirstClue: true),
        .dailyPuzzleStarted(puzzleID: "daily-001", isResume: false, source: "home"),
        .dailyPuzzleCompleted(puzzleID: "daily-001", seconds: 154),
        .puzzleAbandoned(puzzleID: "daily-001", fillPercent: 40, seconds: 60, wallSeconds: 70, hintsUsed: 1, cellTaps: 3, keyPresses: 9),
        .hintUsed(type: "letter", cost: 1),
        .hintLimitReached(type: "word"),
        .checkUsed(scope: "word", wrongCount: 2),
        .stallNudgeShown(puzzleID: "daily-001", fillPercent: 50, idleSeconds: 45, kind: "check"),
        .stallNudgeTapped(puzzleID: "daily-001", fillPercent: 50, idleSeconds: 45, kind: "check"),
        .starterWordGifted(puzzleID: "daily-001", answerLength: 5),
        .widgetOpened(destination: "daily"),
        .streakUpdated(streak: 7),
        .streakBroken(previousLength: 12),
        .streakComebackStarted(source: "organic"),
        .achievementUnlocked(id: "bible-beginner"),
        .premiumPurchased(plan: "yearly", source: "onboarding", isTrial: true, amount: amount, acquisition: "purchase"),
        .subscriptionRenewed(plan: "yearly", isTrial: false, amount: amount),
        .purchaseFailed(plan: "yearly", source: "onboarding", reason: "network"),
        .purchaseCancelled(plan: "yearly", source: "onboarding", offersTrial: true, amount: amount, elapsedMs: 4200, canMakePayments: true, path: "package"),
        .paywallOpened(source: "hint_limit"),
        .paywallCTATapped(plan: "yearly", source: "hint_limit", offersTrial: true),
        .paywallDismissed(source: "hint_limit", secondsOnScreen: 12, ctaTapped: false, exit: .close),
        .notificationPermission(granted: true, source: "completion"),
        .reminderAskShown(source: "completion"),
        .upsellShown(source: "first_completion"),
        .reminderDeclined(source: "completion"),
        .reminderSettingChanged(enabled: true),
        .reviewPromptRequested(trigger: "milestone_10", totalCompleted: 10),
        .packOpened(id: "first-steps", source: "packs"),
        .packCompleted(id: "first-steps"),
        .questOpened(id: "beginnings", source: "home"),
        .questStepCompleted(id: "beginnings", step: 2, total: 5),
        .questCompleted(id: "beginnings"),
        .challengeSent(puzzleID: "daily-001"),
        .challengeOpened(puzzleID: "daily-001", via: "link"),
        .challengeCompleted(puzzleID: "daily-001", won: true, deltaSeconds: -12),
        .challengeRematchSent(puzzleID: "daily-001"),
        .challengeShareCancelled(puzzleID: "daily-001"),
        .familyBoardStarted(puzzleID: "daily-001"),
        .familyBoardOpened(puzzleID: "daily-001", size: 3),
        .familyBoardShared(puzzleID: "daily-001", size: 3),
        .scriptureOpened(reference: "John 3:16", source: "hint"),
        .readerClosed(source: "hint", seconds: 30, chaptersPaged: 1, scrolledPastVerse: true, expanded: false),
        .verseAction(kind: "bookmark", reference: "John 3:16"),
        .bookmarksOpened(count: 4),
        .readSearch(kind: "reference", results: 1),
        .shareOpened(kind: "scorecard"),
        .shareCompleted(kind: "scorecard", completed: true),
        .planStarted(plan: "john"),
        .planChapterRead(plan: "john", day: 3),
        .planCompleted(plan: "john", days: 21),
        .planStopped(plan: "john", day: 3),
        .completionChainTapped(fromPuzzleID: "daily-001", toPuzzleID: "mini-001"),
        .memoryListOpened(source: "completion"),
        .memoryVerseAdded(reference: "John 3:16", source: "completion"),
        .memoryVerseStarted(reference: "John 3:16", level: 1, source: "memory"),
        .memoryVerseCompleted(reference: "John 3:16", level: 1, leveledUp: true, hintsUsed: 0),
        .memoryVerseMastered(reference: "John 3:16"),
        .journeyOpened(source: "profile"),
        .achievementsOpened(source: "profile"),
        .appCrash(signal: 11, exceptionType: 1, exceptionCode: 0, reason: "x", build: "21", os: "26.0", frames: "a", appFrames: "b"),
        .appHang(seconds: 2.5, build: "21", os: "26.0", frames: "a", appFrames: "b"),
        ]
        for event in events {
            file.cases.append(VectorCase(
                name: event.name,
                given: ["case": String(describing: event).prefix(while: { $0 != "(" }).description],
                expect: ["name": event.name, "parameterKeys": event.parameters.keys.sorted()]
            ))
        }
        file.constants = [
            // Listed rather than derived: PaywallExit isn't CaseIterable, and a
            // test is not a reason to widen app code.
            "paywallExits": [
                PaywallExit.close, .freeLink, .swipe, .purchase, .afterCancel, .premiumContinue, .noPlan,
            ].map(\.rawValue),
            "eventCount": events.count,
        ]
        try emit(file)
    }

    // MARK: Hint quota

    @Test func hintQuota() throws {
        var file = VectorFile(
            family: "hint_quota",
            description: "hintsRemaining(isPremium:limit:) and consumeHint(cost:) over the daily pool at both sizes. `remaining` of -1 means unlimited (Swift Int.max).",
            source: ["Models/Persistence.swift — extension PlayerProfile (Hint helpers)"]
        )

        func remaining(isPremium: Bool, completed: Int, usedToday: Int, hintsDaysAgo: Int?, limit: Int) -> Int {
            let p = PlayerProfile()
            p.totalPuzzlesCompleted = completed
            p.hintsUsedToday = usedToday
            p.hintsDate = hintsDaysAgo.map(daysAgo)
            let r = p.hintsRemaining(isPremium: isPremium, limit: limit, now: fixedNow, calendar: utc)
            return r == .max ? -1 : r
        }

        // Both pool sizes the app has shipped, so the vectors cover the
        // function rather than one constant.
        for limit in [3, PlayerProfile.freeHintLimit] {
            for (completed, label) in [(2, "learning"), (3, "graduated"), (10, "veteran")] {
                for used in [0, 1, 2, 3, 4] {
                    for daysBack in [nil, 0, 1] as [Int?] {
                        for premium in [false, true] {
                            let name = "limit \(limit) · \(label) · used \(used) · stamped \(daysBack.map { "\($0)d ago" } ?? "never") · premium \(premium)"
                            file.cases.append(VectorCase(
                                name: name,
                                given: [
                                    "limit": limit, "totalCompleted": completed, "hintsUsedToday": used,
                                    "hintsDaysAgo": daysBack ?? NSNull(), "isPremium": premium,
                                ],
                                expect: ["remaining": remaining(isPremium: premium, completed: completed, usedToday: used, hintsDaysAgo: daysBack, limit: limit)]
                            ))
                        }
                    }
                }
            }
        }

        // consumeHint transitions.
        struct Consume { let completed: Int; let used: Int; let daysBack: Int?; let cost: Int }
        let consumes = [
            Consume(completed: 10, used: 0, daysBack: nil, cost: 1),
            Consume(completed: 10, used: 1, daysBack: 0, cost: 1),
            Consume(completed: 10, used: 1, daysBack: 0, cost: 2),
            Consume(completed: 10, used: 3, daysBack: 1, cost: 1),   // yesterday's spend resets first
            Consume(completed: 10, used: 2, daysBack: 0, cost: 0),   // the verse rung charges nothing
            Consume(completed: 2, used: 0, daysBack: nil, cost: 3),  // learning window pays nothing
            Consume(completed: 3, used: 0, daysBack: nil, cost: 3),  // first graduated hint
        ]
        for c in consumes {
            let p = PlayerProfile()
            p.totalPuzzlesCompleted = c.completed
            p.hintsUsedToday = c.used
            p.hintsDate = c.daysBack.map(daysAgo)
            p.consumeHint(cost: c.cost, now: fixedNow, calendar: utc)
            file.cases.append(VectorCase(
                name: "consume cost \(c.cost) · completed \(c.completed) · used \(c.used) · stamped \(c.daysBack.map { "\($0)d ago" } ?? "never")",
                given: ["op": "consumeHint", "totalCompleted": c.completed, "hintsUsedToday": c.used, "hintsDaysAgo": c.daysBack ?? NSNull(), "cost": c.cost],
                expect: ["hintsUsedToday": p.hintsUsedToday, "hintsDaysAgo": daysAgoOf(p.hintsDate)]
            ))
        }
        try emit(file)
    }

    // MARK: Streaks

    @Test func streaks() throws {
        var file = VectorFile(
            family: "streaks",
            description: "Streaks.normalize (launch) and Streaks.registerCompletion (solve). All dates are day offsets from an unemitted fixed now, on a UTC calendar.",
            source: ["Models/Persistence.swift — enum Streaks"]
        )

        struct Norm { let streak: Int; let lastDaysAgo: Int?; let freezes: Int }
        let norms: [Norm] = [
            Norm(streak: 0, lastDaysAgo: nil, freezes: 1),
            Norm(streak: 5, lastDaysAgo: 0, freezes: 1),
            Norm(streak: 5, lastDaysAgo: 1, freezes: 1),
            Norm(streak: 5, lastDaysAgo: 2, freezes: 1),   // one missed day, freeze bridges it
            Norm(streak: 5, lastDaysAgo: 2, freezes: 0),   // one missed day, nothing to spend
            Norm(streak: 5, lastDaysAgo: 3, freezes: 3),   // two missed days: freezes never bridge that
            Norm(streak: 0, lastDaysAgo: 2, freezes: 1),   // no running streak: nothing to save, nothing to report
            Norm(streak: 0, lastDaysAgo: 9, freezes: 1),
            Norm(streak: 12, lastDaysAgo: 30, freezes: 2),
        ]
        for n in norms {
            let p = PlayerProfile()
            p.currentStreak = n.streak
            p.lastCompletedDate = n.lastDaysAgo.map(daysAgo)
            p.streakFreezes = n.freezes
            let outcome = Streaks.normalize(p, now: fixedNow, calendar: utc)
            let outcomeJSON: [String: Any]
            switch outcome {
            case .unchanged: outcomeJSON = ["kind": "unchanged"]
            case .freezeSaved: outcomeJSON = ["kind": "freezeSaved"]
            case .broken(let previous): outcomeJSON = ["kind": "broken", "previous": previous]
            }
            file.cases.append(VectorCase(
                name: "normalize · streak \(n.streak) · last \(n.lastDaysAgo.map { "\($0)d ago" } ?? "never") · freezes \(n.freezes)",
                given: ["op": "normalize", "currentStreak": n.streak, "lastCompletedDaysAgo": n.lastDaysAgo ?? NSNull(), "streakFreezes": n.freezes],
                expect: [
                    "outcome": outcomeJSON,
                    "currentStreak": p.currentStreak,
                    "streakFreezes": p.streakFreezes,
                    "lastCompletedDaysAgo": daysAgoOf(p.lastCompletedDate),
                    "lastFreezeUsedDaysAgo": daysAgoOf(p.lastFreezeUsedDate),
                ]
            ))
        }

        struct Reg { let streak: Int; let best: Int; let total: Int; let lastDaysAgo: Int?; let replay: Bool; let freezes: Int }
        let regs: [Reg] = [
            Reg(streak: 0, best: 0, total: 0, lastDaysAgo: nil, replay: false, freezes: 1),
            Reg(streak: 3, best: 3, total: 5, lastDaysAgo: 1, replay: false, freezes: 1),
            Reg(streak: 3, best: 3, total: 5, lastDaysAgo: 0, replay: false, freezes: 1),   // second solve today: count, don't advance
            Reg(streak: 3, best: 9, total: 5, lastDaysAgo: 4, replay: false, freezes: 1),   // gap: restart at 1
            Reg(streak: 6, best: 6, total: 20, lastDaysAgo: 1, replay: false, freezes: 1),  // crosses 7: earns a freeze
            Reg(streak: 6, best: 6, total: 20, lastDaysAgo: 1, replay: false, freezes: 3),  // crosses 7 at the cap: no gain
            Reg(streak: 13, best: 13, total: 40, lastDaysAgo: 1, replay: false, freezes: 2), // crosses 14
            Reg(streak: 6, best: 6, total: 20, lastDaysAgo: 0, replay: false, freezes: 1),  // already today: 7 not crossed, no freeze
            Reg(streak: 3, best: 3, total: 5, lastDaysAgo: 1, replay: true, freezes: 1),    // replay: streak yes, count no
            Reg(streak: 0, best: 0, total: 0, lastDaysAgo: nil, replay: true, freezes: 1),
        ]
        for r in regs {
            let p = PlayerProfile()
            p.currentStreak = r.streak
            p.bestStreak = r.best
            p.totalPuzzlesCompleted = r.total
            p.lastCompletedDate = r.lastDaysAgo.map(daysAgo)
            p.streakFreezes = r.freezes
            let advanced = Streaks.registerCompletion(p, isReplay: r.replay, now: fixedNow, calendar: utc)
            file.cases.append(VectorCase(
                name: "register · streak \(r.streak) · last \(r.lastDaysAgo.map { "\($0)d ago" } ?? "never") · replay \(r.replay) · freezes \(r.freezes)",
                given: [
                    "op": "registerCompletion", "currentStreak": r.streak, "bestStreak": r.best,
                    "totalPuzzlesCompleted": r.total, "lastCompletedDaysAgo": r.lastDaysAgo ?? NSNull(),
                    "isReplay": r.replay, "streakFreezes": r.freezes,
                ],
                expect: [
                    "advanced": advanced,
                    "currentStreak": p.currentStreak,
                    "bestStreak": p.bestStreak,
                    "totalPuzzlesCompleted": p.totalPuzzlesCompleted,
                    "streakFreezes": p.streakFreezes,
                    "lastCompletedDaysAgo": daysAgoOf(p.lastCompletedDate),
                ]
            ))
        }
        try emit(file)
    }

    // MARK: Achievements

    @Test func achievements() throws {
        var file = VectorFile(
            family: "achievements",
            description: "Achievements.newlyUnlocked plus per-achievement progress and progressText for a profile shape. The catalogue itself is in constants.json.",
            source: ["Models/Persistence.swift — struct Achievement, enum Achievements"]
        )

        struct Shape {
            var total = 0, best = 0, current = 0, bestSolve: Int? = nil, noHints = 0, hard = 0
            var packs = 0, quests = 0, unlocked: [String] = []
        }
        let shapes: [(String, Shape)] = [
            ("fresh", Shape()),
            ("five solves", Shape(total: 5)),
            ("five solves, beginner already recorded", Shape(total: 5, unlocked: ["bible-beginner"])),
            ("fast and unaided", Shape(total: 1, bestSolve: 299, noHints: 1)),
            ("lightning", Shape(total: 1, bestSolve: 120, noHints: 0)),
            ("just over lightning", Shape(total: 1, bestSolve: 121)),
            ("current streak counts toward streak goals", Shape(total: 30, best: 10, current: 30)),
            ("hard five", Shape(total: 8, hard: 5)),
            ("collector", Shape(total: 40, packs: 3, quests: 1)),
            ("everything, all recorded", Shape(total: 300, best: 100, current: 100, bestSolve: 60, noHints: 10, hard: 5, packs: 3, quests: 3,
                                                unlocked: Achievements.all.map(\.id))),
        ]
        for (name, s) in shapes {
            let p = PlayerProfile()
            p.totalPuzzlesCompleted = s.total
            p.bestStreak = s.best
            p.currentStreak = s.current
            p.bestSolveSeconds = s.bestSolve
            p.noHintSolves = s.noHints
            p.hardCompleted = s.hard
            p.completedPackIDs = (0..<s.packs).map { "pack-\($0)" }
            p.completedQuestIDs = (0..<s.quests).map { "quest-\($0)" }
            p.unlockedAchievementIDs = s.unlocked
            var progress: [String: Any] = [:]
            for a in Achievements.all {
                progress[a.id] = ["progress": a.progress(for: p), "text": a.progressText(for: p), "unlocked": a.isUnlocked(by: p)]
            }
            file.cases.append(VectorCase(
                name: name,
                given: [
                    "totalPuzzlesCompleted": s.total, "bestStreak": s.best, "currentStreak": s.current,
                    "bestSolveSeconds": s.bestSolve ?? NSNull(), "noHintSolves": s.noHints, "hardCompleted": s.hard,
                    "completedPackCount": s.packs, "completedQuestCount": s.quests, "unlockedAchievementIDs": s.unlocked,
                ],
                expect: ["newlyUnlocked": Achievements.newlyUnlocked(for: p).map(\.id), "progress": progress]
            ))
        }
        try emit(file)
    }

    // MARK: Rotation

    @Test func rotation() throws {
        var file = VectorFile(
            family: "rotation",
            description: "PuzzleProvider day/week indexing and which puzzle each pool serves on a UTC calendar date. Pins the epoch, the Sunday-week rule, the Sunday offset and the rolling window walk.",
            source: ["Services/PuzzleProvider.swift"]
        )
        let provider = PuzzleProvider.shared
        let dates = [
            isoDay(2026, 6, 30), isoDay(2026, 7, 1), isoDay(2026, 7, 2), isoDay(2026, 7, 5),
            isoDay(2026, 8, 8), isoDay(2026, 8, 9), isoDay(2026, 8, 15), isoDay(2026, 9, 4),
            isoDay(2026, 12, 25), isoDay(2027, 3, 1), isoDay(2027, 7, 1), isoDay(2028, 2, 29),
        ]
        for (iso, date) in dates {
            file.cases.append(VectorCase(
                name: iso,
                given: ["date": iso],
                expect: [
                    "dayIndex": provider.dayIndex(for: date, calendar: local),
                    "weekIndex": provider.weekIndex(for: date, calendar: local),
                    "daily": provider.dailyPuzzle(for: date, calendar: local)?.id ?? NSNull(),
                    "mini": provider.dailyMini(for: date, calendar: local)?.id ?? NSNull(),
                    "sunday": provider.sundaySpecial(for: date, calendar: local)?.id ?? NSNull(),
                    "dailyWindow": provider.rotationWindow(provider.puzzles, for: date, calendar: local, length: PuzzleAccess.windowLength).map(\.id),
                    "miniWindow": provider.rotationWindow(provider.minis, for: date, calendar: local, length: PuzzleAccess.windowLength).map(\.id),
                ]
            ))
        }
        try emit(file)
    }

    // MARK: Puzzle access

    @Test func puzzleAccess() throws {
        var file = VectorFile(
            family: "puzzle_access",
            description: "PuzzleAccess.canPlay / isInWindow truth table on one date, over four puzzle kinds × premium × progress × challenged.",
            source: ["Services/PuzzleAccess.swift"]
        )
        let provider = PuzzleProvider.shared
        let (iso, date) = isoDay(2026, 8, 8)
        let monthAgo = local.date(byAdding: .day, value: -30, to: date)!
        let today = try #require(provider.dailyPuzzle(for: date, calendar: local))
        let mini = try #require(provider.dailyMini(for: date, calendar: local))
        let sunday = try #require(provider.sundaySpecial(for: date, calendar: local))
        let old = try #require(provider.dailyPuzzle(for: monthAgo, calendar: local))
        let oldMini = try #require(provider.dailyMini(for: monthAgo, calendar: local))
        let packOnly = try #require(provider.allPuzzles.first { $0.id.hasPrefix("pack-") })
        let subjects: [(String, Puzzle)] = [
            ("today's daily", today), ("today's mini", mini), ("this week's sunday", sunday),
            ("a daily from 30 days ago", old), ("a mini from 30 days ago", oldMini), ("a pack exclusive", packOnly),
        ]
        for (label, puzzle) in subjects {
            for premium in [false, true] {
                for progress in [false, true] {
                    for challenged in [false, true] {
                        let access = PuzzleAccess(
                            provider: provider, date: date, calendar: local,
                            challengedIDs: challenged ? [puzzle.id] : []
                        )
                        file.cases.append(VectorCase(
                            name: "\(label) · premium \(premium) · progress \(progress) · challenged \(challenged)",
                            given: ["date": iso, "puzzleID": puzzle.id, "isPremium": premium, "hasProgress": progress, "isChallenged": challenged],
                            expect: ["canPlay": access.canPlay(puzzle, isPremium: premium, hasProgress: progress), "isInWindow": access.isInWindow(puzzle)]
                        ))
                    }
                }
            }
        }
        try emit(file)
    }

    // MARK: Asks

    @Test func reminderAsk() throws {
        var file = VectorFile(
            family: "reminder_ask",
            description: "ReminderAsk.decide for each surface. `lastAskDaysAgo` null = never asked.",
            source: ["Models/ReminderAsk.swift"]
        )
        struct S { let enabled: Bool; let undetermined: Bool; let total: Int; let streak: Int; let shown: Int; let streakShown: Bool; let lastDaysAgo: Int?; let session: Bool; let sheetShown: Bool; let install: Bool }
        let states: [S] = [
            S(enabled: false, undetermined: true, total: 1, streak: 0, shown: 0, streakShown: false, lastDaysAgo: nil, session: false, sheetShown: false, install: false),
            S(enabled: false, undetermined: true, total: 0, streak: 0, shown: 0, streakShown: false, lastDaysAgo: nil, session: false, sheetShown: false, install: false),
            S(enabled: true, undetermined: true, total: 5, streak: 5, shown: 0, streakShown: false, lastDaysAgo: nil, session: false, sheetShown: false, install: false),
            S(enabled: false, undetermined: false, total: 5, streak: 5, shown: 0, streakShown: false, lastDaysAgo: nil, session: false, sheetShown: false, install: false),
            S(enabled: false, undetermined: true, total: 5, streak: 5, shown: 0, streakShown: false, lastDaysAgo: nil, session: true, sheetShown: false, install: false),
            S(enabled: false, undetermined: true, total: 5, streak: 5, shown: 0, streakShown: false, lastDaysAgo: 0, session: false, sheetShown: false, install: false),
            S(enabled: false, undetermined: true, total: 5, streak: 5, shown: 0, streakShown: false, lastDaysAgo: 1, session: false, sheetShown: false, install: false),
            S(enabled: false, undetermined: true, total: 5, streak: 5, shown: 2, streakShown: false, lastDaysAgo: 1, session: false, sheetShown: false, install: false),
            S(enabled: false, undetermined: true, total: 5, streak: 5, shown: 3, streakShown: false, lastDaysAgo: 1, session: false, sheetShown: false, install: false),
            S(enabled: false, undetermined: true, total: 5, streak: 1, shown: 3, streakShown: false, lastDaysAgo: 1, session: false, sheetShown: false, install: false),
            S(enabled: false, undetermined: true, total: 5, streak: 2, shown: 3, streakShown: true, lastDaysAgo: 1, session: false, sheetShown: false, install: false),
            S(enabled: false, undetermined: true, total: 1, streak: 0, shown: 0, streakShown: false, lastDaysAgo: nil, session: false, sheetShown: false, install: true),
            S(enabled: false, undetermined: true, total: 1, streak: 0, shown: 0, streakShown: false, lastDaysAgo: nil, session: false, sheetShown: true, install: false),
        ]
        for (i, s) in states.enumerated() {
            let state = ReminderAsk.State(
                remindersEnabled: s.enabled, permissionUndetermined: s.undetermined, totalCompleted: s.total,
                currentStreak: s.streak, completionAsksShown: s.shown, streakAskShown: s.streakShown,
                lastAskDay: s.lastDaysAgo.map { utc.startOfDay(for: daysAgo($0)) }, askedThisSession: s.session,
                returnDaySheetShown: s.sheetShown, isInstallDay: s.install, now: fixedNow, calendar: utc
            )
            file.cases.append(VectorCase(
                name: "state \(i)",
                given: [
                    "remindersEnabled": s.enabled, "permissionUndetermined": s.undetermined, "totalCompleted": s.total,
                    "currentStreak": s.streak, "completionAsksShown": s.shown, "streakAskShown": s.streakShown,
                    "lastAskDaysAgo": s.lastDaysAgo ?? NSNull(), "askedThisSession": s.session,
                    "returnDaySheetShown": s.sheetShown, "isInstallDay": s.install,
                ],
                expect: [
                    ReminderAsk.Surface.completion.rawValue: ReminderAsk.decide(.completion, state),
                    ReminderAsk.Surface.streakCard.rawValue: ReminderAsk.decide(.streakCard, state),
                    ReminderAsk.Surface.returnDaySheet.rawValue: ReminderAsk.decide(.returnDaySheet, state),
                ]
            ))
        }
        try emit(file)
    }

    @Test func reviewAsk() throws {
        var file = VectorFile(
            family: "review_ask",
            description: "ReviewAsk.decide: which trigger fires (or none). Offsets are in days; fractional values are deliberate boundary probes.",
            source: ["Models/ReviewAsk.swift"]
        )
        struct S { let total: Int; let streak: Int; let milestoneAsked: Int; let streakAsked: Bool; let versionAsked: String; let version: String; let lastAskDaysAgo: Double?; let installedDaysAgo: Double? }
        let states: [S] = [
            S(total: 3, streak: 0, milestoneAsked: 0, streakAsked: false, versionAsked: "", version: "2.10", lastAskDaysAgo: nil, installedDaysAgo: nil),
            S(total: 3, streak: 0, milestoneAsked: 0, streakAsked: false, versionAsked: "", version: "2.10", lastAskDaysAgo: nil, installedDaysAgo: 2.9),
            S(total: 3, streak: 0, milestoneAsked: 0, streakAsked: false, versionAsked: "", version: "2.10", lastAskDaysAgo: nil, installedDaysAgo: 3.0),
            S(total: 2, streak: 0, milestoneAsked: 0, streakAsked: false, versionAsked: "", version: "2.10", lastAskDaysAgo: nil, installedDaysAgo: 10),
            S(total: 12, streak: 0, milestoneAsked: 3, streakAsked: false, versionAsked: "", version: "2.10", lastAskDaysAgo: 20, installedDaysAgo: 40),
            S(total: 12, streak: 0, milestoneAsked: 3, streakAsked: false, versionAsked: "", version: "2.10", lastAskDaysAgo: 13.9, installedDaysAgo: 40),
            S(total: 12, streak: 0, milestoneAsked: 10, streakAsked: false, versionAsked: "", version: "2.10", lastAskDaysAgo: 20, installedDaysAgo: 40),
            S(total: 12, streak: 7, milestoneAsked: 10, streakAsked: false, versionAsked: "", version: "2.10", lastAskDaysAgo: 20, installedDaysAgo: 40),
            S(total: 12, streak: 7, milestoneAsked: 10, streakAsked: true, versionAsked: "", version: "2.10", lastAskDaysAgo: 20, installedDaysAgo: 40),
            S(total: 12, streak: 8, milestoneAsked: 3, streakAsked: false, versionAsked: "", version: "2.10", lastAskDaysAgo: 20, installedDaysAgo: 40), // milestone outranks streak
            S(total: 30, streak: 0, milestoneAsked: 30, streakAsked: true, versionAsked: "2.9", version: "2.10", lastAskDaysAgo: 20, installedDaysAgo: 90),
            S(total: 30, streak: 0, milestoneAsked: 30, streakAsked: true, versionAsked: "2.10", version: "2.10", lastAskDaysAgo: 20, installedDaysAgo: 90),
            S(total: 29, streak: 0, milestoneAsked: 10, streakAsked: true, versionAsked: "2.9", version: "2.10", lastAskDaysAgo: 20, installedDaysAgo: 90),
            S(total: 30, streak: 0, milestoneAsked: 30, streakAsked: true, versionAsked: "2.9", version: "", lastAskDaysAgo: 20, installedDaysAgo: 90),
            S(total: 300, streak: 0, milestoneAsked: 150, streakAsked: true, versionAsked: "2.10", version: "2.10", lastAskDaysAgo: 20, installedDaysAgo: 400),
        ]
        for (i, s) in states.enumerated() {
            let state = ReviewAsk.State(
                totalCompleted: s.total, currentStreak: s.streak, milestoneAsked: s.milestoneAsked,
                streakAsked: s.streakAsked, versionAsked: s.versionAsked, currentVersion: s.version,
                lastAsk: s.lastAskDaysAgo.map { fixedNow.addingTimeInterval(-$0 * 86_400) },
                installedAt: s.installedDaysAgo.map { fixedNow.addingTimeInterval(-$0 * 86_400) },
                now: fixedNow
            )
            let trigger = ReviewAsk.decide(state)
            file.cases.append(VectorCase(
                name: "state \(i)",
                given: [
                    "totalCompleted": s.total, "currentStreak": s.streak, "milestoneAsked": s.milestoneAsked,
                    "streakAsked": s.streakAsked, "versionAsked": s.versionAsked, "currentVersion": s.version,
                    "lastAskDaysAgo": s.lastAskDaysAgo ?? NSNull(), "installedDaysAgo": s.installedDaysAgo ?? NSNull(),
                ],
                expect: ["trigger": trigger?.analyticsValue ?? NSNull()]
            ))
        }
        try emit(file)
    }

    @Test func trialReoffer() throws {
        var file = VectorFile(
            family: "trial_reoffer",
            description: "TrialReoffer.decide. `abandonedHoursAgo` / `launchedHoursAgo` are hours before the fixed now (UTC noon), so same-day vs later-day is exact.",
            source: ["Models/TrialReoffer.swift"]
        )
        struct S { let abandonedHoursAgo: Double?; let premium: Bool; let shown: Bool; let launchedHoursAgo: Double }
        let states: [S] = [
            S(abandonedHoursAgo: nil, premium: false, shown: false, launchedHoursAgo: 1),
            S(abandonedHoursAgo: 2, premium: true, shown: false, launchedHoursAgo: 1),
            S(abandonedHoursAgo: 2, premium: false, shown: true, launchedHoursAgo: 1),
            S(abandonedHoursAgo: 0.5, premium: false, shown: false, launchedHoursAgo: 1),   // same sitting: same launch, same day
            S(abandonedHoursAgo: 2, premium: false, shown: false, launchedHoursAgo: 1),     // later launch, same day
            S(abandonedHoursAgo: 20, premium: false, shown: false, launchedHoursAgo: 24),   // same launch, later day
            S(abandonedHoursAgo: 24 * 14 - 1, premium: false, shown: false, launchedHoursAgo: 1),
            S(abandonedHoursAgo: 24 * 14 + 1, premium: false, shown: false, launchedHoursAgo: 1),   // past the window
        ]
        for (i, s) in states.enumerated() {
            let state = TrialReoffer.State(
                abandonedAt: s.abandonedHoursAgo.map { fixedNow.addingTimeInterval(-$0 * 3_600) },
                isPremium: s.premium, reofferShown: s.shown,
                launchedAt: fixedNow.addingTimeInterval(-s.launchedHoursAgo * 3_600),
                now: fixedNow, calendar: utc
            )
            file.cases.append(VectorCase(
                name: "state \(i)",
                given: ["abandonedHoursAgo": s.abandonedHoursAgo ?? NSNull(), "isPremium": s.premium, "reofferShown": s.shown, "launchedHoursAgo": s.launchedHoursAgo],
                expect: ["show": TrialReoffer.decide(state)]
            ))
        }
        try emit(file)
    }

    // MARK: Sync merge

    @Test func syncMerge() throws {
        var file = VectorFile(
            family: "sync_merge",
            description: "SyncMerge.mergeProfiles / mergeRecords: the most generous value of each field survives. Profiles are listed oldest-created first; records in array order.",
            source: ["Models/Persistence.swift — enum SyncMerge"]
        )
        let container = try ModelContainer(
            for: PlayerProfile.self, PuzzleRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext

        func profileJSON(_ p: PlayerProfile) -> [String: Any] {
            [
                "username": p.username, "currentStreak": p.currentStreak, "bestStreak": p.bestStreak,
                "totalPuzzlesCompleted": p.totalPuzzlesCompleted, "lastCompletedDaysAgo": daysAgoOf(p.lastCompletedDate),
                "hintsUsedToday": p.hintsUsedToday, "hintsDaysAgo": daysAgoOf(p.hintsDate),
                "unlockedAchievementIDs": p.unlockedAchievementIDs, "completedPackIDs": p.completedPackIDs,
                "completedQuestIDs": p.completedQuestIDs, "bestSolveSeconds": p.bestSolveSeconds ?? NSNull(),
                "noHintSolves": p.noHintSolves, "hardCompleted": p.hardCompleted, "streakFreezes": p.streakFreezes,
                "lastFreezeUsedDaysAgo": daysAgoOf(p.lastFreezeUsedDate), "createdDaysAgo": daysAgoOf(p.createdAt),
            ]
        }

        let a = PlayerProfile(
            username: "Friend", currentStreak: 3, bestStreak: 9, totalPuzzlesCompleted: 20,
            lastCompletedDate: daysAgo(1), hintsUsedToday: 2, hintsDate: daysAgo(1),
            unlockedAchievementIDs: ["bible-beginner"], bestSolveSeconds: 400, noHintSolves: 2, hardCompleted: 1,
            completedPackIDs: ["first-steps"], completedQuestIDs: [], streakFreezes: 3,
            lastFreezeUsedDate: daysAgo(5), createdAt: daysAgo(60)
        )
        let b = PlayerProfile(
            username: "Sam", currentStreak: 5, bestStreak: 5, totalPuzzlesCompleted: 12,
            lastCompletedDate: daysAgo(0), hintsUsedToday: 1, hintsDate: daysAgo(0),
            unlockedAchievementIDs: ["unaided", "bible-beginner"], bestSolveSeconds: 250, noHintSolves: 4, hardCompleted: 0,
            completedPackIDs: ["women-of-the-bible"], completedQuestIDs: ["beginnings"], streakFreezes: 2,
            lastFreezeUsedDate: daysAgo(2), createdAt: daysAgo(10)
        )
        let c = PlayerProfile(username: "Friend", createdAt: daysAgo(3))
        let inputs = [a, b, c].map(profileJSON)
        for p in [a, b, c] { context.insert(p) }
        let survivor = try #require(SyncMerge.mergeProfiles([a, b, c], context: context))
        file.cases.append(VectorCase(
            name: "three profiles, oldest survives with the best of each",
            given: ["op": "mergeProfiles", "profiles": inputs],
            expect: ["survivor": profileJSON(survivor)]
        ))

        func recordJSON(_ r: PuzzleRecord) -> [String: Any] {
            [
                "puzzleID": r.puzzleID, "isCompleted": r.isCompleted, "completedDaysAgo": daysAgoOf(r.completedDate),
                "elapsedSeconds": r.elapsedSeconds, "entries": r.entries, "pencil": r.pencil, "usedHint": r.usedHint,
                "updatedDaysAgo": daysAgoOf(r.updatedAt),
            ]
        }
        let r1 = PuzzleRecord(puzzleID: "daily-001", isCompleted: false, elapsedSeconds: 120, entriesData: try JSONEncoder().encode(["0,0": "A"]), usedHint: false, updatedAt: daysAgo(0))
        let r2 = PuzzleRecord(puzzleID: "daily-001", isCompleted: true, completedDate: daysAgo(4), elapsedSeconds: 600, entriesData: try JSONEncoder().encode(["0,0": "A", "0,1": "b"]), usedHint: true, updatedAt: daysAgo(4))
        let r3 = PuzzleRecord(puzzleID: "daily-001", isCompleted: true, completedDate: daysAgo(2), elapsedSeconds: 500, usedHint: false, updatedAt: daysAgo(2))
        let recordInputs = [r1, r2, r3].map(recordJSON)
        for r in [r1, r2, r3] { context.insert(r) }
        let rs = try #require(SyncMerge.mergeRecords([r1, r2, r3], context: context))
        file.cases.append(VectorCase(
            name: "completed beats in-progress, latest completed wins, earliest completion date kept, usedHint OR'd",
            given: ["op": "mergeRecords", "records": recordInputs],
            expect: ["survivor": recordJSON(rs)]
        ))
        try emit(file)
    }

    // MARK: Challenge links

    @Test func challengeLinks() throws {
        var file = VectorFile(
            family: "challenge_links",
            description: "ChallengeService.parse outcomes and the outgoing URL builders. `puzzleExists` is stubbed to {daily-001, mini-001} so the corpus is bundle-independent.",
            source: ["Services/ChallengeService.swift"]
        )
        let defaults = try #require(UserDefaults(suiteName: "spec-vectors-challenge-\(UUID().uuidString)"))
        let service = ChallengeService(defaults: defaults, now: { fixedNow }, puzzleExists: { ["daily-001", "mini-001"].contains($0) })

        let links = [
            "biblecrossword://challenge?v=1&p=daily-001&t=154&n=Sam",
            "https://biblecrosswordchallenge.com/challenge/?v=1&p=daily-001&t=154&n=Sam",
            "https://www.biblecrosswordchallenge.com/challenge/?v=1&p=daily-001&t=154&n=Sam",
            "https://biblecrosswordchallenge.com/challenge?v=1&p=mini-001&t=60&n=A%20very%20long%20name%20indeed%20yes",
            "https://biblecrosswordchallenge.com/challenge/?v=1&p=daily-001&t=154",
            "https://biblecrosswordchallenge.com/challenge/?v=1&p=daily-001&t=154&n=%20%20",
            "https://biblecrosswordchallenge.com/challenge/?v=2&p=daily-001&t=154&n=Sam",
            "https://biblecrosswordchallenge.com/challenge/?v=1&p=daily-999&t=154&n=Sam",
            "https://biblecrosswordchallenge.com/challenge/?p=daily-001&t=154&n=Sam",
            "https://biblecrosswordchallenge.com/challenge/?v=1&p=daily-001&t=0&n=Sam",
            "https://biblecrosswordchallenge.com/challenge/?v=1&p=daily-001&t=86401&n=Sam",
            "https://biblecrosswordchallenge.com/challenge/?v=1&p=daily-001&t=abc&n=Sam",
            "https://biblecrosswordchallenge.com/challenge/?v=1&p=&t=154&n=Sam",
            "https://biblecrosswordchallenge.com/other/?v=1&p=daily-001&t=154&n=Sam",
            "https://example.com/challenge/?v=1&p=daily-001&t=154&n=Sam",
            "biblecrossword://memory",
            "https://biblecrosswordchallenge.com/challenge/?v=1&p=daily-001&t=154&n=Sam&e=154%3ASam&e=200%3AJo",
        ]
        for link in links {
            let url = try #require(URL(string: link))
            let outcome: [String: Any]
            switch service.parse(url) {
            case .valid(let ch):
                outcome = ["kind": "valid", "puzzleID": ch.puzzleID, "challengerName": ch.challengerName, "seconds": ch.seconds]
            case .needsUpdate: outcome = ["kind": "needsUpdate"]
            case .notAChallenge: outcome = ["kind": "notAChallenge"]
            }
            file.cases.append(VectorCase(name: link, given: ["op": "parse", "url": link], expect: ["outcome": outcome]))
        }

        struct Out { let id: String; let seconds: Int; let name: String }
        let outs = [
            Out(id: "daily-001", seconds: 154, name: "Sam"),
            Out(id: "mini-001", seconds: 60, name: "A very long name indeed yes"),
            Out(id: "daily-001", seconds: 154, name: "Ana & Bob"),
            Out(id: "daily-001", seconds: 154, name: ""),
        ]
        for o in outs {
            file.cases.append(VectorCase(
                name: "build · \(o.id) · \(o.seconds)s · \"\(o.name)\"",
                given: ["op": "build", "puzzleID": o.id, "seconds": o.seconds, "name": o.name],
                expect: [
                    "webURL": service.challengeWebURL(puzzleID: o.id, seconds: o.seconds, name: o.name)?.absoluteString ?? NSNull(),
                    "schemeURL": service.challengeURL(puzzleID: o.id, seconds: o.seconds, name: o.name)?.absoluteString ?? NSNull(),
                ]
            ))
        }
        try emit(file)
    }

    // MARK: Engine

    /// Scripted play against real bundled puzzles. Each step records the
    /// engine's observable state so a port that diverges fails at the exact
    /// input, not at the end.
    @Test func engineTraces() throws {
        var file = VectorFile(
            family: "engine_traces",
            description: "GameViewModel driven by input scripts against bundled puzzles (loaded by id from the shared puzzles.json). `state` after init is step 0. Entries: uppercase = player letter, lowercase = hint-locked.",
            source: ["ViewModels/GameViewModel.swift"]
        )
        let provider = PuzzleProvider.shared

        enum Op {
            case tap(Int, Int), enter(Character), delete, toggle, pencil(Bool)
            case selectSlot(String), advanceClue(Int), revealLetter, revealWord, revealPuzzle
            case check(CheckScope), gift, restore([String: String], [String: String]), move(Int, Int)

            var json: [String: Any] {
                switch self {
                case .tap(let r, let c): return ["op": "tap", "row": r, "col": c]
                case .enter(let ch): return ["op": "enter", "letter": String(ch)]
                case .delete: return ["op": "delete"]
                case .toggle: return ["op": "toggleDirection"]
                case .pencil(let on): return ["op": "pencilMode", "on": on]
                case .selectSlot(let id): return ["op": "selectSlot", "id": id]
                case .advanceClue(let n): return ["op": "advanceClue", "by": n]
                case .revealLetter: return ["op": "revealLetter"]
                case .revealWord: return ["op": "revealWord"]
                case .revealPuzzle: return ["op": "revealPuzzle"]
                case .check(let s): return ["op": "check", "scope": s.rawValue]
                case .gift: return ["op": "giftStarterWord"]
                case .restore(let e, let p): return ["op": "restore", "entries": e, "pencil": p]
                case .move(let dr, let dc): return ["op": "moveSelection", "rowDelta": dr, "colDelta": dc]
                }
            }
        }

        func state(_ vm: GameViewModel, result: Any? = nil) -> [String: Any] {
            var s: [String: Any] = [
                "selected": [vm.selected.row, vm.selected.col],
                "direction": vm.direction.rawValue,
                "activeSlot": vm.activeSlot?.id ?? NSNull(),
                "filled": vm.filledPlayableCount,
                "remainingClues": vm.remainingClueCount,
                "hintsUsed": vm.hintsUsed,
                "isComplete": vm.isComplete,
                "wordSolveTick": vm.wordSolveTick,
            ]
            if let result { s["result"] = result }
            return s
        }

        /// `dynamic`, when given, is asked for the next op after the static
        /// script runs out, until it returns nil. Every op it produces is
        /// recorded into the emitted script, so the JSON stays a static replay.
        func run(
            _ name: String, puzzleID: String, learning: Bool = false,
            script: [Op], dynamic: ((GameViewModel) -> Op?)? = nil
        ) throws {
            let puzzle = try #require(provider.puzzle(id: puzzleID))
            let vm = GameViewModel(puzzle: puzzle, learning: learning, now: fixedNow)
            var completed: [String] = []
            var checks: [[String: Any]] = []
            vm.onWordCompleted = { completed.append($0.id) }
            vm.onCheckResult = { correct, wrong in
                checks.append(["correct": correct.map { [$0.row, $0.col] }, "wrong": wrong])
            }
            var steps: [[String: Any]] = [["step": 0, "state": state(vm)]]
            var ops = script
            var i = 0
            while true {
                let op: Op
                if i < ops.count {
                    op = ops[i]
                } else if let next = dynamic?(vm), ops.count < 2_000 {
                    ops.append(next)
                    op = next
                } else {
                    break
                }
                var result: Any? = nil
                switch op {
                case .tap(let r, let c): vm.tapCell(GridPos(row: r, col: c))
                case .enter(let ch): vm.enter(ch)
                case .delete: vm.delete()
                case .toggle: vm.toggleDirection()
                case .pencil(let on): vm.isPencilMode = on
                case .selectSlot(let id):
                    let slot = try #require(vm.allSlots.first { $0.id == id })
                    vm.select(slot: slot)
                case .advanceClue(let n): vm.advanceClue(by: n)
                case .revealLetter: result = vm.revealLetter()
                case .revealWord: result = vm.revealWord()
                case .revealPuzzle: result = vm.revealPuzzle()
                case .check(let scope): result = vm.check(scope) ?? NSNull()
                case .gift: result = vm.giftStarterWord()?.id ?? NSNull()
                case .restore(let e, let p): vm.restore(e, pencil: p)
                case .move(let dr, let dc): vm.moveSelection(rowDelta: dr, colDelta: dc)
                }
                i += 1
                steps.append(["step": i, "input": op.json, "state": state(vm, result: result)])
            }
            file.cases.append(VectorCase(
                name: name,
                given: ["puzzleID": puzzleID, "learning": learning, "script": ops.map(\.json)],
                expect: [
                    "slots": vm.allSlots.map { ["id": $0.id, "answer": $0.answer, "start": [$0.positions[0].row, $0.positions[0].col], "length": $0.length] },
                    "steps": steps,
                    "entries": vm.snapshot(),
                    "pencil": vm.pencilSnapshot(),
                    "wordsCompleted": completed,
                    "checks": checks,
                    "cellTaps": vm.cellTaps,
                    "keyPresses": vm.keyPresses,
                ]
            ))
        }

        // A mini: small enough that whole solves fit in a script.
        let mini = try #require(provider.minis.first)
        let miniAnswers = mini.clues.sorted { ($0.direction == .down ? 1 : 0, $0.number) < ($1.direction == .down ? 1 : 0, $1.number) }

        try run("opening selection and typing along a word", puzzleID: mini.id, script: [
            .enter("X"), .enter("Y"), .delete, .delete, .delete,
        ])

        // Type the first across answer letter by letter from its start.
        if let first = miniAnswers.first {
            let id = "\(first.number)-\(first.direction.rawValue)"
            try run("solve one word correctly, watch the cursor move on", puzzleID: mini.id, script:
                [.selectSlot(id)] + first.answer.uppercased().map { Op.enter($0) }
            )
            try run("wrong letters then a word check", puzzleID: mini.id, script:
                [.selectSlot(id)] + first.answer.uppercased().map { _ in Op.enter("Q") } + [.selectSlot(id), .check(.word), .enter("Z")]
            )
            try run("selectSlot lands on the first empty cell of the word", puzzleID: mini.id, script:
                [.selectSlot(id), .enter(first.answer.uppercased().first!), .selectSlot(id)]
            )
        }

        try run("pencil letters never complete and never count", puzzleID: mini.id, script: [
            .pencil(true), .enter("A"), .enter("B"), .pencil(false), .enter("C"), .delete, .delete, .delete,
        ])

        try run("hints: letter, word, then refuse when nothing left in the word", puzzleID: mini.id, script: [
            .revealLetter, .revealWord, .revealWord, .toggle, .revealLetter,
        ])

        let opening = GameViewModel(puzzle: mini, now: fixedNow).selected
        try run("typing into a locked cell skips it", puzzleID: mini.id, script: [
            .revealLetter, .tap(opening.row, opening.col), .enter("Q"),
        ])

        try run("starter gift fills the opening word and moves to a crosser", puzzleID: mini.id, learning: true, script: [
            .gift, .gift, .enter("M"),
        ])

        try run("give up fills everything and completes", puzzleID: mini.id, script: [
            .revealPuzzle, .revealPuzzle,
        ])

        // Solve the whole mini by always typing the correct letter for
        // wherever the cursor is — the engine's own advance rules drive the
        // walk, so this pins them end to end.
        try run("full solve following the cursor", puzzleID: mini.id, script: [], dynamic: { vm in
            guard !vm.isComplete, let letter = vm.cell(at: vm.selected).solution else { return nil }
            return .enter(letter)
        })

        // Restore a snapshot with a locked letter and a pencil mark, then resume.
        if let first = miniAnswers.first {
            let p0 = first.start
            let entries = [p0.storageKey: String(first.answer.uppercased().first!).lowercased()]
            let p1 = first.positions.count > 1 ? first.positions[1] : p0
            let pencil = [p1.storageKey: "Z"]
            try run("restore with a locked letter and a pencil mark", puzzleID: mini.id, script: [
                .restore(entries, pencil), .tap(p0.row, p0.col), .enter("Q"), .delete,
            ])
        }

        try run("hardware cursor walks over blocks", puzzleID: mini.id, script: [
            .move(0, 1), .move(0, 1), .move(1, 0), .move(-1, 0), .move(0, -1),
        ])

        // A daily, for the nearest-incomplete-word walk after a full word.
        let daily = try #require(provider.puzzles.first)
        let dailyFirst = try #require(daily.clues.min { ($0.answer.count, $0.direction == .down ? 1 : 0, $0.number) < ($1.answer.count, $1.direction == .down ? 1 : 0, $1.number) })
        try run("daily: finish the shortest word, cursor prefers a crosser", puzzleID: daily.id, script:
            dailyFirst.answer.uppercased().map { Op.enter($0) } + [.advanceClue(1), .advanceClue(-1), .advanceClue(-1)]
        )

        try emit(file)
    }

    /// The clock contract: ticks advance active time only while attached and
    /// unsuppressed, each delta capped at 1.5s, fractions carried.
    @Test func engineTimer() throws {
        var file = VectorFile(
            family: "engine_timer",
            description: "GameViewModel.tick(now:) — offsets are seconds from an unemitted base instant. `attached`/`suppressed` are set before each tick.",
            source: ["ViewModels/GameViewModel.swift — Timing"]
        )
        let puzzle = try #require(PuzzleProvider.shared.minis.first)
        struct Tick { let at: Double; let attached: Bool; let suppressed: Bool }
        let scripts: [(String, Int, [Tick])] = [
            ("steady one-second ticks", 0, (0...5).map { Tick(at: Double($0), attached: true, suppressed: false) }),
            ("first tick only sets the baseline", 0, [Tick(at: 0, attached: true, suppressed: false), Tick(at: 10, attached: true, suppressed: false)]),
            ("gap is capped at 1.5s", 0, [Tick(at: 0, attached: true, suppressed: false), Tick(at: 1, attached: true, suppressed: false), Tick(at: 60, attached: true, suppressed: false), Tick(at: 61, attached: true, suppressed: false)]),
            ("fractions carry", 0, (0...5).map { Tick(at: Double($0) * 0.4, attached: true, suppressed: false) }),
            ("detached ticks drop the baseline", 0, [
                Tick(at: 0, attached: true, suppressed: false), Tick(at: 1, attached: true, suppressed: false),
                Tick(at: 2, attached: false, suppressed: false), Tick(at: 30, attached: false, suppressed: false),
                Tick(at: 31, attached: true, suppressed: false), Tick(at: 32, attached: true, suppressed: false),
            ]),
            ("suppressed (verse sheet) ticks drop the baseline", 0, [
                Tick(at: 0, attached: true, suppressed: false), Tick(at: 1, attached: true, suppressed: false),
                Tick(at: 2, attached: true, suppressed: true), Tick(at: 40, attached: true, suppressed: true),
                Tick(at: 41, attached: true, suppressed: false), Tick(at: 42, attached: true, suppressed: false),
            ]),
            ("seeded elapsed resumes without a jump", 3600, [Tick(at: 0, attached: true, suppressed: false), Tick(at: 1, attached: true, suppressed: false), Tick(at: 2, attached: true, suppressed: false)]),
        ]
        let base = fixedNow
        for (name, seed, ticks) in scripts {
            let vm = GameViewModel(puzzle: puzzle, now: base)
            if seed > 0 { vm.seedElapsed(seed) }
            var out: [Int] = []
            for t in ticks {
                vm.isAttachedToWindow = t.attached
                vm.isTimerSuppressed = t.suppressed
                vm.tick(now: base.addingTimeInterval(t.at))
                out.append(vm.elapsed())
            }
            file.cases.append(VectorCase(
                name: name,
                given: ["seedElapsed": seed, "ticks": ticks.map { ["at": $0.at, "attached": $0.attached, "suppressed": $0.suppressed] }],
                expect: ["elapsedAfterEach": out]
            ))
        }
        try emit(file)
    }
}
