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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
