//
//  ClueListView.swift
//  Bible Crossword Challenge
//
//  Full Across/Down clue list presented as a sheet. Tapping a clue selects it
//  on the grid and dismisses.
//
//  This is also where a solved clue names the passage its answer comes from.
//  The clue bar and the grid deliberately don't: they are the solving surface,
//  and a reference there is a hint. Here, after the solve, the same line is a
//  reward.
//

import SwiftUI

struct ClueListView: View {
    @Bindable var vm: GameViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.analytics) private var analytics

    /// The passage a tapped reference opened. Presented from here rather than
    /// through `ReaderRouter`, whose cover hangs off the tab bar and can't come
    /// up while this sheet is — see ReaderModal.
    @State private var readerTarget: ReaderRouter.Target?

    /// Width of the clue-number gutter. Shared so the reference line below a
    /// clue starts under the clue text rather than under its number.
    private let numberColumn: CGFloat = 24

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
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
                .onAppear {
                    // Land on the clue you were working — the list can be long.
                    if let active = vm.activeSlot {
                        proxy.scrollTo(active.id, anchor: .center)
                    }
                }
                // Closing the reader returns to the clue list, so reading a
                // passage doesn't cost the player their place.
                .fullScreenCover(item: $readerTarget) { target in
                    ReaderModal(target: target)
                }
            }
        }
    }

    private func section(title: String, slots: [Slot]) -> some View {
        Section {
            ForEach(slots) { slot in
                let isActive = slot.id == vm.activeSlot?.id
                let solved = isSolved(slot)
                // Two independent targets in one row, so they sit side by side
                // rather than nested: the clue selects, the reference reads.
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Button {
                        vm.select(slot: slot)
                        dismiss()
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
                            Text("\(slot.number)")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.accent)
                                .frame(minWidth: numberColumn, alignment: .trailing)
                            Text(slot.clue)
                                .font(.body)
                                .foregroundStyle(.primary)
                            Spacer(minLength: 0)
                            if solved {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .accessibilityLabel("Solved")
                            }
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)

                    // Absent until solved, never dimmed. A greyed-out "1 Samuel
                    // 10:1" would still tell you which book the answer is in,
                    // which is a hint arriving by the back door.
                    if solved, let reference = slot.reference {
                        referenceLink(reference)
                            .padding(.leading, numberColumn + Theme.Spacing.s)
                    }
                }
                .id(slot.id)
                .listRowBackground(isActive ? Theme.accent.opacity(0.12) : nil)
                .accessibilityAddTraits(isActive ? [.isSelected] : [])
            }
        } header: {
            Text(title)
        }
    }

    /// The passage a solved answer comes from, opening the same modal reader as
    /// the Verse of the Day.
    private func referenceLink(_ reference: String) -> some View {
        Button {
            guard let target = ReaderRouter.Target(reference: reference) else { return }
            analytics.log(.scriptureOpened(reference: reference, source: "clue"))
            readerTarget = target
        } label: {
            HStack(spacing: 2) {
                Text(reference)
                Image(systemName: "chevron.forward")
                    .font(.caption2.weight(.semibold))
            }
            .font(.caption)
            .foregroundStyle(Theme.accent)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Read \(reference)")
        .accessibilityHint("Opens the passage in the reader")
    }

    private func isSolved(_ slot: Slot) -> Bool {
        slot.positions.allSatisfy { pos in
            vm.grid[pos.row][pos.col].isCorrect
        }
    }
}
