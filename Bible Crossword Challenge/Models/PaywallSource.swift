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
    /// The upgrade card on Today.
    case homeCard = "home_card"
    /// The upsell card on the profile screen.
    case profile
    /// A locked row, or the footer button, in the archive.
    case archive
    /// A premium collection the player opened but can't play.
    case packLocked = "pack_locked"
    /// Finishing a puzzle inside a pack whose remainder is locked.
    case packCompletion = "pack_completion"
    /// Finishing a Mini, with earlier Minis behind the wall.
    case miniCompletion = "mini_completion"
    /// A premium Journey's detail screen.
    case questLocked = "quest_locked"
    /// A locked puzzle in a book on the Bible map.
    case journey
    /// The free memory-verse cap, hit from the list or from the reader.
    case memoryVerseLimit = "memory_verse_limit"
    /// A locked puzzle chip under a chapter in the reader.
    case readChip = "read_chip"
    /// The one re-offer a player gets after backing out of Apple's sheet.
    /// See `TrialReoffer`.
    case trialAbandon = "trial_abandon"
    /// The app's one proactive ask on Today, once a player has the habit and
    /// has never asked for Premium themselves. See `PremiumAsk`.
    case premiumAsk = "premium_ask"
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
        case .hintLimit:
            return "Never stuck for long."
        case .homeCard:
            return "Make it part of the morning."
        case .archive:
            return PremiumCopy.archive
        case .packLocked:
            // The evergreen line. A seasonal pack states its own constraint —
            // see `PaywallView.headlineText`.
            return "The collections are waiting."
        case .packCompletion:
            return "The rest of the pack is waiting."
        case .miniCompletion:
            return "Two minutes was just the start."
        case .questLocked:
            // The Journey's own promise, in the words its locked state uses.
            return "Every Journey, a step a day."
        case .journey:
            // A locked puzzle inside a book: the gap is the rest of the book,
            // not the shelf.
            return "Every book, all the way through."
        case .memoryVerseLimit:
            // Names what the cap took, not the cap. The player is mid-verse
            // and being told to stop; "keep" is the outcome they wanted.
            return "Keep every verse you're learning."
        case .readChip:
            // They were reading, and the chapter offered a puzzle they can't
            // open. The promise is the pairing, which is the app's whole idea.
            return "A puzzle for every chapter you read."
        case .premiumAsk:
            // Nothing was withheld to get here — the player has simply kept
            // coming back — so the line names what the library holds rather
            // than a wall they just met. Depth is the honest reason to act, and
            // it is the one claim this player is finally in a position to care
            // about.
            //
            // One line, deliberately. It opened as "You've got the habit. The
            // shelf goes back years.", which is truer but ran to three lines on
            // a 402pt screen and pushed the trial timeline under the pinned
            // CTA — the page's strongest trust element, and the same fold this
            // screen already dropped a fourth benefit row to protect. The half
            // that was cut is the half the page states better anyway: the
            // progress line directly underneath is this player's own tally.
            return "The shelf goes back years."
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
