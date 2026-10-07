//
//  PaywallSource.swift
//  Bible Crossword Challenge
//
//  Every place in the app that can open the paywall, as a type instead of a
//  string.
//
//  It used to be a bare `String`, matched inside `PaywallView` with a failable
//  `init(rawValue:)` that fell through to the standing promise when nothing
//  matched. That fallback was doing far more work than it looked: four live
//  entry points — the memory-verse cap, a locked step on a Journey, a locked
//  book on the map, and a locked puzzle chip under a chapter — had never been
//  added to the switch, so four walls in the app sold Premium with the line
//  written for a player who hadn't hit one. Nothing failed and nothing logged;
//  the copy just quietly went missing at the moment it mattered most.
//
//  As a type the same mistake can't compile. `headline` switches over every
//  case with no `default`, so a new entry point cannot be added without
//  deciding what it says.
//
//  The raw values are the analytics labels, unchanged — every `paywall_opened`,
//  `paywall_cta_tapped` and `premium_purchased` series keeps its history across
//  this change.
//

/// Where a paywall was opened from. Drives both the promise at the top of the
/// screen and the attribution on every event the screen emits.
enum PaywallSource: String, CaseIterable, Hashable {
    /// The daily hint quota ran out and the player tapped "Unlimited" on the
    /// inline notice.
    case hintLimit = "hint_limit"
    /// The offer card raised the first time in a puzzle a hint is refused.
    /// Its own label so it reads against the old chip's `hint_limit` taps.
    /// See `HintUpgradeSheet`.
    case hintLimitCard = "hint_limit_card"
    /// The one-time row under the verse on the completion screen — the
    /// second ask, after the player has finished a puzzle rather than
    /// 30 seconds into the app. Not `completion`: that label is a pre-2.0
    /// mis-attribution artifact and must stay filtered out of readouts.
    case completionOffer = "completion_offer"
    /// The upgrade card on Today.
    case homeCard = "home_card"
    /// The same card once the player has a streak of a week or more, when it
    /// speaks to the habit instead of the catalogue. Its own label so the
    /// streak copy can be judged against the plain card.
    case streakCard = "streak_card"
    /// The upsell card on the profile screen.
    case profile
    /// A locked row, or the footer button, in the archive.
    case archive
    /// A premium collection the player opened but can't play.
    case packLocked = "pack_locked"
    /// Finishing a puzzle inside a pack whose remainder is locked.
    case packCompletion = "pack_completion"
    /// A premium Journey's detail screen.
    case questLocked = "quest_locked"
    /// A locked puzzle in a book on the Bible map.
    case journey
    /// The one re-offer a player gets after backing out of Apple's sheet.
    /// See `TrialReoffer`.
    case trialAbandon = "trial_abandon"
    /// Onboarding's own premium page. It never presents `PaywallView` — the
    /// page builds `PremiumOfferView` itself and picks its own promise — but
    /// it shares the label so both surfaces land in one funnel.
    case onboarding

    /// The promise this entry point opens with.
    ///
    /// Someone who just hit a hint wall and someone browsing from their profile
    /// are asking different questions, and `source` is already threaded through
    /// for attribution — so the copy follows it with no new plumbing, and
    /// `premium_purchased` carries the same value to judge it by later.
    ///
    /// Deliberately exhaustive, with no `default`. The generic promise is a
    /// real answer for the surfaces that have no wall to name, but it has to be
    /// chosen rather than inherited: as a fallback it silently absorbed four
    /// entry points that each had something specific to say.
    ///
    /// Two of these are refined at the point of use, where the screen knows
    /// something this type can't — the season a pack is leaving in, and the
    /// length of the trial a player walked away from. See
    /// `PaywallView.headlineText`.
    var headline: String {
        switch self {
        case .hintLimit, .hintLimitCard:
            return "Never stuck for long."
        case .completionOffer:
            // They just finished one; the offer is the rest of it.
            return "There's so much more\nwhere that came from."
        case .homeCard:
            return "Make it part of the morning."
        case .streakCard:
            // They already have the habit; the offer is what's beyond the
            // daily. Nothing about the streak itself: Premium doesn't touch
            // it, and implying it protects one would be a lie.
            return "You've made it a habit.\nHere's the rest of it."
        case .archive:
            return PremiumCopy.archive
        case .packLocked:
            // The evergreen line. A seasonal pack states its own constraint —
            // see `PaywallView.headlineText`.
            return "The packs are waiting."
        case .packCompletion:
            return "The rest of the pack is waiting."
        case .questLocked:
            // The Journey's own promise, in the words its locked state uses.
            return "Every Journey, a step a day."
        case .journey:
            // A locked puzzle inside a book: the gap is the rest of the book,
            // not the shelf. Said as puzzles, because every benefit under it
            // is about play — "all the way through" read as a reading offer.
            return "Every puzzle, in every book."
        case .profile, .onboarding, .trialAbandon:
            // No wall behind them. A player who hasn't hit one needs telling
            // what the app is for, not what it withholds — and the re-offer
            // names the trial itself when the offer is still live.
            return PremiumCopy.promise
        }
    }

    /// Whether the paywall names the collections this player can't open yet.
    ///
    /// Only where they just bounced off a pack, where the strip is evidence
    /// about the very thing they asked for. Everywhere else it was a second
    /// icon-row list under the benefits — eight rows of prose between the
    /// promise and the price, about content the player never asked about.
    var showsLockedPacks: Bool {
        switch self {
        case .packLocked, .packCompletion: return true
        default: return false
        }
    }
}
