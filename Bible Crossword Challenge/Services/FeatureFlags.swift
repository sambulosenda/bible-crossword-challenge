//
//  FeatureFlags.swift
//  Bible Crossword Challenge
//
//  Typed access to PostHog feature flags — the app's experiment switchboard.
//  A flag read at the moment it takes effect carves the audience into treatment
//  and control, and because the PostHog SDK stamps every captured event with
//  the active flags (`$feature/<key>`), the downstream metrics of the two
//  groups separate without any extra logging.
//
//  Reads go through `getFeatureFlag` rather than `isFeatureEnabled`: the latter
//  collapses "flag says off" and "flag never loaded" into one `false`, and
//  those must differ — an offline first launch or a suppressed-simulator run
//  should get the shipped default, not silently join a group it was never
//  assigned to. The SDK caches the last-fetched flags across launches, so
//  assignment is stable once a device has reached PostHog even once.
//
//  This file sat unmerged on a branch for weeks while `stall-nudge` ran live in
//  PostHog with nothing in the app reading it — so the nudge shipped to
//  everyone, the holdout was empty, and its readout was void. Anything added
//  here has to reach `main` in the same change as the flag that needs it.
//

import Foundation
import PostHog

/// Every flag the app reads, with the value used when PostHog is unreachable
/// (never set up, or flags not yet fetched on a first launch).
enum FeatureFlag: String {
    /// Holdout for the near-finish stall nudge (see `GameViewModel`). Default
    /// on — the nudge is shipped behavior; the flag exists to carve a control
    /// group, so a device that has never reached PostHog behaves as released.
    case stallNudge = "stall-nudge"

    /// Cuts the free daily hint pool from three to one
    /// (`PlayerProfile.reducedHintLimit`). Default **off** — three is shipped
    /// behavior, so a device we can't measure keeps the app it has.
    case hintQuotaOne = "hint-quota-one"

    var defaultValue: Bool {
        switch self {
        case .stallNudge: return true
        case .hintQuotaOne: return false
        }
    }
}

enum FeatureFlags {
    /// The flag's value for this device, or its default when unknown. Each read
    /// also emits `$feature_flag_called`, which is what ties a device into an
    /// experiment's exposure — so read at the moment the flag takes effect, not
    /// speculatively at launch.
    static func isEnabled(_ flag: FeatureFlag) -> Bool {
        value(of: flag) ?? flag.defaultValue
    }

    /// PostHog's actual answer, or nil when it hasn't given one — the flag is
    /// still loading, the device has never reached PostHog, or the key doesn't
    /// exist in the project yet.
    ///
    /// The distinction `isEnabled` throws away, kept for the one caller that
    /// needs it. Anything that *assigns* a player to an arm has to know the
    /// difference: a `nil` folded into `false` would enrol every player into
    /// control on a build whose flag had not been created yet — and for a
    /// once-ever assignment, the experiment would launch already spent. The
    /// hint quota keeps the shipped pool instead, and reads again next game.
    static func value(of flag: FeatureFlag) -> Bool? {
        PostHogSDK.shared.getFeatureFlag(flag.rawValue) as? Bool
    }

    /// Stamps every subsequent event with the arm this device is in.
    ///
    /// A **super property**, not a person property, because this project has no
    /// person profiles to hang one on: `personProfiles` is at its
    /// `.identifiedOnly` default and the app never calls `identify`, so every
    /// event is anonymous (see `PostHogAnalyticsService.configure`). A
    /// `person_properties` write would have gone nowhere. `register` persists
    /// across launches and rides on every capture, which is what a variant
    /// column has to do.
    ///
    /// `$feature/<key>` already carries the same fact, so this is redundant by
    /// design — and worth it: the SDK only stamps that key once flags have
    /// loaded, and it is easy to lose in a raw SQL query. `hint_quota_variant`
    /// is one column that says which arm every event belongs to.
    static func registerVariant(_ name: String, isTreatment: Bool) {
        PostHogSDK.shared.register([name: isTreatment ? "treatment" : "control"])
    }
}
