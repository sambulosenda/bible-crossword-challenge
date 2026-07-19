//
//  ChallengeService.swift
//  Bible Crossword Challenge
//
//  The friend-challenge loop, with no backend: a solved puzzle is turned into a
//  share URL ("beat my time") that encodes everything a recipient needs to play
//  the same grid and see a head-to-head result. Incoming challenges are parsed
//  from that URL and held device-locally (UserDefaults, not CloudKit) — a
//  pending challenge has no cross-device meaning, so it deliberately doesn't
//  sync and needs no schema change.
//
//  URL shape (custom scheme; Phase 2 will add an https universal-link twin that
//  parses the same query items):
//
//      biblecrossword://challenge?v=1&p=daily-042&t=154&n=Sam
//
//  Times are honest-system plaintext — casual tampering is possible and accepted
//  for v1 (the stakes are bragging rights). No cryptography.
//

import Foundation
import Observation
import os

@Observable
final class ChallengeService {
    static let shared = ChallengeService()

    /// A "beat my time" a friend sent us, parsed from a challenge URL.
    struct Challenge: Codable, Equatable, Hashable {
        let puzzleID: String
        let challengerName: String
        let seconds: Int
        let receivedAt: Date
    }

    /// Outcome of parsing an incoming URL, mapped to what the UI must do.
    enum ParseOutcome: Equatable {
        /// A well-formed challenge for a puzzle this build knows — play it.
        case valid(Challenge)
        /// Structurally a challenge, but from a newer payload version or for a
        /// puzzle id this bundle lacks. Both resolve to "update the app".
        case needsUpdate
        /// Not a challenge link (wrong scheme/host) or malformed — ignore.
        case notAChallenge
    }

    static let currentVersion = 1
    static let scheme = "biblecrossword"
    static let host = "challenge"
    /// Universal-link host and path. Shared links use this https form (tappable
    /// everywhere and, for non-installed recipients, routed to the web landing
    /// page); the custom scheme above stays a parseable fallback.
    /// Incoming links are accepted from `webHost` and any subdomain of it.
    static let webHost = "biblecrosswordchallenge.com"
    /// Outgoing links are generated on www: the apex DNS still points at the
    /// old host, which 404s the AASA file — apex links would open Safari, not
    /// the app. www is served by Railway/Caddy with a correct AASA. Safe to
    /// fold back to the apex once its DNS moves to the same deployment.
    static let outgoingWebHost = "www.biblecrosswordchallenge.com"
    static let webPath = "/challenge/"
    /// The default profile name — treated as "no name chosen yet" so we prompt
    /// once before the first outgoing challenge rather than shipping "Friend".
    static let placeholderName = "Friend"
    private static let maxNameLength = 20
    private static let maxSeconds = 86_400  // a day — clamps absurd/hostile values

    private let defaults: UserDefaults
    private let now: () -> Date
    /// Injectable so tests can assert the unknown-puzzle path without a bundle.
    private let puzzleExists: (String) -> Bool
    private let storageKey = "pendingChallenges.v1"

    /// Pending challenges, newest-per-puzzle. Loaded once and kept in sync with
    /// `defaults`; exposed for observation so a view can react to acceptance.
    private(set) var challenges: [Challenge] = []

    init(
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init,
        puzzleExists: @escaping (String) -> Bool = { PuzzleProvider.shared.puzzle(id: $0) != nil }
    ) {
        self.defaults = defaults
        self.now = now
        self.puzzleExists = puzzleExists
        self.challenges = Self.load(from: defaults, key: storageKey)
    }

    // MARK: - Parsing

    /// Validate an incoming URL. Structural checks first (cheap, no I/O), then
    /// the puzzle-existence check that decides valid-vs-needsUpdate. Accepts both
    /// the custom scheme and the https universal link — the query is identical.
    func parse(_ url: URL) -> ParseOutcome {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return .notAChallenge
        }

        let isCustom = url.scheme == Self.scheme && url.host() == Self.host
        // Match the apex and any subdomain (www) of the web host.
        let host = url.host() ?? ""
        let isUniversal = url.scheme == "https"
            && (host == Self.webHost || host.hasSuffix("." + Self.webHost))
            && components.path.hasPrefix("/challenge")
        guard isCustom || isUniversal else { return .notAChallenge }

        var query: [String: String] = [:]
        for item in components.queryItems ?? [] where item.value != nil {
            query[item.name] = item.value
        }

        // Version: a newer payload than we understand can't be trusted to have
        // the same fields — send the player to the App Store instead of guessing.
        guard let versionString = query["v"], let version = Int(versionString) else {
            return .notAChallenge
        }
        guard version <= Self.currentVersion else { return .needsUpdate }

        guard let puzzleID = query["p"], !puzzleID.isEmpty,
              let secondsString = query["t"], let seconds = Int(secondsString),
              (1...Self.maxSeconds).contains(seconds)
        else { return .notAChallenge }

        // Name is percent-decoded by URLComponents already; trim + cap, and fall
        // back to a neutral label rather than showing an empty "beat  :".
        let rawName = (query["n"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let name = rawName.isEmpty ? "A friend" : String(rawName.prefix(Self.maxNameLength))

        guard puzzleExists(puzzleID) else { return .needsUpdate }

        return .valid(Challenge(
            puzzleID: puzzleID,
            challengerName: name,
            seconds: seconds,
            receivedAt: now()
        ))
    }

    // MARK: - Building outgoing links

    /// The https universal link to share. Tappable in any messaging app; opens
    /// the app for installed recipients and the web landing page for everyone
    /// else. This is the link players actually send.
    func challengeWebURL(puzzleID: String, seconds: Int, name: String) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = Self.outgoingWebHost
        components.path = Self.webPath
        components.queryItems = queryItems(puzzleID: puzzleID, seconds: seconds, name: name)
        return components.url
    }

    /// The custom-scheme equivalent — kept as a parseable fallback (e.g. tests,
    /// or a channel that strips https link previews).
    func challengeURL(puzzleID: String, seconds: Int, name: String) -> URL? {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = Self.host
        components.queryItems = queryItems(puzzleID: puzzleID, seconds: seconds, name: name)
        return components.url
    }

    private func queryItems(puzzleID: String, seconds: Int, name: String) -> [URLQueryItem] {
        [
            URLQueryItem(name: "v", value: String(Self.currentVersion)),
            URLQueryItem(name: "p", value: puzzleID),
            URLQueryItem(name: "t", value: String(seconds)),
            URLQueryItem(name: "n", value: String(name.prefix(Self.maxNameLength))),
        ]
    }

    // MARK: - Pending store

    func pending(for puzzleID: String) -> Challenge? {
        challenges.first { $0.puzzleID == puzzleID }
    }

    /// Store a challenge to play. One per puzzle — a newer link for the same
    /// puzzle replaces the older (idempotent if identical).
    func accept(_ challenge: Challenge) {
        challenges.removeAll { $0.puzzleID == challenge.puzzleID }
        challenges.append(challenge)
        persist()
    }

    /// Drop a puzzle's pending challenge once its result has been shown.
    func consume(puzzleID: String) {
        let before = challenges.count
        challenges.removeAll { $0.puzzleID == puzzleID }
        if challenges.count != before { persist() }
    }

    // MARK: - Persistence

    private func persist() {
        do {
            defaults.set(try JSONEncoder().encode(challenges), forKey: storageKey)
        } catch {
            // Non-fatal: the challenge just won't survive relaunch.
            Log.persistence.error("Failed to persist challenges: \(error, privacy: .public)")
        }
    }

    private static func load(from defaults: UserDefaults, key: String) -> [Challenge] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([Challenge].self, from: data)) ?? []
    }
}
