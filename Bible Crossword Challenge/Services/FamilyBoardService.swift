//
//  FamilyBoardService.swift
//  Bible Crossword Challenge
//
//  A family board is a ranked list of times on one puzzle, passed around as a
//  link. No backend, no accounts, no rooms: the board *is* the URL. Whoever you
//  send it to plays the same grid, their time is added to their copy, and they
//  send it on — the scorecard travels with the group.
//
//      https://www.biblecrosswordchallenge.com/challenge/?v=2&p=daily-042&e=154:Sam&e=201:Ann
//
//  It rides the `/challenge/` path deliberately. The apple-app-site-association
//  file only claims `/challenge*`, so a `/board/` link would open Safari instead
//  of the app until a web deploy caught up — this works the day the app ships.
//  The payload version does the discriminating: a board is `v=2`, so a build
//  that predates boards reads it as "newer than I understand" and shows its
//  existing "update the app" alert rather than failing silently. One-to-one
//  challenges keep emitting `v=1`, so old builds still accept those.
//
//  Times are honest-system plaintext, exactly as in `ChallengeService`. Anyone
//  can hand-edit a link. The stakes are who cooks Sunday lunch.
//

import Foundation
import Observation
import os

@Observable
final class FamilyBoardService {
    static let shared = FamilyBoardService()

    /// One person's standing on a board.
    struct Standing: Codable, Equatable, Hashable, Identifiable {
        var id: String { name }
        let name: String
        let seconds: Int
    }

    /// A puzzle's board: everyone this device has heard about, best time each.
    struct Board: Codable, Equatable, Hashable, Identifiable {
        var id: String { puzzleID }
        let puzzleID: String
        /// Denormalised so a board reads correctly without a bundle lookup.
        var puzzleTitle: String
        /// Ranked fastest-first; see `merged(with:)` for the ordering rule.
        var standings: [Standing]
        var updatedAt: Date

        /// Fastest first, then alphabetically so equal times are stable rather
        /// than shuffling on every merge.
        static func rank(_ standings: [Standing]) -> [Standing] {
            standings.sorted {
                $0.seconds == $1.seconds ? $0.name < $1.name : $0.seconds < $1.seconds
            }
        }

        /// Fold another copy of this board into this one.
        ///
        /// Lowest time wins per name. That rule is what lets the link criss-cross
        /// a group in any order and still converge: merging is commutative and
        /// associative, so Ann forwarding Bob's board to Carol produces the same
        /// standings as Bob sending to Carol directly. "Newest wins" would not —
        /// it would make the final list depend on who happened to share last.
        ///
        /// Two people sharing a first name merge into one row. Accepted for v1.
        func merged(with others: [Standing]) -> [Standing] {
            var best: [String: Int] = [:]
            for standing in standings + others {
                if let existing = best[standing.name], existing <= standing.seconds { continue }
                best[standing.name] = standing.seconds
            }
            let ranked = Self.rank(best.map { Standing(name: $0.key, seconds: $0.value) })
            return Array(ranked.prefix(FamilyBoardService.maxStandings))
        }

        func standing(for name: String) -> Standing? {
            standings.first { $0.name == name }
        }

        /// A message-friendly ranked list, for the share caption.
        var shareText: String {
            let rows = standings.enumerated().map { index, standing in
                "\(Self.medal(index)) \(standing.name) — \(TimeFormat.clock(standing.seconds))"
            }
            return (["“\(puzzleTitle)” — family board"] + rows).joined(separator: "\n")
        }

        private static func medal(_ index: Int) -> String {
            switch index {
            case 0: "🥇"
            case 1: "🥈"
            case 2: "🥉"
            default: "\(index + 1)."
            }
        }
    }

    enum ParseOutcome: Equatable {
        case valid(Board)
        /// A board payload we can't read, or one naming a puzzle this bundle
        /// lacks — both resolve to "update the app".
        case needsUpdate
        /// Not a board link. The caller should try the one-to-one challenge
        /// parser next; they share a path.
        case notABoard
    }

    /// The payload version a board is carried on. `ChallengeService.currentVersion`
    /// stays at 1 so one-to-one links keep opening on older builds.
    static let boardVersion = 2
    /// Twelve rows is a family or a small group, and keeps the link comfortably
    /// inside what messaging apps will carry without truncating.
    static let maxStandings = 12
    /// Boards kept on device, newest first.
    static let maxBoards = 20
    private nonisolated static let maxNameLength = 20
    private nonisolated static let maxSeconds = 86_400

    private let defaults: UserDefaults
    private let now: () -> Date
    private let puzzleExists: (String) -> Bool
    private let storageKey = "familyBoards.v1"

    private(set) var boards: [Board] = []

    init(
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init,
        puzzleExists: @escaping (String) -> Bool = { PuzzleProvider.shared.puzzle(id: $0) != nil }
    ) {
        self.defaults = defaults
        self.now = now
        self.puzzleExists = puzzleExists
        self.boards = Self.load(from: defaults, key: storageKey)
    }

    // MARK: - Parsing

    /// Read an incoming link as a board. Returns `.notABoard` for anything
    /// without standings, so the caller can fall through to `ChallengeService`.
    func parse(_ url: URL, title: (String) -> String?) -> ParseOutcome {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return .notABoard
        }
        guard ChallengeService.isChallengeLink(url, components: components) else { return .notABoard }

        let items = components.queryItems ?? []
        let rawStandings = items.filter { $0.name == "e" }.compactMap(\.value)
        // No standings means this is the one-to-one payload, not a board.
        guard !rawStandings.isEmpty else { return .notABoard }

        var query: [String: String] = [:]
        for item in items where item.value != nil && item.name != "e" {
            query[item.name] = item.value
        }

        guard let versionString = query["v"], let version = Int(versionString) else {
            return .notABoard
        }
        guard version <= Self.boardVersion else { return .needsUpdate }

        guard let puzzleID = query["p"], !puzzleID.isEmpty else { return .notABoard }

        let standings = rawStandings.compactMap(Self.parseStanding)
        guard !standings.isEmpty else { return .needsUpdate }

        guard puzzleExists(puzzleID) else { return .needsUpdate }

        return .valid(Board(
            puzzleID: puzzleID,
            puzzleTitle: title(puzzleID) ?? puzzleID,
            standings: Board.rank(standings),
            updatedAt: now()
        ))
    }

    /// `"154:Sam"` — seconds first so a name may contain anything, colons
    /// included. Splitting on the *first* colon keeps that unambiguous.
    ///
    /// `nonisolated` because the module defaults to `@MainActor`, and this is
    /// passed as a function value to `compactMap`, which wants a plain one.
    private nonisolated static func parseStanding(_ raw: String) -> Standing? {
        guard let separator = raw.firstIndex(of: ":") else { return nil }
        guard let seconds = Int(raw[raw.startIndex..<separator]),
              (1...maxSeconds).contains(seconds)
        else { return nil }
        let name = raw[raw.index(after: separator)...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        return Standing(name: String(name.prefix(maxNameLength)), seconds: seconds)
    }

    // MARK: - Building outgoing links

    func boardURL(_ board: Board) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = ChallengeService.outgoingWebHost
        components.path = ChallengeService.webPath
        components.queryItems = [
            URLQueryItem(name: "v", value: String(Self.boardVersion)),
            URLQueryItem(name: "p", value: board.puzzleID),
        ] + board.standings.map {
            URLQueryItem(name: "e", value: "\($0.seconds):\($0.name.prefix(Self.maxNameLength))")
        }
        return components.url
    }

    // MARK: - Store

    func board(for puzzleID: String) -> Board? {
        boards.first { $0.puzzleID == puzzleID }
    }

    /// Fold an incoming board into whatever this device already knows, and
    /// return the result.
    @discardableResult
    func accept(_ incoming: Board) -> Board {
        var board = self.board(for: incoming.puzzleID) ?? Board(
            puzzleID: incoming.puzzleID,
            puzzleTitle: incoming.puzzleTitle,
            standings: [],
            updatedAt: now()
        )
        board.standings = board.merged(with: incoming.standings)
        board.puzzleTitle = incoming.puzzleTitle
        board.updatedAt = now()
        store(board)
        return board
    }

    /// Add this device's own solve, creating the board if it's the first entry.
    ///
    /// A name already on the board is left alone rather than improved: the
    /// puzzle is solved by then, so a replay knows every answer, and letting the
    /// second run overwrite the first would make "best time" mean "most
    /// replays". Everyone else's times still merge lowest-wins — the difference
    /// is that only here do we know the run wasn't a replay.
    @discardableResult
    func record(puzzleID: String, puzzleTitle: String, name: String, seconds: Int) -> Board {
        var board = self.board(for: puzzleID) ?? Board(
            puzzleID: puzzleID,
            puzzleTitle: puzzleTitle,
            standings: [],
            updatedAt: now()
        )
        if board.standing(for: name) == nil {
            board.standings = board.merged(with: [Standing(name: name, seconds: seconds)])
        }
        board.puzzleTitle = puzzleTitle
        board.updatedAt = now()
        store(board)
        return board
    }

    /// Re-label this device's own row once the player picks a display name.
    ///
    /// A board can be joined before a name is chosen — you land on it from a
    /// link, solve, and see where you placed under the placeholder. The name is
    /// only actually asked for when the board is about to leave the device, and
    /// at that point the row already on it is the one that needs the new label.
    /// Merging afterwards would keep the faster of the two rows, so the rename
    /// has to drop the old one rather than add a second.
    @discardableResult
    func rename(puzzleID: String, from oldName: String, to newName: String) -> Board? {
        guard oldName != newName, var board = board(for: puzzleID),
              let existing = board.standing(for: oldName)
        else { return board(for: puzzleID) }

        // Drop the old row first, then *merge* the new one in rather than
        // appending it: the board may already carry a row under the chosen name
        // (you joined anonymously, and the copy you were sent already had you on
        // it). Appending leaves the same person listed twice — ranking sorts,
        // it doesn't collapse — so the merge does it under the board's own
        // lowest-time-wins rule.
        var stripped = board
        stripped.standings = board.standings.filter { $0.name != oldName }
        board.standings = stripped.merged(with: [Standing(name: newName, seconds: existing.seconds)])
        board.updatedAt = now()
        store(board)
        return board
    }

    private func store(_ board: Board) {
        boards.removeAll { $0.puzzleID == board.puzzleID }
        boards.insert(board, at: 0)
        if boards.count > Self.maxBoards {
            boards.removeLast(boards.count - Self.maxBoards)
        }
        persist()
    }

    // MARK: - Persistence

    private func persist() {
        do {
            defaults.set(try JSONEncoder().encode(boards), forKey: storageKey)
        } catch {
            Log.persistence.error("Failed to persist family boards: \(error, privacy: .public)")
        }
    }

    private static func load(from defaults: UserDefaults, key: String) -> [Board] {
        guard let data = defaults.data(forKey: key) else { return [] }
        let stored = (try? JSONDecoder().decode([Board].self, from: data)) ?? []
        return stored.sorted { $0.updatedAt > $1.updatedAt }
    }
}
