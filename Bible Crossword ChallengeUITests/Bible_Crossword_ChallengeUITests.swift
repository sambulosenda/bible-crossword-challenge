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

    /// Swiping home mid-puzzle closes no screen, so it logged nothing: about
    /// half of first-puzzle quitters left no `puzzle_abandoned`. Coming back
    /// is a `puzzle_reattached`, and a later real exit still logs.
    @MainActor
    func testBackgroundingMidPuzzleLogsAnAbandonAndReturningReopensIt() throws {
        let app = launch()
        openTodaysPuzzle(app)

        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 10))
        // The process reaches the background before SwiftUI hands the view
        // its `.background` scene phase, which is what logs the abandon:
        // read at once, the log had only the start (2026-11-16).
        var events = loggedEvents(waitingFor: "puzzle_abandoned")
        XCTAssertEqual(events.count(of: "puzzle_abandoned"), 1, "\(events)")
        XCTAssertEqual(events.count(of: "puzzle_reattached"), 0, "\(events)")

        app.activate()
        XCTAssertTrue(app.buttons["Q"].waitForExistence(timeout: 10))
        events = loggedEvents()
        XCTAssertEqual(events.count(of: "puzzle_reattached"), 1, "\(events)")
        XCTAssertEqual(events.count(of: "daily_puzzle_started"), 1, "\(events)")
        XCTAssertEqual(events.count(of: "puzzle_abandoned"), 1, "\(events)")

        // A real exit after coming back still logs. The hero's label isn't
        // waited on: an untouched grid reads "Start Puzzle" again.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["Q"].waitForNonExistence(timeout: 10))
        events = loggedEvents()
        XCTAssertEqual(events.count(of: "puzzle_abandoned"), 2, "\(events)")
    }

    /// The calendar's impression is once per visit: `.task` runs again on
    /// the pop back from a day's puzzle. A day opened from it is attributed
    /// to the calendar, not the Library.
    @MainActor
    func testPastPuzzlesLogsOncePerVisitAndAttributesItsPuzzles() throws {
        let app = launch()
        let tab = app.tabBars.buttons["Puzzles"]
        XCTAssertTrue(tab.waitForExistence(timeout: 20))
        tab.tap()
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Past Puzzles'")).firstMatch
        let today = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Today,'")).firstMatch
        tap(row, until: today, in: app)

        today.tap()
        XCTAssertTrue(app.buttons["Q"].waitForExistence(timeout: 10), "The keypad never appeared")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(today.waitForExistence(timeout: 10))

        let events = loggedEvents()
        XCTAssertEqual(events.count(of: "past_puzzles_opened"), 1, "\(events)")
        XCTAssertEqual(events.count(of: "daily_puzzle_started", source: "past_puzzles"), 1, "\(events)")
    }

    /// Clue of the Day's impression is once per visit: a rotation must not
    /// log it again, and each easier clue logs once.
    @MainActor
    func testClueOfTheDayLogsOncePerVisit() throws {
        let app = launch(extra: ["-uiShowClueOfDay"])
        let row = app.buttons["clueOfTheDayRow"]
        XCTAssertTrue(row.waitForExistence(timeout: 20), "The Clue of the Day row never appeared")
        let easier = app.buttons["clueOfTheDayEasier"]
        tap(row, until: easier, in: app)

        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(easier.waitForExistence(timeout: 5))
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(easier.waitForExistence(timeout: 5))
        easier.tap()
        XCTAssertTrue(app.staticTexts["Clue 2 of 4"].waitForExistence(timeout: 5))

        var events = loggedEvents()
        XCTAssertEqual(events.count(of: "clue_of_day_opened"), 1, "\(events)")
        XCTAssertEqual(events.count(of: "clue_of_day_clue_revealed"), 1, "\(events)")
        XCTAssertEqual(events.count(of: "clue_of_day_finished"), 0, "\(events)")

        // Back on Today the row carries the progress, and a second visit is
        // a second impression.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertTrue(row.label.contains("Clue 2 of 4"), row.label)
        tap(row, until: easier, in: app)
        events = loggedEvents()
        XCTAssertEqual(events.count(of: "clue_of_day_opened"), 2, "\(events)")
    }

    /// Piece by Piece's impression is once per visit: a rotation moves the
    /// board and the tray, and must not log it again. A piece put down is
    /// still down after leaving and coming back.
    @MainActor
    func testPieceByPieceLogsOncePerVisitAndKeepsItsPieces() throws {
        let app = launch(extra: ["-uiShowPieceByPiece"])
        let row = app.buttons["pieceByPieceRow"]
        XCTAssertTrue(row.waitForExistence(timeout: 20), "The Piece by Piece row never appeared")
        let trayPiece = app.buttons.matching(NSPredicate(format: "label ENDSWITH 'in the tray'")).firstMatch
        tap(row, until: trayPiece, in: app)

        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(trayPiece.waitForExistence(timeout: 5))
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(trayPiece.waitForExistence(timeout: 5))

        // Pick a piece up, then try squares until one takes it: where it
        // fits depends on the day's cut.
        let placed = app.buttons.matching(NSPredicate(format: "label CONTAINS ', at row '")).firstMatch
        trayPiece.tap()
        let squares = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Empty square'"))
        for index in 0..<squares.count where !placed.exists {
            squares.element(boundBy: index).tap()
        }
        XCTAssertTrue(placed.waitForExistence(timeout: 5), "No square took the piece")

        var events = loggedEvents()
        XCTAssertEqual(events.count(of: "piece_by_piece_opened"), 1, "\(events)")
        XCTAssertEqual(events.count(of: "piece_by_piece_finished"), 0, "\(events)")

        // Back on Today the row carries the progress, and a second visit is
        // a second impression with the piece where it was left.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertTrue(row.label.contains("1 of "), row.label)
        tap(row, until: placed, in: app)
        events = loggedEvents()
        XCTAssertEqual(events.count(of: "piece_by_piece_opened"), 2, "\(events)")
    }

    /// The solving move logs `piece_by_piece_finished` once, and coming back
    /// to the solved round doesn't log it again. The ending's two doors each
    /// carry the game as their source: the verse into Memory verses and the
    /// day's crossword. A fixed Monday, so there is no decoy in the tray.
    @MainActor
    func testPieceByPieceFinishLogsOnceAndItsDoorsCarryTheSource() throws {
        let app = launch(extra: ["-uiShowPieceByPiece", "-uiPiecesAllButOne", "-uiToday", "2026-11-23"])
        let row = app.buttons["pieceByPieceRow"]
        XCTAssertTrue(row.waitForExistence(timeout: 20), "The Piece by Piece row never appeared")
        let trayPiece = app.buttons.matching(NSPredicate(format: "label ENDSWITH 'in the tray'")).firstMatch
        tap(row, until: trayPiece, in: app)
        XCTAssertEqual(loggedEvents().count(of: "piece_by_piece_finished"), 0)

        // The last piece: pick it up and try the open squares until it lands.
        let play = app.buttons["pieceByPiecePlay"]
        let squares = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Empty square'"))
        trayPiece.tap()
        for index in 0..<squares.count where !play.exists && squares.element(boundBy: index).exists {
            squares.element(boundBy: index).tap()
        }
        XCTAssertTrue(play.waitForExistence(timeout: 5), "The round never finished\n\(app.debugDescription)")
        var events = loggedEvents()
        XCTAssertEqual(events.count(of: "piece_by_piece_finished"), 1, "\(events)")

        // The verse goes on the shelf in place, and says so.
        let learn = app.buttons["pieceByPieceMemory"]
        XCTAssertTrue(learn.waitForExistence(timeout: 5), "No Learn it by heart link")
        learn.tap()
        XCTAssertTrue(learn.waitForNonExistence(timeout: 5), "The link stayed after the verse was added")
        events = loggedEvents()
        XCTAssertEqual(events.count(of: "memory_verse_added", source: "piece_by_piece"), 1, "\(events)")

        // Out and back in: solved stays solved, and is not finished twice.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertTrue(row.label.contains("Solved in"), row.label)
        tap(row, until: play, in: app)
        events = loggedEvents()
        XCTAssertEqual(events.count(of: "piece_by_piece_opened"), 2, "\(events)")
        XCTAssertEqual(events.count(of: "piece_by_piece_finished"), 1, "\(events)")

        // On to the grid, as this game's start.
        tap(play, until: app.buttons["Q"], in: app)
        events = loggedEvents()
        XCTAssertEqual(events.count(of: "daily_puzzle_started", source: "piece_by_piece"), 1, "\(events)")
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

    /// The scorecard's invite row: its impression is the denominator of the
    /// invite's tap rate, so it logs once, when the row is on screen, and its
    /// ✕ takes the row away without a second impression.
    @MainActor
    func testInviteAskLogsOnceWhenSeenAndDismisses() throws {
        let app = launch(extra: ["-uiAutoSolve", "-uiForceInviteAsk", "-uiNoReview"])
        openTodaysPuzzle(app)

        let send = app.buttons["inviteAskSend"]
        XCTAssertTrue(send.waitForExistence(timeout: 10), "No invite row on the scorecard")
        let seen = NSPredicate { _, _ in self.loggedEvents().count(of: "invite_ask_shown") == 1 }
        expectation(for: seen, evaluatedWith: nil)
        waitForExpectations(timeout: 10)
        app.swipeUp()
        app.swipeDown()
        XCTAssertEqual(loggedEvents().count(of: "invite_ask_shown"), 1)

        app.buttons["inviteAskDismiss"].tap()
        XCTAssertTrue(send.waitForNonExistence(timeout: 5), "The row stayed after its close button")
        let events = loggedEvents(waitingFor: "invite_ask_dismissed")
        XCTAssertEqual(events.count(of: "invite_ask_dismissed"), 1, "\(events)")
        XCTAssertEqual(events.count(of: "invite_ask_shown"), 1, "\(events)")
        XCTAssertEqual(events.count(of: "challenge_tapped"), 0, "\(events)")
    }

    /// The row's button goes straight to the share sheet: the tap is logged
    /// with its source, and no name prompt stands in front of a first send.
    @MainActor
    func testInviteAskTapOpensTheShareWithoutANamePrompt() throws {
        let app = launch(extra: ["-uiAutoSolve", "-uiForceInviteAsk", "-uiNoReview"])
        openTodaysPuzzle(app)

        let send = app.buttons["inviteAskSend"]
        XCTAssertTrue(send.waitForExistence(timeout: 10), "No invite row on the scorecard")
        send.tap()
        let events = loggedEvents(waitingFor: "challenge_tapped")
        XCTAssertEqual(events.count(of: "challenge_tapped", source: "invite_row"), 1, "\(events)")
        XCTAssertFalse(app.alerts["What should we call you?"].waitForExistence(timeout: 2))
    }

    /// The family board row under the verse: its impression is the
    /// denominator of the row's tap rate, so it logs once, when the row has
    /// been scrolled to, and the tap logs before the name prompt a first
    /// board asks for.
    @MainActor
    func testFamilyBoardOfferLogsOnceWhenSeenAndTaps() throws {
        let app = launch(extra: ["-uiAutoSolve", "-uiForceBoardOffer", "-uiNoReview"])
        openTodaysPuzzle(app)

        let offer = app.buttons["familyBoardOffer"]
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 15), "No completion screen")
        for _ in 0..<4 where !(offer.exists && offer.isHittable) { app.swipeUp() }
        XCTAssertTrue(offer.exists && offer.isHittable, "No family board row\n\(app.debugDescription)")
        var events = loggedEvents(waitingFor: "family_board_offer_shown")
        XCTAssertEqual(events.count(of: "family_board_offer_shown"), 1, "\(events)")
        XCTAssertEqual(events.count(of: "family_board_offer_tapped"), 0, "\(events)")

        offer.tap()
        XCTAssertTrue(app.alerts["What should we call you?"].waitForExistence(timeout: 5))
        events = loggedEvents(waitingFor: "family_board_offer_tapped")
        XCTAssertEqual(events.count(of: "family_board_offer_tapped"), 1, "\(events)")
        XCTAssertEqual(events.count(of: "family_board_offer_shown"), 1, "\(events)")
    }

    /// Premium's weekly freeze, offered under the streak in the flame's sheet:
    /// a free player with a run sees the line, and its tap opens the paywall
    /// under its own label once the sheet is down.
    @MainActor
    func testStreakSheetOffersTheWeeklyFreeze() throws {
        let app = launch(extra: ["-uiSeedShowcase", "-uiFree", "-uiNoReview"])
        let flame = app.buttons.matching(NSPredicate(format: "label ENDSWITH 'day streak'")).firstMatch
        XCTAssertTrue(flame.waitForExistence(timeout: 20), app.debugDescription)
        let offer = app.buttons["streakFreezeOffer"]
        tap(flame, until: offer, in: app)
        offer.tap()
        let opened = NSPredicate { _, _ in
            self.loggedEvents().count(of: "paywall_opened", source: "streak_freeze") == 1
        }
        expectation(for: opened, evaluatedWith: nil)
        waitForExpectations(timeout: 10)
    }

    /// `pack_opened` is the denominator of pack conversion. It used to fire
    /// again on every pop back from a puzzle, so one visit counted twice.
    @MainActor
    func testPackOpenLogsOncePerVisit() throws {
        let app = launch()
        let packsTab = app.tabBars.buttons["Puzzles"]
        XCTAssertTrue(packsTab.waitForExistence(timeout: 20))
        packsTab.tap()

        // First Steps sits on the Old Testament shelf, below the fold, and
        // the tab's shelves are lazy: the cover isn't in the tree until it's
        // scrolled to.
        let pack = app.buttons.matching(NSPredicate(format: "label CONTAINS 'First Steps'")).firstMatch
        for _ in 0..<6 where !(pack.exists && pack.isHittable) {
            app.swipeUp()
        }
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

    /// Onboarding hands a new player to the first path step. That screen
    /// used to vanish within two seconds for players who closed the offer
    /// with its ✕ and pressed again where it had been — the back button sits
    /// in the same corner. The second press must not cost the puzzle, and the
    /// start must log under the hand-off's own source.
    @MainActor
    func testOnboardingHandOffSurvivesASecondPressOnTheOfferClose() throws {
        let app = launch(onboarded: false)

        let skip = app.buttons["Skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 20), "Onboarding's solve page never appeared")
        skip.tap()
        // A skipper goes straight to the offer: the reminder page is for a
        // player who solved the clue (asserted below).

        let close = app.buttons["Close and continue with the free puzzle"]
        XCTAssertTrue(close.waitForExistence(timeout: 10), "The offer page never appeared")
        // Anchored to the app, not to `close`: a coordinate from an element
        // resolves that element again at tap time, and by then it is gone.
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let corner = origin.withOffset(CGVector(dx: close.frame.midX, dy: close.frame.midY))
        close.tap()
        // The player's second press, where the ✕ was, as the puzzle arrives.
        Thread.sleep(forTimeInterval: 1.0)
        corner.tap()

        XCTAssertTrue(app.buttons["Q"].waitForExistence(timeout: 10), "The first puzzle never appeared")
        // Past the held beat the way back is there again.
        let back = app.navigationBars.buttons.matching(
            NSPredicate(format: "label IN {'Today', 'Back'}")
        ).firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 5), "No way back after the opening beat")
        XCTAssertTrue(app.buttons["Q"].exists, "The first puzzle closed\n\(app.debugDescription)")

        let events = loggedEvents()
        XCTAssertEqual(events.count(of: "daily_puzzle_started", source: "onboarding_handoff"), 1, "\(events)")
        XCTAssertEqual(events.count(of: "daily_puzzle_started"), 1, "\(events)")
        XCTAssertEqual(events.count(of: "puzzle_abandoned"), 0, "\(events)")
        // Skipping the clue skips the reminder page, so its ask is neither
        // shown nor spent.
        XCTAssertEqual(events.count(of: "reminder_ask_shown"), 0, "\(events)")
    }

    @MainActor
    func testBeginnerPathCompletesSevenStepsAndLeavesToday() throws {
        let app = launch(extra: ["-uiAutoSolve"])
        let start = app.buttons["beginnerPathPlay"]
        XCTAssertTrue(start.waitForExistence(timeout: 20))
        start.tap()
        for step in 1...7 {
            let close = app.buttons["Close"]
            XCTAssertTrue(close.waitForExistence(timeout: 15), "No completion for step \(step)")
            if step < 7 {
                let next = app.buttons["completionNextPuzzle"]
                XCTAssertTrue(next.waitForExistence(timeout: 10))
                next.tap()
                // Wait for the next solve event, not a stale completion button.
                let expected = step + 1
                let predicate = NSPredicate { _, _ in
                    self.loggedEvents().count(of: "quest_step_completed") >= expected
                }
                expectation(for: predicate, evaluatedWith: nil)
                waitForExpectations(timeout: 20)
            } else {
                XCTAssertFalse(app.buttons["completionNextPuzzle"].exists)
                close.tap()
            }
        }
        XCTAssertFalse(app.buttons["beginnerPathPlay"].exists)
        let events = loggedEvents()
        XCTAssertEqual(events.count(of: "quest_step_completed"), 7)
        XCTAssertEqual(events.count(of: "quest_completed"), 1)
        XCTAssertEqual(events.count(of: "completion_chain_tapped"), 6)
    }

    @MainActor
    func testBeginnerPathCanBeLeftAndResumedWithoutCompletingAStep() throws {
        let app = launch()
        let start = app.buttons["beginnerPathPlay"]
        XCTAssertTrue(start.waitForExistence(timeout: 20))
        start.tap()
        XCTAssertTrue(app.buttons["Q"].waitForExistence(timeout: 10))
        app.buttons["Q"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        XCTAssertTrue(start.label.contains("Continue"))
        start.tap()
        XCTAssertTrue(app.buttons["Q"].waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertEqual(loggedEvents().count(of: "daily_puzzle_started"), 2)
        XCTAssertEqual(loggedEvents().count(of: "quest_step_completed"), 0)
    }

    /// Finishing Your First Seven offers the next Premium Journey under the
    /// finished card. The impression logs once, only once the row is on
    /// screen, and survives scrolling away and back without a second count.
    @MainActor
    func testGraduationOfferLogsOnceWhenSeen() throws {
        let app = launch(extra: ["-uiFree", "-uiSeedJourney", "first-week", "6", "-uiAutoSolve", "-uiNoReview"])
        let start = app.buttons["beginnerPathPlay"]
        XCTAssertTrue(start.waitForExistence(timeout: 20))
        tap(start, until: app.buttons["Close"], in: app)
        let offer = app.buttons["graduationOffer"]
        XCTAssertTrue(offer.waitForExistence(timeout: 10), "No graduation offer on the last step")
        for _ in 0..<3 where !offer.isHittable { app.swipeUp() }
        let seen = NSPredicate { _, _ in
            self.loggedEvents().count(of: "upsell_shown", source: "path_graduation") == 1
        }
        expectation(for: seen, evaluatedWith: nil)
        waitForExpectations(timeout: 10)
        app.swipeDown()
        app.swipeUp()
        XCTAssertEqual(loggedEvents().count(of: "upsell_shown", source: "path_graduation"), 1)
        offer.tap()
        let opened = NSPredicate { _, _ in
            self.loggedEvents().count(of: "paywall_opened", source: "path_graduation") == 1
        }
        expectation(for: opened, evaluatedWith: nil)
        waitForExpectations(timeout: 10)
    }

    /// Once the day's puzzles are solved, the hero points at the next Journey
    /// instead of Play again, and Keep going doesn't list that Journey twice.
    @MainActor
    func testSolvedHeroOffersTheNextJourney() throws {
        let app = launch(extra: ["-uiSeedShowcase", "-uiAutoSolve", "-uiNoReview"])
        for _ in 0..<2 {
            // Auto-solve finishes on open, so no keypad to wait for.
            let hero = app.buttons["Start Puzzle"]
            XCTAssertTrue(hero.waitForExistence(timeout: 20))
            let close = app.buttons["Close"]
            tap(hero, until: close, in: app)
            close.tap()
        }
        let next = app.buttons["heroNextJourney"]
        XCTAssertTrue(next.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.buttons["Play again"].exists)
        let journey = next.label.replacingOccurrences(of: "Next: ", with: "")
        let shelfRows = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Journey. \(journey)"))
        XCTAssertEqual(shelfRows.count, 0, "Keep going repeats the hero's Journey")
    }

    /// Daily Bread on Today. The impression logs once however often Today
    /// reappears (here: after the verse sheet and a pushed memory grid), and
    /// the ring closing logs once, after the third beat.
    @MainActor
    func testDailyRitualLogsOnceAndClosesAfterThreeBeats() throws {
        // The showcase seeds a solve dated today (daily-001, Isaiah 11:6), so
        // beat one is done and its verse is waiting.
        let app = launch(extra: ["-uiSeedShowcase", "-uiAutoSolve", "-uiNoReview"])
        let verse = app.buttons["ritualVerse"]
        XCTAssertTrue(verse.waitForExistence(timeout: 20), app.debugDescription)
        for _ in 0..<3 where !verse.isHittable { app.swipeUp() }
        let seen = NSPredicate { _, _ in self.loggedEvents().count(of: "daily_ritual_shown") == 1 }
        expectation(for: seen, evaluatedWith: nil)
        waitForExpectations(timeout: 10)

        // Beat two: read the verse, and put it on the memory shelf.
        verse.tap()
        let learn = app.buttons["ritualVerseLearn"]
        XCTAssertTrue(learn.waitForExistence(timeout: 10), app.debugDescription)
        learn.tap()

        // Beat three: the verse just learned, as its first grid. Auto-solve
        // finishes it; the completion sheet's Done pops back to Today.
        let review = app.buttons["ritualReview"]
        XCTAssertTrue(review.waitForExistence(timeout: 10))
        review.tap()
        let done = app.buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 15), "No completion sheet\n\(app.debugDescription)")
        done.tap()
        XCTAssertTrue(verse.waitForExistence(timeout: 10), "Didn't return to Today")

        let closed = NSPredicate { _, _ in self.loggedEvents().count(of: "daily_ritual_completed") == 1 }
        expectation(for: closed, evaluatedWith: nil)
        waitForExpectations(timeout: 10)

        let events = loggedEvents()
        XCTAssertEqual(events.count(of: "daily_ritual_shown"), 1, "\(events)")
        XCTAssertEqual(events.count(of: "daily_ritual_verse_read"), 1, "\(events)")
        XCTAssertEqual(events.count(of: "memory_verse_added", source: "daily_ritual"), 1, "\(events)")
        XCTAssertEqual(events.count(of: "memory_verse_started", source: "daily_ritual"), 1, "\(events)")
        XCTAssertEqual(events.count(of: "memory_verse_completed", source: "daily_ritual"), 1, "\(events)")
    }

    /// Today's Premium row logs its impression once, only once it's scrolled
    /// into view — not on layout at the foot of the page — and not again on
    /// scrolling away and back or on returning to the tab.
    @MainActor
    func testTodayPremiumRowLogsOnceWhenSeen() throws {
        let app = launch(extra: ["-uiFree"])
        let row = app.buttons["upgradeRow"]
        XCTAssertTrue(row.waitForExistence(timeout: 20), "No Premium row on Today")
        XCTAssertEqual(loggedEvents().count(of: "upsell_shown", source: "home_card"), 0,
                       "Logged before the row was scrolled to")
        for _ in 0..<8 where !row.isHittable { app.swipeUp() }
        let seen = NSPredicate { _, _ in
            self.loggedEvents().count(of: "upsell_shown", source: "home_card") == 1
        }
        expectation(for: seen, evaluatedWith: nil)
        waitForExpectations(timeout: 10)

        // Away and back: a scroll, then a tab switch, which re-runs Today's
        // onAppear the way a pop back does.
        app.swipeDown()
        app.swipeDown()
        app.tabBars.buttons["Puzzles"].tap()
        app.tabBars.buttons["Today"].tap()
        for _ in 0..<8 where !row.isHittable { app.swipeUp() }
        XCTAssertTrue(row.isHittable)
        XCTAssertEqual(loggedEvents().count(of: "upsell_shown", source: "home_card"), 1, "\(loggedEvents())")

        row.tap()
        let opened = NSPredicate { _, _ in
            self.loggedEvents().count(of: "paywall_opened", source: "home_card") == 1
        }
        expectation(for: opened, evaluatedWith: nil)
        waitForExpectations(timeout: 10)
    }

    /// With `premium-row-up` on, the row leads the column, above Keep going,
    /// and keeps its source.
    @MainActor
    func testPromotedPremiumRowLeadsTheColumn() throws {
        let app = launch(extra: ["-uiFree", "-uiForcePremiumRowUp"])
        let row = app.buttons["upgradeRow"]
        let keepGoing = app.staticTexts["Keep going"]
        XCTAssertTrue(row.waitForExistence(timeout: 20), "No Premium row on Today")
        XCTAssertTrue(keepGoing.waitForExistence(timeout: 10))
        XCTAssertLessThan(row.frame.minY, keepGoing.frame.minY, "The row didn't move up")
        XCTAssertEqual(app.buttons.matching(identifier: "upgradeRow").count, 1, "The row shows twice")
    }

    // MARK: - Helpers

    @MainActor
    private func launch(onboarded: Bool = true, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        // Straight to the tabs: the `hasOnboarded` default, via the
        // argument domain `@AppStorage` reads. `onboarded: false` runs the
        // first-launch flow instead, and passes nothing: an argument would
        // outrank the write that ends onboarding, and it would never end.
        // `-uiCleanSlate`: in-memory store and no saved settings, so tests
        // can't see each other's solves.
        app.launchArguments = ["-uiCleanSlate"] + (onboarded ? ["-hasOnboarded", "YES"] : []) + extra
        app.launchEnvironment["UI_ANALYTICS_LOG"] = logURL.path
        app.launch()
        return app
    }

    /// Taps until `target` shows. `-uiCleanSlate` skips Game Center sign-in,
    /// but a sheet from a non-test launch could still be up; clear it first.
    @MainActor
    private func tap(_ button: XCUIElement, until target: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<3 {
            let gameCenter = app.buttons["UIA.GameCenter.SignIn.cancelButton"]
            if gameCenter.exists { gameCenter.tap() }
            if button.exists { button.tap() }
            if target.waitForExistence(timeout: 10) { return }
        }
        XCTFail("\(target) never appeared\n\(app.debugDescription)", file: #filePath, line: #line)
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

    /// The log once `name` is in it, or as it stands after `timeout`: for an
    /// event the app logs on its own time rather than in step with the UI.
    private func loggedEvents(waitingFor name: String, timeout: TimeInterval = 5) -> [String] {
        let deadline = Date().addingTimeInterval(timeout)
        var events = loggedEvents()
        while events.count(of: name) == 0, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            events = loggedEvents()
        }
        return events
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
