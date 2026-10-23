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
    /// Where this paywall was opened from. Attributed on both `paywall_opened`
    /// and `premium_purchased` so each entry point's view → purchase conversion
    /// can be compared, and it chooses the promise at the top of the screen.
    ///
    /// A `PaywallSource` rather than the string it used to be: the headline
    /// switch was failable, and four live entry points had quietly fallen
    /// through it to the generic promise. See `PaywallSource`.
    let source: PaywallSource

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

    /// The plan to open on, when the entry point knows which one the player
    /// already chose — today only the trial re-offer, which puts them back on
    /// the plan they backed out of rather than making them pick it again.
    var initialPlanID: String? = nil

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
    /// Set by the ✕ before it dismisses. Anything else that ends the
    /// presentation — a pull-down, or the parent taking the sheet away —
    /// reaches `onDisappear` with this still nil and is logged as `swipe`.
    @State private var exitReason: PaywallExit?

    private var selectedProduct: Product? {
        store.products.first { $0.id == selectedID }
    }

    var body: some View {
        // A real navigation bar rather than a floating overlay: the header used
        // to scroll underneath the close and restore buttons and collide with
        // them. The system bar brings its own material on scroll, and drops the
        // magic 64pt top padding the overlay needed.
        NavigationStack {
            // The whole offer when it fits above the pinned bar; without the
            // tiles, in a scroll view, when it doesn't. `ViewThatFits` decides
            // on every layout pass, so there is nothing to measure, time or
            // latch — an earlier version did, and lost a race with the sheet's
            // own first layout (a 292pt container on a Pro Max), hiding the
            // tiles on phones they fit on. On most phones the tiles don't fit
            // here, and the price outranks the decoration.
            //
            // Both sizes sit on the bottom edge. Top-aligned, every point the
            // page didn't need pooled between the trial timeline and the
            // pinned button, so the plans and the button that buys them read
            // as two separate things. The spare room goes above the headline.
            ViewThatFits(in: .vertical) {
                offer(compact: false)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                offer(compact: true, keepsSmallHero: true)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                ScrollView {
                    offer(compact: true)
                }
                // Content shorter than the viewport rests on the bottom; the
                // scroll still opens at the top when it's taller.
                .defaultScrollAnchor(.bottom, for: .alignment)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Theme.background)
            // Pinned, not scrolled. Every addition to this page pushed the CTA
            // further down; on a 667pt screen it had fallen below the fold,
            // which means scrolling to find the primary action. Anchoring it
            // also means the page above can grow later without re-checking.
            .modifier(PinnedBar { pinnedPurchaseBar })
            .toolbar {
                // Trailing, like every other ✕ in the app. Leading is where a
                // sheet's Cancel lives; this is a dismiss, not a cancel.
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        exitReason = .close
                        dismiss()
                    } label: {
                        Label("Close", systemImage: "xmark")
                            .font(.system(size: 15, weight: .bold))
                    }
                    .tint(.secondary)
                }
                // No Restore up here any more: it lives in the pinned footer
                // with the other housekeeping links, which never scrolls away,
                // so a second copy was only competing with the close button for
                // the top of the screen.
            }
            .modifier(LegacyOpaqueNavigationBar())
        }
        .onAppear {
            // Every presentation logs exactly once, whatever the entry point.
            if !didLogOpen {
                didLogOpen = true
                analytics.log(.paywallOpened(source: source.rawValue))
            }
            if appearedAt == nil { appearedAt = Date() }
            if let initialPlanID { selectedID = initialPlanID }
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
                source: source.rawValue,
                secondsOnScreen: Int(Date().timeIntervalSince(appearedAt).rounded()),
                ctaTapped: didTapCTA,
                exit: exitReason ?? .swipe
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

    /// The offer, at the size `body` chose for it.
    private func offer(compact: Bool, keepsSmallHero: Bool = false) -> some View {
        PremiumOfferView(
            headline: headlineText,
            progressLine: progressLine,
            selectedID: $selectedID,
            showsLockedPacks: source.showsLockedPacks,
            highlightedPackID: contextPackID,
            // The pinned bar's terms line already states the trial, the
            // renewal and cancelling.
            compact: compact,
            keepsSmallHero: keepsSmallHero
        )
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.top, Theme.Spacing.s)
        .padding(.bottom, Theme.Spacing.l)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Headline

    /// The promise, chosen by where the player came from — and refined here in
    /// the two cases where this screen knows something `PaywallSource` can't.
    ///
    /// Everything else lives on the type, exhaustively, so an entry point added
    /// later cannot reach the screen without a line of its own. That is exactly
    /// what went wrong before: the match was a failable `init(rawValue:)`, and
    /// `memory_verse_limit`, `journey`, `quest_locked` and `read_chip` all fell
    /// through it to the standing promise without a word in any log.
    private var headlineText: String {
        switch source {
        case .packLocked:
            // A seasonal pack states its own constraint; an evergreen one has
            // none to state, and inventing urgency for it would be a lie.
            if let subject { return "\(subject) is only here this season." }
            return source.headline
        case .trialAbandon:
            // Names the thing they were one tap from, in the store's own words
            // for its length. A player whose trial has since been used (or a
            // plan that lost its offer) gets the standing promise.
            if let product = selectedProduct, let offer = store.introOffer(for: product) {
                return "Your \(offer.trialText) is still waiting."
            }
            return source.headline
        default:
            return source.headline
        }
    }

    /// The player's own gap, stated as a fact and nothing more. A personal
    /// number is a stronger reason to act now than a generic claim, and unlike
    /// social proof it's something the app can honestly know.
    ///
    /// Hidden at zero: "You've solved 0" is a discouragement, not a nudge.
    private var progressLine: String? {
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
        // Capped like the system's own bars: uncapped, the largest sizes grew
        // this pinned bar to half the sheet and left the offer it pays for a
        // sliver to scroll in. The scrolling content above stays uncapped.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .modifier(LegacyBarEdge())
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
                        source: source.rawValue,
                        offersTrial: store.introOfferText(for: product) != nil
                    ))
                    // `premium_purchased` is emitted by StoreService, which sees
                    // every grant rather than only the ones that finish inside
                    // this call. Logging it here as well would double-count.
                    switch await store.purchase(product, source: source.rawValue) {
                    case .purchased:
                        break
                    case .failed(let reason):
                        analytics.log(.purchaseFailed(plan: plan, source: source.rawValue, reason: reason))
                    case .cancelled, .pending:
                        break
                    }
                }
            } label: {
                Group {
                    if store.purchaseInFlight {
                        ProgressView().tint(Theme.onInk)
                    } else {
                        // Wraps rather than truncates: at accessibility sizes
                        // the label was cut to "Start 7-day free t…" on the
                        // one button that says what you're agreeing to.
                        Text(ctaTitle)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
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
/// The offer's button and its terms, as every card that sells Premium draws
/// them: a full-width accent capsule naming the trial, and the price under it.
/// Accent, not the ink pill — ink is the app's "play" (Continue, Resume), and
/// an offer in the same dress read as one more step in the game. A label, not
/// a Button: each card is itself the button that opens the paywall.
struct PremiumOfferCTA: View {
    @Environment(StoreService.self) private var store

    var body: some View {
        VStack(spacing: Theme.Spacing.s) {
            Text(PremiumCopy.cardCTA(store))
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Theme.accent, in: .capsule)
            // The price, said up front: a trial button that hides what
            // follows it is the button people don't trust.
            if let terms = PremiumCopy.terms(store) {
                Text(terms)
                    .font(.caption)
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
                    .multilineTextAlignment(.center)
            }
        }
    }
}

enum PremiumCopy {
    /// "Then £9.99 a year. Cancel anytime." under a trial; the yearly price
    /// alone without one; nil until the products load.
    static func terms(_ store: StoreService) -> String? {
        guard let yearly = store.yearly else { return nil }
        guard store.introOffer(for: yearly) != nil else {
            return "\(store.yearlyPriceText) a year. Cancel anytime."
        }
        return "Then \(store.yearlyPriceText) a year. Cancel anytime."
    }

    /// The promise itself, in the app's own register: what you'd be doing with
    /// the library rather than what's in it. Said by onboarding's premium page
    /// and by the paywall wherever the entry point has nothing more specific.
    /// "More", because as a bare noun phrase the line read as a description of
    /// the app rather than of what Premium adds — and every reader already has
    /// the app.
    ///
    /// The break is set by hand, after the comma: left to wrap at `.title`
    /// the line broke as "…the Word, one / clue at a time." Both places
    /// that say it are headlines, so the newline never lands mid-sentence.
    static let promise = "More time in the Word,\none clue at a time."

    /// The upsell cards' button, on Today and in Profile.
    ///
    /// "See plans" was accurate — the button opens the paywall, it doesn't buy
    /// anything — but accuracy was all it had. It describes the app's plumbing
    /// instead of offering the reader something, and a plan is what you read
    /// when you have already decided to pay, not what persuades you to look.
    ///
    /// Where a free trial is really on the table the button names it, because
    /// that is the offer and the reason to tap. It still doesn't overstate the
    /// tap: it says *try*, and the paywall behind it is where the trial
    /// actually starts. The duration comes off the product, so a 3-day offer
    /// can never be advertised as a week.
    ///
    /// With nothing to offer — products still loading, or a player who has
    /// already spent their trial — it falls back to "See plans" rather than
    /// promising a free week they can't have. That fallback is the honest
    /// half of the old button, kept for the case it was right about.
    static func cardCTA(_ store: StoreService) -> String {
        guard let yearly = store.yearly,
              let offer = store.introOffer(for: yearly) else { return "See plans" }
        return "Try \(offer.duration) free"
    }

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
    /// four, including a "No ads, ever" the app can't really honour. A player
    /// who saw both was reading two different products.
    ///
    /// Hints lead. They are the most-hit paywall trigger in the app, so most
    /// readers arrive here mid-frustration with a hint they were refused —
    /// and the list used to open on shelf inventory instead, making them read
    /// past their own reason for coming. The row says what the lifted limit
    /// means rather than naming the limit: "No hint limits" was a negation
    /// aimed at someone already annoyed.
    ///
    /// The library row carries the only number on the page. The count comes
    /// from the bundle rather than a written "100+", so it can't go stale, and
    /// it earns its place by being large and checkable. What changed is the
    /// job it does: "the whole library" described a shelf, and a shelf is not
    /// a reason to pay — today's puzzle is already free. "Catch up" names what
    /// the archive actually buys. (An earlier "not just today's" said the same
    /// thing by negation and spent the opening words on what free lacks; this
    /// stays affirmative.)
    ///
    /// Every row here is costed in lines, not words. The column takes about
    /// 28 characters, and a first draft of this row ran to two — which with
    /// the packs row below it grew the card by 50pt and put the trial
    /// timeline under the fold, the very thing the fourth benefit was cut to
    /// prevent. Any rewrite here has to be checked on screen against the
    /// timeline, not just read.
    ///
    /// The packs row names seasons instead of counting packs. Counting was
    /// the real weakness: all 59 pack puzzles are inside the library count
    /// above, so "All 9 packs" advertised the same content a second time at a
    /// smaller number, and a smaller number next to 241 reads as a discount on
    /// the first claim. What packs genuinely add is the calendar — Lent,
    /// Easter, Advent and Christmas carry real date windows in `packs.json` —
    /// and a thing that comes back every year is the honest argument for a
    /// subscription over a one-off.
    ///
    /// One line since 2026-10-03: "Lent, Advent, Christmas — every collection,
    /// and each new one" was the only row that wrapped, breaking the list's
    /// rhythm on every phone. The seasons are still named where they're
    /// evidence — the locked-pack strip lists them by title — and "every
    /// year" keeps the calendar argument the row exists to make. Sized for
    /// the narrowest phone: about 31 characters fit beside the symbol on a
    /// 375pt screen, and this is 26.
    ///
    /// Three rows, not four. "Replay any puzzle, any time" was cut on
    /// 2026-09-07: it restated the library row (a shelf you own is a shelf
    /// you can reopen), and the ~30pt it cost was what pushed the trial
    /// timeline below the fold once the App Store rating moved above the
    /// plan cards. The timeline is the page's strongest trust element; a
    /// fourth benefit is not worth hiding it.
    ///
    /// "No ads" is gone entirely, and so is the ad scaffold behind it: the app
    /// serves no advertising, so there is nothing for Premium to remove — and
    /// free players have no ads either, which makes it an argument for the
    /// product rather than for paying. Add the row back only alongside a real
    /// ad integration.
    ///
    /// `firstRun` drops the hints row, for onboarding. Hints lead on the sheet
    /// because players arrive there from a refused hint; a player on their
    /// first run has never been refused one (hints are free until their third
    /// solve), so the row sold a limit they hadn't met and pushed the content
    /// rows down the five seconds the page gets.
    static func all(puzzleCount: Int, firstRun: Bool = false) -> [PremiumBenefit] {
        let hints = PremiumBenefit(
            icon: "lightbulb",
            title: "Hints whenever you need them"
        )
        return (firstRun ? [] : [hints]) + [
            PremiumBenefit(
                icon: "square.grid.3x3",
                title: "Catch up on all \(puzzleCount) puzzles"
            ),
            PremiumBenefit(
                // A calendar, not a stack: the row's claim is the seasons,
                // and the stack glyph read as a blob at this size. All three
                // are outline symbols — `calendar` has no fill to match the
                // others, and one weight across the list reads as a set.
                icon: "calendar",
                title: "Seasonal packs, every year"
            ),
            PremiumBenefit(
                // Added 2026-10-07: memory verses are what retained players
                // actually use, and they were nowhere on the offer, which sold
                // puzzle counts to daily players who don't need more puzzles.
                // Premium already lifts the 3-verse cap. "Memorize", not
                // "Unlimited verses": every verse is already free to read.
                // The brain matches "Try it from memory". 25 characters.
                icon: "brain",
                title: "Memorize unlimited verses"
            ),
        ]
    }
}

/// External legal links shown on the paywall. Terms uses Apple's standard EULA.
enum LegalLinks {
    static let terms = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    static let privacy = URL(string: "https://biblecrosswordchallenge.com/privacy.html")!
}

// MARK: - Bars, by system

/// The purchase bar as a system bar on iOS 26, where the scroll edge effect
/// blurs the page under it the way it does under a toolbar; a plain inset
/// before that, with its own fill and hairline (see `LegacyBarEdge`).
private struct PinnedBar<Bar: View>: ViewModifier {
    @ViewBuilder let bar: () -> Bar

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.safeAreaBar(edge: .bottom) { bar() }
        } else {
            content.safeAreaInset(edge: .bottom) { bar() }
        }
    }
}

/// Before iOS 26 the bar needs its own edge: the fill matches the canvas so
/// it reads continuous with the page, and a hairline separates it from the
/// content scrolling underneath. On 26 the system draws that edge.
private struct LegacyBarEdge: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
        } else {
            content
                .background(Theme.background)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color.primary.opacity(0.08))
                        .frame(height: 1)
                }
        }
    }
}

/// Before iOS 26 the navigation bar is transparent by default, which put the
/// serif hero underneath the close button as soon as the content scrolled;
/// an opaque bar in the page's own colour fixed it. On 26 the scroll edge
/// effect does that job, and a custom bar background would paint over it —
/// and over the side rail on iPhone Duo.
private struct LegacyOpaqueNavigationBar: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
        } else {
            content
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbarBackground(Theme.background, for: .navigationBar)
        }
    }
}
