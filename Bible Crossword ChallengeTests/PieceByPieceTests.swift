//
//  PieceByPieceTests.swift
//  Bible Crossword ChallengeTests
//
//  Piece by Piece: how a Mini is cut, what counts as a right or wrong fit,
//  the day's pick, and a round saved and picked up again.
//

import Testing
import Foundation
@testable import Bible_Crossword_Challenge

struct PieceByPieceTests {

    private func round(_ grid: [String], id: String = "mini-test", seed: UInt64 = 0) -> JigsawRound {
        JigsawRound(puzzle: Puzzle(
            id: id, title: "T", difficulty: .easy, verse: "v", reference: "r",
            publishDate: "2026-01-01", size: grid.count, grid: grid, clues: [], kind: .mini
        ), seed: seed)
    }

    private let sample = [
        "...WELL",
        "...A...",
        "B..T.N.",
        "REBEKAH",
        "I..R.H.",
        "D....O.",
        "E....R.",
    ]

    // MARK: - Cutting

    @Test func everyLetterSquareIsInExactlyOnePiece() {
        let round = round(sample)
        let covered = round.pieces.flatMap { $0.squares(at: $0.home).map(\.pos) }
        #expect(covered.count == round.solution.count)
        #expect(Set(covered) == Set(round.solution.keys))
    }

    @Test func piecesCarryTheSolvedLetters() {
        let round = round(sample)
        for piece in round.pieces {
            for square in piece.squares(at: piece.home) {
                #expect(round.solution[square.pos] == square.letter)
            }
        }
    }

    @Test func piecesAreConnectedAndSmall() {
        let round = round(sample)
        for piece in round.pieces {
            #expect((2...JigsawRound.maxPieceSize).contains(piece.cells.count), "piece of \(piece.cells.count)")
            // Flood from the first cell reaches them all.
            let all = Set(piece.cells.map { GridPos(row: $0.row, col: $0.col) })
            var seen: Set<GridPos> = [all.first!]
            var queue = [all.first!]
            while let next = queue.popLast() {
                for step in [(0, 1), (1, 0), (0, -1), (-1, 0)] {
                    let pos = GridPos(row: next.row + step.0, col: next.col + step.1)
                    if all.contains(pos), seen.insert(pos).inserted { queue.append(pos) }
                }
            }
            #expect(seen == all)
        }
    }

    @Test func theSameRoundCutsTheSameWayEveryTime() {
        #expect(round(sample) == round(sample))
        #expect(round(sample).pieces.map(\.id) == round(sample).pieces.map(\.id))
    }

    /// Every Mini in the bundle has to cut cleanly: they are the rounds.
    @Test func everyBundledMiniCuts() {
        for mini in PuzzleProvider.shared.minis {
            let round = JigsawRound(puzzle: mini)
            let covered = round.pieces.flatMap { $0.squares(at: $0.home).map(\.pos) }
            #expect(Set(covered) == Set(round.solution.keys), "\(mini.id)")
            #expect(covered.count == round.solution.count, "\(mini.id) overlaps")
            #expect(round.pieces.allSatisfy { $0.cells.count >= 2 }, "\(mini.id) has a single letter")
            #expect(round.pieces.allSatisfy { $0.cells.count <= JigsawRound.maxPieceSize }, "\(mini.id) has a piece of \(round.pieces.map(\.cells.count).max() ?? 0)")
        }
    }

    // MARK: - Playing

    @Test func placingEveryPieceAtHomeSolvesIt() {
        var game = JigsawGame(round: round(sample))
        #expect(!game.isSolved)
        for piece in game.round.pieces {
            let placed1 = game.place(piece.id, at: piece.home)
            #expect(placed1)
            #expect(!game.isWrong(piece.id))
        }
        #expect(game.isSolved)
        #expect(game.trayPieces.isEmpty)
    }

    @Test func aPieceCannotCoverAnother() throws {
        var game = JigsawGame(round: round(sample))
        let first = try #require(game.round.pieces.first)
        let placed2 = game.place(first.id, at: first.home)
        #expect(placed2)
        let other = try #require(game.round.pieces.first { $0.id != first.id })
        // Any origin that lands a cell on the first piece's top-left square.
        let target = first.squares(at: first.home)[0].pos
        let cell = other.cells[0]
        let origin = GridPos(row: target.row - cell.row, col: target.col - cell.col)
        let placed3 = game.place(other.id, at: origin)
        #expect(!placed3)
        #expect(game.origin(of: other.id) == nil)
    }

    @Test func aPieceOnlyGoesOnLetterSquares() throws {
        var game = JigsawGame(round: round(sample))
        let piece = try #require(game.round.pieces.first)
        // Row 0, col 0 is a block in the sample; 7,7 is off the board.
        #expect(!game.canPlace(piece, at: GridPos(row: 0, col: 0)))
        let onBlock = game.place(piece.id, at: GridPos(row: 0, col: 0))
        let offBoard = game.place(piece.id, at: GridPos(row: 7, col: 7))
        #expect(!onBlock && !offBoard)
        #expect(game.origin(of: piece.id) == nil)
    }

    /// A piece that fits the shape but spells the wrong letters goes down,
    /// reads as wrong, and is counted once however long it sits there.
    @Test func aWrongFitIsCountedWhenItLands() {
        // Two words of the same shape, different letters.
        var game = JigsawGame(round: round(["AB.", "...", "CD."]))
        let (a, b) = (game.round.pieces[0], game.round.pieces[1])
        let swapped = game.place(a.id, at: b.home)
        #expect(swapped)
        #expect(game.isWrong(a.id))
        #expect(game.wrongFits == 1)
        // Putting it down again in the same place is not a second mistake.
        game.place(a.id, at: b.home)
        #expect(game.wrongFits == 1)
        game.place(a.id, at: a.home)
        game.place(b.id, at: b.home)
        #expect(game.wrongFits == 1)
        #expect(game.isSolved)
    }

    @Test func returningAPieceEmptiesItsSquares() throws {
        var game = JigsawGame(round: round(sample))
        let piece = try #require(game.round.pieces.first)
        game.place(piece.id, at: piece.home)
        game.returnToTray(piece.id)
        #expect(game.board.isEmpty)
        #expect(game.trayPieces.count == game.round.pieces.count)
    }

    /// Judged by letters: a piece that spells the same thing in another
    /// place is right there.
    @Test func identicalPiecesAreInterchangeable() {
        // Two separate "AB" words, each one piece.
        let round = round(["AB.", "...", "AB."])
        var game = JigsawGame(round: round)
        #expect(round.pieces.count == 2)
        let (a, b) = (round.pieces[0], round.pieces[1])
        let placed7 = game.place(a.id, at: b.home)
        #expect(placed7)
        let placed8 = game.place(b.id, at: a.home)
        #expect(placed8)
        #expect(!game.isWrong(a.id) && !game.isWrong(b.id))
        #expect(game.isSolved)
    }

    // MARK: - Saved progress

    private let day = Date(timeIntervalSinceReferenceDate: 800_000_000)

    @Test func aRoundIsPickedUpWhereItWasLeft() throws {
        var game = JigsawGame(round: round(sample))
        let first = try #require(game.round.pieces.first)
        game.place(first.id, at: first.home)
        let saved = game.progress(day: day, seconds: 40)
        #expect(saved.placements.count == 1)
        #expect(saved.pieceCount == game.round.pieces.count)
        #expect(!saved.isSolved)
        #expect(saved.summary == "1 of \(game.round.pieces.count) pieces placed")

        let data = try JSONEncoder().encode(saved)
        let decoded = try JSONDecoder().decode(JigsawProgress.self, from: data)
        let resumed = JigsawGame(round: round(sample), day: day, saved: decoded)
        #expect(resumed == game)
    }

    @Test func yesterdaysProgressIsNotTodays() throws {
        var game = JigsawGame(round: round(sample))
        let first = try #require(game.round.pieces.first)
        game.place(first.id, at: first.home)
        let saved = game.progress(day: day, seconds: 10)
        let tomorrow = day.addingTimeInterval(86_400)
        #expect(JigsawGame(round: round(sample), day: tomorrow, saved: saved).placements.isEmpty)
        // Nor another Mini's on the same day.
        #expect(JigsawGame(round: round(sample, id: "mini-other"), day: day, saved: saved).placements.isEmpty)
    }

    @Test func aSolvedRoundSaysHowLongItTook() {
        var game = JigsawGame(round: round(sample))
        for piece in game.round.pieces { game.place(piece.id, at: piece.home) }
        let saved = game.progress(day: day, seconds: 95)
        #expect(saved.isSolved)
        #expect(saved.summary == "Solved in 1:35")
        #expect(JigsawGame(round: round(sample), day: day, saved: saved).isSolved)
    }

    @Test func startingAgainClearsTheBoardButKeepsTheCount() {
        var game = JigsawGame(round: round(["AB.", "...", "CD."]))
        game.place(game.round.pieces[0].id, at: game.round.pieces[1].home)
        game.startAgain()
        #expect(game.placements.isEmpty)
        #expect(game.wrongFits == 1)
    }

    // MARK: - The day's pick

    private func mini(_ id: String, answers: [String]) -> Puzzle {
        Puzzle(
            id: id, title: id, difficulty: .easy, verse: "v", reference: "r", publishDate: "2026-01-01",
            size: 7, grid: [], clues: answers.enumerated().map { index, answer in
                ClueData(number: index + 1, direction: .across, row: index, col: 0, text: "c", answer: answer)
            }, kind: .mini
        )
    }

    @Test func pickStartsHalfThePoolAwayAndWraps() {
        let minis = (0..<6).map { mini("mini-\($0)", answers: ["W\($0)"]) }
        #expect(PieceByPiece.pick(dayIndex: 0, from: minis)?.id == "mini-3")
        #expect(PieceByPiece.pick(dayIndex: 3, from: minis)?.id == "mini-0")
        #expect(PieceByPiece.pick(dayIndex: -1, from: minis)?.id == "mini-2")
        #expect(PieceByPiece.pick(dayIndex: 0, from: []) == nil)
    }

    @Test func pickStepsPastMinisAndAnswersToAvoid() {
        let minis = [
            mini("mini-0", answers: ["ARK"]), mini("mini-1", answers: ["DOVE"]),
            mini("mini-2", answers: ["MANNA"]), mini("mini-3", answers: ["LAMB", "ARK"]),
        ]
        // Day 0 starts at mini-2; a clash looks a quarter of the pool on
        // (mini-3), then walks.
        #expect(PieceByPiece.pick(dayIndex: 0, from: minis, avoidingIDs: ["mini-2"])?.id == "mini-3")
        #expect(PieceByPiece.pick(dayIndex: 0, from: minis, avoidingIDs: ["mini-2"], avoidingAnswers: ["ARK"])?.id == "mini-1")
        #expect(PieceByPiece.pick(dayIndex: 0, from: minis, avoidingAnswers: ["MANNA", "ARK", "DOVE"])?.id == "mini-2",
                "when everything clashes the day still has a round")
    }

    /// Against the bundle, across a year: never a Mini from the week either
    /// side, never an answer from today's grids, and not the same round two
    /// days running.
    @Test func bundledPickStaysClearOfTheDaysAroundIt() throws {
        let provider = PuzzleProvider.shared
        let calendar = Calendar.current
        var previous: String?
        for offset in 0..<365 {
            let date = try #require(calendar.date(byAdding: .day, value: offset, to: day))
            let pick = try #require(PieceByPiece.puzzle(on: date, provider: provider, calendar: calendar))
            #expect(pick.isMini)
            for near in -PieceByPiece.clearDays...PieceByPiece.clearDays {
                let other = try #require(calendar.date(byAdding: .day, value: near, to: date))
                #expect(provider.dailyMini(for: other, calendar: calendar)?.id != pick.id, "day \(offset), \(near) away")
            }
            let today = [provider.dailyPuzzle(for: date, calendar: calendar), provider.dailyMini(for: date, calendar: calendar)]
            let answers = Set(today.compactMap { $0 }.flatMap { $0.clues.map { $0.answer.uppercased() } })
            #expect(!pick.clues.contains { answers.contains($0.answer.uppercased()) }, "day \(offset) shares an answer")
            #expect(pick.id != previous, "day \(offset) repeats yesterday")
            previous = pick.id
        }
    }

    // MARK: - Words and decoys

    /// The sample grid with its clues, so words can be rebuilt.
    private func cluedRound(decoys: Int = 0) -> JigsawRound {
        JigsawRound(puzzle: Puzzle(
            id: "mini-clued", title: "T", difficulty: .easy, verse: "v", reference: "r",
            publishDate: "2026-01-01", size: sample.count, grid: sample, clues: [
                ClueData(number: 1, direction: .across, row: 0, col: 3, text: "Jacob met Rachel at one", answer: "WELL"),
                ClueData(number: 2, direction: .down, row: 0, col: 3, text: "Moses struck the rock for it", answer: "WATER"),
                ClueData(number: 3, direction: .down, row: 2, col: 0, text: "The church, to Christ", answer: "BRIDE"),
                ClueData(number: 4, direction: .across, row: 3, col: 0, text: "Isaac's wife", answer: "REBEKAH"),
                ClueData(number: 5, direction: .down, row: 2, col: 5, text: "Abraham's brother", answer: "NAHOR"),
            ], kind: .mini
        ), decoys: decoys)
    }

    @Test func aWordCountsOnceEverySquareHoldsItsLetter() throws {
        var game = JigsawGame(round: cluedRound())
        #expect(game.completedWords.isEmpty)
        // Cover WELL's squares piece by piece; it counts only when the last lands.
        let well = Set(try #require(game.round.words.first { $0.answer == "WELL" }).positions)
        let pieces = game.round.realPieces.filter { piece in
            piece.squares(at: piece.home).contains { well.contains($0.pos) }
        }
        for (index, piece) in pieces.enumerated() {
            #expect(!game.completedWords.contains { $0.answer == "WELL" })
            game.place(piece.id, at: piece.home)
            if index == pieces.count - 1 {
                #expect(game.completedWords.contains { $0.answer == "WELL" })
            }
        }
    }

    @Test func aWrongLetterKeepsAWordOpen() throws {
        var game = JigsawGame(round: cluedRound())
        for piece in game.round.realPieces { game.place(piece.id, at: piece.home) }
        #expect(game.completedWords.count == game.round.words.count)
        // Pull one piece and every word through it reopens.
        let piece = try #require(game.round.realPieces.first)
        game.returnToTray(piece.id)
        let gone = Set(piece.squares(at: piece.home).map(\.pos))
        for word in game.completedWords {
            #expect(gone.isDisjoint(with: word.positions))
        }
    }

    @Test func aDecoyFitsNowhereAndTheRoundSolvesWithoutIt() throws {
        let round = cluedRound(decoys: 1)
        let decoy = try #require(round.pieces.first { $0.isDecoy })
        #expect(round.pieces.filter { $0.isDecoy }.count == 1)
        #expect((2...3).contains(decoy.cells.count))
        for row in -3..<sample.count {
            for col in -3..<sample.count {
                let squares = decoy.squares(at: GridPos(row: row, col: col))
                #expect(!squares.allSatisfy { round.solution[$0.pos] == $0.letter }, "fits at \(row),\(col)")
            }
        }
        var game = JigsawGame(round: round)
        for piece in round.realPieces { game.place(piece.id, at: piece.home) }
        #expect(game.isSolved)
        #expect(game.trayPieces.map(\.id) == [decoy.id])
    }

    @Test func aDecoyLeavesTheRealCutAlone() {
        let plain = cluedRound()
        let weekend = cluedRound(decoys: 1)
        #expect(weekend.realPieces == plain.pieces, "same pieces, same tray order")
    }

    @Test func theTodayRowCountsOnlyRealPieces() throws {
        var game = JigsawGame(round: cluedRound(decoys: 1))
        let decoy = try #require(game.round.pieces.first { $0.isDecoy })
        let real = try #require(game.round.realPieces.first)
        game.place(real.id, at: real.home)
        // A decoy put down somewhere still isn't progress.
        for row in 0..<sample.count {
            for col in 0..<sample.count where game.origin(of: decoy.id) == nil {
                game.place(decoy.id, at: GridPos(row: row, col: col))
            }
        }
        let progress = game.progress(day: day, seconds: 10)
        #expect(progress.pieceCount == game.round.realPieces.count)
        #expect(progress.summary == "1 of \(game.round.realPieces.count) pieces placed")
    }

    @Test func weekendsGetADecoy() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        // 2026-11-23 is a Monday.
        let monday = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 23)))
        var counts: [Int] = []
        for offset in 0..<7 {
            let date = try #require(calendar.date(byAdding: .day, value: offset, to: monday))
            counts.append(PieceByPiece.decoys(on: date, calendar: calendar))
        }
        #expect(counts == [0, 0, 0, 0, 1, 1, 1])
    }

    @Test func everyBundledMiniTakesADecoy() {
        for mini in PuzzleProvider.shared.minis {
            let round = JigsawRound(puzzle: mini, decoys: 1)
            #expect(round.pieces.contains { $0.isDecoy }, "\(mini.id) has no decoy")
            #expect(round.words.count == mini.clues.count)
        }
    }
}
