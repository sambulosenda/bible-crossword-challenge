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
    }

    /// Wire the engine's word-complete callback to the flash + haptic.
    private func wireFeedback() {
        vm.onWordCompleted = { positions in
            wordTick &+= 1
            withAnimation(.easeOut(duration: 0.18)) { flashing.formUnion(positions) }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(480))
                withAnimation(.easeOut(duration: 0.3)) { flashing.subtract(positions) }
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
