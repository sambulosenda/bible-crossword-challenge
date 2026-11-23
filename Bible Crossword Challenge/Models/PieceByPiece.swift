//
//  PieceByPiece.swift
//  Bible Crossword Challenge
//
//  Piece by Piece (2026-11-23): a finished Mini cut into small pieces of
//  letters, which the player fits back together. No clues and no typing, so
//  nobody is stuck on a word they don't know. A third kind of play beside
//  the grid and Clue of the Day, and no new content: every round is a Mini
//  already in the bundle.
//
//  The rules are plain values here, the same pattern as `ClueOfTheDay`, so
//  the cut, the day's pick and a round's play are testable without SwiftUI.
//  The view (`PieceByPieceView`) owns persistence and analytics.
//
//  Free for everyone, and it does not keep the streak, for the reason Clue
//  of the Day doesn't: a two-minute game that did would become the way to
//  skip the crossword.
//

import Foundation

/// A few letter squares that move as one.
struct JigsawPiece: Identifiable, Hashable {
    struct Cell: Hashable {
        /// Offset from the piece's top-left corner.
        let row: Int
        let col: Int
        let letter: Character
    }

    let id: Int
    /// In reading order. Offsets are from the piece's bounding box, so some
    /// corner of the box may be empty (an L).
    let cells: [Cell]
    /// Where the piece sits in the solved grid. Not the only right place: a
    /// piece that spells the same letters elsewhere is right there too. A
    /// decoy has none; its `home` is meaningless.
    let home: GridPos
    /// A weekend extra that fits nowhere: the right shape, the wrong letters.
    /// The round is solved with it still in the tray.
    var isDecoy = false

    var rows: Int { (cells.map(\.row).max() ?? 0) + 1 }
    var cols: Int { (cells.map(\.col).max() ?? 0) + 1 }

    /// The squares the piece covers with its top-left corner at `origin`.
    func squares(at origin: GridPos) -> [(pos: GridPos, letter: Character)] {
        cells.map { (GridPos(row: origin.row + $0.row, col: origin.col + $0.col), $0.letter) }
    }
}

/// One round: a solved grid and the pieces it was cut into.
struct JigsawRound: Equatable {
    let puzzleID: String
    let title: String
    let verse: String
    let reference: String
    let size: Int
    /// The solved letters by square. Squares not in it are blocks.
    let solution: [GridPos: Character]
    /// In tray order, which is shuffled: reading order would hand the player
    /// the answer from left to right. Includes any decoy.
    let pieces: [JigsawPiece]
    /// The Mini's answers, revealed with their clues as each one is rebuilt:
    /// no clue is needed to play, and every word still teaches one.
    let words: [ClueData]

    static let pieceSizes = 2...4
    static let maxPieceSize = 5

    /// Cuts `puzzle` into pieces. The same puzzle and seed always cut the
    /// same way, so a round can be resumed and two players can compare.
    /// `decoys` adds that many pieces that fit nowhere; they come from a
    /// second generator, so the real cut and its tray order are the same
    /// with or without them.
    init(puzzle: Puzzle, seed: UInt64 = 0, decoys: Int = 0) {
        var solution: [GridPos: Character] = [:]
        for (row, line) in puzzle.grid.enumerated() {
            for (col, character) in line.enumerated() where character.isLetter {
                solution[GridPos(row: row, col: col)] = character
            }
        }
        var rng = WidgetBridge.SeededGenerator(seed: seed &+ UInt64(truncatingIfNeeded: puzzle.id.hashValueStable))
        let groups = Self.cut(Set(solution.keys), using: &rng)
        var pieces = groups.enumerated().map { index, group in
            Self.piece(id: index, squares: group, solution: solution)
        }
        pieces.shuffle(using: &rng)

        var decoyRNG = WidgetBridge.SeededGenerator(seed: ~(seed &+ UInt64(truncatingIfNeeded: puzzle.id.hashValueStable)))
        for _ in 0..<max(decoys, 0) {
            guard let decoy = Self.decoy(id: pieces.count, like: pieces, solution: solution, using: &decoyRNG) else { break }
            pieces.insert(decoy, at: Int.random(in: 0...pieces.count, using: &decoyRNG))
        }

        self.puzzleID = puzzle.id
        self.title = puzzle.title
        self.verse = puzzle.verse
        self.reference = puzzle.reference
        self.size = puzzle.size
        self.solution = solution
        self.pieces = pieces
        self.words = puzzle.clues.sorted { ($0.direction == .across ? 0 : 1, $0.number) < ($1.direction == .across ? 0 : 1, $1.number) }
    }

    /// The pieces the grid is cut into, without decoys.
    var realPieces: [JigsawPiece] { pieces.filter { !$0.isDecoy } }

    /// A piece shaped like one of the real ones (2–3 squares, so it reads as
    /// ordinary), lettered from the grid's own letters, that spells nothing
    /// anywhere on the board. Nil when every try lands on a real fit.
    private static func decoy<G: RandomNumberGenerator>(
        id: Int, like pieces: [JigsawPiece], solution: [GridPos: Character], using rng: inout G
    ) -> JigsawPiece? {
        let shapes = pieces.filter { !$0.isDecoy && (2...3).contains($0.cells.count) }
        let letters = Array(solution.values)
        guard !shapes.isEmpty, !letters.isEmpty else { return nil }
        let rows = solution.keys.map(\.row), cols = solution.keys.map(\.col)
        for _ in 0..<50 {
            guard let shape = shapes.randomElement(using: &rng) else { return nil }
            let cells = shape.cells.map {
                JigsawPiece.Cell(row: $0.row, col: $0.col, letter: letters.randomElement(using: &rng) ?? "A")
            }
            let candidate = JigsawPiece(id: id, cells: cells, home: GridPos(row: -1, col: -1), isDecoy: true)
            let fitsSomewhere = (rows.min()!...rows.max()!).contains { row in
                (cols.min()!...cols.max()!).contains { col in
                    candidate.squares(at: GridPos(row: row, col: col)).allSatisfy { solution[$0.pos] == $0.letter }
                }
            }
            if !fitsSomewhere { return candidate }
        }
        return nil
    }

    private static func piece(id: Int, squares: [GridPos], solution: [GridPos: Character]) -> JigsawPiece {
        let top = squares.map(\.row).min() ?? 0
        let left = squares.map(\.col).min() ?? 0
        let cells = squares
            .sorted { ($0.row, $0.col) < ($1.row, $1.col) }
            .map { JigsawPiece.Cell(row: $0.row - top, col: $0.col - left, letter: solution[$0] ?? " ") }
        return JigsawPiece(id: id, cells: cells, home: GridPos(row: top, col: left))
    }

    /// Splits the letter squares into connected groups of 2–4.
    ///
    /// Grows each group from the square with the fewest free neighbours, so
    /// the ends of words are taken first and aren't left stranded. A square
    /// that still ends up alone joins the smallest group beside it, because
    /// a single loose letter is a piece with no shape to read; a group that
    /// grows past `maxPieceSize` that way is cut in two.
    static func cut<G: RandomNumberGenerator>(_ squares: Set<GridPos>, using rng: inout G) -> [[GridPos]] {
        var free = squares
        var groups: [[GridPos]] = []

        func neighbours(_ pos: GridPos) -> [GridPos] {
            [GridPos(row: pos.row - 1, col: pos.col), GridPos(row: pos.row, col: pos.col - 1),
             GridPos(row: pos.row, col: pos.col + 1), GridPos(row: pos.row + 1, col: pos.col)]
        }
        func order(_ a: GridPos, _ b: GridPos) -> Bool { (a.row, a.col) < (b.row, b.col) }

        while !free.isEmpty {
            // Sorted first, so the pick doesn't depend on Set's order.
            let start = free.sorted(by: order).min { a, b in
                neighbours(a).filter(free.contains).count < neighbours(b).filter(free.contains).count
            }!
            let target = Int.random(in: pieceSizes, using: &rng)
            var group = [start]
            free.remove(start)
            while group.count < target {
                let frontier = Set(group.flatMap(neighbours)).filter(free.contains).sorted(by: order)
                guard !frontier.isEmpty else { break }
                // A square this group is about to strand goes first: left
                // for later it becomes a single, and singles pile up on
                // whichever group is beside them.
                let stranded = frontier.filter { square in
                    !neighbours(square).contains { free.contains($0) && !frontier.contains($0) }
                        && neighbours(square).filter(free.contains).isEmpty
                }
                let next = stranded.first ?? frontier.randomElement(using: &rng)!
                group.append(next)
                free.remove(next)
            }
            groups.append(group)
        }

        // Singles join the smallest group beside them.
        for index in groups.indices.reversed() where groups[index].count == 1 {
            let single = groups[index][0]
            let beside = groups.indices
                .filter { $0 != index && groups[$0].contains { neighbours(single).contains($0) } }
                .min { groups[$0].count < groups[$1].count }
            if let beside {
                groups[beside].append(single)
                groups.remove(at: index)
            }
        }

        // A group the singles made too big is cut in two.
        func isConnected(_ part: [GridPos]) -> Bool {
            guard let first = part.first else { return false }
            let all = Set(part)
            var seen: Set<GridPos> = [first]
            var queue = [first]
            while let next = queue.popLast() {
                for step in neighbours(next) where all.contains(step) && seen.insert(step).inserted {
                    queue.append(step)
                }
            }
            return seen.count == part.count
        }
        /// The halves of `group` nearest equal in size that each hold
        /// together, or nil when no cut leaves two pieces of 2 or more.
        func halves(_ group: [GridPos]) -> ([GridPos], [GridPos])? {
            let all = Set(group)
            var best: ([GridPos], [GridPos])?
            for start in group.sorted(by: order) {
                // Breadth-first from `start`: every prefix holds together.
                var walk = [start]
                var seen: Set<GridPos> = [start]
                var index = 0
                while index < walk.count {
                    for step in neighbours(walk[index]).sorted(by: order)
                    where all.contains(step) && seen.insert(step).inserted {
                        walk.append(step)
                    }
                    index += 1
                }
                for count in 2...(group.count - 2) {
                    let rest = Array(walk[count...])
                    guard isConnected(rest) else { continue }
                    let gap = abs(count - rest.count)
                    if best == nil || gap < abs(best!.0.count - best!.1.count) {
                        best = (Array(walk[..<count]), rest)
                    }
                }
            }
            return best
        }
        var index = 0
        while index < groups.count {
            if groups[index].count > maxPieceSize - 1, let (first, second) = halves(groups[index]) {
                groups[index] = first
                groups.insert(second, at: index + 1)
            } else {
                index += 1
            }
        }
        return groups
    }
}

private extension String {
    /// `hashValue` is seeded per launch; a cut has to be the same every time.
    var hashValueStable: UInt64 {
        utf8.reduce(14_695_981_039_346_656_037) { ($0 ^ UInt64($1)) &* 1_099_511_628_211 }
    }
}

/// A round in play: which pieces are on the board, and where.
struct JigsawGame: Equatable {
    let round: JigsawRound
    /// Top-left corner of each placed piece. A piece not in it is in the tray.
    private(set) var placements: [Int: GridPos] = [:]
    /// How many times a piece was put down where it doesn't belong.
    private(set) var wrongFits = 0

    init(round: JigsawRound) { self.round = round }

    /// A round picked up where it was left. A saved placement that no longer
    /// fits (the cut changed under it) is dropped back to the tray.
    init(round: JigsawRound, day: Date, saved: JigsawProgress?) {
        self.round = round
        guard let saved, saved.belongs(to: round.puzzleID, on: day) else { return }
        for placement in saved.placements {
            guard let piece = piece(placement.piece) else { continue }
            let origin = GridPos(row: placement.row, col: placement.col)
            if canPlace(piece, at: origin) { placements[piece.id] = origin }
        }
        wrongFits = saved.wrongFits
    }

    var trayPieces: [JigsawPiece] { round.pieces.filter { placements[$0.id] == nil } }

    /// The words whose every square holds its solved letter, in clue order.
    var completedWords: [ClueData] {
        let board = board
        return round.words.filter { word in
            word.positions.allSatisfy { board[$0] != nil && board[$0] == round.solution[$0] }
        }
    }

    func piece(_ id: Int) -> JigsawPiece? { round.pieces.first { $0.id == id } }

    /// The letter on each covered square.
    var board: [GridPos: Character] {
        var board: [GridPos: Character] = [:]
        for piece in round.pieces {
            guard let origin = placements[piece.id] else { continue }
            for square in piece.squares(at: origin) { board[square.pos] = square.letter }
        }
        return board
    }

    /// Whether `piece` may be put down at `origin`: on squares that take a
    /// letter, and on nothing another piece covers.
    func canPlace(_ piece: JigsawPiece, at origin: GridPos) -> Bool {
        let taken = Set(round.pieces
            .filter { $0.id != piece.id }
            .flatMap { other in placements[other.id].map { other.squares(at: $0).map(\.pos) } ?? [] })
        return piece.squares(at: origin).allSatisfy { square in
            round.solution[square.pos] != nil && !taken.contains(square.pos)
        }
    }

    /// Puts a piece down. False, and nothing changes, when it can't go there.
    @discardableResult
    mutating func place(_ pieceID: Int, at origin: GridPos) -> Bool {
        guard let piece = piece(pieceID), canPlace(piece, at: origin) else { return false }
        guard placements[pieceID] != origin else { return true }
        placements[pieceID] = origin
        if isWrong(pieceID) { wrongFits += 1 }
        return true
    }

    mutating func returnToTray(_ pieceID: Int) { placements[pieceID] = nil }

    mutating func startAgain() { placements = [:] }

    func origin(of pieceID: Int) -> GridPos? { placements[pieceID] }

    /// A placed piece is wrong when any of its letters differs from the
    /// solved grid there. Judged by letters, not by `home`: two pieces that
    /// spell the same thing are interchangeable.
    func isWrong(_ pieceID: Int) -> Bool {
        guard let piece = piece(pieceID), let origin = placements[pieceID] else { return false }
        return piece.squares(at: origin).contains { round.solution[$0.pos] != $0.letter }
    }

    var isSolved: Bool { board == round.solution }

    /// What to save: where everything is, and how long it has taken.
    func progress(day: Date, seconds: Int) -> JigsawProgress {
        JigsawProgress(
            day: day.timeIntervalSinceReferenceDate,
            puzzleID: round.puzzleID,
            placements: placements
                .map { JigsawProgress.Placement(piece: $0.key, row: $0.value.row, col: $0.value.col) }
                .sorted { $0.piece < $1.piece },
            pieceCount: round.realPieces.count,
            wrongFits: wrongFits,
            seconds: seconds,
            isSolved: isSolved,
            decoy: round.pieces.first(where: \.isDecoy)?.id
        )
    }
}

/// Where a player stands in one day's round. Saved between visits.
struct JigsawProgress: Codable, Equatable {
    struct Placement: Codable, Equatable {
        let piece: Int
        let row: Int
        let col: Int
    }

    /// Start of the day the round belongs to, as a reference-date interval.
    var day: Double
    var puzzleID: String
    var placements: [Placement]
    /// Carried so the Today row can say "3 of 8" without cutting the grid.
    var pieceCount: Int
    var wrongFits: Int
    /// Time on the screen so far. Shown only once the round is solved.
    var seconds: Int
    var isSolved: Bool
    /// The decoy's id on a weekend round, so the Today row counts only real
    /// pieces. Absent in progress saved before decoys.
    var decoy: Int? = nil

    func belongs(to puzzleID: String, on day: Date) -> Bool {
        self.puzzleID == puzzleID && self.day == day.timeIntervalSinceReferenceDate
    }

    /// The Today row's line for this state.
    var summary: String {
        if isSolved { return "Solved in \(TimeFormat.clock(seconds))" }
        let placed = placements.filter { $0.piece != decoy }.count
        return "\(placed) of \(pieceCount) pieces placed"
    }
}

// MARK: - The day's round

enum PieceByPiece {
    /// How many days either side of today a Mini is kept out of the pick: a
    /// round is a solved grid, so it must not be one the player is about to
    /// meet, or has just met, as a crossword.
    static let clearDays = 7

    /// Friday to Sunday add a decoy: a piece that fits nowhere, so the
    /// weekend round asks a little more than the weekday one.
    static func decoys(on day: Date, calendar: Calendar = .current) -> Int {
        [6, 7, 1].contains(calendar.component(.weekday, from: day)) ? 1 : 0
    }

    /// The Mini for the day at `dayIndex`: the same one for every player.
    /// Starts half the pool away from the rotation's own pick. A Mini in
    /// `avoidingIDs`, or sharing an answer with `avoidingAnswers`, is passed
    /// over for one a quarter of the pool further on: far enough that
    /// tomorrow's own pick is not the one borrowed today.
    static func pick(
        dayIndex: Int, from minis: [Puzzle], avoidingIDs: Set<String> = [], avoidingAnswers: Set<String> = []
    ) -> Puzzle? {
        guard !minis.isEmpty else { return nil }
        let count = minis.count
        let start = (((dayIndex + count / 2) % count) + count) % count
        func clashes(_ candidate: Puzzle) -> Bool {
            avoidingIDs.contains(candidate.id)
                || candidate.clues.contains { avoidingAnswers.contains($0.answer.uppercased()) }
        }
        if !clashes(minis[start]) { return minis[start] }
        for step in 0..<count {
            let candidate = minis[(start + count / 4 + step) % count]
            if !clashes(candidate) { return candidate }
        }
        // Everything clashes (a tiny pool): the grid still plays.
        return minis[start]
    }

    /// Today's round: clear of the Minis around today, of every answer in
    /// today's daily and Mini, and of the round played yesterday.
    static func puzzle(on day: Date, provider: PuzzleProvider = .shared, calendar: Calendar = .current) -> Puzzle? {
        var avoiding: Set<String> = []
        // Yesterday's round as it would be picked on its own. Two days that
        // both step aside can land on the same Mini; this keeps them apart.
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: day),
           let played = puzzle(on: yesterday, alsoAvoiding: [], provider: provider, calendar: calendar) {
            avoiding.insert(played.id)
        }
        return puzzle(on: day, alsoAvoiding: avoiding, provider: provider, calendar: calendar)
    }

    private static func puzzle(
        on day: Date, alsoAvoiding: Set<String>, provider: PuzzleProvider, calendar: Calendar
    ) -> Puzzle? {
        let nearby = (-clearDays...clearDays).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: day)
                .flatMap { provider.dailyMini(for: $0, calendar: calendar)?.id }
        }
        let grids = [provider.dailyPuzzle(for: day, calendar: calendar), provider.dailyMini(for: day, calendar: calendar)]
        let answers = Set(grids.compactMap { $0 }.flatMap { $0.clues.map { $0.answer.uppercased() } })
        return pick(
            dayIndex: provider.dayIndex(for: day, calendar: calendar), from: provider.minis,
            avoidingIDs: Set(nearby).union(alsoAvoiding), avoidingAnswers: answers
        )
    }
}
