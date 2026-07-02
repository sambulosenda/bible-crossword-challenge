//
//  CrosswordGridView.swift
//  Bible Crossword Challenge
//
//  Renders the square grid, sized to fit its container. Cells are value-typed
//  and Equatable so only changed cells repaint on each keystroke.
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

    var body: some View {
        GeometryReader { geo in
            let available = min(geo.size.width, geo.size.height)
            let side = floor(available / CGFloat(vm.size))
            let activeWord = vm.activeWordPositions
            let total = side * CGFloat(vm.size)

            VStack(spacing: 0) {
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
                                showError: vm.showErrors,
                                flash: flashing.contains(pos),
                                onTap: { vm.select(pos) }
                            )
                            .equatable()
                        }
                    }
                }
            }
            .frame(width: total, height: total)
            .background(CellPalette.border)
            .overlay(
                Rectangle().strokeBorder(CellPalette.border, lineWidth: 1)
            )
            .clipShape(.rect(cornerRadius: 6))
            .modifier(ShakeEffect(animatableData: CGFloat(shakeTick)))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
        .sensoryFeedback(.impact(weight: .light), trigger: wordTick)
        .sensoryFeedback(.error, trigger: shakeTick)
        .onAppear { wireFeedback() }
        .onChange(of: vm.showErrors) { _, showing in
            guard showing, vm.hasVisibleErrors else { return }
            if reduceMotion {
                shakeTick += 1                                      // haptic only
            } else {
                withAnimation(.linear(duration: 0.45)) { shakeTick += 1 }
            }
        }
        .onChange(of: vm.isComplete) { _, complete in
            guard complete, !reduceMotion else { return }
            celebrationWave()
        }
    }

    /// Wire the engine's word-complete callback to the flash + haptic.
    private func wireFeedback() {
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
