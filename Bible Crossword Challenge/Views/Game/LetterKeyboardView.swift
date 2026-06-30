//
//  LetterKeyboardView.swift
//  Bible Crossword Challenge
//
//  Custom A–Z keypad. A dedicated keyboard avoids autocorrect/return-key issues
//  and gives precise control over crossword entry. Uses sensory feedback rather
//  than UIKit feedback generators.
//

import SwiftUI

struct LetterKeyboardView: View {
    let onLetter: (Character) -> Void
    let onDelete: () -> Void

    @State private var lastKeyTick = 0

    /// Key height grows with the user's text-size setting so large Dynamic Type
    /// glyphs aren't clipped.
    @ScaledMetric(relativeTo: .title3) private var keyHeight: CGFloat = 46

    private let rows = ["QWERTYUIOP", "ASDFGHJKL", "ZXCVBNM"]

    var body: some View {
        VStack(spacing: Theme.Spacing.s) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 6) {
                    if row.count < 10 { Spacer(minLength: 0) }
                    ForEach(Array(row), id: \.self) { letter in
                        key(for: letter)
                    }
                    if row == rows.last {
                        deleteKey
                    }
                    if row.count < 10 { Spacer(minLength: 0) }
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.s)
        .padding(.vertical, Theme.Spacing.m)
        .sensoryFeedback(.selection, trigger: lastKeyTick)
    }

    private func key(for letter: Character) -> some View {
        Button {
            lastKeyTick &+= 1
            onLetter(letter)
        } label: {
            Text(String(letter))
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: keyHeight)
                .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .accessibilityLabel(String(letter))
    }

    private var deleteKey: some View {
        Button(role: .destructive) {
            lastKeyTick &+= 1
            onDelete()
        } label: {
            Image(systemName: "delete.left")
                .font(.title3)
                .frame(maxWidth: .infinity, minHeight: keyHeight)
                .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .accessibilityLabel("Delete")
    }
}
