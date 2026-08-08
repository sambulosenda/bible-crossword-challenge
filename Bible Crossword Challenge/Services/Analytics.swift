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
    case dailyPuzzleStarted(puzzleID: String)
    case dailyPuzzleCompleted(puzzleID: String, seconds: Int)
    case hintUsed(type: String)
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
    case notificationPermission(granted: Bool)
    case reminderSettingChanged(enabled: Bool)
    case packOpened(id: String)
    case packCompleted(id: String)
    case challengeSent(puzzleID: String)
    case challengeOpened(puzzleID: String)
    case challengeCompleted(puzzleID: String, won: Bool, deltaSeconds: Int)
    case challengeRematchSent(puzzleID: String)
    /// Someone opened a passage in the reader. `source` separates the two ways
    /// in — the Verse of the Day at the top of Today, and the closing verse
    /// after a solve — because they answer different questions: the first is
    /// whether the verse earns its place above the daily puzzle card, the
    /// second whether finishing a puzzle actually sends anyone to Scripture.
    /// Both were unmeasured, so any claim about either was a guess.
    case scriptureOpened(reference: String, source: String)

    var name: String {
        switch self {
        case .appOpen: return "app_open"
        case .onboardingStep: return "onboarding_step"
        case .onboardingFirstSolve: return "onboarding_first_solve"
        case .onboardingCompleted: return "onboarding_completed"
        case .dailyPuzzleStarted: return "daily_puzzle_started"
        case .dailyPuzzleCompleted: return "daily_puzzle_completed"
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
        case .reminderSettingChanged: return "reminder_setting_changed"
        case .packOpened: return "pack_opened"
        case .packCompleted: return "pack_completed"
        case .challengeSent: return "challenge_sent"
        case .challengeOpened: return "challenge_opened"
        case .challengeCompleted: return "challenge_completed"
        case .challengeRematchSent: return "challenge_rematch_sent"
        case .scriptureOpened: return "scripture_opened"
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
        case .dailyPuzzleStarted(let id):
            return ["puzzle_id": id]
        case .dailyPuzzleCompleted(let id, let seconds):
            return ["puzzle_id": id, "seconds": seconds]
        case .hintUsed(let type):
            return ["type": type]
        case .streakUpdated(let streak):
            return ["streak": streak]
        case .streakBroken(let previousLength):
            return ["previous_length": previousLength]
        case .streakComebackStarted(let source):
            return ["source": source]
        case .achievementUnlocked(let id):
            return ["achievement_id": id]
        case .notificationPermission(let granted):
            return ["granted": granted]
        case .reminderSettingChanged(let enabled):
            return ["enabled": enabled]
        case .packOpened(let id):
            return ["pack_id": id]
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
        case .scriptureOpened(let reference, let source):
            return ["reference": reference, "source": source]
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
