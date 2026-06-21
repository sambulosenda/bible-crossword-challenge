//
//  ClueListView.swift
//  Bible Crossword Challenge
//
//  Full Across/Down clue list presented as a sheet. Tapping a clue selects it
//  on the grid and dismisses.
//

import SwiftUI

struct ClueListView: View {
    @Bindable var vm: GameViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                section(title: "Across", slots: vm.acrossSlots)
                section(title: "Down", slots: vm.downSlots)
            }
            .navigationTitle("Clues")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func section(title: String, slots: [Slot]) -> some View {
        Section {
            ForEach(slots) { slot in
                Button {
                    vm.select(slot: slot)
                    dismiss()
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
                        Text("\(slot.number)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                            .frame(minWidth: 24, alignment: .trailing)
                        Text(slot.clue)
                            .font(.body)
                            .foregroundStyle(.primary)
                        Spacer(minLength: 0)
                        if isSolved(slot) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .accessibilityLabel("Solved")
                        }
                    }
                }
            }
        } header: {
            Text(title)
        }
    }

    private func isSolved(_ slot: Slot) -> Bool {
        slot.positions.allSatisfy { pos in
            vm.grid[pos.row][pos.col].isCorrect
        }
    }
}
