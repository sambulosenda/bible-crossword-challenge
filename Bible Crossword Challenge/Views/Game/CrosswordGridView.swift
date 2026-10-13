//
//  CrosswordGridView.swift
//  Bible Crossword Challenge
//
//  Renders the square grid. Up to 15×15 it is sized to fit its container —
//  the shipped feel, untouched. Beyond that (the 21×21 Sunday Special) cells
//  fitted to a phone would be ~17pt, unreadable and untappable, so the grid
//  becomes a pinch-zoomable, pannable viewport that keeps the selected cell
//  in view. Cells are value-typed and Equatable so only changed cells repaint
//  on each keystroke.
//

import SwiftUI

/// Height the fitted board can't use, published so the screen can spend it
/// elsewhere. A mini's cells are capped by the screen's width, so on a tall
/// phone the board leaves a band of empty paper it has no way to fill. Zero in
/// zoom mode, which fills whatever it's given. A preference rather than a
/// callback property: a closure can't be compared, so it would mark the grid
/// changed on every redraw of the screen around it.
struct SpareGridHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct CrosswordGridView: View {
    @Bindable var vm: GameViewModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Cells currently showing the word-complete green pulse.
    @State private var flashing: Set<GridPos> = []
    /// Bumped per completed word — drives the light completion haptic.
    @State private var wordTick = 0
    /// Bumped per failed check — drives the shake transform and error haptic.
    @State private var shakeTick = 0

    /// Current cell side in zoom mode; nil until the first layout pass picks
    /// a default. Never smaller than fit (whole grid visible), never larger
    /// than a full touch target.
    @State private var zoomSide: CGFloat?
    /// The side the current pinch started from, so magnification composes
    /// against a stable base instead of feeding back into itself.
    @State private var pinchBase: CGFloat?
    /// `playableBounds`, cached: blocks never change mid-puzzle, and the body
    /// that reads it runs on every keystroke. Set on appear; until then the
    /// first layout computes it inline.
    @State private var cachedBounds: (puzzleID: String, bounds: PlayableBounds)?

    /// Grids wider than this get the zoomable treatment. Every shipped daily
    /// is 15 or under and keeps the fit-to-width feel exactly as it was.
    private static let zoomThreshold = 15
    /// Zoom-mode bounds: `maxZoomSide` is a comfortable full-size touch
    /// target; the minimum is whatever side fits the whole grid on screen.
    private static let maxZoomSide: CGFloat = 44
    /// The default zoom shows readable, tappable cells rather than the whole
    /// board — the first act on a big grid is reading a clue, not surveying.
    private static let comfortableSide: CGFloat = 30
    /// The smallest cell the fitted layout is allowed to produce. Under this a
    /// cell holds neither a legible letter nor a hittable target, and fitting
    /// the board on screen has stopped buying anything — see `body`.
    private static let minimumFittedSide: CGFloat = 24
    /// Cropping to the playable cells can leave a sparse mini with a lot of
    /// room; past this a cell stops looking like a crossword square.
    private static let maximumFittedSide: CGFloat = 60
    /// One press of the accessibility zoom action. Coarse on purpose: the
    /// whole range is fit→44pt, and a stepper you have to work a dozen times
    /// is its own kind of inaccessible.
    private static let zoomStep: CGFloat = 1.5

    #if DEBUG
    /// Screenshot helper: `-uiHideSelection` draws the board with no selected
    /// cell or active word — same family as -uiFillSolved.
    private static let hidesSelection = ProcessInfo.processInfo.arguments.contains("-uiHideSelection")
    #else
    private static let hidesSelection = false
    #endif

    var body: some View {
        GeometryReader { geo in
            // Fit or zoom is a question about the container, not just the
            // puzzle. A 15×15 fits comfortably in portrait and not at all in
            // landscape, or at accessibility text sizes, where the clue bar and
            // keypad leave the grid a sliver. `fittedGrid` had no floor, so it
            // went on shrinking past the point of use: ~5pt cells at AX5, and
            // in landscape nothing at all — the grid was absent from the screen
            // and from the accessibility tree alike.
            //
            // Below `minimumFittedSide` the whole-board view is given up for
            // the same pan/zoom viewport the 21×21 uses. A grid you can reach
            // beats a grid you can see all of.
            //
            // Fit is measured against the playable cells' bounding box, not the
            // nominal N×N: blocks are invisible, and a board whose outer rows
            // or columns are empty was centring that empty margin — the
            // visible cells sat off-centre, and smaller than they needed to be.
            // Keyed to the puzzle, so a view reused for another board can't
            // centre on the last one's cells.
            let box = cachedBounds.flatMap { $0.puzzleID == vm.puzzle.id ? $0.bounds : nil } ?? playableBounds
            let fit = min(
                floor(geo.size.width / CGFloat(box.cols.count)),
                floor(geo.size.height / CGFloat(box.rows.count)),
                Self.maximumFittedSide
            )
            let zooms = vm.size > Self.zoomThreshold || fit < Self.minimumFittedSide
            let spare = zooms ? 0 : max(0, geo.size.height - fit * CGFloat(box.rows.count))
            Group {
                if zooms {
                    zoomableGrid(in: geo.size)
                } else {
                    fittedGrid(side: fit, box: box)
                }
            }
            .preference(key: SpareGridHeightKey.self, value: spare)
        }
        .sensoryFeedback(.impact(weight: .light), trigger: wordTick)
        .sensoryFeedback(.error, trigger: shakeTick)
        // Typing on a locked (revealed) cell: the letter is skipped, and a
        // silent skip reads as a broken keyboard — pulse the cell green (it
        // is, after all, already right) with a warning tap.
        .sensoryFeedback(.warning, trigger: vm.lockedEntryTick)
        .onChange(of: vm.lockedEntryTick) { _, _ in
            guard let pos = vm.lockedEntryPos else { return }
            AccessibilityNotification.Announcement("Already revealed").post()
            withAnimation(.easeOut(duration: 0.15)) { _ = flashing.insert(pos) }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(350))
                withAnimation(.easeOut(duration: 0.25)) { _ = flashing.remove(pos) }
            }
        }
        .onAppear {
            wireFeedback()
            cachedBounds = (vm.puzzle.id, playableBounds)
        }
        .onChange(of: vm.puzzle.id) { _, id in cachedBounds = (id, playableBounds) }
        .onChange(of: vm.isComplete) { _, complete in
            guard complete, !reduceMotion else { return }
            celebrationWave()
        }
    }

    // MARK: - Fit mode (the shipped behavior, whenever the cells stay usable)

    /// Centred in whatever rect `body` measured. The square frame that used to
    /// do the centring (`aspectRatio(1, .fit)`) is gone with it: it sized the
    /// grid to the *shorter* side of the container, which is exactly how a
    /// landscape screen reduced the board to nothing.
    private func fittedGrid(side: CGFloat, box: PlayableBounds) -> some View {
        gridRows(side: side, rows: box.rows, cols: box.cols)
            .frame(width: side * CGFloat(box.cols.count), height: side * CGFloat(box.rows.count))
            .modifier(ShakeEffect(animatableData: CGFloat(shakeTick)))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Zoom mode (Sunday Specials, and any container too small to fit)

    private func zoomableGrid(in size: CGSize) -> some View {
        let fit = floor(min(size.width, size.height) / CGFloat(vm.size))
        let side = zoomSide.map { clamped($0, fit: fit) } ?? max(fit, Self.comfortableSide)
        let total = side * CGFloat(vm.size)

        return ScrollViewReader { proxy in
            ScrollView([.horizontal, .vertical], showsIndicators: false) {
                gridRows(side: side)
                    .frame(width: total, height: total)
                    .modifier(ShakeEffect(animatableData: CGFloat(shakeTick)))
                    // Centered while zoomed out smaller than the viewport;
                    // a plain ScrollView would pin it top-leading.
                    .frame(
                        width: max(total, size.width),
                        height: max(total, size.height)
                    )
            }
            .simultaneousGesture(magnify(fit: fit))
            // Pinch is the only way to work this viewport, and it is a gesture
            // not everyone can make. Zoom mode is also where a large text size
            // lands the ordinary 15×15 (see `body`), so the people most likely
            // to be here are the ones least likely to pinch.
            .accessibilityZoomAction { action in
                let base = zoomSide ?? max(fit, Self.comfortableSide)
                let factor = action.direction == .zoomIn
                    ? Self.zoomStep
                    : 1 / Self.zoomStep
                zoomSide = clamped(base * factor, fit: fit)
            }
            .onChange(of: vm.selected) { _, pos in
                scrollTo(pos, proxy: proxy)
            }
            .onAppear {
                if zoomSide == nil { zoomSide = max(fit, Self.comfortableSide) }
                // Without animation: arriving on a screen already framed on
                // your cursor, not watching it travel there.
                proxy.scrollTo(vm.selected, anchor: .center)
            }
        }
    }

    /// Typing along a word must never walk the cursor off-screen — including
    /// under the keyboard, which is why the anchor is the viewport's center
    /// rather than its nearest edge.
    private func scrollTo(_ pos: GridPos, proxy: ScrollViewProxy) {
        if reduceMotion {
            proxy.scrollTo(pos, anchor: .center)
        } else {
            withAnimation(.easeOut(duration: 0.15)) {
                proxy.scrollTo(pos, anchor: .center)
            }
        }
    }

    private func clamped(_ side: CGFloat, fit: CGFloat) -> CGFloat {
        min(max(side, fit), Self.maxZoomSide)
    }

    private func magnify(fit: CGFloat) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let base = pinchBase ?? zoomSide ?? max(fit, Self.comfortableSide)
                pinchBase = base
                zoomSide = clamped(base * value.magnification, fit: fit)
            }
            .onEnded { _ in pinchBase = nil }
    }

    // MARK: - Shared rows

    /// Rows and columns holding at least one playable cell. Falls back to the
    /// whole grid for a board with none, which no shipped puzzle is.
    private var playableBounds: PlayableBounds {
        var minR = vm.size, maxR = -1, minC = vm.size, maxC = -1
        for r in 0..<vm.size {
            for c in 0..<vm.size where !vm.grid[r][c].isBlock {
                minR = min(minR, r); maxR = max(maxR, r)
                minC = min(minC, c); maxC = max(maxC, c)
            }
        }
        guard maxR >= 0 else { return PlayableBounds(rows: 0..<vm.size, cols: 0..<vm.size) }
        return PlayableBounds(rows: minR..<(maxR + 1), cols: minC..<(maxC + 1))
    }

    private func gridRows(side: CGFloat) -> some View {
        gridRows(side: side, rows: 0..<vm.size, cols: 0..<vm.size)
    }

    private func gridRows(side: CGFloat, rows: Range<Int>, cols: Range<Int>) -> some View {
        let activeWord = vm.activeWordPositions

        return VStack(spacing: 0) {
            ForEach(rows, id: \.self) { r in
                HStack(spacing: 0) {
                    ForEach(cols, id: \.self) { c in
                        let pos = GridPos(row: r, col: c)
                        let cell = vm.grid[r][c]
                        CellView(
                            cell: cell,
                            side: side,
                            isSelected: !Self.hidesSelection && vm.selected == pos,
                            isInWord: !Self.hidesSelection && activeWord.contains(pos),
                            // Auto-check marks mistakes continuously; a
                            // one-shot check marks its cells until edited
                            // (that part rides on the cell itself).
                            showError: vm.autoCheck || cell.isCheckedWrong,
                            showCorrect: showCorrectOverlay,
                            flash: flashing.contains(pos),
                            onTap: { vm.tapCell(pos) }
                        )
                        .equatable()
                        .id(pos)
                    }
                }
            }
        }
    }

    /// Screenshot helpers paint correct cells green; live play never does —
    /// check feedback is a transient flash, not a stored state.
    private var showCorrectOverlay: Bool {
        #if DEBUG
        vm.showCorrectOverlay
        #else
        false
        #endif
    }

    /// Wire the engine's word-complete and check-result callbacks to the
    /// flash, shake and haptics.
    private func wireFeedback() {
        vm.onCheckResult = { correct, wrongCount in
            if wrongCount > 0 {
                if reduceMotion {
                    shakeTick += 1                                  // haptic only
                } else {
                    withAnimation(.linear(duration: 0.45)) { shakeTick += 1 }
                }
                AccessibilityNotification.Announcement(
                    wrongCount == 1 ? "1 letter incorrect" : "\(wrongCount) letters incorrect"
                ).post()
            } else if !correct.isEmpty {
                AccessibilityNotification.Announcement("All checked letters correct").post()
            }
            // Brief green pulse on what checked out — shown once, not stored,
            // so repeated checking can't paint a permanent answer key.
            guard !correct.isEmpty else { return }
            let positions = Set(correct)
            withAnimation(.easeOut(duration: 0.18)) { flashing.formUnion(positions) }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(600))
                withAnimation(.easeOut(duration: 0.3)) { flashing.subtract(positions) }
            }
        }
        vm.onWordCompleted = { slot in
            let positions = slot.positions
            wordTick &+= 1
            // Confirm the solve to VoiceOver — a no-op when VoiceOver is off.
            AccessibilityNotification.Announcement("\(slot.answer.capitalized) complete").post()
            if reduceMotion {
                withAnimation(.easeOut(duration: 0.18)) { flashing.formUnion(positions) }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(480))
                    withAnimation(.easeOut(duration: 0.3)) { flashing.subtract(positions) }
                }
            } else {
                cascadeFlash(positions)
            }
        }
    }

    /// Pop the word's cells one after another along its length, each fading
    /// back out on its own — a rolling green cascade rather than a block flash.
    private func cascadeFlash(_ positions: [GridPos], perCellMillis: Int = 45) {
        for (i, pos) in positions.enumerated() {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(i * perCellMillis))
                withAnimation(.spring(duration: 0.25, bounce: 0.5)) { _ = flashing.insert(pos) }
                try? await Task.sleep(for: .milliseconds(450))
                withAnimation(.easeOut(duration: 0.3)) { _ = flashing.remove(pos) }
            }
        }
    }

    /// Diagonal sweep across the whole grid at the solve moment, played in the
    /// beat before the completion screen covers it. Cells are batched per
    /// diagonal so the sweep costs two state updates per diagonal, not per cell.
    private func celebrationWave() {
        var diagonals: [Int: Set<GridPos>] = [:]
        for r in 0..<vm.size {
            for c in 0..<vm.size where !vm.grid[r][c].isBlock {
                diagonals[r + c, default: []].insert(GridPos(row: r, col: c))
            }
        }
        for (diagonal, positions) in diagonals {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(diagonal * 40))
                withAnimation(.spring(duration: 0.25, bounce: 0.5)) { flashing.formUnion(positions) }
                try? await Task.sleep(for: .milliseconds(380))
                withAnimation(.easeOut(duration: 0.25)) { flashing.subtract(positions) }
            }
        }
    }
}

/// The rows and columns holding at least one playable cell.
struct PlayableBounds: Equatable {
    let rows: Range<Int>
    let cols: Range<Int>
}

/// Horizontal shake used to signal a failed answer check. The translation is
/// interpolated as `animatableData` advances by 1, producing a few oscillations.
/// `nonisolated`: SwiftUI may evaluate an effect on its async render thread,
/// and under the target's main-actor default a Swift 6 isolation check would
/// trap there (as `Theme.adaptive`'s colour provider did).
nonisolated private struct ShakeEffect: GeometryEffect {
    var amount: CGFloat = 5
    var shakes: CGFloat = 3
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(
            CGAffineTransform(translationX: amount * sin(animatableData * .pi * shakes), y: 0)
        )
    }
}
