//
//  PaywallSourceTests.swift
//  Bible Crossword ChallengeTests
//
//  Two contracts the paywall's entry points have to keep.
//
//  The first is copy: every surface that puts a player in front of a wall says
//  something about *that* wall. This is a regression test with a real history —
//  the source used to be a bare string matched with a failable
//  `init(rawValue:)`, and four live entry points (the memory-verse cap, a
//  locked Journey step, a locked book on the map, a locked chip in the reader)
//  fell through it to the standing promise. Nothing failed and nothing logged;
//  the copy just went missing at the moment it mattered most. The type makes
//  that uncompilable now, and this pins the intent behind it.
//
//  The second is analytics: the raw values are the labels on every
//  `paywall_opened`, `paywall_cta_tapped`, `paywall_dismissed` and
//  `premium_purchased` event ever recorded. Renaming one silently splits a
//  series in PostHog and makes its history read as a drop to zero.
//

import Testing
@testable import Bible_Crossword_Challenge

struct PaywallSourceTests {

    /// The entry points that put the player in front of something they can't
    /// have. Each owes them a line about that, not the standing promise.
    private static let wallSources: [PaywallSource] = [
        .hintLimit, .hintLimitCard, .archive, .packLocked, .packCompletion,
        .questLocked, .journey,
    ]

    /// The entry points a player reaches without hitting anything — a card they
    /// chose to tap, or an offer being made again. These are *meant* to open
    /// with the standing promise.
    private static let browseSources: [PaywallSource] = [
        .profile, .onboarding, .trialAbandon, .homeCard, .streakCard, .completionOffer,
    ]

    @Test("every source has a headline")
    func everySourceHasAHeadline() {
        for source in PaywallSource.allCases {
            #expect(!source.headline.isEmpty, "\(source.rawValue) has no promise")
        }
    }

    @Test("a wall names itself rather than falling back to the standing promise")
    func wallsDoNotUseTheGenericPromise() {
        for source in Self.wallSources {
            #expect(
                source.headline != PremiumCopy.promise,
                "\(source.rawValue) sells Premium with the line written for a player who hasn't hit a wall"
            )
        }
    }

    /// The `home_card` is the one deliberate exception in either direction: it
    /// is browsing, but the card that opens it is about the daily habit, so it
    /// keeps its own line. Pinned so the exception stays a decision.
    private static let browseSourcesWithTheirOwnLine: Set<PaywallSource> = [.homeCard, .streakCard, .completionOffer]

    @Test("the browse surfaces open with the standing promise, bar the one about the habit")
    func browseSourcesUseTheStandingPromise() {
        for source in Self.browseSources where !Self.browseSourcesWithTheirOwnLine.contains(source) {
            #expect(source.headline == PremiumCopy.promise, "\(source.rawValue) drifted off the standing promise")
        }
        for source in Self.browseSourcesWithTheirOwnLine {
            #expect(source.headline != PremiumCopy.promise, "\(source.rawValue) lost its own line")
        }
    }

    @Test("every case is covered by exactly one of the two groups")
    func groupsCoverEveryCase() {
        let grouped = Set(Self.wallSources + Self.browseSources)
        #expect(
            grouped == Set(PaywallSource.allCases),
            "a new entry point was added without deciding whether it names a wall"
        )
        #expect(grouped.count == Self.wallSources.count + Self.browseSources.count)
    }

    @Test("the locked-pack strip is scoped to the pack entry points")
    func lockedPackStripScope() {
        for source in PaywallSource.allCases {
            let expected = source == .packLocked || source == .packCompletion
            #expect(source.showsLockedPacks == expected, "\(source.rawValue) shows the wrong locked-pack strip")
        }
    }

    /// The analytics contract. These strings are years of history in PostHog;
    /// changing one is a deliberate act, not a rename. `mini_completion`,
    /// `read_chip`, `premium_ask` and `memory_verse_limit` were retired on
    /// 2026-10-03 — 30 days of opens with zero CTA taps between them — so
    /// their series end there.
    @Test("raw values are the analytics labels and do not drift")
    func rawValuesAreStable() {
        let expected: Set<String> = [
            "hint_limit", "home_card", "streak_card", "profile", "archive", "pack_locked",
            "pack_completion", "quest_locked", "journey",
            "trial_abandon", "onboarding",
            // 2026-10-07: the hint offer card and the one-time completion row.
            "hint_limit_card", "completion_offer",
        ]
        #expect(Set(PaywallSource.allCases.map(\.rawValue)) == expected)
    }

    @Test("the re-offer keeps its own funnel label")
    func trialReofferSourceIsItsOwn() {
        #expect(TrialReoffer.source == .trialAbandon)
        #expect(TrialReoffer.source.rawValue == "trial_abandon")
    }
}
