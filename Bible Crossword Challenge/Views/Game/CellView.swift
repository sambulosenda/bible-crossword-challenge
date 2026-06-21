//
//  CellView.swift
//  Bible Crossword Challenge
//
//  A single crossword cell. Equatable so SwiftUI skips redrawing cells whose
//  visual inputs are unchanged — important for keystroke latency on large grids.
//

import SwiftUI

struct CellView: View, Equatable {
    let cell: CellState
    let side: CGFloat
    let isSelected: Bool
    let isInWord: Bool
    let showError: Bool
    let onTap: () -> Void

    static func == (lhs: CellView, rhs: CellView) -> Bool {
        lhs.cell == rhs.cell
            && lhs.side == rhs.side
            && lhs.isSelected == rhs.isSelected
            && lhs.isInWord == rhs.isInWord
            && lhs.showError == rhs.showError
    }

    private var errorVisible: Bool {
        showError && cell.entry != nil && !cell.isCorrect
    }

    private var correctVisible: Bool {
        showError && cell.entry != nil && cell.isCorrect
    }

    var body: some View {
        if cell.isBlock {
            Rectangle()
                .fill(CellPalette.block)
                .frame(width: side, height: side)
                .accessibilityHidden(true)
        } else {
            Button(action: onTap) {
                ZStack {
                    Rectangle()
                        .fill(CellPalette.fill(
                            isSelected: isSelected,
                            isInWord: isInWord,
                            showError: errorVisible,
                            isCorrect: correctVisible
                        ))

                    if let number = cell.number {
                        Text("\(number)")
                            .font(.system(size: side * 0.26, weight: .medium))
                            .foregroundStyle(isSelected ? Color.white.opacity(0.9) : .secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .padding(.leading, side * 0.07)
                            .padding(.top, side * 0.04)
                    }

                    if let entry = cell.entry {
                        Text(String(entry))
                            .font(.system(size: side * 0.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(CellPalette.textColor(isSelected: isSelected))
                    }
                }
                .frame(width: side, height: side)
                .overlay(
                    Rectangle().strokeBorder(CellPalette.border, lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        }
    }

    private var accessibilityLabel: String {
        let base = "Row \(cell.pos.row + 1), Column \(cell.pos.col + 1)"
        if let entry = cell.entry {
            return "\(base), \(String(entry))"
        }
        return "\(base), empty"
    }
}
