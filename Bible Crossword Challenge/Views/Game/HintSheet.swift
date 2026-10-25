//
//  HintSheet.swift
//  Bible Crossword Challenge
//
//  The hints, as a sheet over the grid (design canvas, 2026-10-24).
//
//  They were the first section of the toolbar's one Menu, beside the checks
//  and two settings toggles. A menu row has a title and one grey line, so the
//  price and the reason behind it shared that line, and the day's pool sat in
//  a section header. The sheet names the clue it acts on, prices each rung on
//  its own trailing edge and states the pool once, with the way past it.
//
//  Checks stay in the More menu: they judge the grid without giving anything
//  away, which is play rather than aid.
//

import SwiftUI

/// What a rung costs this player right now, as its row's trailing edge says it.
enum HintPrice: Equatable {
    /// Spends one of today's free hints — the accented chip.
    case freeHint
    /// Costs nothing: the verse always, every rung in the learning window.
    case free
    case hints(Int)
    /// More than a day's pool will ever cover.
    case premium
    /// The pool covers it, just not what's left of today's.
    case backTomorrow
    /// Premium: unmetered, nothing to price.
    case included
}

struct HintSheet: View {
    /// The clue under the cursor.
    struct Clue {
        /// "12 Across" — as the clue bar names it.
        let label: String
        let text: String
        let length: Int
        /// The passage behind the answer. Nil drops the verse row: most clues
        /// don't have one yet, and a dimmed row would advertise a hint they
        /// can't offer.
        let reference: String?
    }

    enum Choice { case letter, word, verse, premium }

    /// Nil only with no active clue, when the header drops its second line.
    let clue: Clue?
    let price: (HintType) -> HintPrice
    /// "1 free hint today". Nil for Premium, which has no pool to state.
    let quota: String?
    /// Whether the footer carries the way past the pool — not in the learning
    /// window, where nothing is metered yet.
    let offersPremium: Bool
    /// Called once, with the row tapped. The caller dismisses and acts once
    /// the sheet has gone, so a reveal lands on a grid the player can see.
    let onChoose: (Choice) -> Void

    @Environment(\.dismiss) private var dismiss

    /// The system's own sheet (2026-10-25): a navigation bar with the system
    /// close button, an inset-grouped list, the clue as the section's header
    /// and the pool as its footer, on the sheet's own background — Liquid
    /// Glass on iOS 26. It was hand-dressed on the app's paper with its own
    /// header and ✕, which turned the glass off and made a system sheet look
    /// like a custom one.
    var body: some View {
        NavigationStack {
            List {
                Section {
                    row(.letter, symbol: "character", title: "Reveal a letter",
                        detail: "Fills the selected square")
                    row(.word, symbol: "textformat.abc", title: "Reveal the word",
                        detail: clue.map { "Fills all \($0.length) squares" } ?? "Fills the whole word")
                    if let reference = clue?.reference {
                        row(.verse, symbol: "book", title: "Read the verse", detail: reference)
                    }
                } header: {
                    if let clue {
                        Text("\(clue.label) · \(clue.text)")
                            .textCase(nil)
                    }
                } footer: {
                    footer
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Hint")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    closeButton
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private var closeButton: some View {
        if #available(iOS 26.0, *) {
            Button(role: .close) { dismiss() }
        } else {
            Button("Close") { dismiss() }
        }
    }

    private func row(_ choice: Choice, symbol: String, title: String, detail: String) -> some View {
        Button {
            onChoose(choice)
        } label: {
            HStack(spacing: Theme.Spacing.m) {
                // Absolute colours: inside a list's button, `.primary` and
                // `.secondary` resolve against the button's tint, and every
                // row read blue.
                Image(systemName: symbol)
                    .font(.body)
                    .foregroundStyle(Color.secondary)
                    .frame(width: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(Color.primary)
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(Color.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Theme.Spacing.s)
                priceTag(price(choice.hintType))
            }
            .contentShape(.rect)
        }
    }

    @ViewBuilder
    private func priceTag(_ price: HintPrice) -> some View {
        switch price {
        case .freeHint:
            Text("Free")
                .font(.footnote.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(Theme.accent, in: .capsule)
        case .free:
            quietTag(Text("Free"))
        case .hints(let count):
            quietTag(Text(count == 1 ? "1 hint" : "\(count) hints"))
        case .premium:
            quietTag(Text("\(Image(systemName: "lock.fill")) Premium"))
        case .backTomorrow:
            quietTag(Text("Back tomorrow"))
        case .included:
            EmptyView()
        }
    }

    private func quietTag(_ text: Text) -> some View {
        text
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Color.secondary)
            .lineLimit(1)
            .fixedSize()
    }

    /// The pool, said once, and the way past it, as the section's footer.
    @ViewBuilder
    private var footer: some View {
        if quota != nil || offersPremium {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                quotaLine
                premiumLink
            }
        }
    }

    @ViewBuilder
    private var quotaLine: some View {
        if let quota {
            Text(quota)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var premiumLink: some View {
        if offersPremium {
            Button("Unlimited with Premium") {
                onChoose(.premium)
            }
            .buttonStyle(.borderless)
            .tint(Theme.accent)
            .accessibilityHint("Opens Premium upgrade options")
        }
    }
}

private extension HintSheet.Choice {
    var hintType: HintType {
        switch self {
        case .letter: .letter
        case .word: .word
        // Never priced: the footer link has no row.
        case .verse, .premium: .verse
        }
    }
}

#Preview {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            HintSheet(
                clue: .init(label: "12 Across", text: "Son of Jesse who became king of Israel",
                            length: 5, reference: "1 Samuel 16:13"),
                price: { type in
                    switch type {
                    case .letter: .freeHint
                    case .word, .puzzle: .premium
                    case .verse: .free
                    }
                },
                quota: "1 free hint today",
                offersPremium: true,
                onChoose: { _ in }
            )
        }
}
