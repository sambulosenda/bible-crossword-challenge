//
//  GameCenterService.swift
//  Bible Crossword Challenge
//
//  Game Center: authenticates the local player at launch and submits Daily
//  Mini solve times to the recurring weekly leaderboard. Game Center buckets
//  scores into weekly occurrences on its own — no backend involved.
//

import GameKit
import UIKit

@Observable
final class GameCenterService {
    static let shared = GameCenterService()

    /// Recurring leaderboard configured in App Store Connect: elapsed-time
    /// format (to the second), lower-is-better, restarts every 7 days.
    static let weeklyMiniLeaderboardID = "mini.weekly.time"

    private(set) var isAuthenticated = false

    /// A Mini time earned before authentication completed (or while offline),
    /// held in defaults so it survives relaunch and posts once auth lands.
    private static let pendingScoreKey = "gameCenter.pendingMiniSeconds"
    private static let pendingDateKey = "gameCenter.pendingMiniDate"

    /// Installs the authentication handler. GameKit invokes it on launch and
    /// again whenever the signed-in player changes; it must be set before any
    /// score submit, and setting it once is all launch-time setup needed.
    func authenticate() {
        GKLocalPlayer.local.authenticateHandler = { [weak self] viewController, error in
            if let viewController {
                Self.topViewController()?.present(viewController, animated: true)
                return
            }
            let authenticated = GKLocalPlayer.local.isAuthenticated
            self?.isAuthenticated = authenticated
            if authenticated { self?.flushPendingScore() }
            #if DEBUG
            if let error {
                print("🎮 Game Center auth: \(error.localizedDescription)")
            }
            #endif
        }
    }

    /// Submits a Daily Mini solve time. The celebration must never block on
    /// GameKit, so when the player isn't signed in yet (auth races the first
    /// solve of the session) the score is held and posted as soon as
    /// authentication completes instead of being dropped.
    func submitWeeklyMiniTime(seconds: Int) {
        guard GKLocalPlayer.local.isAuthenticated else {
            holdPendingScore(seconds)
            return
        }
        Task { await submit(seconds) }
    }

    private func submit(_ seconds: Int) async {
        do {
            try await GKLeaderboard.submitScore(
                seconds,
                context: 0,
                player: GKLocalPlayer.local,
                leaderboardIDs: [Self.weeklyMiniLeaderboardID]
            )
        } catch {
            // Network blip: hold the score; the auth handler fires on every
            // launch, so it retries next session (same-day only).
            holdPendingScore(seconds)
            #if DEBUG
            print("🎮 Game Center submit: \(error.localizedDescription)")
            #endif
        }
    }

    private func holdPendingScore(_ seconds: Int) {
        let defaults = UserDefaults.standard
        defaults.set(seconds, forKey: Self.pendingScoreKey)
        defaults.set(Date(), forKey: Self.pendingDateKey)
    }

    /// Posts a held score once authentication lands. Same-day only: the
    /// weekly board buckets by submission time, so a stale score could land
    /// in the wrong week's occurrence — better dropped than misfiled.
    private func flushPendingScore() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: Self.pendingScoreKey) != nil else { return }
        let seconds = defaults.integer(forKey: Self.pendingScoreKey)
        let heldAt = defaults.object(forKey: Self.pendingDateKey) as? Date
        defaults.removeObject(forKey: Self.pendingScoreKey)
        defaults.removeObject(forKey: Self.pendingDateKey)
        guard seconds > 0, let heldAt, Calendar.current.isDateInToday(heldAt) else { return }
        Task { await submit(seconds) }
    }

    /// The local player's standing on this week's Mini board — rank plus field
    /// size, for the completion screen's leaderboard button. Nil when signed
    /// out, offline, or the player has no score in this week's occurrence yet
    /// (a just-submitted score can take Game Center a moment to fold in).
    func weeklyMiniRank() async -> (rank: Int, total: Int)? {
        guard GKLocalPlayer.local.isAuthenticated else { return nil }
        do {
            guard let board = try await GKLeaderboard
                .loadLeaderboards(IDs: [Self.weeklyMiniLeaderboardID]).first
            else { return nil }
            let (local, _, total) = try await board.loadEntries(
                for: .global, timeScope: .week, range: NSRange(location: 1, length: 1)
            )
            guard let local, local.rank > 0 else { return nil }
            return (local.rank, total)
        } catch {
            #if DEBUG
            print("🎮 Game Center rank: \(error.localizedDescription)")
            #endif
            return nil
        }
    }

    /// Presents the system leaderboard UI for the weekly Mini board.
    /// (GKGameCenterViewController is deprecated; the access-point trigger is
    /// the sanctioned presentation path and needs no hosting controller.)
    func showWeeklyMiniLeaderboard() {
        GKAccessPoint.shared.trigger(
            leaderboardID: Self.weeklyMiniLeaderboardID,
            playerScope: .global,
            timeScope: .week
        ) {}
    }

    /// GameKit hands us a login view controller to present ourselves; find
    /// the frontmost controller of the active scene to host it.
    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
