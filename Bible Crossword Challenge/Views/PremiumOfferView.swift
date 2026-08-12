//
//  PremiumOfferView.swift
//  Bible Crossword Challenge
//
//  The Premium offer itself — promise, benefits, plans — shared by the two
//  surfaces that sell it: `PaywallView` (a sheet, reached from every in-app
//  entry point) and onboarding's final page.
//
//  These were two implementations of one offer, and they drifted every time
//  either changed. The copy had already been pulled into `PremiumCopy` and
//  `PremiumBenefit` for exactly that reason; what stayed split was the part
//  that mattered most — the *offer*. Onboarding sold the yearly plan alone,
//  with no monthly, no lifetime, no per-month figure and no savings badge, to
//  91% of everyone who has ever seen a paywall in this app. It also couldn't be
//  audited beside the sheet, because there was no shared thing to audit.
//
//  Now anything true of the offer is true in one place. What stays per-surface
//  is only the chrome: how the screen is dismissed, where the CTA sits, and the
//  promise at the top — which each surface still chooses, because the sheet
//  knows the entry point and onboarding knows whether the player just solved
//  their first clue.
//

import SwiftUI
import StoreKit

private extension View {
    /// The shared look of a thing you can pick on this page: a tinted, accented
    /// card when it's the one, an outline on bare paper when it isn't.
    ///
    /// Unselected plans used to be filled with `Theme.surface` — the same white
    /// as the benefits card directly above them. Two blocks in the same material
    /// read as two blocks of the same kind, so the monthly card looked like more
    /// information rather than the other half of a choice. Outlining them
    /// instead leaves exactly one white card on the page (the benefits) and
    /// makes every bordered thing below it something you can tap.
    func planChrome(selected: Bool) -> some View {
        background(selected ? Theme.accent.opacity(0.12) : .clear,
                   in: .rect(cornerRadius: Theme.cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .strokeBorder(selected ? Theme.accent : Color(.separator),
                                  lineWidth: selected ? 2 : 1)
            }
            // Without this the card only answers to taps that land on the
            // glyphs themselves: a SwiftUI button's hit area is its content,
            // and neither the padding nor the background extends it. Most of a
            // card this size is padding, so most of it was dead to the touch.
            .contentShape(.rect(cornerRadius: Theme.cornerRadius, style: .continuous))
    }
}

struct PremiumOfferView: View {
    /// The promise, chosen by the surface presenting it.
    let headline: String

    /// The player's own progress, when the surface has any worth stating.
    ///
    /// Nil during onboarding: the most they can have solved by then is the
    /// tutorial clue, and a tally of one reads as a tally of nothing.
    var progressLine: String? = nil

    /// Which plan is selected.
    ///
    /// Owned by the caller because on both surfaces the CTA that acts on it
    /// sits outside this view — pinned to the sheet's bottom edge, or down in
    /// onboarding's shared controls row.
    @Binding var selectedID: String

    /// When non-nil, the blocks fade in on a stagger, as onboarding's other
    /// pages do. Nil on the sheet, which is already an animated presentation.
    var entranceActive: Bool? = nil

    /// Whether to name the collections this player can't open yet.
    ///
    /// A flag rather than a slot the caller fills, because the strip is built
    /// from the same two environment values everything else here reads, and
    /// belongs beside the benefit line it makes concrete. What varies is only
    /// whether a surface wants it: the sheet does, onboarding doesn't. A player
    /// three minutes into their first run has no relationship with the packs
    /// yet, so a list of things they can't have reads as a wall rather than as
    /// content withheld — and ticket 08 scopes the strip to the sheet anyway.
    var showsLockedPacks: Bool = false

    /// The pack the player just bounced off, when they came from one. It sorts
    /// to the front of the strip, so the collection that sent them here is the
    /// first one they see.
    var highlightedPackID: String? = nil

    @Environment(StoreService.self) private var store
    @Environment(\.puzzleProvider) private var puzzleProvider
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ScaledMetric(relativeTo: .body) private var checkSize: CGFloat = 22

    var body: some View {
        VStack(spacing: Theme.Spacing.m) {
            staggered(headlineBlock, delay: 0.05)
            staggered(featureList, delay: 0.14)
            staggered(lockedPackStrip, delay: 0.17)

            if store.isPremium {
                premiumBadge
            } else if store.products.isEmpty {
                productsPlaceholder
            } else {
                staggered(plans, delay: 0.20)
                staggered(trialTimeline, delay: 0.26)
                staggered(socialProof, delay: 0.30)
            }
        }
    }

    /// The plan the CTA outside this view would buy. Derived rather than passed
    /// in: the binding is the caller's, but everything on this page that has to
    /// describe the selection needs the product, not the id.
    private var selectedProduct: Product? {
        store.products.first { $0.id == selectedID }
    }

    /// Applies onboarding's entrance treatment when the caller asked for it and
    /// leaves the view alone otherwise.
    @ViewBuilder
    private func staggered<V: View>(_ view: V, delay: Double) -> some View {
        if let entranceActive {
            view.entrance(active: entranceActive, delay: delay, reduceMotion: reduceMotion)
        } else {
            view
        }
    }

    // MARK: - Headline

    private var headlineBlock: some View {
        VStack(spacing: Theme.Spacing.s) {
            // A bare label: the puzzle count already leads the benefits list
            // one block down, and stating it up here as well meant the screen's
            // first two numbers were the same number.
            Text("Premium")
                .kicker()
            Text(headline)
                .font(.scripture(.largeTitle, weight: .semibold))
                .multilineTextAlignment(.center)

            // Only the no-trial path gets a subhead. When a trial exists the
            // page already states it three times — the timeline, the CTA and
            // the commitment line — and the fourth copy up here was the
            // weakest of them: an adjective ("3-day free trial") where the
            // timeline below answers the actual question, which is when money
            // starts. A player with no trial left still needs something above
            // the fold about what costs nothing, so the free tier keeps its
            // line.
            if trialText == nil {
                Text(PremiumCopy.freeDailyReassurance)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if let progressLine {
                Text(progressLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    /// The introductory offer on the *selected* plan, when there is one and the
    /// player hasn't already used theirs.
    ///
    /// Keyed to the selection rather than to `store.yearly`: only yearly
    /// carries an introductory offer, so an unkeyed read would show the
    /// free-tier reassurance to a trial-holder the moment they tapped monthly
    /// — which is correct, and stops the header describing an offer the CTA
    /// underneath isn't making.
    private var trialText: String? {
        guard let selectedProduct else { return nil }
        return store.introOfferText(for: selectedProduct)
    }

    // MARK: - Benefits

    /// The benefits, grouped into one surface rather than floating on the page.
    /// Loose on the canvas they read as an unbroken wall of text; bounding them
    /// makes the list a single object the eye can skip past on the way to the
    /// price.
    ///
    /// One line per row — see `PremiumBenefit`. `.top` alignment stays for the
    /// accessibility sizes where a row does wrap, so the disc sits beside the
    /// first line rather than floating in the middle of two.
    private var featureList: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            ForEach(PremiumBenefit.all(
                puzzleCount: puzzleProvider.totalPuzzleCount,
                packCount: puzzleProvider.packs.filter(\.isPremium).count
            )) { benefit in
                HStack(alignment: .top, spacing: Theme.Spacing.m) {
                    // Accent, not green: green means "solved" everywhere else
                    // in the app, and it shouldn't also mean "included".
                    // The disc scales with the label: at a fixed size the glyph
                    // outgrew it at accessibility sizes and spilled over.
                    Image(systemName: benefit.icon)
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(Theme.accent)
                        .frame(width: checkSize, height: checkSize)
                        .background(Theme.accent.opacity(0.12), in: .circle)
                    Text(benefit.title)
                        .font(.body.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.m)
        .elevatedCard()
    }

    // MARK: - Withheld collections

    /// How many packs the strip names before it starts counting instead.
    private static let namedPackLimit = 3

    /// The collections this player can't open yet, named rather than counted.
    ///
    /// The benefits list one block up says "All 7 packs, and every new one",
    /// and a number is only a claim — the reader has to take it on trust and
    /// has no idea whether the seven are worth having. Three titles are
    /// evidence, and they're the app's own content rather than a promise about
    /// it. This is the strip `PaywallView`'s header comment has described since
    /// it was written ("then the named packs they can't open yet") and which
    /// the screen never actually had.
    ///
    /// Deliberately not tappable. Every other surface that lists packs pushes
    /// pack detail, but this one is a sheet whose whole job is a single
    /// decision, and pack detail is where half these players just came from —
    /// its own locked CTA reopens this very paywall. A preview that goes
    /// nowhere is the honest shape here; the strip is evidence, not navigation.
    @ViewBuilder
    private var lockedPackStrip: some View {
        let locked = lockedPacks
        if !locked.isEmpty {
            let named = Array(locked.prefix(Self.namedPackLimit))
            let remainder = locked.count - named.count
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Text("Locked collections").kicker()
                ForEach(named) { pack in
                    // `.top` for the same reason the benefits list uses it: a
                    // title that wraps at large text sizes should keep its
                    // symbol beside the first line, not floating between two.
                    HStack(alignment: .top, spacing: Theme.Spacing.m) {
                        // The pack's own symbol and tint, as the Packs tab
                        // draws them. Uniform accent discs here would have made
                        // the strip a second benefits list; the collections
                        // already have identities, and using them is what says
                        // "real content" rather than "more bullet points".
                        Image(systemName: pack.coverSymbol)
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(pack.accent)
                            .frame(width: checkSize, height: checkSize)
                            .background(pack.accent.opacity(0.14), in: .circle)
                        Text(pack.title)
                            .font(.body.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
                // Says the strip is a sample and how much it's leaving out,
                // rather than letting three titles imply three packs.
                //
                // Indented onto the titles' own column rather than sitting
                // flush with the card's padding: it continues the list, and
                // flush left it hung out past every row above it — the one
                // ragged edge on an otherwise squared-off card.
                if remainder > 0 {
                    Text("and \(remainder) more")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.leading, checkSize + Theme.Spacing.m)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.m)
            .elevatedCard()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(lockedPacksLabel(named: named, remainder: remainder))
        }
    }

    /// The premium packs on offer today, the one they came from first.
    ///
    /// `availablePacks` rather than every premium pack: an out-of-season
    /// collection is hidden outright everywhere else in the app rather than
    /// teased, because a locked "returns in December" row is a dead end — and
    /// it would be a worse one here, where the whole point is that paying fixes
    /// it. Paying does not fix December.
    private var lockedPacks: [PuzzlePack] {
        guard showsLockedPacks, !store.isPremium else { return [] }
        var locked = puzzleProvider.availablePacks().filter(\.isPremium)
        if let highlightedPackID,
           let index = locked.firstIndex(where: { $0.id == highlightedPackID }) {
            locked.insert(locked.remove(at: index), at: 0)
        }
        return locked
    }

    /// One spoken sentence for the whole strip. Read row by row it's a list of
    /// bare titles with no hint of why they're being read out.
    private func lockedPacksLabel(named: [PuzzlePack], remainder: Int) -> String {
        var label = "Premium collections locked. "
            + named.map(\.title).joined(separator: ", ")
        if remainder > 0 { label += ", and \(remainder) more" }
        return label + "."
    }

    private var premiumBadge: some View {
        Label("You're Premium — thank you!", systemImage: "checkmark.seal.fill")
            .font(.headline)
            .foregroundStyle(.green)
            .padding(.vertical, Theme.Spacing.l)
    }

    /// Loading spinner while products fetch; a retry card if the fetch failed.
    @ViewBuilder private var productsPlaceholder: some View {
        VStack(spacing: Theme.Spacing.m) {
            if store.productsLoadFailed {
                Label("Couldn't load plans", systemImage: "wifi.exclamationmark")
                    .font(.headline)
                Text("Check your connection and try again.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Retry") {
                    Task { await store.refresh() }
                }
                .buttonStyle(.borderedProminent)
            } else {
                ProgressView("Loading plans…")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.Spacing.xl)
        .elevatedCard()
    }

    // MARK: - Plans

    /// The two subscriptions side by side, with the lifetime unlock demoted to
    /// a line beneath them.
    ///
    /// Three equal-weight rows made the player rank three things before they
    /// could do anything, and pushed the price itself below the fold. Two
    /// columns turn it into one comparison — which is the only question most
    /// people are actually asking — and lifetime stays reachable for the few
    /// who want it without competing for the same attention.
    private var plans: some View {
        VStack(spacing: Theme.Spacing.s) {
            // AnyLayout rather than a branch on the view itself, so selection
            // keeps its identity (and its animation) across the switch.
            let layout = stacksPlans
                ? AnyLayout(VStackLayout(spacing: Theme.Spacing.s))
                : AnyLayout(HStackLayout(alignment: .top, spacing: Theme.Spacing.s))
            layout {
                ForEach(subscriptionProducts, id: \.id) { product in
                    planCard(product)
                }
            }
            // The cards are height-flexible so the pair can match the taller of
            // the two (see `planCard`). Flexible is contagious: onboarding puts
            // this offer in a page that proposes at least the full screen
            // height, and without this the row would swallow every spare point
            // of it and draw two enormous cards. Pinned to its ideal height,
            // the flexibility does its job inside the row and stops there.
            .fixedSize(horizontal: false, vertical: true)
            if let lifetime = store.products.first(where: { $0.id == StoreService.lifetimeID }) {
                lifetimeRow(lifetime)
            }
        }
        // Spring the selection between plans instead of snapping.
        .animation(.snappy(duration: 0.2), value: selectedID)
    }

    /// Yearly and monthly, in that order — never lifetime, which has its own row.
    private var subscriptionProducts: [Product] {
        store.products.filter { $0.id != StoreService.lifetimeID }
    }

    private func planCard(_ product: Product) -> some View {
        let selected = product.id == selectedID
        return Button {
            selectedID = product.id
        } label: {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                badgeSlot(product)
                // The same mark the lifetime row below has always used. The two
                // used to speak different languages — cards signalled selection
                // with a tint and a border, the row with a radio — so one screen
                // asked the player to learn "selected" twice.
                HStack(spacing: Theme.Spacing.s) {
                    selectionMark(selected)
                    Text(planTitle(product))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                Text(planPrice(product))
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(planFootnote(product))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.m)
            // Side by side, the pair shares a bottom edge even when one card
            // needs a second line and the other doesn't — which is what larger
            // text sizes do to "$1.99/month" while "$9.99/year" still fits.
            // Two cards ending at different heights is the first thing the eye
            // catches on a row of two. Stacked they are full width and follow
            // one another, so there is nothing to equalise.
            .frame(maxHeight: stacksPlans ? nil : .infinity, alignment: .topLeading)
            .planChrome(selected: selected)
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    /// Lifetime, priced against the subscription rather than presented as a
    /// peer of it. At roughly two years of the yearly plan it's a real choice,
    /// not a decoy — so it stays selectable and keeps its own price.
    private func lifetimeRow(_ product: Product) -> some View {
        let selected = product.id == selectedID
        return Button {
            selectedID = product.id
        } label: {
            HStack(spacing: Theme.Spacing.s) {
                selectionMark(selected)
                Text("Or pay once — \(product.displayPrice) forever")
                    .font(.subheadline.weight(selected ? .semibold : .regular))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            // The same inset the plan cards use, so the three options share one
            // left edge down the whole group.
            .padding(Theme.Spacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Same chrome as the cards above. Unselected it used to be bare
            // paper with no edge at all, so until you tapped it the third option
            // read as a caption about the other two rather than a third choice.
            .planChrome(selected: selected)
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    /// The one mark every option on this page uses to say "this is the one".
    private func selectionMark(_ selected: Bool) -> some View {
        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
            .font(.subheadline)
            .foregroundStyle(selected ? Theme.accent : Color(.separator))
    }

    /// The savings pill itself.
    private func savingsPill(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .foregroundStyle(Theme.onInk)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Theme.ink, in: .capsule)
    }

    /// The badge's row inside the card — the pill on yearly, and the same row
    /// held empty on monthly so the two columns line up.
    ///
    /// The pill used to straddle the card's top border instead, centred on the
    /// edge, to save the card a row. It cost more than it saved: the black pill
    /// cut through the selected card's accent border, so the one element meant
    /// to look deliberate was the one that read as a collision — and the space
    /// it hung in was a hardcoded 10pt guess at half its own height, which is
    /// only correct at one text size. Larger type grew the pill into the card
    /// above.
    ///
    /// In the flow it costs a row, and the reserved copy on monthly is what
    /// keeps "Yearly" and "Monthly" — and every line under them — on one
    /// baseline. Stacked, the cards are full width and share no baseline, so
    /// only the card with something to say spends the row.
    @ViewBuilder
    private func badgeSlot(_ product: Product) -> some View {
        if let text = badgeText(product) {
            savingsPill(text)
        } else if !stacksPlans {
            // A real pill, hidden: only its height is being borrowed, and
            // taking it from the same view is what keeps the reservation
            // correct as the text size grows. Hidden also keeps the phantom
            // out of VoiceOver, which would otherwise read the badge twice.
            savingsPill("SAVE").hidden()
        }
    }

    /// Whether the plans stack instead of sitting side by side. Two columns
    /// can't hold a price and a per-month figure once the text gets large.
    private var stacksPlans: Bool { dynamicTypeSize.isAccessibilitySize }

    // MARK: - Social proof

    /// The one external voice on the page, kept to a single line and sitting
    /// with the plans rather than up in the header — trust matters most at the
    /// moment of paying, not the moment of reading.
    ///
    /// The number is hand-written, so it can go stale the way no other figure
    /// on this screen can (every price and count is read from StoreKit or the
    /// bundle). Check it against App Store Connect whenever release copy is
    /// touched, and drop the line entirely rather than round up.
    ///
    /// In the non-premium branch deliberately: it argues for a purchase, and a
    /// player who already paid or is looking at a retry card isn't being asked
    /// for one.
    private var socialProof: some View {
        Text("★ 4.8 on the App Store")
            .font(.footnote.weight(.medium))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            // VoiceOver reads the bare glyph as "black star", which turns the
            // line into noise for exactly the reader it should reassure.
            .accessibilityLabel("Rated 4.8 on the App Store")
    }

    // MARK: - Trial timeline

    /// What actually happens if they tap the button: access today, money on a
    /// named day. The trial is stated four times on this page already, but only
    /// ever as an adjective — "3-day free trial" says how long it lasts, not
    /// what arrives at the end of it, and the unanswered version of that
    /// question is the one that stops a purchase.
    ///
    /// Two steps, not the three this pattern usually has. The middle step is
    /// normally "we'll remind you before it ends", and this app cannot honestly
    /// make that promise: `NotificationService` schedules the daily reminder,
    /// season openings and the streak nudge, and nothing for a trial — and
    /// notification permission is optional here, so even once something is
    /// scheduled the claim would be false for everyone who declined. Add the
    /// step when there is a real reminder behind it, and only for players who
    /// granted notifications.
    ///
    /// Keyed to the *selected* plan rather than to yearly: monthly carries no
    /// introductory offer, so leaving a trial timeline on screen while monthly
    /// is selected would describe an offer the CTA isn't making.
    @ViewBuilder
    private var trialTimeline: some View {
        if let product = selectedProduct, let offer = store.introOffer(for: product) {
            VStack(alignment: .leading, spacing: 0) {
                timelineStep(
                    icon: "lock.open.fill",
                    title: "Today",
                    // No puzzle count: the benefits list two blocks up owns
                    // that number, and this line's one job is "you pay nothing".
                    detail: "Full access. You pay nothing.",
                    isLast: false
                )
                timelineStep(
                    icon: "creditcard.fill",
                    title: "In \(offer.duration)",
                    // The price and period come from the same product the CTA
                    // will buy, so this line cannot drift from the button.
                    detail: "\(product.displayPrice)\(store.periodText(for: product) ?? "") begins, unless you cancel first.",
                    isLast: true
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.m)
            .elevatedCard()
        }
    }

    private func timelineStep(icon: String, title: String, detail: String, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
            // The rail is drawn by the step above it, filling whatever height
            // the text beside it turns out to need — so it still joins the two
            // discs when a detail line wraps at large text sizes.
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: checkSize, height: checkSize)
                    .background(Theme.accent.opacity(0.12), in: .circle)
                if !isLast {
                    Rectangle()
                        .fill(Theme.accent.opacity(0.2))
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, isLast ? 0 : Theme.Spacing.m)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Plan copy

    private func planTitle(_ product: Product) -> String {
        PremiumOfferView.planTitle(product)
    }

    /// The plan's name, as both surfaces' analytics label it. Static so the CTA
    /// outside this view can name the plan it is about to buy without
    /// duplicating the mapping.
    static func planTitle(_ product: Product) -> String {
        switch product.id {
        case StoreService.yearlyID: return "Yearly"
        case StoreService.monthlyID: return "Monthly"
        default: return "Lifetime"
        }
    }

    /// The CTA label for a plan.
    ///
    /// Names the thing being started, never the transaction: "Subscribe"
    /// describes what the player gives up, while the trial length and the
    /// puzzle count describe what they get. The renewal terms are stated in
    /// full directly underneath either way — see `commitmentText`.
    ///
    /// Static, and shared, because the button sits outside this view on both
    /// surfaces and they had already ended up saying different things: the
    /// sheet named the puzzle count, onboarding said a flat "Unlock Premium",
    /// and neither could say "Unlock Lifetime" on the plan the other couldn't
    /// sell.
    static func ctaTitle(for product: Product?, store: StoreService, puzzleCount: Int) -> String {
        guard let product else { return "Continue" }
        if let trial = store.introOfferText(for: product) { return PremiumCopy.trialCTA(trial) }
        if store.periodText(for: product) != nil { return "Unlock \(puzzleCount) puzzles" }
        return "Unlock Lifetime"
    }

    /// The one-line disclosure under the CTA: exactly what the player is
    /// committing to, restated at the commit point where purchase anxiety
    /// peaks.
    ///
    /// Onboarding used to carry a shorter version of this that never said when
    /// money starts or that the charge repeats. Same offer, same words now.
    static func commitmentText(for product: Product?, store: StoreService) -> String? {
        guard let product else { return nil }
        let period = store.periodText(for: product) ?? ""
        if let offer = store.introOffer(for: product) {
            // Says when money starts, not just that a trial exists — the
            // question a trial-sceptic is actually asking at this point.
            // `duration`, not the trial phrase with " free trial" trimmed off
            // it: after "Free for" the length needs its plural back.
            return "Free for \(offer.duration), then \(product.displayPrice)\(period), renewing until cancelled. Cancel anytime."
        }
        if !period.isEmpty {
            return "Auto-renews at \(product.displayPrice)\(period) until cancelled. Cancel anytime in Settings."
        }
        return "One-time purchase — yours forever."
    }

    /// The headline figure on a card: what leaves the account, and how often.
    private func planPrice(_ product: Product) -> String {
        product.displayPrice + (store.periodText(for: product) ?? "")
    }

    /// The line under the price: the same price read the other way round, so
    /// each card is legible on its own — the per-month figure on yearly, the
    /// annual total on monthly. That makes the saving a subtraction the reader
    /// can see rather than a percentage they have to trust.
    ///
    /// The trial does not appear here, and used to be all that did: this
    /// returned the introductory offer early, so whenever one existed the
    /// yearly card read "3-day free trial" and the per-month figure appeared
    /// *nowhere on the screen*. The cheapest way to read this price was the one
    /// number the page never showed.
    ///
    /// The trial is already stated three times — the subhead, the CTA, and the
    /// commitment line — and it reads as attached to yearly because yearly is
    /// preselected: choosing monthly changes the CTA away from "Start 3-day
    /// free trial", which says it more plainly than a fourth caption would.
    /// Adding it back here only cost the card a second line, and left the two
    /// plans at visibly different heights.
    private func planFootnote(_ product: Product) -> String {
        switch product.id {
        case StoreService.yearlyID:
            return yearlyPerMonthText.map { "\($0)/month" } ?? ""
        case StoreService.monthlyID:
            return monthlyPerYearText.map { "\($0) a year" } ?? ""
        default:
            return "one-time"
        }
    }

    /// The monthly plan's price over twelve months, in the product's own
    /// currency — the number the yearly plan is quietly being compared against.
    private var monthlyPerYearText: String? {
        guard let monthly = store.products.first(where: { $0.id == StoreService.monthlyID })
        else { return nil }
        return (monthly.price * 12).formatted(monthly.priceFormatStyle)
    }

    /// The yearly plan's price divided by twelve, formatted in the product's
    /// own currency and locale rather than hand-built from the display string.
    private var yearlyPerMonthText: String? {
        guard let yearly = store.products.first(where: { $0.id == StoreService.yearlyID })
        else { return nil }
        let perMonth = yearly.price / 12
        return perMonth.formatted(yearly.priceFormatStyle)
    }

    /// Tinted pill on the yearly plan — the computed saving vs. paying monthly,
    /// or a "BEST VALUE" fallback when monthly isn't available to compare against.
    private func badgeText(_ product: Product) -> String? {
        guard product.id == StoreService.yearlyID else { return nil }
        if let pct = yearlySavingsPercent { return "SAVE \(pct)%" }
        return "BEST VALUE"
    }

    private var yearlySavingsPercent: Int? {
        guard
            let yearly = store.products.first(where: { $0.id == StoreService.yearlyID }),
            let monthly = store.products.first(where: { $0.id == StoreService.monthlyID })
        else { return nil }
        let monthlyAnnual = monthly.price * 12
        guard monthlyAnnual > 0 else { return nil }
        let saved = (monthlyAnnual - yearly.price) / monthlyAnnual
        let pct = Int((NSDecimalNumber(decimal: saved).doubleValue * 100).rounded())
        return pct > 0 ? pct : nil
    }
}
