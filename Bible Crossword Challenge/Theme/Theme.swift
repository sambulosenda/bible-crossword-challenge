//
//  Theme.swift
//  Bible Crossword Challenge
//
//  Semantic colours and shared layout constants. Colours are built from system
//  materials so dark mode is supported automatically.
//

import SwiftUI

enum Theme {
    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 16
        static let l: CGFloat = 24
        static let xl: CGFloat = 32
    }

    static let cornerRadius: CGFloat = 16
    static let accent = Color.accentColor
}

enum CellPalette {
    static let block = Color(.label).opacity(0.92)
    static let empty = Color(.secondarySystemGroupedBackground)
    static let border = Color(.separator)

    static func fill(isSelected: Bool, isInWord: Bool, showError: Bool, isCorrect: Bool) -> Color {
        if isSelected { return Theme.accent.opacity(0.85) }
        if showError { return Color.red.opacity(0.28) }
        if isCorrect { return Color.green.opacity(0.18) }
        if isInWord { return Theme.accent.opacity(0.18) }
        return empty
    }

    static func textColor(isSelected: Bool) -> Color {
        isSelected ? .white : .primary
    }
}
