//
//  Analytics.swift
//  Bible Crossword Challenge
//
//  Analytics abstraction. `FirebaseAnalyticsService` is the production backend
//  (the environment default — see AppEnvironment). `ConsoleAnalyticsService`
//  remains for previews/tests that want no network side effects.
//

import Foundation

/// The control a player used to leave a paywall surface. Raw values are the
/// `exit` property on `paywall_dismissed`.
///
/// Small on purpose. `close` is the ✕; `free_link` is "Continue with today's
/// free puzzle" (onboarding only — the sheet has no free exit, the ✕ is it).
/// `swipe` is the sheet pulled down, and also covers a parent view dismissing
/// it, which SwiftUI can't tell apart in `onDisappear`. The last three are
/// onboarding leaving on the player's behalf: after a purchase, after they
/// backed out of Apple's sheet, or from the "Continue" that replaces the buy
/// button once a Restore on that page finds them already subscribed.
enum PaywallExit: String {
    case close
    case freeLink = "free_link"
    case swipe
    case purchase
    case afterCancel = "after_cancel"
    case premiumContinue = "premium_continue"
    /// The CTA with no product behind it — should be unreachable, since the
    /// button is hidden until products load, but the fallback exists in code.
    case noPlan = "no_plan"
}

enum AnalyticsEvent {
    case appOpen
    // First-run funnel. `onboardingStep` fires on every entry to a page, so
    // count distinct users per step rather than raw events; the other two fire
    // once each. Together they answer the question the redesign was a bet on:
    // does solving a clue up front make people finish onboarding?
    case onboardingStep(index: Int, name: String)
    case onboardingFirstSolve(solved: Bool, attempts: Int)
    case onboardingCompleted(solvedFirstClue: Bool)
    /// Fires on every entry to the game screen, so `isResume` is what makes it
    /// readable: without it a player who opens the daily four times counts as
    /// four starts, and the start→completion rate reads a third lower than it
    /// is. A fresh start is `isResume: false`; everything else is the same
    /// attempt continuing. `source` is the surface whose navigation pushed the
    /// screen (`home` / `library` / `pack`) — quick closes cluster somewhere,
    /// and until 2026-08-28 nothing said where.
    case dailyPuzzleStarted(puzzleID: String, isResume: Bool, source: String)
    case dailyPuzzleCompleted(puzzleID: String, seconds: Int)
    /// Leaving the game screen mid-solve — the other half of the start→complete
    /// funnel, which previously had no shape: 55% of starters didn't finish and
    /// nothing said whether they bounced at the empty grid or gave up at 80%.
    /// `fillPercent` is where they stopped, `seconds` how long they tried on
    /// the *active* clock (rendered ticks only — a sub-second bounce can
    /// legitimately report 0), `wallSeconds` the wall-clock time the screen was
    /// open, so a fast bounce is distinguishable from a prewarm-and-detach.
    /// `hintsUsed` is this sitting's hints. Fires when the screen leaves the
    /// window, so a quit via app-kill from the background is not counted — the
    /// numbers are a floor, not a census.
    case puzzleAbandoned(puzzleID: String, fillPercent: Int, seconds: Int, wallSeconds: Int, hintsUsed: Int, cellTaps: Int, keyPresses: Int)

    /// Wall-clock ceiling for a `bounce`: an exit with no cell tap and no key
    /// press below this is someone who opened the screen and left, not someone
    /// who tried and gave up.
    ///
    /// Fifteen seconds is where the data separates, not a round number. Of the
    /// 152 zero-interaction exits in the 21 days to 2026-09-18, 136 were under
    /// 15s wall (81 under 5s, 55 from 5–15s) and then it falls off a cliff:
    /// 6 in 15–30s, 6 in 30–120s. The ones past the cliff average 36% fill —
    /// a gifted grid someone actually considered — so they are real
    /// abandonments and must stay in the rate.
    ///
    /// This matters because these exits are a third of `puzzle_abandoned` and
    /// nothing could ever rescue them: the median is 2s active / 4s wall, and
    /// the earliest stall nudge fires at 12s. Every abandonment number tuned
    /// before this flag existed — nudge timings, gift thresholds — was fitted
    /// against a metric a third of which was noise.
    static let bounceWallSeconds = 15
    case hintUsed(type: String, cost: Int)
    /// A paid hint tapped with no quota left. Logged at the wall, not at the
    /// paywall: the inline notice that replaced the auto-opened sheet
    /// (2026-09-02) means `paywall_opened` with `source=hint_limit` now counts
    /// only players who chose to tap through, so this keeps the wall itself
    /// measurable. `type` is the rung they reached for.
    case hintLimitReached(type: String)
    /// A free one-shot answer check (letter/word/puzzle scope). Separate from
    /// `hintUsed` because checks cost nothing — the interesting read is whether
    /// check-availability moves hint usage and completion rate.
    case checkUsed(scope: String, wrongCount: Int)
    /// The mid-solve rescue line, shown after `idleSeconds` of active-clock
    /// silence. `kind` is the tier (see `GameViewModel.StallNudgeKind`):
    /// `check` or `verse` at ≥ 40% fill, `hints` (the hints button bounces)
    /// under 40% after a shorter idle, or mid-solve with nothing else to
    /// offer. `hints` was `free_letter` before 2026-10-24 — a free reveal.
    /// A `hints` tap is the bulb tapped while that nudge stands.
    /// Shown/tapped pair so each fill bucket of the abandon histogram can be
    /// read against whether its nudge is being seen, taken, and followed by a
    /// completion.
    case stallNudgeShown(puzzleID: String, fillPercent: Int, idleSeconds: Int, kind: String)
    case stallNudgeTapped(puzzleID: String, fillPercent: Int, idleSeconds: Int, kind: String)
    /// A new player's session opened with the starter word filled in for free
    /// (see `GameViewModel.giftStarterWord`). Fires on every fresh (non-resume)
    /// puzzle open until the third completion — once per install proved too
    /// little: the one engineered win was spent on a single puzzle and quick
    /// closes stayed at 43% of abandons. The read: do gifted sessions complete
    /// more often than the pre-gift baseline, whose abandons piled up under
    /// 10% fill (287 of 675 in the 30 days to 2026-08-27)? Compare
    /// `daily_puzzle_completed` rates for sessions with and without this event.
    case starterWordGifted(puzzleID: String, answerLength: Int)
    /// A widget tap landed in the app. `destination` is which surface the tap
    /// resolved to (`daily` / `mini` / `today`) — the widget picks the most
    /// useful next action, and this is the read on whether players take it.
    case widgetOpened(destination: String)
    /// The completion screen's once-ever line offering the Verse of the Day
    /// widget came into view (after a third solve), and was tapped for the
    /// how-to. Read against `widget_opened`, which was 0 in the 30 days to
    /// 2026-10-14: nobody added a widget nobody had told them about.
    case widgetOfferShown
    case widgetOfferTapped
    /// A local notification was tapped. `kind` is `daily`, `winback` (the
    /// passive daily copy after a lapse), `streak_risk` or `pack_news`;
    /// `dayOffset` is which day of the 14-day horizon a daily one was scheduled
    /// for. Until 2026-10 a reminder tap left no trace — the app just opened —
    /// so "do reminders bring people back?" had no answer. Read it against
    /// `notification_permission` grants and next-day return.
    case notificationTapped(kind: String, dayOffset: Int?)
    case streakUpdated(streak: Int)
    // The two halves of a lost streak. `streakBroken` fires once, on the launch
    // that resets it (see `Streaks.Outcome`), carrying what was lost — the
    // length is the interesting part, since a 3-day lapse and a 60-day one are
    // different events. `streakComebackStarted` fires on the solve that starts
    // the next one, so the pair answers: after a break, do they come back, from
    // where, and how long did the lost streak have to be before they don't.
    case streakBroken(previousLength: Int)
    case streakComebackStarted(source: String)
    case achievementUnlocked(id: String)
    // Purchases. `isTrial` is what StoreKit actually applied, so a trial start
    // and a paid conversion are never counted as the same thing — the yearly
    // plan carries a free trial and is the default selection, so without this
    // nearly every "purchase" is really a trial that may still churn.
    //
    // `acquisition` records which path granted the entitlement. Until 2026-08-04
    // this event was emitted by the two paywall views, so it only ever saw a
    // purchase that began *and* finished inside one uninterrupted call — an Ask
    // to Buy approval, a purchase made on another device, and a trial that
    // converted while the app was closed all landed silently. `StoreService`
    // now owns the event, keyed on the transaction, so every grant is counted
    // once; `acquisition` is how a self-serve tap is told apart from the rest.
    case premiumPurchased(
        plan: String,
        source: String,
        isTrial: Bool,
        amount: StoreService.PurchaseAmount,
        acquisition: String
    )
    /// A subscription billing period that renewed. Deliberately *not*
    /// `premium_purchased`: a renewal is real revenue but not a new customer,
    /// and folding the two together would make the purchase count drift away
    /// from anything App Store Connect reports.
    case subscriptionRenewed(plan: String, isTrial: Bool, amount: StoreService.PurchaseAmount)
    /// Fires when a purchase attempt ends without an entitlement for a reason
    /// other than the player simply cancelling, so "opened the paywall and
    /// didn't buy" can be split from "tried to buy and it broke".
    case purchaseFailed(plan: String, source: String, reason: String)
    /// The player pressed the CTA, saw Apple's sheet, and backed out of it.
    ///
    /// Until 2026-09-07 this was only derivable — a `paywall_cta_tapped` with
    /// nothing after it — which also matched a player who quit the app with
    /// the sheet up, and needed a timestamp join to count. It is the single
    /// largest leak in the funnel (17 cancels to 16 purchases in the 30 days
    /// before this shipped), so it gets a row of its own, with the price the
    /// sheet showed, from the one place that sees every cancel on every
    /// surface: `StoreService.purchase`.
    ///
    /// `elapsedMs` is tap → result. A human cancel takes seconds; one under a
    /// quarter-second means Apple's sheet never appeared (3 of 15 cancellers
    /// in Sep 2026 sat at 70–210 ms). `canMakePayments` and `path` are there
    /// to tell those apart — a Screen Time purchase block versus a failure on
    /// the RevenueCat package or bare-product route.
    case purchaseCancelled(
        plan: String, source: String, offersTrial: Bool, amount: StoreService.PurchaseAmount,
        elapsedMs: Int, canMakePayments: Bool, path: String
    )
    /// An inline upsell came on screen. The denominator for its
    /// `paywall_opened` taps — a row the player scrolls past never opens a
    /// paywall, so without this its tap rate can't be read.
    case upsellShown(source: String)
    case paywallOpened(source: String)
    /// The moment someone commits — the buy button, before StoreKit takes over.
    ///
    /// Without it, "read the paywall and closed it" and "tried to buy and
    /// backed out at the sheet" are the same shape in the data: no purchase,
    /// no failure, nothing. They are completely different problems — the first
    /// is the offer, the second is price shock or friction at the till — and
    /// the fix for one does nothing for the other.
    ///
    /// A cancel at the sheet is its own event, `purchase_cancelled`; a tap with
    /// nothing at all after it is a player who quit with the sheet up.
    case paywallCTATapped(plan: String, source: String, offersTrial: Bool)
    /// The player left a paywall surface — the ✕, a sheet swipe, the free-exit
    /// button, or the dismissal that follows a purchase. Fired by both selling
    /// surfaces (the sheet and onboarding's offer page), once per presentation.
    ///
    /// This is the missing half of `paywall_opened`: without it, someone who
    /// read the offer for forty seconds and someone who closed it on sight are
    /// the same row, and "the price scares them off" can't be told apart from
    /// "they never read it". `seconds_on_screen` is the split.
    ///
    /// `cta_tapped` marks whether the commit button was pressed during this
    /// presentation, so a plain bounce can be isolated without joining against
    /// `paywall_cta_tapped` by timestamp. Deliberately no `purchased` flag:
    /// `premium_purchased` is StoreService's, keyed on the transaction, and a
    /// second opinion here would drift from it (Ask to Buy, grants that land
    /// after the sheet is gone). A quit-the-app exit emits nothing — this event
    /// undercounts the hardest bounces, so read it beside session data.
    ///
    /// `exit` names the control that took them out (see `PaywallExit`). Added
    /// 2026-09-07 to answer one question: does the ✕ carry the exits, or does
    /// the free-puzzle link? The ✕ was added on 2026-08-23 because a third of
    /// onboarding reachers quit the app on the offer page rather than find a
    /// way out; removing it again is only safe if the link is what people
    /// actually use. Without this property the two were one row.
    case paywallDismissed(source: String, secondsOnScreen: Int, ctaTapped: Bool, exit: PaywallExit)
    /// `source` names the surface whose button reached the system dialog
    /// (`onboarding`, `prompt`, `completion`, `streak_card`, `profile`) — the
    /// grant rate is per-ask, and without the source every surface's yes and no
    /// landed in one indistinguishable pile.
    case notificationPermission(granted: Bool, source: String)
    /// A reminder ask was put in front of the player (impression, not outcome),
    /// so each surface has a denominator. Same source vocabulary as
    /// `notificationPermission`.
    case reminderAskShown(source: String)
    /// The player declined reminders in the app, before iOS was ever asked.
    ///
    /// Without this the decline was invisible: `notification_permission` only
    /// fires once `requestAuthorization` runs, so tapping "Not now" produced no
    /// event at all and the drop-off could only be inferred by subtracting the
    /// prompts from the people who reached the page. That subtraction said two
    /// thirds decline in-app — a bigger leak than the system prompt's — which
    /// is too large a number to keep estimating.
    ///
    /// `source` names the surface, since onboarding's page and the standalone
    /// `DailyReminderPrompt` ask the same question at very different moments.
    case reminderDeclined(source: String)
    case reminderSettingChanged(enabled: Bool)
    /// Seasonal pack news turned on or off in Settings — a separate consent from
    /// the daily reminder, so a separate event.
    ///
    /// It has no ask surface of its own: the row is the only way to reach it,
    /// and it starts off. Whether seasonal packs keep a notification channel at
    /// all rests on how many people ever find it and say yes, which is a number
    /// nothing else in this enum can answer — `reminder_setting_changed` counts
    /// a different consent, and pack notices no longer follow from it.
    case packNewsSettingChanged(enabled: Bool)
    /// The system review prompt was *called* (Apple decides whether it shows —
    /// display rate is invisible, so calls are the only tunable denominator).
    /// `trigger` names the `ReviewAsk` rung ("milestone_75", "streak",
    /// "version"); `totalCompleted` says where in the ladder players sit when
    /// each trigger fires, which is the number the ladder is tuned against.
    case reviewPromptRequested(trigger: String, totalCompleted: Int)
    /// `source` names the surface that pushed the pack (`home`, `packs`,
    /// `notification`) — the question a seasonal pack raises is not how many
    /// people opened it but which surface got them there, and the Home carousel
    /// and the Packs tab were previously indistinguishable.
    case packOpened(id: String, source: String)
    case packCompleted(id: String)
    /// Journey Quests. `quest_opened` mirrors `pack_opened` (`source` = which
    /// surface pushed the detail screen). `quest_step_completed` fires on the
    /// first completion of any quest member puzzle, carrying how deep into the
    /// line it landed — the read is whether the one-a-day framing actually
    /// produces day-over-day returns (step N events on N distinct days) or
    /// binging. `quest_completed` is the badge moment, logged where it
    /// happens (the game screen's completion hook), once per quest.
    case questOpened(id: String, source: String)
    case questStepCompleted(id: String, step: Int, total: Int)
    case questCompleted(id: String)
    /// Logged when the share sheet reports the link actually went somewhere —
    /// not when it was presented. 30 days to 2026-08-24: 22 "sent" at
    /// presentation, 0 ever opened; whether links even leave the phone was
    /// unmeasurable. `challengeShareCancelled` is the other half of that split.
    case challengeSent(puzzleID: String)
    /// `via` is `link` (a tapped link, the app already installed) or
    /// `pasteboard` (carried across an App Store install — the invite worked
    /// on someone new). Zero of these had ever fired before 2026-09-07; the
    /// split says which half of the fix is doing the work.
    case challengeOpened(puzzleID: String, via: String)
    case challengeCompleted(puzzleID: String, won: Bool, deltaSeconds: Int)
    case challengeRematchSent(puzzleID: String)
    case challengeShareCancelled(puzzleID: String)
    /// The family board, which travels as a link rather than living on a server.
    /// `size` is how many names the board carried at that moment — the only
    /// measure of whether a board actually spread past two people, since there
    /// is nothing server-side to count.
    case familyBoardStarted(puzzleID: String)
    case familyBoardOpened(puzzleID: String, size: Int)
    case familyBoardShared(puzzleID: String, size: Int)
    /// Someone opened a passage in the reader. `source` separates the two ways
    /// in — the Verse of the Day at the top of Today, and the closing verse
    /// after a solve — because they answer different questions: the first is
    /// whether the verse earns its place above the daily puzzle card, the
    /// second whether finishing a puzzle actually sends anyone to Scripture.
    /// Both were unmeasured, so any claim about either was a guess.
    case scriptureOpened(reference: String, source: String)
    /// The other half of `scriptureOpened`. In the 30 days to 2026-09-03 the
    /// reader was opened 1,630 times and nothing said how long anyone stayed
    /// or whether they read past the verse they came for — 92% of those opens
    /// were the mid-puzzle verse hint, which is consulting, not reading.
    /// `seconds` is wall time open; `chaptersPaged` counts page turns after
    /// the first chapter settled; `scrolledPastVerse` is whether the player
    /// scrolled a deep-linked verse's page by hand; `expanded` is whether the
    /// verse-first hint sheet was opened out to the full chapter (always true
    /// for the chapter reader itself).
    case readerClosed(source: String, seconds: Int, chaptersPaged: Int, scrolledPastVerse: Bool, expanded: Bool)
    /// The reader's long-press: `kind` is memorize / bookmark / share / copy.
    /// Memorize from here was the first way into memory verses that isn't a
    /// solved puzzle; `memory_verse_added.source` now names every door.
    case verseAction(kind: String, reference: String)
    case bookmarksOpened(count: Int)
    /// A submitted search on the Read tab. `kind` is what the query resolved
    /// to — reference / book / word / none — and `results` how many rows it
    /// produced. Reaching a chapter was three taps with no search until 2.9.
    case readSearch(kind: String, results: Int)
    /// Card shares. `kind` is the campaign token the link carries —
    /// `share_card` (completion scorecard) or `share_verse` (reader) — so
    /// these pair with App Store Connect's Campaigns report. `shareOpened`
    /// is the tap; `shareCompleted` is the sheet closing, with whether a
    /// destination was actually picked.
    case shareOpened(kind: String)
    /// The completion screen's result block, which carries enough about the
    /// solve to segment sends: does a clean solve travel further than a hinted
    /// one, and does the Mini (which renders 1:1) beat the downsampled Daily.
    /// Logs as `share_opened` with the same `share_card` token, so the ASC
    /// Campaigns series stays continuous across this change.
    case resultShareOpened(
        puzzleID: String, puzzleKind: String, hintsUsed: Int, seconds: Int, gridCells: Int
    )
    case shareCompleted(kind: String, completed: Bool)
    // The chapter-a-day plan. `day` is 1-based within the book.
    case planStarted(plan: String)
    case planChapterRead(plan: String, day: Int)
    case planCompleted(plan: String, days: Int)
    case planStopped(plan: String, day: Int)
    /// The mini→daily chain: the completion screen's offer to roll straight
    /// into today's full puzzle. Completing a puzzle on day one is the
    /// strongest D1 retention signal we have, so the button is measured
    /// directly rather than inferred from back-to-back `daily_puzzle_started`.
    case completionChainTapped(fromPuzzleID: String, toPuzzleID: String)
    // Memory-verse mode. `level` on start/complete is the mastery level the
    // grid was built at, so the level-4 hint rate — the full-recall cliff —
    // can be read directly. `leveled_up` false with `hints_used` 0 means the
    // anti-grind spacing held the level, not a failure.
    //
    // `added` is a verse entering the list; `started` is a practice session
    // opening. Both carry `source` — the door: `list`, `completion` (the
    // solve's verse block), `hint_sheet` (the verse hint mid-grid), or
    // `reader` (the chapter long-press). In the 30 days to 2026-09-10 the
    // list was the only door in use — 37 of 38 list opens came from the Today
    // card — so the split is the readout on the two doors added since.
    case memoryListOpened(source: String)
    case memoryVerseAdded(reference: String, source: String)
    case memoryVerseStarted(reference: String, level: Int, source: String)
    case memoryVerseCompleted(reference: String, level: Int, leveledUp: Bool, hintsUsed: Int)
    case memoryVerseMastered(reference: String)
    // The two screens re-homed in 2.8: the journey map moved from Profile to
    // the Read tab, and achievements lost their tab for a Profile card and a
    // tappable next-achievement card on Today. `source` says which door.
    case journeyOpened(source: String)
    case achievementsOpened(source: String)
    // MetricKit diagnostics, forwarded by `CrashReporter` on the launch after
    // the event. The app has no crash SDK, and in the 30 days to 2026-09-03,
    // 19 of 51 day-0 non-finishers on 2.0+ builds logged a puzzle start and
    // then nothing at all — not even `Application Backgrounded`. A crash and
    // an app-kill before the analytics queue flushed look identical from the
    // outside; these two events are what makes them distinguishable.
    // `build` and `os` come from the payload, not the running app, because
    // the crash may predate an update. `frames` is the crashed thread's
    // deepest frames as `Binary+0xoffset` (symbolicate with `atos` against
    // that build's dSYM); `app_frames` is the subset in our own binary, which
    // is the grouping key.
    case appCrash(signal: Int?, exceptionType: Int?, exceptionCode: Int?, reason: String?, build: String, os: String, frames: String, appFrames: String)
    case appHang(seconds: Double, build: String, os: String, frames: String, appFrames: String)

    var name: String {
        switch self {
        case .appOpen: return "app_open"
        case .onboardingStep: return "onboarding_step"
        case .onboardingFirstSolve: return "onboarding_first_solve"
        case .onboardingCompleted: return "onboarding_completed"
        case .dailyPuzzleStarted: return "daily_puzzle_started"
        case .dailyPuzzleCompleted: return "daily_puzzle_completed"
        case .puzzleAbandoned: return "puzzle_abandoned"
        case .hintUsed: return "hint_used"
        case .hintLimitReached: return "hint_limit_reached"
        case .checkUsed: return "check_used"
        case .stallNudgeShown: return "stall_nudge_shown"
        case .stallNudgeTapped: return "stall_nudge_tapped"
        case .starterWordGifted: return "starter_word_gifted"
        case .widgetOpened: return "widget_opened"
        case .widgetOfferShown: return "widget_offer_shown"
        case .widgetOfferTapped: return "widget_offer_tapped"
        case .notificationTapped: return "notification_tapped"
        case .streakUpdated: return "streak_updated"
        case .streakBroken: return "streak_broken"
        case .streakComebackStarted: return "streak_comeback_started"
        case .achievementUnlocked: return "achievement_unlocked"
        case .premiumPurchased: return "premium_purchased"
        case .subscriptionRenewed: return "subscription_renewed"
        case .purchaseFailed: return "purchase_failed"
        case .purchaseCancelled: return "purchase_cancelled"
        case .upsellShown: return "upsell_shown"
        case .paywallOpened: return "paywall_opened"
        case .paywallCTATapped: return "paywall_cta_tapped"
        case .paywallDismissed: return "paywall_dismissed"
        case .notificationPermission: return "notification_permission"
        case .reminderAskShown: return "reminder_ask_shown"
        case .reminderDeclined: return "reminder_declined"
        case .reminderSettingChanged: return "reminder_setting_changed"
        case .packNewsSettingChanged: return "pack_news_setting_changed"
        case .reviewPromptRequested: return "review_prompt_requested"
        case .packOpened: return "pack_opened"
        case .packCompleted: return "pack_completed"
        case .questOpened: return "quest_opened"
        case .questStepCompleted: return "quest_step_completed"
        case .questCompleted: return "quest_completed"
        case .challengeSent: return "challenge_sent"
        case .challengeOpened: return "challenge_opened"
        case .challengeCompleted: return "challenge_completed"
        case .challengeRematchSent: return "challenge_rematch_sent"
        case .challengeShareCancelled: return "challenge_share_cancelled"
        case .familyBoardStarted: return "family_board_started"
        case .familyBoardOpened: return "family_board_opened"
        case .familyBoardShared: return "family_board_shared"
        case .scriptureOpened: return "scripture_opened"
        case .readerClosed: return "reader_closed"
        case .verseAction: return "verse_action"
        case .bookmarksOpened: return "bookmarks_opened"
        case .readSearch: return "read_search"
        case .shareOpened, .resultShareOpened: return "share_opened"
        case .shareCompleted: return "share_completed"
        case .planStarted: return "plan_started"
        case .planChapterRead: return "plan_chapter_read"
        case .planCompleted: return "plan_completed"
        case .planStopped: return "plan_stopped"
        case .completionChainTapped: return "completion_chain_tapped"
        case .memoryListOpened: return "memory_list_opened"
        case .memoryVerseAdded: return "memory_verse_added"
        case .memoryVerseStarted: return "memory_verse_started"
        case .memoryVerseCompleted: return "memory_verse_completed"
        case .memoryVerseMastered: return "memory_verse_mastered"
        case .journeyOpened: return "journey_opened"
        case .achievementsOpened: return "achievements_opened"
        case .appCrash: return "app_crash"
        case .appHang: return "app_hang"
        }
    }

    var parameters: [String: Any] {
        switch self {
        case .appOpen, .widgetOfferShown, .widgetOfferTapped:
            return [:]
        case .onboardingStep(let index, let name):
            return ["step_index": index, "step_name": name]
        case .onboardingFirstSolve(let solved, let attempts):
            return ["solved": solved, "attempts": attempts]
        case .onboardingCompleted(let solvedFirstClue):
            return ["solved_first_clue": solvedFirstClue]
        case .premiumPurchased(let plan, let source, let isTrial, let amount, let acquisition):
            return [
                "plan": plan,
                "source": source,
                "is_trial": isTrial,
                "acquisition": acquisition,
                // Money travels in whole minor units (2999 = $29.99) — the
                // `_minor_units` suffix is deliberate, so nobody later reads a
                // 2999 as a price. Point PostHog's Revenue tab at
                // `revenue_minor_units` + `currency`.
                "price_minor_units": amount.minorUnits,
                // What was charged *now*: zero for a trial start, so summing
                // per source gives real money rather than notional value.
                "revenue_minor_units": isTrial ? 0 : amount.minorUnits,
                "currency": amount.currencyCode,
            ]
        case .subscriptionRenewed(let plan, let isTrial, let amount):
            return [
                "plan": plan,
                "is_trial": isTrial,
                "price_minor_units": amount.minorUnits,
                "revenue_minor_units": isTrial ? 0 : amount.minorUnits,
                "currency": amount.currencyCode,
            ]
        case .purchaseFailed(let plan, let source, let reason):
            return ["plan": plan, "source": source, "reason": reason]
        case .purchaseCancelled(let plan, let source, let offersTrial, let amount,
                                let elapsedMs, let canMakePayments, let path):
            return [
                "plan": plan,
                "source": source,
                "offers_trial": offersTrial,
                // The number the sheet showed, so a cancel can be read against
                // the price the player was looking at when they backed out.
                "price_minor_units": amount.minorUnits,
                "currency": amount.currencyCode,
                "elapsed_ms": elapsedMs,
                "can_make_payments": canMakePayments,
                "path": path,
            ]
        case .upsellShown(let source):
            return ["source": source]
        case .paywallOpened(let source):
            return ["source": source]
        case .paywallCTATapped(let plan, let source, let offersTrial):
            return [
                "plan": plan,
                "source": source,
                // Deliberately not `is_trial`. That property, on
                // `premium_purchased`, is what StoreKit actually applied. This
                // is what the button was advertising when it was pressed —
                // which is the thing to compare tap rates against once a trial
                // is configured, and would be a different number.
                "offers_trial": offersTrial,
            ]
        case .paywallDismissed(let source, let secondsOnScreen, let ctaTapped, let exit):
            return [
                "source": source,
                "seconds_on_screen": secondsOnScreen,
                "cta_tapped": ctaTapped,
                "exit": exit.rawValue,
            ]
        case .dailyPuzzleStarted(let id, let isResume, let source):
            return ["puzzle_id": id, "is_resume": isResume, "source": source]
        case .dailyPuzzleCompleted(let id, let seconds):
            return ["puzzle_id": id, "seconds": seconds]
        case .puzzleAbandoned(let id, let fillPercent, let seconds, let wallSeconds, let hintsUsed, let cellTaps, let keyPresses):
            return [
                "puzzle_id": id,
                "fill_percent": fillPercent,
                "seconds": seconds,
                "wall_seconds": wallSeconds,
                "hints_used": hintsUsed,
                // Splits the 0%-fill bounce three ways — see
                // `GameViewModel.cellTaps`.
                "cell_taps": cellTaps,
                "key_presses": keyPresses,
                // Derived here rather than at the call site so one definition
                // governs every query, insight and dashboard.
                "bounce": cellTaps == 0 && keyPresses == 0
                    && wallSeconds < Self.bounceWallSeconds,
            ]
        case .hintUsed(let type, let cost):
            return ["type": type, "cost": cost]
        case .hintLimitReached(let type):
            return ["type": type]
        case .checkUsed(let scope, let wrongCount):
            return ["scope": scope, "wrong_count": wrongCount]
        case .stallNudgeShown(let puzzleID, let fillPercent, let idleSeconds, let kind),
             .stallNudgeTapped(let puzzleID, let fillPercent, let idleSeconds, let kind):
            return [
                "puzzle_id": puzzleID,
                "fill_percent": fillPercent,
                "idle_seconds": idleSeconds,
                "kind": kind,
            ]
        case .starterWordGifted(let puzzleID, let answerLength):
            return ["puzzle_id": puzzleID, "answer_length": answerLength]
        case .widgetOpened(let destination):
            return ["destination": destination]
        case .notificationTapped(let kind, let dayOffset):
            var params: [String: Any] = ["kind": kind]
            if let dayOffset { params["day_offset"] = dayOffset }
            return params
        case .streakUpdated(let streak):
            return ["streak": streak]
        case .streakBroken(let previousLength):
            return ["previous_length": previousLength]
        case .streakComebackStarted(let source):
            return ["source": source]
        case .achievementUnlocked(let id):
            return ["achievement_id": id]
        case .notificationPermission(let granted, let source):
            return ["granted": granted, "source": source]
        case .reminderAskShown(let source):
            return ["source": source]
        case .reminderDeclined(let source):
            return ["source": source]
        case .reminderSettingChanged(let enabled):
            return ["enabled": enabled]
        case .packNewsSettingChanged(let enabled):
            return ["enabled": enabled]
        case .reviewPromptRequested(let trigger, let totalCompleted):
            return ["trigger": trigger, "total_completed": totalCompleted]
        case .packOpened(let id, let source):
            return ["pack_id": id, "source": source]
        case .packCompleted(let id):
            return ["pack_id": id]
        case .questOpened(let id, let source):
            return ["quest_id": id, "source": source]
        case .questStepCompleted(let id, let step, let total):
            return ["quest_id": id, "step": step, "total": total]
        case .questCompleted(let id):
            return ["quest_id": id]
        case .challengeSent(let id):
            return ["puzzle_id": id]
        case .challengeOpened(let id, let via):
            return ["puzzle_id": id, "via": via]
        case .challengeCompleted(let id, let won, let delta):
            return ["puzzle_id": id, "won": won, "delta_seconds": delta]
        case .challengeRematchSent(let id):
            return ["puzzle_id": id]
        case .challengeShareCancelled(let id):
            return ["puzzle_id": id]
        case .familyBoardStarted(let id):
            return ["puzzle_id": id]
        case .familyBoardOpened(let id, let size):
            return ["puzzle_id": id, "size": size]
        case .familyBoardShared(let id, let size):
            return ["puzzle_id": id, "size": size]
        case .scriptureOpened(let reference, let source):
            return ["reference": reference, "source": source]
        case .verseAction(let kind, let reference):
            return ["kind": kind, "reference": reference]
        case .bookmarksOpened(let count):
            return ["count": count]
        case .readSearch(let kind, let results):
            return ["kind": kind, "results": results]
        case .shareOpened(let kind):
            return ["kind": kind]
        case .resultShareOpened(let puzzleID, let puzzleKind, let hintsUsed, let seconds, let gridCells):
            return [
                "kind": "share_card",
                "puzzle_id": puzzleID,
                "puzzle_kind": puzzleKind,
                "hints_used": hintsUsed,
                "seconds": seconds,
                "grid_cells": gridCells,
            ]
        case .shareCompleted(let kind, let completed):
            return ["kind": kind, "completed": completed]
        case .planStarted(let plan):
            return ["plan": plan]
        case .planChapterRead(let plan, let day), .planStopped(let plan, let day):
            return ["plan": plan, "day": day]
        case .planCompleted(let plan, let days):
            return ["plan": plan, "days": days]
        case .readerClosed(let source, let seconds, let chaptersPaged, let scrolledPastVerse, let expanded):
            return [
                "source": source,
                "seconds": seconds,
                "chapters_paged": chaptersPaged,
                "scrolled_past_verse": scrolledPastVerse,
                "expanded": expanded,
            ]
        case .completionChainTapped(let from, let to):
            return ["from_puzzle_id": from, "to_puzzle_id": to]
        case .memoryListOpened(let source):
            return ["source": source]
        case .memoryVerseAdded(let reference, let source):
            return ["reference": reference, "source": source]
        case .memoryVerseStarted(let reference, let level, let source):
            return ["reference": reference, "level": level, "source": source]
        case .memoryVerseCompleted(let reference, let level, let leveledUp, let hintsUsed):
            return [
                "reference": reference,
                "level": level,
                "leveled_up": leveledUp,
                "hints_used": hintsUsed,
            ]
        case .memoryVerseMastered(let reference):
            return ["reference": reference]
        case .journeyOpened(let source), .achievementsOpened(let source):
            return ["source": source]
        case .appCrash(let signal, let exceptionType, let exceptionCode, let reason, let build, let os, let frames, let appFrames):
            return [
                // -1 stands in for "not reported" — a dictionary of Any can't
                // carry nil, and a missing key would vanish from breakdowns.
                "signal": signal ?? -1,
                "exception_type": exceptionType ?? -1,
                "exception_code": exceptionCode ?? -1,
                "reason": reason ?? "",
                "build": build,
                "os": os,
                "frames": frames,
                "app_frames": appFrames,
            ]
        case .appHang(let seconds, let build, let os, let frames, let appFrames):
            return [
                "seconds": seconds,
                "build": build,
                "os": os,
                "frames": frames,
                "app_frames": appFrames,
            ]
        }
    }
}

protocol AnalyticsService {
    func log(_ event: AnalyticsEvent)
}

enum AnalyticsEnvironment {
    /// Simulator runs are development, never real usage, so no production
    /// backend should hear about them. Both PostHog and Firebase can filter
    /// them server-side after the fact — PostHog's SDK even stamps
    /// `$is_emulator` for exactly that — but those rules are query-time: the
    /// events are ingested, billed and counted first, and raw SQL or an
    /// un-toggled insight still sees them. Every simulator reinstall also mints
    /// a fresh anonymous id, which inflates unique-user counts wherever the
    /// filter isn't applied. Dropping at the source is the one place that can't
    /// be forgotten.
    ///
    /// Pass `-analyticsAllowSimulator` in the scheme's launch arguments to
    /// report anyway; that is the only way to confirm a newly added event
    /// actually reaches a backend without building to a device.
    /// `ConsoleAnalyticsService` still prints every event in DEBUG regardless,
    /// so day-to-day work on the simulator loses nothing.
    static var isSuppressedSimulatorRun: Bool {
        #if targetEnvironment(simulator)
        return !ProcessInfo.processInfo.arguments.contains("-analyticsAllowSimulator")
        #else
        return false
        #endif
    }
}

struct ConsoleAnalyticsService: AnalyticsService {
    static let shared = ConsoleAnalyticsService()

    func log(_ event: AnalyticsEvent) {
        #if DEBUG
        print("📊 \(event.name) \(event.parameters)")
        AnalyticsRecorder.record(event.name, source: event.parameters["source"] as? String)
        #endif
    }
}

/// Sends each event to every backend. Order is the order given; a slow or
/// misconfigured backend can't stop the others, because none of them throw.
struct MultiAnalyticsService: AnalyticsService {
    let services: [any AnalyticsService]

    init(_ services: [any AnalyticsService]) {
        self.services = services
    }

    func log(_ event: AnalyticsEvent) {
        for service in services {
            service.log(event)
        }
    }
}

extension MultiAnalyticsService {
    /// The production sink for the Firebase → PostHog overlap. Both backends
    /// collect everything so the two can be reconciled before Firebase is
    /// dropped; the Firebase half exists to keep the paywall-source history
    /// that started on 2026-07-19 continuous through the switch.
    static let production = MultiAnalyticsService([
        ConsoleAnalyticsService.shared,
        FirebaseAnalyticsService.shared,
        PostHogAnalyticsService.shared,
    ])
}
