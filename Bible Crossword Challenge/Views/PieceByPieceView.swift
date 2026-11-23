//
//  PieceByPieceView.swift
//  Bible Crossword Challenge
//
//  The Piece by Piece screen and its row on Today. A framed board with the
//  day's pieces waiting in a tray; drag a piece onto the board, or tap a
//  piece and then a square. A wrong fit turns red and stays until it is
//  moved: no tries to lose, no clock while playing. Rules live in
//  `PieceByPiece.swift`.
//
//  Progress is saved in settings, not SwiftData, for the reason Clue of the
//  Day's is: one small value that only matters today, and it must not ride
//  CloudKit into a merge.
//

import SwiftData
import SwiftUI

/// Pushes `PieceByPieceView` on Today's stack.
struct PieceByPieceRoute: Hashable {}

/// A puzzle opened from a finished round, so its start reads as source
/// `piece_by_piece`: the measure of whether the game leads into the grid.
struct PiecesPuzzleRoute: Hashable {
    let puzzle: Puzzle
}

/// Where the day's progress is kept.
enum PieceByPieceStorage {
    static let progressKey = "pieceByPiece.progress"

    static func decode(_ data: Data) -> JigsawProgress? {
        data.isEmpty ? nil : try? JSONDecoder().decode(JigsawProgress.self, from: data)
    }

    static func encode(_ progress: JigsawProgress) -> Data {
        (try? JSONEncoder().encode(progress)) ?? Data()
    }
}

// MARK: - Today row

/// Today's row. Renders nothing when there is no round to play.
struct PieceByPieceRow: View {
    @Environment(\.today) private var today
    @AppStorage(PieceByPieceStorage.progressKey) private var saved = Data()

    var body: some View {
        if let puzzle = PieceByPiece.puzzle(on: today) {
            let progress = PieceByPieceStorage.decode(saved).flatMap { $0.belongs(to: puzzle.id, on: today) ? $0 : nil }
            let started = progress.map { $0.isSolved || !$0.placements.isEmpty } ?? false
            let subtitle = started ? progress?.summary ?? "" : "A crossword in pieces"
            NavigationLink(value: PieceByPieceRoute()) {
                CoverRow(
                    symbol: progress?.isSolved == true ? "checkmark" : "puzzlepiece.fill",
                    tint: FeatureTint.daily,
                    title: "Piece by Piece",
                    subtitle: subtitle
                )
                .cardRowPadding()
            }
            .buttonStyle(PressableCardStyle())
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("Piece by Piece. \(subtitle)")
            .accessibilityIdentifier("pieceByPieceRow")
        }
    }
}

// MARK: - Screen

struct PieceByPieceView: View {
    @Environment(\.today) private var today
    @Environment(\.analytics) private var analytics
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.memoryVerses) private var memoryVerses
    @Environment(StoreService.self) private var store
    @AppStorage(PieceByPieceStorage.progressKey) private var saved = Data()
    @Query private var records: [PuzzleRecord]

    /// Built in `onAppear`, not `State(initialValue:)`: that argument is
    /// evaluated on every parent redraw, and this one cuts a grid.
    @State private var game: JigsawGame?
    /// `onAppear` runs again on every return to the screen; the impression
    /// is once per visit.
    @State private var didLogOpen = false
    /// The piece picked by a tap, waiting for a square.
    @State private var selected: Int?
    @State private var drag: Drag?
    /// Time banked before this stretch on the screen, and when it began.
    @State private var bankedSeconds = 0
    @State private var resumedAt = Date()
    /// The word just rebuilt, shown in the header with its clue for a
    /// moment. A move that finishes two words shows them one after the other.
    @State private var revealing: ClueData?
    @State private var revealTask: Task<Void, Never>?
    /// The header fades out, changes, and fades back in: a cross-fade laid
    /// the clue over the title.
    @State private var headerOpacity = 1.0
    /// The diagonal the solve's sweep is on: the word tint crossing the
    /// whole board once as the last piece lands. Nil at every other time,
    /// including a return to a round already solved.
    @State private var sweep: Int?
    @State private var sweepTask: Task<Void, Never>?

    private struct Drag: Equatable {
        let pieceID: Int
        /// The piece's top-left corner, in the screen's space.
        var corner: CGPoint
    }

    private static let space = "pieceByPiece"
    /// How far above the finger a dragged piece rides, so the hand doesn't
    /// cover it.
    private static let lift: CGFloat = 36
    private static let trayScale: CGFloat = 0.74
    private static let gap: CGFloat = 3
    private static let snap = Animation.snappy(duration: 0.22)
    /// Long enough to read a Mini's clue, short enough not to hold up the
    /// next piece.
    private static let revealTime: Duration = .milliseconds(2400)

    var body: some View {
        // One tree for every size and state: the board, tray and ending are
        // laid out by `Layout`, so a rotation or a Duo fold moves things and
        // rebuilds nothing. The lifecycle below hangs off this.
        GeometryReader { proxy in
            if let game {
                board(game, layout: Layout(game: game, size: proxy.size))
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                    .coordinateSpace(.named(Self.space))
            }
        }
        .background(Theme.gameCanvas)
        .navigationTitle("Piece by Piece")
        .navigationBarTitleDisplayMode(.inline)
        // A place to play, like the grid: the tabs come back on the way out.
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            if let game, !game.isSolved, !game.placements.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Start again", systemImage: "arrow.counterclockwise", action: startAgain)
                }
            }
        }
        .sensoryFeedback(.success, trigger: game?.isSolved == true) { _, solved in solved }
        .sensoryFeedback(.error, trigger: game?.wrongFits ?? 0)
        .onAppear {
            setUpIfNeeded()
            resumedAt = Date()
        }
        .onDisappear {
            bankTime()
            revealTask?.cancel()
            sweepTask?.cancel()
            revealing = nil
            sweep = nil
            headerOpacity = 1
        }
        // Left open over midnight: the day's round changes under it.
        .onChange(of: today) {
            game = nil
            setUpIfNeeded()
        }
    }

    private func setUpIfNeeded() {
        guard game == nil, let puzzle = PieceByPiece.puzzle(on: today) else { return }
        let progress = PieceByPieceStorage.decode(saved).flatMap { $0.belongs(to: puzzle.id, on: today) ? $0 : nil }
        let round = JigsawRound(puzzle: puzzle, decoys: PieceByPiece.decoys(on: today))
        var built = JigsawGame(round: round, day: today, saved: progress)
        #if DEBUG
        // `-uiPiecesSolved`: the ending without playing to it, for layout.
        // `-uiPiecesAllButOne`: one piece from the end, so a UI test can
        // make the solving move without knowing the day's answer.
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-uiPiecesSolved") {
            for piece in round.realPieces { built.place(piece.id, at: piece.home) }
        } else if arguments.contains("-uiPiecesAllButOne") {
            for piece in round.realPieces.dropLast() { built.place(piece.id, at: piece.home) }
        }
        #endif
        game = built
        selected = nil
        drag = nil
        bankedSeconds = progress?.seconds ?? 0
        resumedAt = Date()
        if !didLogOpen {
            didLogOpen = true
            let state = built.isSolved ? "solved" : built.placements.isEmpty ? "new" : "in_progress"
            analytics.log(.pieceByPieceOpened(puzzleID: puzzle.id, state: state))
        }
    }

    // MARK: - Layout

    /// Where everything sits for one size of screen. Pieces are placed by
    /// hand, not by a stack, so one can travel from the tray to the board
    /// as a single view and animate the whole way.
    private struct Layout {
        let cell: CGFloat
        let trayCell: CGFloat
        let boardOrigin: CGPoint
        let boardSide: CGFloat
        /// The tray's room, and the ending's once the round is solved: under
        /// the board in portrait, beside it when the screen is wide.
        let trayRect: CGRect
        static let headerHeight: CGFloat = 56
        static let solvedScale: CGFloat = 0.72
        /// Top-left corner of each tray piece.
        var tray: [Int: CGPoint] = [:]

        init(game: JigsawGame, size: CGSize) {
            let margin = Theme.Spacing.m
            let top = Self.headerHeight + Theme.Spacing.s
            if size.width > size.height * 1.15 {
                // Wide (landscape, an open Duo): board left of centre, tray right.
                boardSide = max(min(size.height - top - margin, size.width / 2 - margin * 1.5, 430), 1)
                boardOrigin = CGPoint(x: max(margin, size.width / 2 - margin / 2 - boardSide), y: top)
                let left = size.width / 2 + margin / 2
                trayRect = CGRect(x: left, y: top, width: min(size.width - left - margin, 480), height: size.height - top)
            } else {
                // The board takes the width, but never more than half the
                // height: the tray needs the rest.
                // Once solved the board is a keepsake, not a work surface: it
                // steps back so the verse, the way on and the words get the
                // room.
                let column = min(size.width, 560)
                let scale: CGFloat = game.isSolved ? Self.solvedScale : 1
                boardSide = max(min(column - margin * 2, size.height * 0.5, 430) * scale, 1)
                // A Mini rarely fills all seven rows and columns. The letters
                // are centred and start at the top, and the tray begins under
                // the last row that holds one, not under an empty band.
                let unit = boardSide / CGFloat(game.round.size)
                let rows = game.round.solution.keys.map(\.row)
                let cols = game.round.solution.keys.map(\.col)
                let (firstRow, lastRow) = (rows.min() ?? 0, rows.max() ?? game.round.size - 1)
                let spareRight = CGFloat(game.round.size - 1 - (cols.max() ?? 0))
                let spareLeft = CGFloat(cols.min() ?? 0)
                boardOrigin = CGPoint(
                    x: (size.width - boardSide) / 2 + (spareRight - spareLeft) / 2 * unit,
                    y: top - CGFloat(firstRow) * unit
                )
                let trayTop = top + CGFloat(lastRow - firstRow + 1) * unit + Theme.Spacing.l
                trayRect = CGRect(
                    x: (size.width - column) / 2 + margin, y: trayTop,
                    width: column - margin * 2, height: max(size.height - trayTop, 0)
                )
            }
            cell = boardSide / CGFloat(game.round.size)
            trayCell = cell * PieceByPieceView.trayScale

            // Pieces flow left to right, wrapping, each row as tall as its
            // tallest piece and centred under the board. Every piece keeps
            // its slot whether or not it is in the tray: taking one out
            // leaves a gap instead of sending the rest to new places, and a
            // piece sent back goes where it came from.
            let spacing = Theme.Spacing.m
            let (minX, maxX, room) = (trayRect.minX, trayRect.maxX, trayRect.width)
            var slots: [Int: CGPoint] = [:]
            var row: [(id: Int, x: CGFloat)] = []
            var x = minX, y = trayRect.minY, rowHeight: CGFloat = 0
            func closeRow() {
                let shift = max((room - (x - spacing - minX)) / 2, 0)
                for item in row { slots[item.id] = CGPoint(x: item.x + shift, y: y) }
                row = []
            }
            for piece in game.round.pieces {
                let width = CGFloat(piece.cols) * trayCell
                let height = CGFloat(piece.rows) * trayCell
                if x + width > maxX, x > minX {
                    closeRow()
                    x = minX
                    y += rowHeight + spacing
                    rowHeight = 0
                }
                row.append((piece.id, x))
                x += width + spacing
                rowHeight = max(rowHeight, height)
            }
            closeRow()
            tray = slots
        }

        func point(for pos: GridPos) -> CGPoint {
            CGPoint(x: boardOrigin.x + CGFloat(pos.col) * cell, y: boardOrigin.y + CGFloat(pos.row) * cell)
        }

        /// The square whose corner is nearest `corner`.
        func square(nearest corner: CGPoint) -> GridPos {
            GridPos(row: Int(((corner.y - boardOrigin.y) / cell).rounded()),
                    col: Int(((corner.x - boardOrigin.x) / cell).rounded()))
        }

        /// Whether a piece let go with its corner at `corner` is over the
        /// tray, which sends it back.
        func isOverTray(_ piece: JigsawPiece, corner: CGPoint) -> Bool {
            let centre = CGPoint(x: corner.x + CGFloat(piece.cols) * cell / 2,
                                 y: corner.y + CGFloat(piece.rows) * cell / 2)
            return trayRect.insetBy(dx: -Theme.Spacing.m, dy: -Theme.Spacing.s).contains(centre)
        }
    }

    // MARK: - Board

    private func board(_ game: JigsawGame, layout: Layout) -> some View {
        let covered = game.board
        return ZStack(alignment: .topLeading) {
            header(game)
            squares(game, covered: covered, preview: dropPreview(game, layout: layout), layout: layout)
            if game.isSolved {
                ending(game)
                    .frame(width: layout.trayRect.width, height: layout.trayRect.height, alignment: .top)
                    .offset(x: layout.trayRect.minX, y: layout.trayRect.minY)
                    .transition(.opacity)
            }
            // Once solved, the tray is the ending: a decoy left in it goes.
            ForEach(game.round.pieces.filter { !game.isSolved || game.origin(of: $0.id) != nil }) { piece in
                pieceView(piece, game: game, layout: layout)
            }
        }
    }

    /// The Mini's title is the round's theme: with no clues, it is the one
    /// hint at what the words are about, and the verse reference is what
    /// the player is rebuilding toward. A word just rebuilt takes the header
    /// for a moment with its clue.
    private func header(_ game: JigsawGame) -> some View {
        VStack(spacing: 2) {
            if let word = revealing, !game.isSolved {
                Text(word.answer.uppercased())
                    .font(.headline)
                    .tracking(1)
                // Primary, not the instruction's grey: this line is the
                // reward for the word.
                Text(word.text)
                    .font(.subheadline)
            } else if game.isSolved {
                // The time is what the round came to: it leads, and the
                // title steps down beside the promise of tomorrow's.
                Text("Rebuilt in \(TimeFormat.clock(bankedSeconds))")
                    .monospacedDigit()
                    .font(.title3.weight(.semibold))
                Text("\(game.round.title) · A new one tomorrow")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text(game.round.title)
                    .font(.headline)
                Text("Rebuild the crossword behind \(game.round.reference)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .opacity(headerOpacity)
        // The header has a fixed band above the board, like a bar: past
        // this size it would run into the tiles (it did at AX5). The verse
        // and the word list below still scale all the way.
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .padding(.horizontal, Theme.Spacing.m)
        .frame(maxWidth: .infinity)
        .frame(height: Layout.headerHeight)
        .accessibilityElement(children: .combine)
    }

    /// The squares a dragged piece would land on if let go now. Empty when
    /// it wouldn't take: over the tray, off the board, or on another piece.
    private func dropPreview(_ game: JigsawGame, layout: Layout) -> Set<GridPos> {
        guard let drag, let piece = game.piece(drag.pieceID),
              !layout.isOverTray(piece, corner: drag.corner) else { return [] }
        let origin = layout.square(nearest: drag.corner)
        guard game.canPlace(piece, at: origin) else { return [] }
        return Set(piece.squares(at: origin).map(\.pos))
    }

    /// The empty squares, each one a tap target for a picked piece. Those
    /// under a dragged piece's landing spot light up in the accent.
    private func squares(
        _ game: JigsawGame, covered: [GridPos: Character], preview: Set<GridPos>, layout: Layout
    ) -> some View {
        let size = game.round.size
        return ForEach(0..<(size * size), id: \.self) { index in
            let pos = GridPos(row: index / size, col: index % size)
            // Only the squares still open: one under a piece is hidden by it,
            // and would be a second thing for VoiceOver to land on.
            if game.round.solution[pos] != nil, covered[pos] == nil {
                RoundedRectangle(cornerRadius: layout.cell * 0.16, style: .continuous)
                    .fill(preview.contains(pos) ? Theme.accent.opacity(0.22) : Theme.gridBlock.opacity(0.45))
                    .animation(.easeOut(duration: 0.12), value: preview.contains(pos))
                    .frame(width: layout.cell - Self.gap, height: layout.cell - Self.gap)
                    .contentShape(.rect)
                    .onTapGesture { tapSquare(pos) }
                    .offset(x: layout.point(for: pos).x + Self.gap / 2,
                            y: layout.point(for: pos).y + Self.gap / 2)
                    .accessibilityElement()
                    .accessibilityLabel("Empty square, row \(pos.row + 1), column \(pos.col + 1)")
                    .accessibilityHint(selected == nil ? "" : "Puts the picked piece here")
                    .accessibilityAddTraits(selected == nil ? [] : .isButton)
                    .accessibilityAction { tapSquare(pos) }
            }
        }
    }

    // MARK: - Pieces

    @ViewBuilder
    private func pieceView(_ piece: JigsawPiece, game: JigsawGame, layout: Layout) -> some View {
        let placed = game.origin(of: piece.id)
        let dragging = drag?.pieceID == piece.id
        let cell = placed != nil || dragging ? layout.cell : layout.trayCell
        // Where it rests, and at what size: what a drag starts from.
        let restCell = placed != nil ? layout.cell : layout.trayCell
        let rest = placed.map(layout.point(for:)) ?? layout.tray[piece.id] ?? .zero
        let corner = dragging ? drag?.corner ?? rest : rest
        let wrong = placed != nil && game.isWrong(piece.id)
        // The word in the header, marked on the board where the eye is.
        let word = Set(revealing?.positions ?? [])
        let lit = placed.map { origin in
            Set(piece.cells.filter { cell in
                let pos = GridPos(row: origin.row + cell.row, col: origin.col + cell.col)
                // The solve's sweep is four diagonals wide: narrower and a
                // tile is lit for less time than its fade takes to show.
                return word.contains(pos) || sweep.map { (0...3).contains($0 - pos.row - pos.col) } ?? false
            })
        } ?? []

        PieceShape(piece: piece, cell: cell, gap: Self.gap, lit: lit,
                   isWrong: wrong, isSelected: selected == piece.id, isLifted: dragging)
            .offset(x: corner.x, y: corner.y)
            .zIndex(dragging ? 2 : (selected == piece.id ? 1 : 0))
            .gesture(dragGesture(piece, layout: layout, from: rest, cell: restCell))
            .onTapGesture { tapPiece(piece) }
            .allowsHitTesting(!game.isSolved)
            .animation(reduceMotion ? nil : Self.snap, value: placed)
            .animation(reduceMotion ? nil : Self.snap, value: layout.tray[piece.id])
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label(for: piece, placed: placed, wrong: wrong))
            .accessibilityHint(game.isSolved ? "" : placed == nil
                ? "Double tap to pick up, then choose a square"
                : "Double tap to pick up. Double tap again to send it back to the tray")
            .accessibilityAddTraits(game.isSolved ? [] : .isButton)
            .accessibilityAddTraits(selected == piece.id ? .isSelected : [])
            // An L's bounding box has an empty corner, and a double tap
            // lands in the middle of the box: act on the piece directly.
            .accessibilityAction { tapPiece(piece) }
    }

    private func label(for piece: JigsawPiece, placed: GridPos?, wrong: Bool) -> String {
        let letters = piece.cells.map { String($0.letter) }.joined(separator: " ")
        guard let placed else { return "Piece \(letters), in the tray" }
        return "Piece \(letters), at row \(placed.row + 1), column \(placed.col + 1)" + (wrong ? ", doesn't fit" : "")
    }

    /// A piece keeps the point it was grabbed by under the finger, scaled up
    /// if it came from the tray, and rides `lift` above it.
    private func dragGesture(
        _ piece: JigsawPiece, layout: Layout, from rest: CGPoint, cell: CGFloat
    ) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .named(Self.space))
            .onChanged { value in
                let grow = layout.cell / cell
                selected = nil
                drag = Drag(pieceID: piece.id, corner: CGPoint(
                    x: value.location.x - (value.startLocation.x - rest.x) * grow,
                    y: value.location.y - (value.startLocation.y - rest.y) * grow - Self.lift
                ))
            }
            .onEnded { _ in
                guard let drop = drag, drop.pieceID == piece.id else { return }
                change { game in
                    if layout.isOverTray(piece, corner: drop.corner) {
                        game.returnToTray(piece.id)
                    } else {
                        // Refused: it stays where it was, tray or square.
                        game.place(piece.id, at: layout.square(nearest: drop.corner))
                    }
                }
                withAnimation(reduceMotion ? nil : Self.snap) { drag = nil }
            }
    }

    // MARK: - Play

    private func tapPiece(_ piece: JigsawPiece) {
        guard let game, !game.isSolved else { return }
        if selected == piece.id {
            // A second tap on a placed piece sends it back.
            selected = nil
            if game.origin(of: piece.id) != nil {
                change { $0.returnToTray(piece.id) }
            }
        } else {
            selected = piece.id
        }
    }

    /// Puts the picked piece down with its first letter on `pos`.
    private func tapSquare(_ pos: GridPos) {
        guard let id = selected, let piece = game?.piece(id), let first = piece.cells.first else { return }
        let origin = GridPos(row: pos.row - first.row, col: pos.col - first.col)
        change { game in
            if game.place(id, at: origin) { selected = nil }
        }
    }

    private func startAgain() {
        selected = nil
        change { $0.startAgain() }
    }

    /// Every move goes through here: apply it, save it, and say so once when
    /// it is the one that finishes the round.
    private func change(_ move: (inout JigsawGame) -> Void) {
        guard var current = game, !current.isSolved else { return }
        // Read before the move: once it solves the round the clock has stopped.
        let seconds = secondsPlayed
        let before = Set(current.completedWords)
        withAnimation(reduceMotion ? nil : Self.snap) {
            move(&current)
            game = current
        }
        saved = PieceByPieceStorage.encode(current.progress(day: today, seconds: seconds))
        guard current.isSolved else {
            reveal(current.completedWords.filter { !before.contains($0) })
            return
        }
        // The ending lists every word; the header goes back to the time.
        revealTask?.cancel()
        revealing = nil
        headerOpacity = 1
        bankedSeconds = seconds
        sweepBoard(size: current.round.size)
        analytics.log(.pieceByPieceFinished(
            puzzleID: current.round.puzzleID, seconds: seconds,
            wrongFits: current.wrongFits, pieces: current.round.realPieces.count,
            decoys: current.round.pieces.count - current.round.realPieces.count
        ))
    }

    /// Shows each newly rebuilt word in the header, one after the other.
    /// A later move replaces whatever is still showing.
    private func reveal(_ words: [ClueData]) {
        guard !words.isEmpty else { return }
        revealTask?.cancel()
        revealTask = Task { @MainActor in
            for word in words {
                await showInHeader(word)
                if Task.isCancelled { return }
                AccessibilityNotification.Announcement("\(word.answer): \(word.text)").post()
                try? await Task.sleep(for: Self.revealTime)
                if Task.isCancelled { return }
            }
            await showInHeader(nil)
        }
    }

    /// The solve's one flourish: the tint runs corner to corner, in the
    /// time the board takes to step back. Skipped under Reduce Motion.
    private func sweepBoard(size: Int) {
        guard !reduceMotion else { return }
        sweepTask?.cancel()
        sweepTask = Task { @MainActor in
            for diagonal in 0...(size * 2 + 3) {
                sweep = diagonal
                try? await Task.sleep(for: .milliseconds(50))
                if Task.isCancelled { break }
            }
            sweep = nil
        }
    }

    /// Out, change, in. Whoever cancels this mid-way puts the opacity back.
    private func showInHeader(_ word: ClueData?) async {
        guard !reduceMotion else {
            revealing = word
            return
        }
        withAnimation(.easeOut(duration: 0.15)) { headerOpacity = 0 }
        try? await Task.sleep(for: .milliseconds(150))
        if Task.isCancelled { return }
        revealing = word
        withAnimation(.easeIn(duration: 0.2)) { headerOpacity = 1 }
    }

    /// Time on this screen today. Stops for good once the round is solved.
    private var secondsPlayed: Int {
        if game?.isSolved == true { return bankedSeconds }
        return bankedSeconds + max(0, Int(Date().timeIntervalSince(resumedAt).rounded()))
    }

    /// Leaving the screen banks the stretch, so time away isn't counted.
    private func bankTime() {
        guard let game, !game.isSolved else { return }
        bankedSeconds = secondsPlayed
        resumedAt = Date()
        saved = PieceByPieceStorage.encode(game.progress(day: today, seconds: bankedSeconds))
    }

    // MARK: - Ending

    /// Where the tray was: the verse the Mini opens on, then on to the grid.
    /// The time is in the header. Scrolls, since a small phone can't hold
    /// it all under the board.
    private func ending(_ game: JigsawGame) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    Text(game.round.verse)
                        .font(.scripture(.title3))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(game.round.reference)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    memoryLink(game.round)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Theme.Spacing.m)
                .elevatedCard()

                // The screen's one blue button: on to the grid. Sharing
                // steps back to the quiet weight beside it.
                if let next = NextPuzzleLink.make(on: today, records: records) {
                    NavigationLink(value: PiecesPuzzleRoute(puzzle: next.puzzle)) {
                        Label(next.title, systemImage: "play.fill")
                    }
                    .buttonStyle(.pillAccent)
                    .accessibilityIdentifier("pieceByPiecePlay")
                }
                ShareLink(item: shareText) {
                    Label("Share result", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.pillTonal)

                wordList(game.round)
            }
            .padding(.top, Theme.Spacing.s)
            .padding(.bottom, Theme.Spacing.l)
        }
        .scrollBounceBehavior(.basedOnSize)
        // What scrolls up fades out under the board instead of being cut
        // by a hard edge.
        .mask {
            VStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                    .frame(height: Theme.Spacing.s)
                Color.black
            }
        }
    }

    /// "Learn it by heart", inside the verse card: a quiet link, as on the
    /// completion screen, so the blue button stays the only call to act.
    /// Adds in place rather than leaving, since the grid is the next step.
    /// Absent when the verse is too long for a memory grid or the free
    /// shelf is full.
    @ViewBuilder
    private func memoryLink(_ round: JigsawRound) -> some View {
        if MemoryCloze.isEligible(verseText: round.verse) {
            if memoryVerses.entry(for: MemoryCloze.referenceKey(round.reference)) != nil {
                Label("In Memory Verses", systemImage: "brain.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.top, Theme.Spacing.xs)
                    .accessibilityLabel("\(round.reference) is in your memory verses")
            } else if memoryVerses.canStartNewVerse(isPremium: store.isPremium) {
                Button {
                    memoryVerses.start(reference: round.reference, verseText: round.verse)
                    analytics.log(.memoryVerseAdded(reference: round.reference, source: "piece_by_piece"))
                } label: {
                    Label("Learn it by heart", systemImage: "brain")
                        .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.borderless)
                .tint(Theme.accent)
                .padding(.top, Theme.Spacing.xs)
                .accessibilityHint("Adds the verse to your memory verses")
                .accessibilityIdentifier("pieceByPieceMemory")
            }
        }
    }

    /// The words just rebuilt, with the clues they answer: what the round
    /// taught, under the actions so they stay in reach.
    private func wordList(_ round: JigsawRound) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("The words")
                .font(.headline)
                .padding(.top, Theme.Spacing.s)
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                ForEach(round.words, id: \.self) { word in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(word.answer.uppercased())
                            .font(.subheadline.weight(.semibold))
                            .tracking(1)
                        Text(word.text)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(Theme.Spacing.m)
            .elevatedCard()
        }
    }

    /// The result without the words: a friend can still play today's. The
    /// link is the site's install hop, so these installs read as campaign
    /// `pieces` in App Store Connect.
    private var shareText: String {
        "Piece by Piece: rebuilt today's crossword in \(TimeFormat.clock(bankedSeconds)).\nBible Crossword Challenge https://biblecrosswordchallenge.com/go/?s=pieces"
    }
}

// MARK: - Piece

/// The squares of one piece, drawn at `cell` points a square. Only the
/// squares take touches: the empty corner of an L lets a tap through to
/// whatever is under it.
private struct PieceShape: View {
    let piece: JigsawPiece
    let cell: CGFloat
    let gap: CGFloat
    /// Squares of the word just rebuilt: a neutral wash while its clue
    /// shows. Not the accent, which is for things to tap.
    var lit: Set<JigsawPiece.Cell> = []
    let isWrong: Bool
    let isSelected: Bool
    let isLifted: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(piece.cells, id: \.self) { square in
                Text(String(square.letter))
                    .font(.system(size: cell * 0.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(isWrong ? CellPalette.error : CellPalette.textColor())
                    .frame(width: cell - gap, height: cell - gap)
                    .background {
                        RoundedRectangle(cornerRadius: cell * 0.16, style: .continuous)
                            .fill(CellPalette.empty)
                        RoundedRectangle(cornerRadius: cell * 0.16, style: .continuous)
                            .fill(isWrong ? CellPalette.errorWash : .clear)
                        RoundedRectangle(cornerRadius: cell * 0.16, style: .continuous)
                            .fill(Color.primary.opacity(lit.contains(square) ? 0.12 : 0))
                            .animation(.easeOut(duration: 0.25), value: lit)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: cell * 0.16, style: .continuous)
                            .strokeBorder(Theme.accent, lineWidth: isSelected ? 2 : 0)
                    }
                    .offset(x: CGFloat(square.col) * cell + gap / 2, y: CGFloat(square.row) * cell + gap / 2)
            }
        }
        .frame(width: CGFloat(piece.cols) * cell, height: CGFloat(piece.rows) * cell, alignment: .topLeading)
        .contentShape(squares)
        .shadow(color: .black.opacity(isLifted ? 0.22 : 0.06), radius: isLifted ? 10 : 1.5, y: isLifted ? 6 : 1)
        .scaleEffect(isLifted ? 1.04 : 1)
    }

    private var squares: Path {
        var path = Path()
        for square in piece.cells {
            path.addRect(CGRect(x: CGFloat(square.col) * cell, y: CGFloat(square.row) * cell, width: cell, height: cell))
        }
        return path
    }
}
