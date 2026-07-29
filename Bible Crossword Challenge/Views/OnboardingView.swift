//
//  OnboardingView.swift
//  Bible Crossword Challenge
//
//  First-run experience. Five pages, but only the first two are "intro" — the
//  rest are setup asks, each one earned by what came before:
//
//    0  Welcome     the brand, in the app's own vocabulary (a crossword)
//    1  First solve two letters, then a verse — the whole product in ten seconds
//    2  Name        asked once the player has something to be named for
//    3  Reminders   primed with what the notification will actually look like
//    4  Premium     the upsell, dismissible; the daily puzzle is always free
//
//  Everything sits on the app's paper canvas with serif hero titles, so the
//  first screen a player sees is the same app as the hundredth.
//
//  Each page's content animates in (staggered fade + rise) when it becomes
//  active, and all motion respects the Reduce Motion accessibility setting.
//

import SwiftUI
import StoreKit

struct OnboardingView: View {
    @Bindable var profile: PlayerProfile
    var onFinish: () -> Void

    @Environment(StoreService.self) private var store
    @Environment(\.analytics) private var analytics
    @Environment(\.notifications) private var notifications
    @Environment(\.puzzleProvider) private var puzzleProvider
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @AppStorage("remindersEnabled") private var remindersEnabled = false
    @AppStorage("reminderMinutes") private var reminderMinutes = ReminderTime.defaultMinutes

    @State private var page = 0
    @State private var didLogPaywallOpen = false
    @State private var didLogFirstSolve = false
    @FocusState private var nameFocused: Bool

    /// Typed separately from `profile.username` so the field can start empty:
    /// a new profile is created with the placeholder name "Friend", and showing
    /// that as prefilled text makes the player delete it before they can type.
    @State private var name = ""

    // First-solve state.
    @State private var entries: [MiniPoint: Character] = [:]
    @State private var focus: MiniPoint? = MiniCrossword.firstSolveBlanks.first
    @State private var solved = false
    @State private var wrongAttempts = 0

    private let lastPage = 4

    /// Analytics labels for the five pages, indexed by page number.
    private let stepNames = ["welcome", "first_solve", "name", "reminders", "premium"]

    private var reminderTime: Binding<Date> {
        Binding(
            get: { ReminderTime.date(fromMinutes: reminderMinutes) },
            set: { reminderMinutes = ReminderTime.minutes(from: $0) }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            progressBar

            TabView(selection: $page) {
                welcomePage.tag(0)
                firstSolvePage.tag(1)
                namePage.tag(2)
                remindersPage.tag(3)
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
                analytics.log(.paywallOpened(source: "onboarding"))
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

    /// Five ink segments instead of dots: it reads as progress rather than
    /// decoration, and it tells the player up front how short this is.
    private var progressBar: some View {
        HStack(spacing: 5) {
            ForEach(0...lastPage, id: \.self) { i in
                Capsule()
                    .fill(i <= page ? Theme.ink : Color.primary.opacity(0.10))
                    .frame(height: 4)
            }
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.top, Theme.Spacing.s)
        .animation(.spring(duration: 0.35), value: page)
        .accessibilityElement()
        .accessibilityLabel("Step \(page + 1) of \(lastPage + 1)")
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
            .entrance(active: active, delay: 0.12, reduceMotion: reduceMotion)

            // Keeps the keypad — and the verse that replaces it — down by the
            // thumb rather than floating in the middle of the page.
            Spacer(minLength: Theme.Spacing.l)

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
            } else {
                LetterKeyboardView(onLetter: type(_:), onDelete: deleteLetter)
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.3) : .spring(duration: 0.55, bounce: 0.15), value: solved)
    }

    /// The payoff. Same shape as the verse card on the completion screen, so a
    /// player meets the app's one moment of ceremony before their first puzzle.
    private var verseReveal: some View {
        VStack(spacing: Theme.Spacing.s) {
            CelebrationBadge(systemImage: "checkmark", confetti: "puzzle_complete", size: 64)

            Text("That’s the whole game.")
                .font(.headline)

            Text("“By faith Noah, when warned about things not yet seen, in godly fear built an ark to save his family.”")
                .font(.scripture(.subheadline))
                .lineSpacing(3)
                .multilineTextAlignment(.center)

            // Headline weight, not footnote: the accent only clears the
            // contrast bar on paper at large-text sizes.
            Text("Hebrews 11:7")
                .font(.headline)
                .foregroundStyle(Theme.accent)
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity)
        .background(Theme.accent.opacity(0.10), in: .rect(cornerRadius: Theme.cornerRadius, style: .continuous))
    }

    private var namePage: some View {
        let active = page == 2
        return pageFrame(spacing: Theme.Spacing.l) {
            VStack(spacing: Theme.Spacing.m) {
                Text("Nice solve")
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

    private var remindersPage: some View {
        let active = page == 3
        return pageFrame(spacing: Theme.Spacing.l) {
            VStack(spacing: Theme.Spacing.m) {
                Text("Keep the streak")
                    .kicker()
                    .entrance(active: active, delay: 0.05, reduceMotion: reduceMotion)
                Text("One nudge a day.\nThat’s all it takes.")
                    .font(.scripture(.largeTitle, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .entrance(active: active, delay: 0.10, reduceMotion: reduceMotion)
            }

            // Showing the actual notification is the priming: the player agrees
            // to a thing they have already seen, not to "notifications".
            notificationPreview
                .entrance(active: active, delay: 0.18, reduceMotion: reduceMotion)

            HStack {
                Text("Remind me at")
                    .font(.body)
                Spacer()
                DatePicker("Remind me at", selection: reminderTime, displayedComponents: .hourAndMinute)
                    .labelsHidden()
            }
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.vertical, Theme.Spacing.s)
            .elevatedCard()
            .entrance(active: active, delay: 0.24, reduceMotion: reduceMotion)
        }
    }

    private var premiumPage: some View {
        let active = page == 4
        return pageFrame(spacing: Theme.Spacing.l) {
            VStack(spacing: Theme.Spacing.m) {
                Text("Premium")
                    .kicker()
                    .entrance(active: active, delay: 0.05, reduceMotion: reduceMotion)
                Text("Play the whole\nlibrary.")
                    .font(.scripture(.largeTitle, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .entrance(active: active, delay: 0.10, reduceMotion: reduceMotion)
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                // Counted from the bundle, like the main paywall: a written
                // number goes stale the moment the puzzle bank grows.
                benefit("book.pages", "Every puzzle pack", "\(puzzleProvider.totalPuzzleCount) puzzles today, and every pack we add.")
                benefit("books.vertical", "The whole library", "Replay any puzzle, as often as you like.")
                benefit("lightbulb.max", "Unlimited hints", "Never stuck on one clue.")
                benefit("nosign", "No ads, ever", "Just you and the grid.")
            }
            .padding(Theme.Spacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .elevatedCard()
            .entrance(active: active, delay: 0.18, reduceMotion: reduceMotion)
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
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, Theme.Spacing.l)
                    .padding(.vertical, Theme.Spacing.l)
                    .frame(minHeight: geo.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
        }
    }

    private func benefit(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 34, height: 34)
                .background(Theme.accent.opacity(0.12), in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    /// A mock of the reminder the player is being asked to allow.
    private var notificationPreview: some View {
        HStack(spacing: Theme.Spacing.m) {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color(red: 0.29, green: 0.47, blue: 0.96),
                             Color(red: 0.13, green: 0.25, blue: 0.78)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
                .frame(width: 38, height: 38)
                .overlay {
                    Image(systemName: "book.closed.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                }

            VStack(alignment: .leading, spacing: 1) {
                Text("Bible Crossword")
                    .font(.footnote.weight(.semibold))
                Text("Today’s puzzle is ready — keep your streak alive.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Text("now")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(Theme.Spacing.m)
        .elevatedCard(cornerRadius: 18)
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

            case 3:
                Button("Enable reminders") { enableReminders() }
                    .buttonStyle(.pillProminent)
                Button("Not now") { advance() }
                    .font(.subheadline.weight(.semibold))
                    .tint(.secondary)
                    .padding(.top, Theme.Spacing.xs)

            case lastPage:
                premiumControls

            default:
                Button("Continue") { advance() }
                    .buttonStyle(.pillProminent)
            }
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.top, Theme.Spacing.m)
        .padding(.bottom, Theme.Spacing.s)
        .animation(.easeInOut, value: page)
        .animation(.easeInOut, value: solved)
    }

    @ViewBuilder
    private var premiumControls: some View {
        Button {
            buyYearly()
        } label: {
            Group {
                if store.purchaseInFlight {
                    ProgressView().tint(Theme.onInk)
                } else {
                    Text(trialText == nil ? "Unlock Premium" : "Start Free Trial")
                }
            }
        }
        .buttonStyle(.pillProminent)
        .disabled(store.purchaseInFlight || store.yearly == nil)

        Text(priceLine)
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)

        // Quiet, but never hidden: the daily puzzle really is free, and a
        // paywall whose exit is hard to find is a rejection risk.
        Button("Continue with the free daily puzzle") { finish() }
            .font(.subheadline.weight(.semibold))
            .tint(.primary)
            .padding(.top, Theme.Spacing.xs)

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

    private var trialText: String? {
        guard let yearly = store.yearly else { return nil }
        return store.introOfferText(for: yearly)
    }

    private var priceLine: String {
        guard let yearly = store.yearly else { return "" }
        let period = store.periodText(for: yearly) ?? ""
        if let trialText {
            return "\(trialText), then \(yearly.displayPrice)\(period). Cancel anytime."
        }
        return "\(yearly.displayPrice)\(period). Cancel anytime."
    }

    // MARK: - First solve

    private func type(_ letter: Character) {
        guard let target = focus ?? nextBlank() else { return }
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

    private func buyYearly() {
        Task {
            guard let yearly = store.yearly else { return finish() }
            switch await store.purchase(yearly) {
            case .purchased(let isTrial):
                analytics.log(.premiumPurchased(
                    plan: "yearly",
                    source: "onboarding",
                    isTrial: isTrial,
                    amount: store.amount(for: yearly)
                ))
                finish()
            case .cancelled:
                // Nothing to explain, continue on in.
                finish()
            case .failed(let reason):
                analytics.log(.purchaseFailed(plan: "yearly", source: "onboarding", reason: reason))
            case .pending:
                break
            }
            // Failure/pending: stay here so the notice alert can present; the
            // free-puzzle button below still exits.
        }
    }

    private func enableReminders() {
        Task {
            let granted = await notifications.requestAuthorization()
            analytics.log(.notificationPermission(granted: granted))
            if granted {
                remindersEnabled = true
                analytics.log(.reminderSettingChanged(enabled: true))
                await notifications.reschedule(for: profile, enabled: true, minutes: reminderMinutes)
            }
            advance()
        }
    }

    private func logStep(_ index: Int) {
        guard stepNames.indices.contains(index) else { return }
        analytics.log(.onboardingStep(index: index, name: stepNames[index]))
    }

    private func finish() {
        nameFocused = false
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        profile.username = trimmed.isEmpty ? "Friend" : trimmed
        // Carries the solve outcome so completion can be split by it without
        // joining two events downstream.
        analytics.log(.onboardingCompleted(solvedFirstClue: solved))
        onFinish()
    }
}

// MARK: - Staggered entrance

private struct Entrance: ViewModifier {
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

private extension View {
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
