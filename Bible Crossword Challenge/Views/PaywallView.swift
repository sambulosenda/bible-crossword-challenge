//
//  PaywallView.swift
//  Bible Crossword Challenge
//
//  Premium upgrade screen, in the app's native language: paper canvas, serif
//  hero, surface cards, the accent for selection and an ink CTA.
//
//  Order: promise, the player's own progress, benefits, and — from pack entry
//  points only — the named packs they can't open yet, showing the content
//  withheld rather than only the content on offer. Then stacked plan cards
//  (yearly with any free trial + savings badge, monthly, and a one-time
//  lifetime unlock), then the CTA and its subtext. Purchase/restore go
//  through StoreService (StoreKit 2).
//
//  Always presented as a sheet. Pushed onto a navigation stack it collides
//  with the back button and the tab bar.
//

import SwiftUI
import SwiftData
import StoreKit

struct PaywallView: View {
    /// Where this paywall was opened from (e.g. "archive", "hint_limit").
    /// Attributed on both `paywall_opened` and `premium_purchased` so each
    /// entry point's view → purchase conversion can be compared.
    let source: String

    /// What the player just ran into, when the entry point can name it — today
    /// only the seasonal pack behind `pack_locked`. The promise for a pack that
    /// leaves in a fortnight is not the promise for the shelf as a whole.
    var subject: String? = nil

    /// The pack the player just ran into, when they came from one. Only used to
    /// sort that collection to the front of the locked-pack strip.
    ///
    /// Separate from `subject`, which is deliberately nil for evergreen packs —
    /// it exists to write a headline about a season running out, and an
    /// evergreen pack has no season to run out. The strip wants the pack in
    /// every case, so it needs its own parameter rather than a title to match on.
    var contextPackID: String? = nil

    @Environment(StoreService.self) private var store
    @Environment(\.analytics) private var analytics
    @Environment(\.puzzleProvider) private var puzzleProvider
    @Environment(\.dismiss) private var dismiss
    /// Filtered in the fetch rather than in Swift: the progress line only needs
    /// completions, and an unscoped query would materialise every record the
    /// player has ever touched to count a subset of them.
    @Query(filter: #Predicate<PuzzleRecord> { $0.isCompleted })
    private var completedRecords: [PuzzleRecord]

    @State private var selectedID = StoreService.yearlyID
    @State private var didLogOpen = false

    // Dismissal telemetry. When the sheet appeared, whether the CTA was pressed
    // during this presentation, and a once-only guard — `onDisappear` is the
    // one hook that sees every exit (✕, swipe, and the dismissal that follows
    // a purchase), but nothing stops it firing more than once per identity.
    @State private var appearedAt: Date?
    @State private var didTapCTA = false
    @State private var didLogDismiss = false

    private var selectedProduct: Product? {
        store.products.first { $0.id == selectedID }
    }

    var body: some View {
        // A real navigation bar rather than a floating overlay: the header used
        // to scroll underneath the close and restore buttons and collide with
        // them. The system bar brings its own material on scroll, and drops the
        // magic 64pt top padding the overlay needed.
        NavigationStack {
            ScrollView {
                PremiumOfferView(
                    headline: headlineText,
                    progressLine: progressLine,
                    selectedID: $selectedID,
                    showsLockedPacks: showsLockedPacks,
                    highlightedPackID: contextPackID
                )
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.top, Theme.Spacing.s)
                .padding(.bottom, Theme.Spacing.l)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
            .background(Theme.background)
            // Pinned, not scrolled. Every addition to this page pushed the CTA
            // further down; on a 667pt screen it had fallen below the fold,
            // which means scrolling to find the primary action. Anchoring it
            // also means the page above can grow later without re-checking.
            .safeAreaInset(edge: .bottom) { pinnedPurchaseBar }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .bold))
                    }
                    .tint(.secondary)
                    .accessibilityLabel("Close")
                }
                // No Restore up here any more: it lives in the pinned footer
                // with the other housekeeping links, which never scrolls away,
                // so a second copy was only competing with the close button for
                // the top of the screen.
            }
            // Opaque, and in the page's own colour: the bar is transparent by
            // default, which put the serif hero underneath the close button as
            // soon as the content scrolled.
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Theme.background, for: .navigationBar)
        }
        .onAppear {
            // Every presentation logs exactly once, whatever the entry point.
            if !didLogOpen {
                didLogOpen = true
                analytics.log(.paywallOpened(source: source))
            }
            if appearedAt == nil { appearedAt = Date() }
            // Default to the trial plan; fall back to whatever loaded.
            if selectedProduct == nil, let first = store.products.first {
                selectedID = first.id
            }
        }
        .onDisappear {
            // The other half of `paywall_opened` — see `paywallDismissed`.
            // Counted from first appearance, so a sheet that resurfaces under
            // another sheet (Apple's purchase dialog) doesn't reset the clock.
            guard !didLogDismiss, let appearedAt else { return }
            didLogDismiss = true
            analytics.log(.paywallDismissed(
                source: source,
                secondsOnScreen: Int(Date().timeIntervalSince(appearedAt).rounded()),
                ctaTapped: didTapCTA
            ))
        }
        .task {
            if store.products.isEmpty { await store.refresh() }
        }
        .onChange(of: store.products.count) { _, _ in
            if selectedProduct == nil, let first = store.products.first {
                selectedID = first.id
            }
        }
        .purchaseNoticeAlert(store)
    }

    // MARK: - Headline

    /// The entry points that get their own promise. Deliberately a failable
    /// `init(rawValue:)` rather than a match on bare strings: a source that is
    /// renamed, added, or mistyped falls through to the default line instead of
    /// leaving the largest text on the screen blank.
    private enum Entry: String {
        case hintLimit = "hint_limit"
        case completion
        case miniCompletion = "mini_completion"
        case packCompletion = "pack_completion"
        case packLocked = "pack_locked"
        case homeCard = "home_card"
        case archive
    }

    private static let defaultHeadline = PremiumCopy.promise

    /// The locked-pack strip only shows when the player just bounced off a
    /// pack — there it's evidence about the very thing they asked for. From
    /// every other entry point it was a second icon-row list stacked under the
    /// benefits, eight rows of prose standing between the promise and the
    /// price, about content the player hadn't expressed any interest in.
    private var showsLockedPacks: Bool {
        switch Entry(rawValue: source) {
        case .packLocked, .packCompletion: return true
        default: return false
        }
    }

    /// The promise, chosen by where the player came from. Someone who just hit
    /// a hint wall and someone browsing from their profile are asking different
    /// questions, and `source` is already threaded through for attribution — so
    /// the copy can follow it without any new plumbing, and `premium_purchased`
    /// already carries the same value to judge it by later.
    private var headlineText: String {
        switch Entry(rawValue: source) {
        case .hintLimit:
            return "Never stuck for long."
        case .completion:
            return solvedTally ?? Self.defaultHeadline
        case .miniCompletion:
            return "Two minutes was just the start."
        case .packCompletion:
            return "The rest of the pack is waiting."
        case .packLocked:
            // A seasonal pack states its own constraint; an evergreen one has
            // none to state, and inventing urgency for it would be a lie.
            if let subject { return "\(subject) is only here this season." }
            return "The collections are waiting."
        case .homeCard:
            return "Make it part of the morning."
        case .archive:
            return PremiumCopy.archive
        // `profile` and anything added later. A player who hasn't hit a wall
        // needs telling what the app is for, not what it withholds. (Onboarding
        // never arrives here — its premium page is part of `OnboardingView`.)
        case nil:
            return Self.defaultHeadline
        }
    }

    /// "12 down. 165 more waiting." — the player's own two numbers, on the one
    /// screen where they've just finished something and the next one is the
    /// question. "Waiting", not "to go": the remainder is supply, and "to go"
    /// framed it as a debt — 165 puzzles owed rather than 165 on the shelf.
    private var solvedTally: String? {
        let solved = completedRecords.count
        let remaining = puzzleProvider.totalPuzzleCount - solved
        guard solved > 0, remaining > 0 else { return nil }
        return "\(solved) down. \(remaining) more waiting."
    }

    /// The player's own gap, stated as a fact and nothing more. A personal
    /// number is a stronger reason to act now than a generic claim, and unlike
    /// social proof it's something the app can honestly know.
    ///
    /// Hidden at zero: "You've solved 0" is a discouragement, not a nudge.
    private var progressLine: String? {
        // Suppressed when the headline is already the tally — the two lines
        // carry identical numbers and reading them in sequence stutters.
        if Entry(rawValue: source) == .completion, solvedTally != nil { return nil }
        let solved = completedRecords.count
        guard solved > 0 else { return nil }
        return "You've solved \(solved) of \(puzzleProvider.totalPuzzleCount)."
    }

    // MARK: - Purchase

    /// The purchase bar as it sits in the bottom safe area: the CTA, the terms
    /// it commits you to, and the housekeeping links, in that order.
    ///
    /// The legal row is deliberately *outside* the "is there anything to buy"
    /// check. It carries Restore, and the state where that matters most is the
    /// one where products failed to load — a player who has already paid, on a
    /// bad connection, looking at a retry card. Gating it on a successful
    /// product fetch would take Restore away from exactly the person who needs
    /// it, and it is the only copy now that the toolbar button is gone.
    private var pinnedPurchaseBar: some View {
        VStack(spacing: Theme.Spacing.s) {
            if !store.isPremium && !store.products.isEmpty {
                purchaseSection
            }
            legal
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.top, Theme.Spacing.m)
        .padding(.bottom, Theme.Spacing.s)
        // The fill matches the canvas, so the bar reads continuous with
        // the page below it without needing to bleed into the safe area.
        .background(Theme.background)
        .overlay(alignment: .top) {
            // A hairline, because content scrolls underneath and the
            // bar needs an edge to read as a separate layer.
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 1)
        }
    }

    private var purchaseSection: some View {
        VStack(spacing: Theme.Spacing.m) {
            Button {
                guard let product = selectedProduct else { return }
                didTapCTA = true
                Task {
                    let plan = PremiumOfferView.planTitle(product).lowercased()
                    // Before the sheet, not after: this is the only record that
                    // survives a player who backs out of Apple's dialog, which
                    // reports nothing at all.
                    analytics.log(.paywallCTATapped(
                        plan: plan,
                        source: source,
                        offersTrial: store.introOfferText(for: product) != nil
                    ))
                    // `premium_purchased` is emitted by StoreService, which sees
                    // every grant rather than only the ones that finish inside
                    // this call. Logging it here as well would double-count.
                    switch await store.purchase(product, source: source) {
                    case .purchased:
                        break
                    case .failed(let reason):
                        analytics.log(.purchaseFailed(plan: plan, source: source, reason: reason))
                    case .cancelled, .pending:
                        break
                    }
                }
            } label: {
                Group {
                    if store.purchaseInFlight {
                        ProgressView().tint(Theme.onInk)
                    } else {
                        Text(ctaTitle)
                    }
                }
            }
            .buttonStyle(.pillProminent)
            .disabled(store.purchaseInFlight || selectedProduct == nil)

            // Restate what happens right at the commit point — purchase anxiety
            // peaks here, and the trial/price detail otherwise only lives in the
            // plan row above.
            if let subtext = ctaSubtext {
                Text(subtext)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.top, Theme.Spacing.s)
    }

    /// Both shared with onboarding's premium page — see
    /// `PremiumOfferView.ctaTitle` and `commitmentText`.
    private var ctaTitle: String {
        PremiumOfferView.ctaTitle(
            for: selectedProduct,
            store: store,
            puzzleCount: puzzleProvider.totalPuzzleCount
        )
    }

    private var ctaSubtext: String? {
        PremiumOfferView.commitmentText(for: selectedProduct, store: store)
    }

    // MARK: - Legal

    /// Links only. The auto-renewal disclosure lives in `ctaSubtext`, right at
    /// the commit point where it carries the actual price — repeating it here
    /// as a vaguer sentence just made the footer say the same thing twice.
    private var legal: some View {
        HStack(spacing: Theme.Spacing.m) {
            Link("Terms of Use", destination: LegalLinks.terms)
            Link("Privacy Policy", destination: LegalLinks.privacy)
            // The only Restore on the screen since the toolbar copy went. A
            // player who can't find it reads the app as having charged them
            // twice, so it stays pinned rather than living in scrolled content.
            Button("Restore") { Task { await store.restore() } }
                .disabled(store.purchaseInFlight)
        }
        .font(.caption)
        .foregroundStyle(Theme.accent)
    }
}

extension View {
    /// Presents the store's pending `PurchaseNotice` (purchase failure, Ask to
    /// Buy pending, restore outcome) as an alert and clears it on dismiss.
    /// Attach to every screen that can start a purchase or restore.
    func purchaseNoticeAlert(_ store: StoreService) -> some View {
        alert(
            store.purchaseNotice?.title ?? "",
            isPresented: Binding(
                get: { store.purchaseNotice != nil },
                set: { if !$0 { store.purchaseNotice = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.purchaseNotice?.message ?? "")
        }
    }
}

/// Premium headlines that more than one screen makes.
///
/// Each of these was written twice before, in the two places that say it, and
/// the copies drifted — the app ended up making four different promises for one
/// product. A player who sees two of them reads two offers.
enum PremiumCopy {
    /// The promise itself, in the app's own register: what you'd be doing with
    /// the library rather than what's in it. Said by onboarding's premium page
    /// and by the paywall wherever the entry point has nothing more specific.
    /// "More", because as a bare noun phrase the line read as a description of
    /// the app rather than of what Premium adds — and every reader already has
    /// the app.
    static let promise = "More time in the Word, one clue at a time."

    /// The archive's promise. Shared because the Library locked state and the
    /// paywall it opens (`source: "archive"`) are one tap apart — a different
    /// headline on each made a single journey look like two pitches.
    static let archive = "Every puzzle, back to the first."

    /// The trial CTA, e.g. "Start 3-day free trial" — never a bare "Start Free
    /// Trial". The length is the most persuasive part of the offer and the
    /// store already hands it over, so spending the button on a generic phrase
    /// throws away the one number that closes.
    ///
    /// Pass `StoreService.introOfferText(for:)` straight in; the duration comes
    /// from StoreKit rather than any string written here, so a change to the
    /// configured offer can't leave the copy claiming the old length.
    static func trialCTA(_ trial: String) -> String { "Start \(trial)" }

    /// Said under the headline when there is no introductory offer — because
    /// the player has already used theirs, or none is configured. Without it
    /// the no-trial path has nothing above the fold about what costs nothing,
    /// and the free tier is the reason the ask can stay soft.
    static let freeDailyReassurance = "The daily puzzle stays free either way."
}

/// A premium benefit: one line, one claim.
///
/// Each row used to carry a bold title *and* an explanatory line beneath it, so
/// that a row could be both specific and scannable. In practice the details
/// were the least-read text on the busiest screen in the app: three rows of two
/// lines each, both of which wrapped, made nine lines of prose standing between
/// the promise and the price.
///
/// They also earned very little. "No hint limits" was followed by "Every hint
/// on every puzzle" — the same sentence twice. The other two details carried
/// exactly one fact each that the title didn't, and both were facts the title
/// could hold: a count, and replay. So the counts moved up and replay became
/// its own row, which is cheaper than a wrapped line and reads at a glance.
///
/// Four short rows, not three long ones. The list is now skimmable in about the
/// time it takes to decide whether to keep reading, which is all the time it
/// actually gets.
struct PremiumBenefit: Identifiable {
    let icon: String
    let title: String
    var id: String { title }

    /// The promise, written once for both places that make it.
    ///
    /// Onboarding's premium page and the paywall are the same offer at two
    /// moments, and while each kept its own copy they drifted: the paywall was
    /// rewritten to three outcome-led rows while onboarding still advertised
    /// four, including a "No ads, ever" the app can't really honour and a
    /// "whole library" that repeated the row above it. A player who saw both
    /// was reading two different products.
    ///
    /// Counts are passed in from the bundle rather than written as "100+" or
    /// "four", so no claim here can go stale as puzzles and packs are added.
    ///
    /// The first row says "the whole library" rather than "all N puzzles,
    /// unlocked" or the old "not just today's". "Unlocked" described a state
    /// the reader was not in — it invited them to check, find today's puzzle
    /// playable, and discount the other two rows with it. "Not just today's"
    /// fixed that but spent the list's opening words on what free lacks; the
    /// library is a claim about the shelf, not the reader's state, so a daily
    /// player can't catch it out either — and it stays affirmative. The row
    /// still doesn't reach for packs, which the fourth row owns: one row for
    /// the archive, one for replay, one for hints, one for packs.
    ///
    /// Hint limits get their own row rather than sharing one with ads: they're
    /// the most-hit paywall trigger in the app, and pairing the strongest
    /// reason to subscribe with the weakest one buried it. "No ads" is gone
    /// entirely, and so is the ad scaffold behind it: the app serves no
    /// advertising, so there is nothing for Premium to remove. Add the row
    /// back only alongside a real ad integration.
    static func all(puzzleCount: Int, packCount: Int) -> [PremiumBenefit] {
        [
            PremiumBenefit(
                icon: "square.grid.3x3.fill",
                // No "all" before the count: with it the row wraps on a 402pt
                // screen, and the break landed between "all" and its number.
                title: "The whole library — \(puzzleCount) puzzles"
            ),
            PremiumBenefit(
                icon: "arrow.clockwise",
                title: "Replay any puzzle, any time"
            ),
            PremiumBenefit(
                icon: "lightbulb.fill",
                // What the lifted limit means, not the limit: "No hint limits"
                // was the list's second negation, and the reader it matters to
                // is mid-frustration — say the outcome they want instead.
                title: "Hints whenever you need them"
            ),
            PremiumBenefit(
                icon: "rectangle.stack.fill",
                title: "All \(packCount) packs, and every new one"
            ),
        ]
    }
}

/// External legal links shown on the paywall. Terms uses Apple's standard EULA.
enum LegalLinks {
    static let terms = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    static let privacy = URL(string: "https://biblecrosswordchallenge.com/privacy.html")!
}
