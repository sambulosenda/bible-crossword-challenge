//
//  ClueBarView.swift
//  Bible Crossword Challenge
//
//  Shows the active clue above the keyboard with previous/next navigation.
//

import SwiftUI

struct ClueBarView: View {
    @Bindable var vm: GameViewModel

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            Button {
                vm.advanceClue(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.headline)
            }
            .accessibilityLabel("Previous clue")

            VStack(alignment: .leading, spacing: 2) {
                if let slot = vm.activeSlot {
                    Text("\(slot.number) \(slot.direction.label)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                    Text(slot.clue)
                        .font(.callout)
                        .lineLimit(2)
                } else {
                    Text("Select a cell to begin")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                vm.advanceClue(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.headline)
            }
            .accessibilityLabel("Next clue")
        }
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, Theme.Spacing.s)
        .background(Color(.secondarySystemBackground))
    }
}
