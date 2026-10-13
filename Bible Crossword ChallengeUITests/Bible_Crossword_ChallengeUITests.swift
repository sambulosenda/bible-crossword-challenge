//
//  Bible_Crossword_ChallengeUITests.swift
//  Bible Crossword ChallengeUITests
//
//  Analytics-sequence tests. The event bugs that have shipped all lived in
//  view lifecycles — a rotation rebuilding the game screen, a screen closing
//  before a delayed ask, a pop back re-running a `.task` — which unit tests
//  can't drive. The app (DEBUG) appends each event name to the file named in
//  `UI_ANALYTICS_LOG` (see `AnalyticsRecorder`); each test reads it back.
//
//  Run on an iPhone simulator: rotation is driven with `XCUIDevice`.
//

import XCTest

final class Bible_Crossword_ChallengeUITests: XCTestCase {

    private var logURL: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false
        logURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("analytics-\(UUID().uuidString).log")
        XCUIDevice.shared.orientation = .portrait
    }

    override func tearDownWithError() throws {
        XCUIDevice.shared.orientation = .portrait
        try? FileManager.default.removeItem(at: logURL)
    }

    // MARK: - Tests

    /// Rotating mid-puzzle used to rebuild the whole game screen: a false
    /// `puzzle_abandoned` and a second `daily_puzzle_started` each time.
    @MainActor
    func testRotatingMidPuzzleKeepsTheSession() throws {
        let app = launch()
        openTodaysPuzzle(app)

        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.buttons["Q"].waitForExistence(timeout: 5))
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(app.buttons["Q"].waitForExistence(timeout: 5))

        let events = loggedEvents()
        XCTAssertEqual(events.count(of: "daily_puzzle_started"), 1, "\(events)")
        XCTAssertEqual(events.count(of: "puzzle_abandoned"), 0, "\(events)")
    }

    /// The return-day reminder sheet waits 1.5s for the celebration. Closing
    /// the results screen first used to log `reminder_ask_shown` for a sheet
    /// that never appeared.
    @MainActor
    func testClosingResultsBeforeTheReminderSheetLogsNoImpression() throws {
        // A 20s delay, so the close below always lands inside it.
        let app = launch(extra: ["-uiAutoSolve", "-uiForceReminderPrompt", "-uiAskDelay", "20"])
        openTodaysPuzzle(app)

        let close = app.buttons["Close"]
        XCTAssertTrue(close.waitForExistence(timeout: 10))
        close.tap()
        // Let a cancelled ask finish unwinding before reading the log.
        sleep(2)

        let events = loggedEvents()
        XCTAssertEqual(events.count(of: "reminder_ask_shown", source: "prompt"), 0, "\(events)")
    }

    /// `pack_opened` is the denominator of pack conversion. It used to fire
    /// again on every pop back from a puzzle, so one visit counted twice.
    @MainActor
    func testPackOpenLogsOncePerVisit() throws {
        let app = launch()
        let packsTab = app.tabBars.buttons["Packs"]
        XCTAssertTrue(packsTab.waitForExistence(timeout: 20))
        packsTab.tap()

        let pack = app.buttons.matching(NSPredicate(format: "label CONTAINS 'First Steps'")).firstMatch
        XCTAssertTrue(pack.waitForExistence(timeout: 10))
        pack.tap()

        let play = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Start' OR label BEGINSWITH 'Continue'")).firstMatch
        XCTAssertTrue(play.waitForExistence(timeout: 10))
        play.tap()
        XCTAssertTrue(app.buttons["Q"].waitForExistence(timeout: 10), "The keypad never appeared")

        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(play.waitForExistence(timeout: 10), "Didn't return to the pack")

        let events = loggedEvents()
        XCTAssertEqual(events.count(of: "pack_opened"), 1, "\(events)")
    }

    // MARK: - Helpers

    @MainActor
    private func launch(extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        // Straight to the tabs: the `hasOnboarded` default, via the
        // argument domain `@AppStorage` reads.
        // `-uiCleanSlate`: in-memory store and no saved settings, so tests
        // can't see each other's solves.
        app.launchArguments = ["-uiCleanSlate", "-hasOnboarded", "YES"] + extra
        app.launchEnvironment["UI_ANALYTICS_LOG"] = logURL.path
        app.launch()
        return app
    }

    /// Starts (or continues) the hero puzzle on Today and waits for the keypad.
    @MainActor
    private func openTodaysPuzzle(_ app: XCUIApplication) {
        let hero = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'Start Puzzle' OR label BEGINSWITH 'Continue'")
        ).firstMatch
        XCTAssertTrue(hero.waitForExistence(timeout: 20), "Today's hero button never appeared")
        hero.tap()
        XCTAssertTrue(app.buttons["Q"].waitForExistence(timeout: 10), "The keypad never appeared")
    }

    private func loggedEvents() -> [String] {
        let text = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
        return text.split(separator: "\n").map(String.init)
    }
}

/// Lines are `name` or `name:source` — see `AnalyticsRecorder`.
private extension Array where Element == String {
    func count(of name: String) -> Int {
        count { $0 == name || $0.hasPrefix(name + ":") }
    }

    func count(of name: String, source: String) -> Int {
        count { $0 == "\(name):\(source)" }
    }
}
