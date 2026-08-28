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

    /// Grids wider than this get the zoomable treatment. Every shipped daily
    /// is 15 or under and keeps the fit-to-width feel exactly as it was.
    private static let zoomThreshold = 15
    /// Zoom-mode bounds: `maxZoomSide` is a comfortable full-size touch
    /// target; the minimum is whatever side fits the whole grid on screen.
    private static let maxZoomSide: CGFloat = 44
    /// The default zoom shows readable, tappable cells rather than the whole
    /// board — the first act on a big grid is reading a clue, not surveying.
    private static let comfortableSide: CGFloat = 30

    var body: some View {
        Group {
            if vm.size > Self.zoomThreshold {
                zoomableGrid
            } else {
                fittedGrid
            }
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
        .onAppear { wireFeedback() }
        .onChange(of: vm.isComplete) { _, complete in
            guard complete, !reduceMotion else { return }
            celebrationWave()
        }
    }

    // MARK: - Fit mode (≤ 15×15, the shipped behavior)

    private var fittedGrid: some View {
        GeometryReader { geo in
            let available = min(geo.size.width, geo.size.height)
            let side = floor(available / CGFloat(vm.size))
            let total = side * CGFloat(vm.size)

            gridRows(side: side)
                .frame(width: total, height: total)
                .modifier(ShakeEffect(animatableData: CGFloat(shakeTick)))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    // MARK: - Zoom mode (Sunday Specials)

    private var zoomableGrid: some View {
        GeometryReader { geo in
            let fit = floor(min(geo.size.width, geo.size.height) / CGFloat(vm.size))
            let side = zoomSide.map { clamped($0, fit: fit) } ?? max(fit, Self.comfortableSide)
            let total = side * CGFloat(vm.size)

            ScrollViewReader { proxy in
                ScrollView([.horizontal, .vertical], showsIndicators: false) {
                    gridRows(side: side)
                        .frame(width: total, height: total)
                        .modifier(ShakeEffect(animatableData: CGFloat(shakeTick)))
                        // Centered while zoomed out smaller than the viewport;
                        // a plain ScrollView would pin it top-leading.
                        .frame(
                            width: max(total, geo.size.width),
                            height: max(total, geo.size.height)
                        )
                }
                .simultaneousGesture(magnify(fit: fit))
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

    private func gridRows(side: CGFloat) -> some View {
        let activeWord = vm.activeWordPositions

        return VStack(spacing: 0) {
            ForEach(0..<vm.size, id: \.self) { r in
                HStack(spacing: 0) {
                    ForEach(0..<vm.size, id: \.self) { c in
                        let pos = GridPos(row: r, col: c)
                        let cell = vm.grid[r][c]
                        CellView(
                            cell: cell,
                            side: side,
                            isSelected: vm.selected == pos,
                            isInWord: activeWord.contains(pos),
                            // Auto-check marks mistakes continuously; a
                            // one-shot check marks its cells until edited
                            // (that part rides on the cell itself).
                            showError: vm.autoCheck || cell.isCheckedWrong,
                            showCorrect: showCorrectOverlay,
                            flash: flashing.contains(pos),
                            onTap: { vm.select(pos) }
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

/// Horizontal shake used to signal a failed answer check. The translation is
/// interpolated as `animatableData` advances by 1, producing a few oscillations.
private struct ShakeEffect: GeometryEffect {
    var amount: CGFloat = 5
    var shakes: CGFloat = 3
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(
            CGAffineTransform(translationX: amount * sin(animatableData * .pi * shakes), y: 0)
        )
    }
}
