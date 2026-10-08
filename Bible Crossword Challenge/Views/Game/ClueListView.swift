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
    /// True when the list is the iPad game screen's always-visible side panel
    /// rather than a sheet: no navigation chrome, a tapped clue keeps the
    /// panel up, the list follows the active clue, and the reader opens as a
    /// sheet — a full-screen cover would detach the grid from its window,
    /// which pauses the clock and logs an abandon for what is just reading.
    var embedded = false
    /// Where the standing panel puts a tapped reference. The game view owns
    /// and presents it: the panel is torn down when iPhone Duo folds, and a
    /// sheet hung off it closed with it, mid-passage.
    var standingReaderTarget: Binding<ReaderRouter.Target?>?
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
        if embedded {
            standingList
        } else {
            NavigationStack {
                sheetList
                    .navigationTitle("Clues")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { dismiss() }
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

    private var sheetList: some View {
        ScrollViewReader { proxy in
            List {
                section(title: "Across", slots: vm.acrossSlots)
                section(title: "Down", slots: vm.downSlots)
            }
            .onAppear {
                // Land on the clue you were working — the list can be long.
                if let active = vm.activeSlot {
                    proxy.scrollTo(active.id, anchor: .center)
                }
            }
        }
    }

    /// The standing panel: the same rows, as two cards in a plain scroll view.
    ///
    /// With the clue text gone from the clue bar beside it, this list is the
    /// only place the active clue is written, so it has to stay in view. As a
    /// `List` it didn't: on iPhone Duo open the panel's height settles over
    /// several layout passes (logged 0 → 255 → 669 → 313pt), and a `scrollTo`
    /// that ran during the 669pt pass found everything fitting, stayed at the
    /// top, and left the active Down clue under the fold once the panel shrank.
    /// So the follow runs again whenever the visible height changes, and the
    /// rows are a plain stack, laid out in full, so `scrollTo` knows exactly
    /// where every row is.
    private var standingList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    standingSection(title: "Across", slots: vm.acrossSlots)
                    standingSection(title: "Down", slots: vm.downSlots)
                }
                .padding(.horizontal, Theme.Spacing.m)
                .padding(.bottom, Theme.Spacing.s)
            }
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.containerSize.height
            } action: { _, _ in
                centreActive(proxy, animated: false)
            }
            // The panel follows play: typing to a word's end or tapping the
            // grid moves the active clue, and the panel keeps it in view.
            .onChange(of: vm.activeSlot?.id, initial: true) { _, _ in
                centreActive(proxy, animated: true)
            }
        }
        .background(Theme.background)
    }

    private func centreActive(_ proxy: ScrollViewProxy, animated: Bool) {
        guard let id = vm.activeSlot?.id else { return }
        if animated {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(id, anchor: .center)
            }
        } else {
            proxy.scrollTo(id, anchor: .center)
        }
    }

    private func standingSection(title: String, slots: [Slot]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.leading, Theme.Spacing.m)
                .padding(.top, Theme.Spacing.m)
                .accessibilityAddTraits(.isHeader)
            CardGroup(dividerInset: Theme.Spacing.m + numberColumn + Theme.Spacing.s) {
                ForEach(slots) { slot in
                    let isActive = slot.id == vm.activeSlot?.id
                    row(slot)
                        .padding(.horizontal, Theme.Spacing.m)
                        .padding(.vertical, 12)
                        .background(isActive ? Theme.accent.opacity(0.12) : .clear)
                        .id(slot.id)
                        .accessibilityAddTraits(isActive ? [.isSelected] : [])
                }
            }
            // The active row's tint stops at the card's corners.
            .clipShape(.rect(cornerRadius: Theme.cornerRadius, style: .continuous))
        }
    }

    private func section(title: String, slots: [Slot]) -> some View {
        Section {
            ForEach(slots) { slot in
                let isActive = slot.id == vm.activeSlot?.id
                row(slot)
                    .id(slot.id)
                    .listRowBackground(isActive ? Theme.accent.opacity(0.12) : nil)
                    .accessibilityAddTraits(isActive ? [.isSelected] : [])
            }
        } header: {
            Text(title)
        }
    }

    /// One clue: the number, the clue, and once solved the passage it is from.
    private func row(_ slot: Slot) -> some View {
        let solved = isSolved(slot)
        // Two independent targets in one row, so they sit side by side
        // rather than nested: the clue selects, the reference reads.
        return VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Button {
                vm.select(slot: slot)
                if !embedded { dismiss() }
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
    }

    /// The passage a solved answer comes from, opening the same modal reader as
    /// the Verse of the Day.
    private func referenceLink(_ reference: String) -> some View {
        Button {
            guard let target = ReaderRouter.Target(reference: reference, source: "clue") else { return }
            analytics.log(.scriptureOpened(reference: reference, source: "clue"))
            if let standingReaderTarget {
                standingReaderTarget.wrappedValue = target
            } else {
                readerTarget = target
            }
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
