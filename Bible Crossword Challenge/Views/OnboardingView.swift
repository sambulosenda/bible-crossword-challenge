//
//  OnboardingView.swift
//  Bible Crossword Challenge
//
//  First-run experience. It opens on the first solve, under the welcome
//  headline (design canvas, 2026-10-25): a player is solving on screen one.
//  The welcome page that came before it went — finishing a puzzle on day 0 is
//  the strongest return signal the app has, and a page of brand ahead of it
//  was one more tap between a new player and the puzzle.
//
//    1  First solve two letters, then a verse — the whole product in ten seconds
//    2  Celebration the payoff, with their own numbers — the emotional peak
//                   the offer used to arrive without
//    3  Premium     the upsell, dismissible; the daily puzzle is always free
//
//  There is no name page any more (removed 2026-10-24). In the 60 days before,
//  13 of ~650 new players ever sent a challenge — the one feature a name is
//  for — while the page itself lost about 2% of the players who reached it.
//  The name is asked at first challenge instead (`CompletionView`'s name
//  prompt), the moment a player has a reason to give it; until then the
//  profile keeps the placeholder "Friend".
//
//  The celebration sits directly before the offer: the pattern the
//  top-converting onboardings share (a stats moment between the demonstrated
//  value and the sell), sized honestly for a two-letter solve.
//
//  The reminder page sits between the celebration and the offer (2026-10-25).
//  An earlier one asked before the app had proved anything — of 102 players
//  who answered it in the 30 days to 2026-08-24, 86 tapped "Not now" — and was
//  cut that day. Without it opt-ins fell from ~25% of installs to ~3%: the
//  later asks (`ReminderAsk`) reach far fewer players. It's back after the
//  first solve, the warmest moment the flow has. Decliners keep the later
//  paths.
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
    /// Starts on the first solve: there is no page 0 any more. The tags keep
    /// their numbers so `step_index` in analytics stays comparable.
    @State private var page = 1
    @State private var didLogPaywallOpen = false
    @State private var didLogFirstSolve = false

    @Environment(\.notifications) private var notifications
    @AppStorage("remindersEnabled") private var remindersEnabled = false
    @AppStorage("reminderMinutes") private var reminderMinutes = ReminderTime.defaultMinutes
    @AppStorage("reminderAskLastDay") private var reminderAskLastDay = 0.0
    /// Whether this run shows the reminder page: only where iOS has never
    /// asked and reminders are off — a reinstall that already granted skips
    /// it. Decided once, on appear, so the pages can't change under a swipe.
    @State private var asksReminder = false
    @State private var didLogReminderAsk = false
    @State private var reminderWorking = false

    // Dismissal telemetry for the offer page, mirroring `PaywallView`'s. Every
    // exit from onboarding goes through `finish()`, so that is where the event
    // fires; what's tracked here is when the page arrived and whether the buy
    // button was pressed. A quit-the-app exit emits nothing — the 34% who
    // leave that way stay visible only as an absent `onboarding_completed`.
    @State private var premiumArrivedAt: Date?
    @State private var didTapPremiumCTA = false

    /// Which plan the premium page has selected. Lives here rather than in
    /// `PremiumOfferView` because the CTA that buys it is down in `controls`,
    /// outside the TabView the offer is a page of.
    @State private var selectedPlanID = StoreService.yearlyID

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

    private let reminderPage = 3
    private let lastPage = 4

    /// Analytics labels, indexed by page number. "welcome" is no longer
    /// logged (2026-10-25): funnels start at first_solve. Labels are stable
    /// across the name page's removal; `step_index` for celebration and
    /// premium dropped by one on 2026-10-24 and premium's rose by one again
    /// with the reminder page on 2026-10-25, so funnels should key on the name.
    private let stepNames = ["welcome", "first_solve", "celebration", "reminder", "premium"]

    var body: some View {
        VStack(spacing: 0) {
            progressBar

            TabView(selection: $page) {
                firstSolvePage.tag(1)
                // Solvers only (2026-10-25): a skipper's version — a tick,
                // "You're all set." and two library counts — celebrated
                // nothing, and was one more tap between a hesitant player and
                // the app. Out of the pager too, so a swipe can't reach it.
                if solved {
                    celebrationPage.tag(2)
                }
                if asksReminder {
                    reminderAskPage.tag(reminderPage)
                }
                premiumPage.tag(lastPage)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut, value: page)

            controls
        }
        .background(canvas)
        .sensoryFeedback(.selection, trigger: page)
        .sensoryFeedback(.success, trigger: solved)
        .sensoryFeedback(.error, trigger: wrongAttempts)
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
            if newPage == reminderPage && !didLogReminderAsk {
                didLogReminderAsk = true
                // Spends the day's ask, so the first puzzle's completion row
                // doesn't ask again in the same sitting.
                reminderAskLastDay = Calendar.current.startOfDay(for: Date()).timeIntervalSinceReferenceDate
                ReminderAskSession.asked = true
                analytics.log(.reminderAskShown(source: ReminderAsk.Surface.onboarding.rawValue))
            }
            // The premium page is a paywall view like any other — count it so
            // onboarding conversion can be compared against in-app sources.
            if newPage == lastPage && !didLogPaywallOpen {
                didLogPaywallOpen = true
                analytics.log(.paywallOpened(source: PaywallSource.onboarding.rawValue))
            }
            // First arrival only, like the open above: swiping back to the
            // celebration and returning shouldn't reset the clock.
            if newPage == lastPage && premiumArrivedAt == nil {
                premiumArrivedAt = Date()
            }
        }
        .onAppear {
            logStep(page)
        }
        .task {
            await notifications.refreshStatus()
            asksReminder = ReminderAsk.decide(.onboarding, ReminderAsk.State(
                remindersEnabled: remindersEnabled,
                permissionUndetermined: notifications.authorizationStatus == .notDetermined,
                totalCompleted: profile.totalPuzzlesCompleted,
                currentStreak: profile.currentStreak,
                completionAsksShown: 0,
                streakAskShown: false,
                lastAskDay: reminderAskLastDay == 0 ? nil : Date(timeIntervalSinceReferenceDate: reminderAskLastDay),
                askedThisSession: ReminderAskSession.asked
            ))
        }
        .purchaseNoticeAlert(store)
    }

    /// Plain paper on the setup pages; a warm gold wash only as the offer
    /// arrives. The setup pages used a 10% accent wash too, and cool blue over
    /// warm paper read as a grey smudge at the top of every screen rather than
    /// as light.
    private var canvas: some View {
        ZStack(alignment: .top) {
            Theme.background
            RadialGradient(
                colors: [page == lastPage ? Theme.badgeRim.opacity(0.10) : .clear, .clear],
                center: .top,
                startRadius: 0,
                endRadius: 380
            )
            .animation(.easeInOut(duration: 0.5), value: page)
        }
        .ignoresSafeArea()
    }

    /// The bar over the pages: on the solve page, a quiet Skip on the
    /// trailing edge (2026-10-25) — it sat between the grid and the keys,
    /// where a thumb typing the answer could catch it. On the offer, the ✕
    /// and Restore of `offerBar`. Elsewhere nothing: one step needs no
    /// progress segments.
    private var progressBar: some View {
        let onOffer = page == lastPage
        return Group {
            if onOffer {
                offerBar
                    .transition(.opacity)
            } else {
                HStack {
                    Spacer(minLength: 0)
                    if page == 1 && !solved {
                        // Never trap a player on a puzzle; quiet, so it
                        // doesn't compete with the clue.
                        Button("Skip") { advance() }
                            .font(.body.weight(.semibold))
                            .tint(.secondary)
                            .frame(minHeight: 44)
                            .transition(.opacity)
                    }
                }
                .frame(height: 44)
            }
        }
        .padding(.horizontal, onOffer ? Theme.Spacing.m : Theme.Spacing.l)
        .padding(.top, Theme.Spacing.s)
        .animation(.spring(duration: 0.35), value: page)
        .animation(.easeInOut, value: solved)
        .accessibilityElement(children: .contain)
    }

    /// The offer page's bar, as the paywall sheet's (design canvas,
    /// 2026-10-24): ✕ on the leading edge, Restore on the trailing one, each
    /// in glass. No progress segments here — setup is over by this page, and
    /// they went gold on it to say so, which the canvas doesn't need to.
    ///
    /// The ✕ is the paywall escape every player scans for. After the
    /// 2026-08-11 price increase, with no visible one, a third of everyone
    /// who reached this page quit the app on the spot (34% of reachers left
    /// without ever playing, up from 6%). It exits to the free daily exactly
    /// like the link under the button. Restore moved up from that link's
    /// row, where it read as legal small print.
    private var offerBar: some View {
        HStack {
            Button {
                finish(exit: .close)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .offerBarGlass(in: .circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close and continue with the free puzzle")

            Spacer(minLength: 0)

            Button {
                Task { await store.restore() }
            } label: {
                Text("Restore")
                    .font(.body)
                    .padding(.horizontal, Theme.Spacing.m)
                    .frame(height: 44)
                    .offerBarGlass(in: .capsule)
            }
            .buttonStyle(.plain)
            .disabled(store.purchaseInFlight)
        }
        .foregroundStyle(.primary)
    }

    // MARK: - Pages

    private var firstSolvePage: some View {
        let active = page == 1
        return pageFrame(spacing: Theme.Spacing.l) {
            // The welcome, on the page where the playing starts (2026-10-25):
            // what the app is, in a line, over the clue that shows it. It
            // folds away once the word is solved — the verse needs the room,
            // and by then the puzzle has said it better.
            if !solved {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    Text("Bible Crossword")
                        .kicker()
                    Text("Know the Word,\none clue at a time.")
                        .font(.scripture(.largeTitle, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .entrance(active: active, delay: 0, reduceMotion: reduceMotion)
                .transition(.opacity)
            }

            // Two spacers to the one below the grid: the clue and grid sit in
            // the lower part of the space above the keypad, near the thumb
            // and the keys they answer to, instead of floating mid-screen
            // with a dead band under them.
            Spacer(minLength: 0)
            Spacer(minLength: 0)

            VStack(spacing: Theme.Spacing.xs) {
                Text(solved ? "1 Down · Solved" : "1 Down · try it")
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
                activeWord: solved ? [] : MiniCrossword.firstSolveWord,
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
                // The game's keys on the game's bed, so the first keyboard a
                // player meets is the one they'll solve every puzzle with.
                // Rounded here: the page's controls sit under it, where the
                // game's bed runs to the screen's edge.
                LetterKeyboardView(onLetter: type(_:), onDelete: deleteLetter, onBed: true)
                    .background(Theme.keyboardBed, in: .rect(cornerRadius: Theme.cornerRadius, style: .continuous))
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
        // every page up front, so an appear-time write would land on an
        // unsettled tree. The flow opens on this page, so it takes focus
        // once the tree has settled, and again on a swipe back.
        .onChange(of: page) { _, new in solveFocused = (new == 1) }
        .task {
            try? await Task.sleep(for: .milliseconds(400))
            if page == 1 { solveFocused = true }
        }
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

    /// The peak before the ask: the player's own solve, over their numbers.
    ///
    /// The solve page's inline verse card is the *product's* payoff (the verse
    /// behind the answer); this page is the *player's* (what they did, what's
    /// waiting). Splitting them keeps each small enough to land — and puts a
    /// high point directly under the offer, which used to arrive off the back
    /// of a keyboard.
    ///
    /// Solvers only — a skipper goes straight on (see the pager in `body`).
    private var celebrationPage: some View {
        let active = page == 2
        return pageFrame(spacing: Theme.Spacing.xl, alignment: .upperThird) {
            // The mark is the grid the player just filled (see CelebrationBadge:
            // a tick says "succeeded", the grid says what). No gold rim here:
            // gold is the offer bar's signal on the next page.
            //
            // Ink, not the accent: a saturated system-blue disc was the
            // loudest object in the flow, on a page of warm paper and serif.
            // Ink is the colour of the one button on every page, so the badge
            // reads as part of the same object family rather than a stock icon.
            CelebrationBadge(grid: ["GRACE", "..R..", "..K.."], confetti: "puzzle_complete", tint: Theme.ink, markTint: Theme.onInk, size: 96, showsRim: false)
            .entrance(active: active, delay: 0.05, reduceMotion: reduceMotion)

            // No kicker: "First solve" over "Well done" said the same thing
            // twice, under a badge that already says it a third time.
            Text(celebrationHeadline)
                .font(.scripture(.largeTitle, weight: .semibold))
                .multilineTextAlignment(.center)
                .entrance(active: active, delay: 0.14, reduceMotion: reduceMotion)

            celebrationTiles
                .entrance(active: active, delay: 0.30, reduceMotion: reduceMotion)
        }
    }

    /// Greets by name only when one already exists — a player re-running
    /// onboarding after naming themselves. New players are still "Friend",
    /// and "Well done, Friend." reads as a form letter, so they get no suffix.
    private var celebrationHeadline: String {
        let trimmed = profile.username.trimmingCharacters(in: .whitespaces)
        let suffix = trimmed.isEmpty || trimmed == ChallengeService.placeholderName ? "" : ", \(trimmed)"
        return "Well done\(suffix)."
    }

    /// Two tiles, Duolingo's stats-moment pattern in this app's own units.
    /// The counts come from the bundle, so neither can go stale.
    ///
    /// The same pair for solvers and skippers. Solvers used to get "Day 1 ·
    /// Your streak" on the left, but the streak only starts with the first
    /// daily puzzle, so seconds later Today and Profile both said 0 — the
    /// first number the app gave a player was one it then took back. The
    /// solve is already celebrated by the badge and the headline above.
    ///
    /// Set as type on the paper, split by a hairline, not boxed: two white
    /// cards were chrome around two numbers, and made the page read as a
    /// template under the badge.
    private var celebrationTiles: some View {
        HStack(spacing: Theme.Spacing.m) {
            statTile(value: "\(puzzleProvider.packs.count)", label: "Themed packs")
            Divider()
            statTile(value: "\(puzzleProvider.totalPuzzleCount)", label: "Puzzles waiting")
        }
        // The divider takes the height of the two columns, not the page's.
        .fixedSize(horizontal: false, vertical: true)
    }

    private func statTile(value: String, label: String) -> some View {
        VStack(spacing: Theme.Spacing.xs) {
            Text(value)
                .font(.scripture(.title, weight: .semibold))
            Text(label)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
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
    /// The reminder ask, between the celebration and the offer. A bell where
    /// the celebration had the solved word, then the notification itself, so
    /// the player agrees to a thing they've seen rather than to
    /// "notifications". The system prompt only follows "Remind me"; "Not now"
    /// and a swipe both go on to the offer.
    private var reminderAskPage: some View {
        let active = page == reminderPage
        return pageFrame(spacing: Theme.Spacing.xl, alignment: .upperThird) {
            CelebrationBadge(systemImage: "bell.fill", tint: Theme.ink, markTint: Theme.onInk, size: 96, showsRim: false)
                .entrance(active: active, delay: 0.05, reduceMotion: reduceMotion)

            VStack(spacing: Theme.Spacing.s + 2) {
                // Wraps rather than truncating: on a 17e it measured one
                // word wider than the column.
                Text("Same time tomorrow?")
                    .font(.scripture(.largeTitle, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text("One nudge a day, when tomorrow's puzzle is ready. Change the time or turn it off in Settings.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.center)
            .entrance(active: active, delay: 0.14, reduceMotion: reduceMotion)

            VStack(spacing: Theme.Spacing.m) {
                NotificationPreviewCard()
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Example reminder: Today's puzzle is ready.")
                // The time, picked here rather than taken as given (2026-10-25):
                // a reminder at the wrong hour is the one most often turned
                // off. As the return-day sheet sets it.
                HStack {
                    Text("Every day at")
                        .font(.body)
                    Spacer()
                    DatePicker("Reminder time", selection: reminderTime, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                }
                .padding(.horizontal, Theme.Spacing.m)
                .padding(.vertical, Theme.Spacing.s)
                .elevatedCard()
            }
            .entrance(active: active, delay: 0.24, reduceMotion: reduceMotion)
        }
        // A first sitting, so "now" is the hour this player plays — see
        // `seedSuggestionIfUnset`.
        .onAppear { ReminderTime.seedSuggestionIfUnset() }
    }

    private var reminderTime: Binding<Date> {
        Binding(
            get: { ReminderTime.date(fromMinutes: reminderMinutes) },
            set: { reminderMinutes = ReminderTime.minutes(from: $0) }
        )
    }

    private var premiumPage: some View {
        let active = page == lastPage
        // The whole offer when it fits the page; without the tiles, in the
        // usual scrolling frame, when it doesn't — a 667pt iPhone SE otherwise
        // hid the prices and the timeline behind the purchase button.
        // `ViewThatFits` decides per layout pass: nothing to measure or latch.
        //
        // Top-anchored, unlike the other pages: the offer changes height when
        // the plan does (monthly has no timeline and a one-line headline), and
        // centred, every tap on a plan card moved the tiles and the headline.
        return ViewThatFits(in: .vertical) {
            // 20pt sides, the app's edge and the sheet's: at 24 the headline
            // beside the fan broke into three lines and the page fell back to
            // the layout without it (2026-10-24).
            premiumOffer(compact: false, active: active)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, Theme.Spacing.m + Theme.Spacing.xs)
                .padding(.vertical, Theme.Spacing.l)
            // The sheet's middle size: the chip and a smaller fan kept. On a
            // 6.1" phone the full page missed by a few dozen points and the
            // compact one left a band of empty paper above the buy button.
            premiumOffer(compact: true, keepsSmallHero: true, active: active)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, Theme.Spacing.m + Theme.Spacing.xs)
                // The bar above and the controls below already space it: on
                // a 17e this layout measured 1.7pt over with 12pt here.
                .padding(.top, Theme.Spacing.s)
                .padding(.bottom, Theme.Spacing.xs)
            // Top-anchored like the full layout above: centred, the compact
            // offer left an empty band over the headline on a 6.1" phone.
            pageFrame(spacing: Theme.Spacing.l, alignment: .top) {
                premiumOffer(compact: true, active: active)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func premiumOffer(compact: Bool, keepsSmallHero: Bool = false, active: Bool) -> some View {
        PremiumOfferView(
            headline: premiumHeadline,
            selectedID: $selectedPlanID,
            entranceActive: active,
            compact: compact,
            keepsSmallHero: keepsSmallHero
        )
    }

    // MARK: - Building blocks

    /// Every page shares one frame: scrollable (so a long clue or a large text
    /// size can never clip), centred, with the same gutters.
    private func pageFrame<Content: View>(
        spacing: CGFloat,
        alignment: Alignment = .center,
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
                    .frame(minHeight: geo.size.height, alignment: alignment)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
        }
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(spacing: Theme.Spacing.s) {
            switch page {
            case 1:
                // Skip is in the bar above while unsolved — see `progressBar`.
                if solved {
                    Button("Continue") { advance() }
                        .buttonStyle(.pillProminent)
                }

            case lastPage:
                premiumControls

            case 2:
                // Momentum, not procedure: "Continue" reads as one more form
                // step, and this is the one page whose only job is momentum.
                Button("Keep going") { advance() }
                    .buttonStyle(.pillProminent)

            case reminderPage:
                Button {
                    enableReminder()
                } label: {
                    Group {
                        if reminderWorking {
                            ProgressView().tint(Theme.onInk)
                        } else {
                            Text("Remind me")
                        }
                    }
                }
                .buttonStyle(.pillProminent)
                .disabled(reminderWorking)
                .accessibilityHint("Asks for notification permission")
                // As quiet as the solve page's Skip: declining costs nothing, and the
                // offer is the next page either way.
                Button("Not now") {
                    analytics.log(.reminderDeclined(source: ReminderAsk.Surface.onboarding.rawValue))
                    advance()
                }
                .font(.subheadline.weight(.semibold))
                .tint(.secondary)
                .padding(.vertical, Theme.Spacing.s)
                .disabled(reminderWorking)

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
                        // Wraps rather than truncates at accessibility sizes.
                        Text(premiumCTATitle)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
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

            // The commitment line, always: trial length, the price after it,
            // and that it renews. The trial timeline used to carry this when
            // there was a trial; it was removed 2026-10-13, so the line is now
            // the page's only statement of it — and App Review's requirement.
            if let plan = selectedPlan,
               let terms = PremiumOfferView.commitmentText(for: plan, store: store) {
                Text(terms)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
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
        // "Not now" first, so it reads as declining the offer rather than as
        // a second way forward (2026-10-24).
        //
        // "today's free puzzle", not "the free daily puzzle": this button
        // lands in the Mini, and the Daily Puzzle is a different, named thing
        // one row below it on Today. Naming the wrong one would be the first
        // promise the app breaks.
        // The vertical padding is the tap target: bare subheadline text is
        // ~20pt tall, and this is an exit — the one control that must never
        // take two tries. Same treatment as the solve page's Skip.
        Button("Not now, play today's free puzzle") { finish(exit: .freeLink) }
            .font(.subheadline.weight(.semibold))
            .tint(.secondary)
            .padding(.vertical, Theme.Spacing.s)

        // Restore and the legal links are App Store review requirements
        // wherever a purchase can start — including here. Restore is in the
        // bar above (`offerBar`), as on the sheet.
        HStack(spacing: Theme.Spacing.m) {
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

    /// The line under the page's fixed headline, aware of what the player
    /// just did — and leading with the trial when there is one.
    ///
    /// Dismissal telemetry put the median time on this page at four seconds:
    /// most players skip before reading anything below the headline, and the
    /// first "free" used to sit in the timeline, half below the fold. The one
    /// fact that changes a four-second reader's mind is that today costs
    /// nothing, so when a trial exists it's the first line under the
    /// headline. (It was the headline itself until 2026-10-24, when the page
    /// took the canvas's fixed one.)
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
            // Non-breaking spaces keep the offer in one piece if the line
            // wraps: "free / for 3 days" split the only phrase the
            // four-second reader is here to catch.
            let freePhrase = "free for \(offer.duration)."
                .replacingOccurrences(of: " ", with: "\u{00a0}")
            return solved
                ? "Keep it going —\n\(freePhrase)"
                : "Everything free for \(offer.duration)."
        }
        // Without a trial there's no offer to lead with: the standing line
        // about what Premium is for (see `PremiumOfferView.subhead`).
        return PremiumCopy.promise
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
        var next = page + 1
        // Past the celebration for a skipper, and past the reminder page's
        // tag when this run doesn't show it.
        if next == 2 && !solved { next += 1 }
        if next == reminderPage && !asksReminder { next = lastPage }
        withAnimation { page = next }
    }

    private func enableReminder() {
        reminderWorking = true
        Task {
            let granted = await ReminderOptIn.enable(
                source: ReminderAsk.Surface.onboarding.rawValue, profile: profile,
                notifications: notifications, analytics: analytics,
                minutes: reminderMinutes
            )
            if granted { remindersEnabled = true }
            reminderWorking = false
            advance()
        }
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
        // The username is left alone: a new profile is already "Friend", and
        // the first challenge asks for a real name when one is needed.
        // Carries the solve outcome so completion can be split by it without
        // joining two events downstream.
        analytics.log(.onboardingCompleted(solvedFirstClue: solved))
        onFinish()
    }
}

// MARK: - Upper-third anchor

extension VerticalAlignment {
    /// A third of the way down a view. Aligning a page's content to the
    /// page's upper third leaves one part of the spare height above it and two
    /// below: the composition statement screens use, where dead-centre
    /// content floats with an equal band of empty paper either side.
    /// `nonisolated`: called from layout, like `ClueBarView`'s `ClueText`.
    nonisolated enum UpperThird: AlignmentID {
        static func defaultValue(in d: ViewDimensions) -> CGFloat { d.height / 3 }
    }
    static let upperThird = VerticalAlignment(UpperThird.self)
}

extension Alignment {
    static let upperThird = Alignment(horizontal: .center, vertical: .upperThird)
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
/// `nonisolated`: SwiftUI may evaluate an effect on its async render thread,
/// and under the target's main-actor default a Swift 6 isolation check would
/// trap there (as `Theme.adaptive`'s colour provider did).
nonisolated private struct Shake: GeometryEffect {
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

private extension View {
    /// The bar buttons' glass on iOS 26, as the sheet's toolbar draws them;
    /// a material before it.
    @ViewBuilder
    func offerBarGlass<S: Shape>(in shape: S) -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(.regular.interactive(), in: shape)
        } else {
            background(.ultraThinMaterial, in: shape)
        }
    }
}
