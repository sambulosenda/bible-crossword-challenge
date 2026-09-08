//
//  OnboardingView.swift
//  Bible Crossword Challenge
//
//  First-run experience. Five pages — intro, one ask, a payoff, the offer:
//
//    0  Welcome     the brand, in the app's own vocabulary (a crossword)
//    1  First solve two letters, then a verse — the whole product in ten seconds
//    2  Name        asked once the player has something to be named for
//    3  Celebration the payoff, by name and with their own numbers — the
//                   emotional peak the offer used to arrive without
//    4  Premium     the upsell, dismissible; the daily puzzle is always free
//
//  The celebration sits directly before the offer, not directly after the
//  solve: the name page's typing would have spent the peak, and a greeting by
//  name needs the name to exist. It is the pattern the top-converting
//  onboardings share (a stats moment between the demonstrated value and the
//  sell), sized honestly for a two-letter solve.
//
//  There is deliberately no reminders page any more. It asked before the app
//  had proved anything: of 102 players who answered it in the 30 days to
//  2026-08-24, 86 tapped "Not now" — 10.8% granted. Killed 2026-08-24; the
//  first ask is now the completion-screen card (`ReminderAsk`, `.completion`),
//  which lands on a player who just finished a real puzzle. Decliners keep the
//  day-2 sheet and streak-card paths, unchanged.
//
//  Everything sits on the app's paper canvas with serif hero titles, so the
//  first screen a player sees is the same app as the hundredth.
//
//  Each page's content animates in (staggered fade + rise) when it becomes
//  active, and all motion respects the Reduce Motion accessibility setting.
//

import SwiftUI
import Lottie
import StoreKit

struct OnboardingView: View {
    @Bindable var profile: PlayerProfile
    var onFinish: () -> Void

    @Environment(StoreService.self) private var store
    @Environment(\.analytics) private var analytics
    @Environment(\.puzzleProvider) private var puzzleProvider
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Hardware-keyboard focus for the first-solve page. The game screen takes
    /// typed letters (iPad, Bluetooth keyboards); the one puzzle a new player
    /// meets before it should too, or the first screen teaches that keys
    /// don't work here.
    @FocusState private var solveFocused: Bool
    @State private var page = 0
    @State private var didLogPaywallOpen = false
    @State private var didLogFirstSolve = false

    // Dismissal telemetry for the offer page, mirroring `PaywallView`'s. Every
    // exit from onboarding goes through `finish()`, so that is where the event
    // fires; what's tracked here is when the page arrived and whether the buy
    // button was pressed. A quit-the-app exit emits nothing — the 34% who
    // leave that way stay visible only as an absent `onboarding_completed`.
    @State private var premiumArrivedAt: Date?
    @State private var didTapPremiumCTA = false
    @FocusState private var nameFocused: Bool

    /// Which plan the premium page has selected. Lives here rather than in
    /// `PremiumOfferView` because the CTA that buys it is down in `controls`,
    /// outside the TabView the offer is a page of.
    @State private var selectedPlanID = StoreService.yearlyID

    /// Typed separately from `profile.username` so the field can start empty:
    /// a new profile is created with the placeholder name "Friend", and showing
    /// that as prefilled text makes the player delete it before they can type.
    @State private var name = ""

    // First-solve state.
    @State private var entries: [MiniPoint: Character] = [:]
    @State private var focus: MiniPoint? = MiniCrossword.firstSolveBlanks.first
    @State private var solved = false
    @State private var wrongAttempts = 0

    // Solve timing, for the celebration page's tile. Started on the first
    // letter typed rather than on page arrival, so reading the clue doesn't
    // count against the player — the number exists to flatter an eight-second
    // solve, not to audit it.
    @State private var solveStartedAt: Date?
    @State private var solveSeconds: Int?

    private let lastPage = 4

    /// How many of the pages are setup steps. The celebration and the offer
    /// both sit past the end of the bar — one is payoff, the other a bonus,
    /// and neither asks the player for anything.
    private let stepCount = 3

    /// Analytics labels for the five pages, indexed by page number.
    private let stepNames = ["welcome", "first_solve", "name", "celebration", "premium"]

    var body: some View {
        VStack(spacing: 0) {
            progressBar

            TabView(selection: $page) {
                welcomePage.tag(0)
                firstSolvePage.tag(1)
                namePage.tag(2)
                celebrationPage.tag(3)
                premiumPage.tag(4)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut, value: page)

            controls
        }
        .background(canvas)
        .sensoryFeedback(.selection, trigger: page)
        .sensoryFeedback(.success, trigger: solved)
        .sensoryFeedback(.error, trigger: wrongAttempts)
        // Swiping off the name page shouldn't leave the keyboard floating over
        // the next page — dismiss it whenever we leave.
        .onChange(of: page) { oldPage, newPage in
            // Logged on the way out of the solve page, not on solving, so a
            // skip is recorded too — the two outcomes are the comparison.
            // Before the step event, so the stream reads in the order it
            // happened rather than the order the handler is written.
            if oldPage == 1 && !didLogFirstSolve {
                didLogFirstSolve = true
                analytics.log(.onboardingFirstSolve(solved: solved, attempts: wrongAttempts))
            }
            logStep(newPage)
            if newPage != 2 { nameFocused = false }
            // Raising the keyboard mid-transition fights the page animation, so
            // wait for the slide to settle before taking focus.
            if newPage == 2 {
                Task {
                    try? await Task.sleep(for: .milliseconds(450))
                    if page == 2 { nameFocused = true }
                }
            }
            // The premium page is a paywall view like any other — count it so
            // onboarding conversion can be compared against in-app sources.
            if newPage == lastPage && !didLogPaywallOpen {
                didLogPaywallOpen = true
                analytics.log(.paywallOpened(source: PaywallSource.onboarding.rawValue))
            }
            // First arrival only, like the open above: swiping back to the
            // name page and returning shouldn't reset the clock.
            if newPage == lastPage && premiumArrivedAt == nil {
                premiumArrivedAt = Date()
            }
        }
        .onAppear {
            if profile.username != "Friend" { name = profile.username }
            logStep(page)
        }
        .purchaseNoticeAlert(store)
    }

    /// Paper, lit from the top by a wash of the page's own colour — accent for
    /// the four setup pages, gold as the premium page arrives.
    private var canvas: some View {
        ZStack(alignment: .top) {
            Theme.background
            RadialGradient(
                colors: [(page == lastPage ? Theme.badgeRim : Theme.accent).opacity(0.10), .clear],
                center: .top,
                startRadius: 0,
                endRadius: 380
            )
            .animation(.easeInOut(duration: 0.5), value: page)
        }
        .ignoresSafeArea()
    }

    /// Three ink segments instead of dots: it reads as progress rather than
    /// decoration, and it tells the player up front how short this is.
    ///
    /// Three, not five — neither the celebration nor the premium page is a
    /// step. The celebration asks nothing (it's the payoff, and it arrives
    /// with the bar already full, which is the point). Filling a final segment
    /// on the offer framed paying as the way to finish setting the app up,
    /// which is both untrue (the free daily is the whole product for most
    /// players) and the kind of bait-and-switch that earns a one-star review.
    /// The bar goes gold on the offer to mark what follows as a bonus — the
    /// same gold the canvas wash already turns on that page, so the two read
    /// as one signal.
    private var progressBar: some View {
        let onOffer = page == lastPage
        return HStack(spacing: 5) {
            ForEach(0..<stepCount, id: \.self) { i in
                Capsule()
                    .fill(onOffer ? Theme.badgeRim : (i <= page ? Theme.ink : Color.primary.opacity(0.10)))
                    .frame(height: 4)
            }
            // The offer page gets the universal paywall escape the moment it
            // arrives. Every paywall in the app opens with an ✕; this one — the
            // busiest — made players scroll their eyes to the quiet decline at
            // the bottom instead, and after the 2026-08-11 price increase a
            // third of everyone who reached it quit the app on the spot rather
            // than find it (34% of reachers left without ever playing, up from
            // 6% at the old price). The ✕ is the affordance they were scanning
            // for; it exits to the free daily exactly like the button below.
            if onOffer {
                Button {
                    finish(exit: .close)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .frame(width: 36, height: 36)
                        .contentShape(.rect)
                }
                // Same quiet gray as PaywallView's close button — the default
                // accent tint read as a blue action on the gold offer page.
                .tint(.secondary)
                .accessibilityLabel("Close and continue with the free puzzle")
                .transition(.opacity)
            }
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.top, Theme.Spacing.s)
        .animation(.spring(duration: 0.35), value: page)
        .accessibilityElement(children: onOffer ? .contain : .ignore)
        .accessibilityLabel(
            onOffer
                ? "Setup complete. Premium offer, optional."
                : page >= stepCount
                    ? "Setup complete."
                    : "Step \(page + 1) of \(stepCount)"
        )
    }

    // MARK: - Pages

    private var welcomePage: some View {
        let active = page == 0
        return pageFrame(spacing: Theme.Spacing.xl) {
            MiniCrossword(layout: MiniCrossword.faithHopeLove)
                .padding(.bottom, Theme.Spacing.s)

            VStack(spacing: Theme.Spacing.m) {
                Text("Bible Crossword")
                    .kicker()
                    .entrance(active: active, delay: 0.30, reduceMotion: reduceMotion)
                Text("Know the Word,\none clue at a time.")
                    .font(.scripture(.largeTitle, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .entrance(active: active, delay: 0.36, reduceMotion: reduceMotion)
                Text("A fresh Scripture crossword every day — with the verse behind every answer.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.Spacing.s)
                    .entrance(active: active, delay: 0.44, reduceMotion: reduceMotion)
            }
        }
    }

    private var firstSolvePage: some View {
        let active = page == 1
        return pageFrame(spacing: Theme.Spacing.l) {
            // Paired with the spacer below the grid: the clue and grid settle
            // into the space above the keypad instead of hugging the top edge.
            Spacer(minLength: 0)

            VStack(spacing: Theme.Spacing.xs) {
                Text(solved ? "1 Down · Solved" : "1 Down")
                    .kicker()
                Text("Noah built one to save his family")
                    .font(.scripture(.title2, weight: .semibold))
                    .multilineTextAlignment(.center)
            }
            .entrance(active: active, delay: 0.05, reduceMotion: reduceMotion)
            .animation(.easeInOut, value: solved)

            MiniCrossword(
                layout: MiniCrossword.firstSolve,
                entries: entries,
                focus: solved ? nil : focus,
                celebrated: solved ? MiniCrossword.firstSolveWord : [],
                numbers: [MiniPoint(row: 0, col: 2): 1],
                // Already assembled by the time the page slides in — the page's
                // own entrance carries it, so the cascade would double up.
                animatesIn: false
            ) { tapped in
                focus = tapped
            }
            .modifier(Shake(travel: CGFloat(wrongAttempts)))
            // The solved word glowing gold is the celebration; the confetti
            // bursts from it, not from a second badge lower down.
            .background {
                if solved, !reduceMotion {
                    LottieView(animation: .named("puzzle_complete"))
                        .configure { $0.contentMode = .scaleAspectFit }
                        .playing(loopMode: .playOnce)
                        .frame(width: 320, height: 320)
                        .allowsHitTesting(false)
                }
            }
            .entrance(active: active, delay: 0.12, reduceMotion: reduceMotion)

            // Unsolved: the keypad stays down by the thumb, so the gap above
            // it flexes. Solved: the verse follows the word it came from, so
            // the gap is fixed and the clue–grid–verse group centres as one.
            if solved {
                Spacer().frame(height: Theme.Spacing.xl)
            } else {
                Spacer(minLength: Theme.Spacing.l)
            }

            if solved {
                verseReveal
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .asymmetric(
                                insertion: .move(edge: .bottom).combined(with: .opacity),
                                removal: .opacity
                            )
                    )
                Spacer(minLength: 0)
            } else {
                LetterKeyboardView(onLetter: type(_:), onDelete: deleteLetter)
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.3) : .spring(duration: 0.55, bounce: 0.15), value: solved)
        // Same routing as CrosswordGameView: the page takes focus and feeds
        // letters and backspace into the mini. Only while unsolved — after
        // the solve the keypad is gone and Continue is the only action.
        .focusable()
        .focusEffectDisabled()
        .focused($solveFocused)
        .onKeyPress(characters: .letters, phases: .down) { press in
            guard !solved, let letter = press.characters.uppercased().first else { return .ignored }
            type(letter)
            return .handled
        }
        .onKeyPress(.delete, phases: .down) { _ in
            guard !solved else { return .ignored }
            deleteLetter()
            return .handled
        }
        // Focus follows the page, not `onAppear`: the paged TabView builds
        // every page up front, so this view appears while page 0 is showing
        // and an appear-time write would land on an unsettled tree anyway.
        .onChange(of: page) { _, new in solveFocused = (new == 1) }
    }

    /// The payoff. Same shape as the verse card on the completion screen, so a
    /// player meets the app's one moment of ceremony before their first puzzle.
    /// The payoff, set on the paper like the completion screen's verse: the
    /// line, the verse at reading size, the reference. No second badge (the
    /// gold word above is the celebration) and no tinted panel around the one
    /// thing on the page that is content rather than chrome.
    private var verseReveal: some View {
        VStack(spacing: Theme.Spacing.s) {
            Text("That’s the whole game.")
                .font(.headline)

            Text("“By faith Noah, when warned about things not yet seen, in godly fear built an ark to save his family.”")
                .font(.scripture(.title3))
                .lineSpacing(4)
                .multilineTextAlignment(.center)

            // A label, not a link: secondary, semibold so it clears contrast.
            Text("Hebrews 11:7")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, Theme.Spacing.s)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var namePage: some View {
        let active = page == 2
        return pageFrame(spacing: Theme.Spacing.l) {
            VStack(spacing: Theme.Spacing.m) {
                // No praise for a clue they skipped — the celebration page
                // already applies this razor, and the two pages reading the
                // same player differently would be the tell.
                Text(solved ? "Nice solve" : "Before you play")
                    .kicker()
                    .entrance(active: active, delay: 0.05, reduceMotion: reduceMotion)
                Text("What should we\ncall you?")
                    .font(.scripture(.largeTitle, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .entrance(active: active, delay: 0.10, reduceMotion: reduceMotion)
            }

            VStack(spacing: Theme.Spacing.s) {
                TextField("Your name", text: $name)
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .focused($nameFocused)
                    .padding(Theme.Spacing.m)
                    .elevatedCard()

                Text("Used to greet you and to sign the puzzles you share. Change it any time in your profile.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .onSubmit { nameFocused = false }
            .entrance(active: active, delay: 0.18, reduceMotion: reduceMotion)
        }
    }

    /// The peak before the ask: the player greeted by the name they just gave,
    /// over their own numbers.
    ///
    /// The solve page's inline verse card is the *product's* payoff (the verse
    /// behind the answer); this page is the *player's* (what they did, what's
    /// waiting). Splitting them keeps each small enough to land — and puts a
    /// high point directly under the offer, which used to arrive off the back
    /// of a keyboard.
    ///
    /// A skipper gets the same page with honest content: no "well done" for a
    /// clue they didn't solve, and library tiles instead of a solve time.
    private var celebrationPage: some View {
        let active = page == 3
        return pageFrame(spacing: Theme.Spacing.xl) {
            // The mark is the grid the player just filled (see CelebrationBadge:
            // a tick says "succeeded", the grid says what). Skippers get the
            // tick — there is nothing of theirs to show. No gold rim here: gold
            // is the offer bar's signal on the next page.
            Group {
                if solved {
                    CelebrationBadge(grid: ["GRACE", "..R..", "..K.."], confetti: "puzzle_complete", size: 96, showsRim: false)
                } else {
                    CelebrationBadge(systemImage: "checkmark", size: 96, showsRim: false)
                }
            }
            .entrance(active: active, delay: 0.05, reduceMotion: reduceMotion)

            VStack(spacing: Theme.Spacing.m) {
                // A solver did something; "setup" undersells it. A skipper
                // did set the app up, and gets the honest word.
                Text(solved ? "First solve" : "Setup complete")
                    .kicker()
                    .entrance(active: active, delay: 0.14, reduceMotion: reduceMotion)
                Text(celebrationHeadline)
                    .font(.scripture(.largeTitle, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .entrance(active: active, delay: 0.20, reduceMotion: reduceMotion)
            }

            celebrationTiles
                .entrance(active: active, delay: 0.30, reduceMotion: reduceMotion)
        }
    }

    /// Greets by name when there is one to use — the field the player just
    /// filled is the freshest thing in the app, and top onboarding flows cash
    /// personalisation in immediately rather than saving it for the profile.
    private var celebrationHeadline: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let suffix = trimmed.isEmpty ? "" : ", \(trimmed)"
        return solved
            ? "Well done\(suffix)."
            : "You're all set\(suffix)."
    }

    /// Two tiles, Duolingo's stats-moment pattern in this app's own units.
    /// The counts come from the bundle, so neither can go stale.
    private var celebrationTiles: some View {
        HStack(spacing: Theme.Spacing.s) {
            // "1s · First clue" was the old left tile: three letters typed in
            // a second reads as a timer bug, and at a minute it is still not
            // a number worth a tile. Day one is true for everyone and points
            // at the habit the next screens ask about.
            if solved {
                statTile(value: "Day 1", label: "Your streak")
            } else {
                statTile(value: "\(puzzleProvider.packs.count)", label: "Themed packs")
            }
            statTile(value: "\(puzzleProvider.totalPuzzleCount)", label: "Puzzles waiting")
        }
    }

    private func statTile(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.scripture(.title, weight: .semibold))
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.Spacing.m)
        .elevatedCard()
        .accessibilityElement(children: .combine)
    }

    /// The same offer the sheet makes, in a page instead of a sheet.
    ///
    /// Everything below the promise — the trial line, the benefits, the plans —
    /// is `PremiumOfferView`, so this page can't drift from `PaywallView` again.
    /// It also means onboarding now shows the *whole* offer: it used to sell the
    /// yearly plan alone, with no monthly, no lifetime, no per-month figure and
    /// no savings badge, to nine in ten of everyone who ever saw a paywall here.
    ///
    /// No progress line: the most the player can have solved by now is the
    /// tutorial clue, and a tally of one reads as a tally of nothing.
    private var premiumPage: some View {
        let active = page == lastPage
        return pageFrame(spacing: Theme.Spacing.l) {
            PremiumOfferView(
                headline: premiumHeadline,
                selectedID: $selectedPlanID,
                entranceActive: active
            )
        }
    }

    // MARK: - Building blocks

    /// Every page shares one frame: scrollable (so a long clue or a large text
    /// size can never clip), centred, with the same gutters.
    private func pageFrame<Content: View>(
        spacing: CGFloat,
        @ViewBuilder content: () -> Content
    ) -> some View {
        // Centred when it fits, scrollable when it doesn't — which is what
        // keeps a long clue, a large text size or a small phone from clipping.
        // Built up front: GeometryReader's closure escapes, so the non-escaping
        // content builder can't be called inside it.
        let stack = VStack(spacing: spacing, content: content)
        return GeometryReader { geo in
            ScrollView {
                stack
                    // Same readable column every tab screen uses — on iPad a
                    // full-bleed onboarding page reads as a stretched phone.
                    .frame(maxWidth: 560)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, Theme.Spacing.l)
                    .padding(.vertical, Theme.Spacing.l)
                    .frame(minHeight: geo.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
        }
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(spacing: Theme.Spacing.s) {
            switch page {
            case 0:
                Button("Get started") { advance() }
                    .buttonStyle(.pillProminent)

            case 1:
                if solved {
                    Button("Continue") { advance() }
                        .buttonStyle(.pillProminent)
                } else {
                    // Never trap a player on a puzzle. The quiet treatment keeps
                    // the nudge without the wall.
                    Button("Skip for now") { advance() }
                        .font(.subheadline.weight(.semibold))
                        .tint(.secondary)
                        .padding(.vertical, Theme.Spacing.m)
                }

            case lastPage:
                premiumControls

            case 3:
                // Momentum, not procedure: "Continue" reads as one more form
                // step, and this is the one page whose only job is momentum.
                Button("Keep going") { advance() }
                    .buttonStyle(.pillProminent)

            default:
                Button("Continue") { advance() }
                    .buttonStyle(.pillProminent)
            }
        }
        // Match the page column above, so the CTA never grows wider than the
        // content it belongs to.
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.top, Theme.Spacing.m)
        .padding(.bottom, Theme.Spacing.s)
        // Take the height these labels actually need instead of being
        // compressed by the TabView above. Without this the controls are the
        // only thing that gives at accessibility text sizes, and the buttons
        // truncate rather than wrap — "Start 3-day fr…" on the one control
        // that has to state the offer exactly. The pages absorb the loss
        // instead, which they can: each is its own ScrollView.
        .fixedSize(horizontal: false, vertical: true)
        .animation(.easeInOut, value: page)
        .animation(.easeInOut, value: solved)
    }

    @ViewBuilder
    private var premiumControls: some View {
        if store.isPremium {
            // A Restore on this page can land here already subscribed. The
            // offer above has swapped to its premium badge; a buy button for
            // a product they own would only have StoreKit refuse it.
            Button("Continue") { finish(exit: .premiumContinue) }
                .buttonStyle(.pillProminent)
        } else if !store.products.isEmpty {
            Button {
                buySelectedPlan()
            } label: {
                Group {
                    if store.purchaseInFlight {
                        ProgressView().tint(Theme.onInk)
                    } else {
                        Text(premiumCTATitle)
                    }
                }
            }
            // Regular size: with the escape demoted to a text link this is the
            // only pill on the page, so the full height reads as the one action
            // rather than as part of a wall of buttons.
            //
            // Gated on loaded products, like the sheet's purchase bar: when
            // the fetch failed the offer above is a retry card, and a disabled
            // pill under it was a dead button pretending to be the way out.
            .buttonStyle(.pillProminent)
            .disabled(store.purchaseInFlight || selectedPlan == nil)

            // No commitment line under the button here, unlike the sheet: on
            // this page the trial timeline sits directly above the CTA saying
            // the same two facts, so the caption was the third telling. The
            // sheet keeps its copy because its timeline scrolls away while
            // the CTA stays pinned.
        }

        // A quiet text link again — but only because the ✕ now exists. The
        // tonal-pill era was the fix for a page with no visible escape at all
        // (34% of reachers quit the app on it after the 2026-08-11 price
        // increase); the ✕ in the progress bar is the affordance those players
        // were actually scanning for, and with it in place a second full-width
        // exit button was competing with the one thing this page sells. If
        // quit-on-page climbs back toward that figure after release, the ✕
        // wasn't carrying the load — re-promote this, don't remove the ✕.
        //
        // "today's free puzzle", not "the free daily puzzle": this button
        // lands in the Mini, and the Daily Puzzle is a different, named thing
        // one row below it on Today. Naming the wrong one would be the first
        // promise the app breaks.
        // The vertical padding is the tap target: bare subheadline text is
        // ~20pt tall, and this is an exit — the one control that must never
        // take two tries. Same treatment as "Skip for now".
        Button("Continue with today's free puzzle") { finish(exit: .freeLink) }
            .font(.subheadline.weight(.semibold))
            .tint(.secondary)
            .padding(.vertical, Theme.Spacing.s)

        // Restore and the legal links are App Store review requirements
        // wherever a purchase can start — including here.
        HStack(spacing: Theme.Spacing.m) {
            Button("Restore") { Task { await store.restore() } }
            Link("Terms", destination: LegalLinks.terms)
            Link("Privacy", destination: LegalLinks.privacy)
        }
        .font(.caption)
        .tint(.secondary)
        .padding(.top, Theme.Spacing.xs)
    }

    /// The plan the page has selected, or nil while products are still loading.
    private var selectedPlan: Product? {
        store.products.first { $0.id == selectedPlanID }
    }

    /// The trial on the *selected* plan. Only yearly carries an introductory
    /// offer today, so picking monthly or lifetime correctly drops the trial
    /// language from the button and the line beneath it.
    private var trialText: String? {
        guard let plan = selectedPlan else { return nil }
        return store.introOfferText(for: plan)
    }

    /// The promise, aware of what the player just did — and leading with the
    /// trial when there is one.
    ///
    /// Dismissal telemetry put the median time on this page at four seconds:
    /// most players skip before reading anything below the headline, and the
    /// first "free" used to sit in the timeline, half below the fold. The one
    /// fact that changes a four-second reader's mind is that today costs
    /// nothing, so when a trial exists it gets the largest text on the screen.
    ///
    /// Keyed to the *selected* plan, like the subhead, the CTA and the
    /// timeline: monthly carries no introductory offer, and a headline
    /// promising free above a CTA that charges immediately is the one drift
    /// this page must never have. "Free for", not "the next N days are" — the
    /// duration string pluralises ("3 days", "1 month"), and only the former
    /// phrasing survives both.
    ///
    /// Someone who solved the first clue thirty seconds ago has already had the
    /// product demonstrated to them, so their line keeps the credit. Someone
    /// who skipped hasn't, so they get the offer cold. No solve tallies in
    /// either: the most they can have solved is the onboarding mini, and a
    /// tally of one reads as a tally of nothing.
    private var premiumHeadline: String {
        if let plan = selectedPlan, let offer = store.introOffer(for: plan) {
            // Non-breaking spaces keep the offer in one piece: left to itself
            // the headline wrapped as "free / for 3 days", splitting the only
            // phrase the four-second reader is here to catch. Glued, the line
            // breaks after "going —" and the offer lands whole.
            let freePhrase = "free for \(offer.duration)."
                .replacingOccurrences(of: " ", with: "\u{00a0}")
            return solved
                ? "You got the idea.\nKeep it going — \(freePhrase)"
                : "Everything free for \(offer.duration)."
        }
        return solved ? "You got the idea.\nKeep it going." : PremiumCopy.promise
    }

    /// Both shared with the sheet — see `PremiumOfferView.ctaTitle` and
    /// `commitmentText`. Driven by StoreKit, so neither can advertise a trial
    /// length or a price that isn't configured.
    private var premiumCTATitle: String {
        PremiumOfferView.ctaTitle(
            for: selectedPlan,
            store: store,
            puzzleCount: puzzleProvider.totalPuzzleCount
        )
    }

    // MARK: - First solve

    private func type(_ letter: Character) {
        guard let target = focus ?? nextBlank() else { return }
        if solveStartedAt == nil { solveStartedAt = Date() }
        entries[target] = letter
        focus = nextBlank(after: target)
        check()
    }

    private func deleteLetter() {
        // Backspace clears the focused cell if it holds a letter, otherwise it
        // steps back — the same rule the real grid uses.
        if let focus, entries[focus] != nil {
            entries[focus] = nil
            return
        }
        if let previous = MiniCrossword.firstSolveBlanks.last(where: { entries[$0] != nil }) {
            entries[previous] = nil
            focus = previous
        }
    }

    private func nextBlank(after point: MiniPoint? = nil) -> MiniPoint? {
        let blanks = MiniCrossword.firstSolveBlanks
        if let point, let i = blanks.firstIndex(of: point), i + 1 < blanks.count {
            return blanks[i + 1]
        }
        return blanks.first { entries[$0] == nil }
    }

    private func check() {
        let blanks = MiniCrossword.firstSolveBlanks
        guard blanks.allSatisfy({ entries[$0] != nil }) else { return }

        let correct = blanks.allSatisfy { point in
            if case .blank(let answer) = MiniCrossword.firstSolve[point.row][point.col] {
                return entries[point] == answer
            }
            return false
        }

        if correct {
            solved = true
            focus = nil
            if let solveStartedAt {
                // At least one second: a sub-second time renders as "0s",
                // which reads as a bug rather than a brag.
                solveSeconds = max(1, Int(Date().timeIntervalSince(solveStartedAt).rounded()))
            }
        } else {
            withAnimation(.spring(duration: 0.4, bounce: 0.5)) { wrongAttempts += 1 }
            // Clear and hand the first cell back rather than leaving the player
            // to work out which letter was wrong on a two-letter word.
            entries.removeAll()
            focus = blanks.first
        }
    }

    // MARK: - Flow

    private func advance() {
        withAnimation { page += 1 }
    }

    private func buySelectedPlan() {
        didTapPremiumCTA = true
        Task {
            guard let plan = selectedPlan else { return finish(exit: .noPlan) }
            // The plan is named the same way the sheet names it, so the two
            // surfaces' `plan` values are comparable rather than one of them
            // always reading "yearly" because that was all it could sell.
            let planName = PremiumOfferView.planTitle(plan).lowercased()
            // Logged here as well as on the paywall, because this screen is
            // where roughly nine in ten players meet the offer — measuring the
            // commit rate everywhere except the busiest surface would answer
            // the question for almost nobody.
            analytics.log(.paywallCTATapped(
                plan: planName,
                source: "onboarding",
                offersTrial: store.introOfferText(for: plan) != nil
            ))
            // StoreService emits `premium_purchased` for every grant, including
            // ones that land after this screen is gone — see its `report`.
            switch await store.purchase(plan, source: "onboarding") {
            case .purchased:
                finish(exit: .purchase)
            case .cancelled:
                // Nothing to explain, continue on in.
                finish(exit: .afterCancel)
            case .failed(let reason):
                analytics.log(.purchaseFailed(plan: planName, source: "onboarding", reason: reason))
            case .pending:
                break
            }
            // Failure/pending: stay here so the notice alert can present; the
            // free-puzzle button below still exits.
        }
    }

    private func logStep(_ index: Int) {
        guard stepNames.indices.contains(index) else { return }
        analytics.log(.onboardingStep(index: index, name: stepNames[index]))
    }

    /// `exit` names what took the player off the offer page — only read when
    /// the offer page was reached, but every caller passes one so the label
    /// can't be forgotten when a new exit is added.
    private func finish(exit: PaywallExit) {
        nameFocused = false
        // Only when the offer page was actually reached — `finish()` is also
        // how a player who never got there would leave, if that ever happens.
        if let premiumArrivedAt {
            analytics.log(.paywallDismissed(
                source: "onboarding",
                secondsOnScreen: Int(Date().timeIntervalSince(premiumArrivedAt).rounded()),
                ctaTapped: didTapPremiumCTA,
                exit: exit
            ))
            self.premiumArrivedAt = nil
        }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        profile.username = trimmed.isEmpty ? "Friend" : trimmed
        // Carries the solve outcome so completion can be split by it without
        // joining two events downstream.
        analytics.log(.onboardingCompleted(solvedFirstClue: solved))
        onFinish()
    }
}

// MARK: - Staggered entrance

/// Internal rather than file-private so `PremiumOfferView` can stagger its own
/// blocks the way this file's pages do — the offer moved out, the page
/// treatment around it did not.
struct Entrance: ViewModifier {
    let active: Bool
    let delay: Double
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .opacity(active ? 1 : 0)
            .offset(y: reduceMotion ? 0 : (active ? 0 : 18))
            .animation(
                reduceMotion
                    ? .easeOut(duration: 0.25)
                    : .spring(duration: 0.55).delay(active ? delay : 0),
                value: active
            )
    }
}

extension View {
    func entrance(active: Bool, delay: Double = 0, reduceMotion: Bool) -> some View {
        modifier(Entrance(active: active, delay: delay, reduceMotion: reduceMotion))
    }
}

// MARK: - Wrong-answer shake

/// A single damped wobble, driven by an incrementing attempt count so repeated
/// wrong answers each get their own shake.
private struct Shake: GeometryEffect {
    var travel: CGFloat
    var animatableData: CGFloat {
        get { travel }
        set { travel = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(
            CGAffineTransform(translationX: 9 * sin(travel * .pi * 3), y: 0)
        )
    }
}
