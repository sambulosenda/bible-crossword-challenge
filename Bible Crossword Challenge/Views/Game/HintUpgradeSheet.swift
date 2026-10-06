//
//  HintUpgradeSheet.swift
//  Bible Crossword Challenge
//
//  The offer a free player meets the first time in a puzzle they tap a hint
//  their daily pool can't cover.
//
//  It replaces, for that first refusal, the caption-sized chip above the grid:
//  in the 30 days to 2026-10-06 the chip fired 163 times for 56 people and was
//  tapped 5 times — it faded after ten seconds, its button was `.mini`, and it
//  sat beside "the verse and checks are still free". Of the 5 who did tap
//  through, 2 bought, so the intent is real; the surface just never asked.
//
//  Not an interruption: it only ever answers a tap on a hint the player chose.
//  It draws the word they are stuck on, sells revealing it as the trial, and on
//  a purchase the caller applies the hint straight away — the thing they paid
//  for happens at once. The free way out stays, but as its own button rather
//  than as copy beside the offer.
//

import StoreKit
import SwiftUI

/// The hint the card was raised for, as a `.sheet(item:)` value.
struct HintUpgrade: Identifiable {
    let type: HintType
    /// The word under the cursor, drawn as tiles. Nil when there is no active
    /// slot to draw.
    let word: Word?
    var id: String { type.rawValue }

    struct Word {
        /// "6 Down" — the clue's name as the clue bar says it.
        let label: String
        /// The answer, one character per cell; the tiles self-describe from it.
        let solution: [Character]
        /// What the player has in each cell so far (nil = empty).
        let entries: [Character?]
        /// The cursor's cell within the word, accented for a letter hint.
        let focus: Int?
    }
}

struct HintUpgradeSheet: View {
    let upgrade: HintUpgrade
    /// Whether the active clue has a passage behind it, so the free rung can
    /// be offered by name.
    let canUseVerse: Bool
    /// Called once, with how the card ended. The caller dismisses and, after a
    /// purchase, applies the hint; after `.verse`, opens the verse hint.
    let onFinish: (Outcome) -> Void

    enum Outcome { case purchased, verse, dismissed }

    @Environment(\.analytics) private var analytics
    @Environment(StoreService.self) private var store

    @State private var openedAt = Date()
    @State private var didTapCTA = false
    /// Set by whichever path ends the card; `onDisappear` logs a swipe when
    /// nothing did.
    @State private var exit: PaywallExit?
    @State private var working = false
    /// The card's natural height, so the sheet hugs it instead of floating it
    /// in the middle of a half-screen detent.
    @State private var contentHeight: CGFloat = 0

    private static let source = PaywallSource.hintLimitCard

    private var type: HintType { upgrade.type }
    private var product: Product? { store.yearly }
    private var trial: StoreService.IntroOffer? { product.flatMap { store.introOffer(for: $0) } }

    private var headline: String {
        switch type {
        case .letter: "Reveal this letter now"
        case .word: "Reveal this word now"
        case .puzzle: "Reveal the whole puzzle now"
        case .verse: "Unlimited hints"
        }
    }

    private var ctaTitle: String {
        if let trial { return "Try free for \(trial.duration)" }
        return "Unlock unlimited hints"
    }

    /// What follows the trial, said once. The CTA already names the free
    /// days, so repeating "Free for 7 days" here only pushed the price down a
    /// line. Without a trial, the full renewal disclosure.
    private var terms: String? {
        guard let product else { return nil }
        if trial != nil, let period = store.periodText(for: product) {
            return "Then \(product.displayPrice)\(period), renewing until cancelled."
        }
        return PremiumOfferView.commitmentText(for: product, store: store)
    }

    var body: some View {
        ScrollView {
            content
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxWidth: .infinity)
        // The sheet's own material otherwise shows around the card.
        .presentationBackground(Theme.background)
        // Fitted to the card; the system caps an over-tall detent at the
        // screen, and the scroll view takes over at accessibility sizes.
        .presentationDetents([.height(max(contentHeight, 280))])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(working)
        .purchaseNoticeAlert(store)
        .onAppear {
            openedAt = Date()
            analytics.log(.paywallOpened(source: Self.source.rawValue))
        }
        .onDisappear {
            analytics.log(.paywallDismissed(
                source: Self.source.rawValue,
                secondsOnScreen: Int(Date().timeIntervalSince(openedAt).rounded()),
                ctaTapped: didTapCTA,
                exit: exit ?? .swipe
            ))
            // A swipe never reached `finish`; the caller still needs to know.
            if exit == nil { onFinish(.dismissed) }
        }
    }

    private var content: some View {
        VStack(spacing: Theme.Spacing.l) {
            VStack(spacing: Theme.Spacing.m) {
                hero

                VStack(spacing: Theme.Spacing.s) {
                    Text(headline)
                        .font(.scripture(.title, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)

                    Text("Unlimited hints, every puzzle, every pack.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(spacing: Theme.Spacing.s) {
                // At the point two in five tappers back out of Apple's sheet:
                // the answer to "will this charge me?", above the button
                // rather than in the small print under it.
                if trial != nil {
                    Label {
                        Text("Nothing to pay today · Cancel anytime")
                            .foregroundStyle(.primary)
                    } icon: {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Theme.accent)
                    }
                    .font(.subheadline.weight(.semibold))
                }

                Button(action: buy) {
                    Group {
                        if working {
                            ProgressView().tint(Theme.onInk)
                        } else {
                            Text(ctaTitle)
                        }
                    }
                }
                .buttonStyle(.pillProminent)
                .disabled(working || product == nil)

                if let terms {
                    Text(terms)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button(canUseVerse ? "Use the verse instead" : "Not now") {
                    finish(canUseVerse ? .verse : .dismissed,
                           exit: canUseVerse ? .freeLink : .close)
                }
                .font(.subheadline.weight(.semibold))
                .tint(.secondary)
                .padding(.top, Theme.Spacing.xs)
                .disabled(working)
            }
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.top, Theme.Spacing.xl)
        .padding(.bottom, Theme.Spacing.m)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity)
    }

    /// The word they are stuck on, in the grid's own tiles — what "reveal
    /// this word" would act on, rather than a generic bulb.
    @ViewBuilder
    private var hero: some View {
        if let word = upgrade.word, !word.solution.isEmpty {
            VStack(spacing: Theme.Spacing.s) {
                MiniCrossword(
                    layout: [word.solution.map { MiniTile.blank($0) }],
                    entries: Dictionary(uniqueKeysWithValues: word.entries.enumerated().compactMap { i, c in
                        c.map { (MiniPoint(row: 0, col: i), $0) }
                    }),
                    focus: type == .letter ? word.focus.map { MiniPoint(row: 0, col: $0) } : nil,
                    animatesIn: false,
                    tileSide: Self.tileSide(for: word.solution.count)
                )
                Text(word.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        } else {
            Image(systemName: "lightbulb.max.fill")
                .font(.title.weight(.semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 56, height: 56)
                .background(Theme.accent.opacity(0.14), in: .circle)
                .accessibilityHidden(true)
        }
    }

    /// Big enough to read as the grid, small enough that a Sunday Special's
    /// fifteen-letter answer still fits a phone's width.
    private static func tileSide(for count: Int) -> CGFloat {
        switch count {
        case ...7: 36
        case ...10: 28
        default: 21
        }
    }

    private func buy() {
        guard let product else { return finish(.dismissed, exit: .noPlan) }
        didTapCTA = true
        working = true
        let planName = PremiumOfferView.planTitle(product).lowercased()
        analytics.log(.paywallCTATapped(
            plan: planName,
            source: Self.source.rawValue,
            offersTrial: trial != nil
        ))
        Task {
            let outcome = await store.purchase(product, source: Self.source.rawValue)
            working = false
            switch outcome {
            case .purchased:
                finish(.purchased, exit: .purchase)
            case .cancelled:
                // Stay: they backed out of Apple's sheet, not out of the card,
                // and the free way out is still right there.
                break
            case .failed(let reason):
                analytics.log(.purchaseFailed(plan: planName, source: Self.source.rawValue, reason: reason))
            case .pending:
                break
            }
        }
    }

    private func finish(_ outcome: Outcome, exit: PaywallExit) {
        guard self.exit == nil else { return }
        self.exit = exit
        onFinish(outcome)
    }
}
