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
        HStack(spacing: Theme.Spacing.s) {
            Button {
                vm.advanceClue(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.headline)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .accessibilityLabel("Previous clue")

            Button {
                vm.toggleDirection()
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    if let slot = vm.activeSlot {
                        Text("\(slot.number) \(slot.direction.label)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                        Text(slot.clue)
                            .font(.callout)
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                    } else {
                        Text("Select a cell to begin")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(clueAccessibilityLabel)
            .accessibilityHint("Switches between across and down")

            Button {
                vm.advanceClue(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.headline)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .accessibilityLabel("Next clue")
        }
        .padding(.horizontal, Theme.Spacing.xs)
        .padding(.vertical, Theme.Spacing.xs)
        .background(Color(.secondarySystemBackground))
        .overlay(alignment: .bottom) { progressStrip }
    }

    /// Fraction of playable cells filled. Deliberately counts *filled*, not
    /// *correct*, so the bar can't be used as a free answer checker.
    private var progress: Double {
        let total = vm.totalPlayableCount
        guard total > 0 else { return 0 }
        return Double(vm.filledPlayableCount) / Double(total)
    }

    /// Thin strip along the bar's bottom edge that fills as the grid does,
    /// turning green at the solve.
    private var progressStrip: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(Color(.tertiarySystemFill))
                Rectangle()
                    .fill(vm.isComplete ? Color.green : Theme.accent)
                    .frame(width: geo.size.width * progress)
            }
        }
        .frame(height: 3)
        .animation(.smooth(duration: 0.35), value: progress)
        .accessibilityElement()
        .accessibilityLabel("Puzzle progress")
        .accessibilityValue("\(Int((progress * 100).rounded())) percent")
    }

    private var clueAccessibilityLabel: String {
        guard let slot = vm.activeSlot else { return "Select a cell to begin" }
        return "Clue \(slot.number) \(slot.direction.label): \(slot.clue)"
    }
}
