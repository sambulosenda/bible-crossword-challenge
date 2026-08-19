//
//  Analytics.swift
//  Bible Crossword Challenge
//
//  Analytics abstraction. `FirebaseAnalyticsService` is the production backend
//  (the environment default — see AppEnvironment). `ConsoleAnalyticsService`
//  remains for previews/tests that want no network side effects.
//

import Foundation

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
    /// attempt continuing.
    case dailyPuzzleStarted(puzzleID: String, isResume: Bool)
    case dailyPuzzleCompleted(puzzleID: String, seconds: Int)
    /// Leaving the game screen mid-solve — the other half of the start→complete
    /// funnel, which previously had no shape: 55% of starters didn't finish and
    /// nothing said whether they bounced at the empty grid or gave up at 80%.
    /// `fillPercent` is where they stopped, `seconds` how long they tried,
    /// `hintsUsed` this sitting's hints. Fires when the screen leaves the
    /// window, so a quit via app-kill from the background is not counted — the
    /// numbers are a floor, not a census.
    case puzzleAbandoned(puzzleID: String, fillPercent: Int, seconds: Int, hintsUsed: Int)
    case hintUsed(type: String, cost: Int)
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
    case paywallOpened(source: String)
    /// The moment someone commits — the buy button, before StoreKit takes over.
    ///
    /// Without it, "read the paywall and closed it" and "tried to buy and
    /// backed out at the sheet" are the same shape in the data: no purchase,
    /// no failure, nothing. They are completely different problems — the first
    /// is the offer, the second is price shock or friction at the till — and
    /// the fix for one does nothing for the other.
    ///
    /// A cancel is the tap with no `premium_purchased` and no `purchase_failed`
    /// after it. Filter the purchase to `acquisition = in_app` when deriving
    /// that: a renewal or a cross-device grant arrives with no tap in front of
    /// it and would otherwise cancel one out.
    case paywallCTATapped(plan: String, source: String, offersTrial: Bool)
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
    /// `source` names the surface that pushed the pack (`home`, `packs`,
    /// `notification`) — the question a seasonal pack raises is not how many
    /// people opened it but which surface got them there, and the Home carousel
    /// and the Packs tab were previously indistinguishable.
    case packOpened(id: String, source: String)
    case packCompleted(id: String)
    case challengeSent(puzzleID: String)
    case challengeOpened(puzzleID: String)
    case challengeCompleted(puzzleID: String, won: Bool, deltaSeconds: Int)
    case challengeRematchSent(puzzleID: String)
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
    /// The mini→daily chain: the completion screen's offer to roll straight
    /// into today's full puzzle. Completing a puzzle on day one is the
    /// strongest D1 retention signal we have, so the button is measured
    /// directly rather than inferred from back-to-back `daily_puzzle_started`.
    case completionChainTapped(fromPuzzleID: String, toPuzzleID: String)
    // Memory-verse mode. `level` on start/complete is the mastery level the
    // grid was built at, so the level-4 hint rate — the full-recall cliff —
    // can be read directly. `leveled_up` false with `hints_used` 0 means the
    // anti-grind spacing held the level, not a failure.
    case memoryListOpened(source: String)
    case memoryVerseStarted(reference: String, level: Int)
    case memoryVerseCompleted(reference: String, level: Int, leveledUp: Bool, hintsUsed: Int)
    case memoryVerseMastered(reference: String)

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
        case .streakUpdated: return "streak_updated"
        case .streakBroken: return "streak_broken"
        case .streakComebackStarted: return "streak_comeback_started"
        case .achievementUnlocked: return "achievement_unlocked"
        case .premiumPurchased: return "premium_purchased"
        case .subscriptionRenewed: return "subscription_renewed"
        case .purchaseFailed: return "purchase_failed"
        case .paywallOpened: return "paywall_opened"
        case .paywallCTATapped: return "paywall_cta_tapped"
        case .notificationPermission: return "notification_permission"
        case .reminderAskShown: return "reminder_ask_shown"
        case .reminderDeclined: return "reminder_declined"
        case .reminderSettingChanged: return "reminder_setting_changed"
        case .packOpened: return "pack_opened"
        case .packCompleted: return "pack_completed"
        case .challengeSent: return "challenge_sent"
        case .challengeOpened: return "challenge_opened"
        case .challengeCompleted: return "challenge_completed"
        case .challengeRematchSent: return "challenge_rematch_sent"
        case .familyBoardStarted: return "family_board_started"
        case .familyBoardOpened: return "family_board_opened"
        case .familyBoardShared: return "family_board_shared"
        case .scriptureOpened: return "scripture_opened"
        case .completionChainTapped: return "completion_chain_tapped"
        case .memoryListOpened: return "memory_list_opened"
        case .memoryVerseStarted: return "memory_verse_started"
        case .memoryVerseCompleted: return "memory_verse_completed"
        case .memoryVerseMastered: return "memory_verse_mastered"
        }
    }

    var parameters: [String: Any] {
        switch self {
        case .appOpen:
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
        case .dailyPuzzleStarted(let id, let isResume):
            return ["puzzle_id": id, "is_resume": isResume]
        case .dailyPuzzleCompleted(let id, let seconds):
            return ["puzzle_id": id, "seconds": seconds]
        case .puzzleAbandoned(let id, let fillPercent, let seconds, let hintsUsed):
            return [
                "puzzle_id": id,
                "fill_percent": fillPercent,
                "seconds": seconds,
                "hints_used": hintsUsed,
            ]
        case .hintUsed(let type, let cost):
            return ["type": type, "cost": cost]
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
        case .packOpened(let id, let source):
            return ["pack_id": id, "source": source]
        case .packCompleted(let id):
            return ["pack_id": id]
        case .challengeSent(let id):
            return ["puzzle_id": id]
        case .challengeOpened(let id):
            return ["puzzle_id": id]
        case .challengeCompleted(let id, let won, let delta):
            return ["puzzle_id": id, "won": won, "delta_seconds": delta]
        case .challengeRematchSent(let id):
            return ["puzzle_id": id]
        case .familyBoardStarted(let id):
            return ["puzzle_id": id]
        case .familyBoardOpened(let id, let size):
            return ["puzzle_id": id, "size": size]
        case .familyBoardShared(let id, let size):
            return ["puzzle_id": id, "size": size]
        case .scriptureOpened(let reference, let source):
            return ["reference": reference, "source": source]
        case .completionChainTapped(let from, let to):
            return ["from_puzzle_id": from, "to_puzzle_id": to]
        case .memoryListOpened(let source):
            return ["source": source]
        case .memoryVerseStarted(let reference, let level):
            return ["reference": reference, "level": level]
        case .memoryVerseCompleted(let reference, let level, let leveledUp, let hintsUsed):
            return [
                "reference": reference,
                "level": level,
                "leveled_up": leveledUp,
                "hints_used": hintsUsed,
            ]
        case .memoryVerseMastered(let reference):
            return ["reference": reference]
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
