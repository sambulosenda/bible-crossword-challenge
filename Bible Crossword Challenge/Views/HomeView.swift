//
//  HomeView.swift
//  Bible Crossword Challenge
//
//  The "Today" tab. The screen opens like a page rather than a dashboard: a
//  greeting and the date, the day's verse set in serif on the bare paper, and
//  only then the daily puzzle — the one card that carries a tint, so the hero
//  is unmistakable among the white cards below it (mini, streak, collections,
//  next achievement, upgrade, and a bottom banner placeholder).
//
//  Each card is its own `View` type with narrow VALUE inputs so SwiftUI can
//  skip re-evaluating cards whose inputs didn't change (e.g. the verse card
//  stays put when only the streak updates).
//

import SwiftUI
import SwiftData

struct HomeView: View {
    let profile: PlayerProfile
    /// Owned by RootView so a widget deep-link can push the daily puzzle here.
    @Binding var path: NavigationPath

    @Environment(\.puzzleProvider) private var puzzleProvider
    @Environment(StoreService.self) private var store
    @Environment(\.analytics) private var analytics
    @Environment(\.memoryVerses) private var memoryVerses
    @Query private var records: [PuzzleRecord]

    /// Written by RootView when a launch breaks the streak; cleared here on
    /// dismiss, and on the solve that starts the next run.
    @AppStorage("pendingStreakBreak") private var pendingStreakBreak = 0
    /// Where the comeback solve came from, read once by the completion that
    /// logs it. Carried through UserDefaults because the puzzle is opened by
    /// navigation — there's no call chain between the tap and the solve.
    @AppStorage("comebackSource") private var comebackSource = ""

    /// Reminder-ask bookkeeping shared with the completion screen and the
    /// day-2 sheet — the rules live in `ReminderAsk.decide`.
    @Environment(\.notifications) private var notifications
    @AppStorage("remindersEnabled") private var remindersEnabled = false
    @AppStorage("completionReminderAsksShown") private var completionReminderAsksShown = 0
    @AppStorage("streakReminderAskShown") private var streakReminderAskShown = false
    @AppStorage("reminderAskLastDay") private var reminderAskLastDay = 0.0
    /// Decided once on appear so spending the impression can't hide the card
    /// mid-view.
    @State private var showStreakAsk = false

    private var dailyPuzzle: Puzzle? { puzzleProvider.dailyPuzzle() }
    private var dailyMini: Puzzle? { puzzleProvider.dailyMini() }
    private var sundaySpecial: Puzzle? { puzzleProvider.sundaySpecial() }

    /// A Special solved any day of its own week stays "solved", because the
    /// card lingers Sunday through Saturday — day-based presentation would
    /// demote Sunday's win to "played before" by Monday morning.
    private func sundayPresentation(_ record: PuzzleRecord?) -> DailyPresentation {
        let base = DailyPresentation.of(record: record, on: Date())
        if case .playedBefore(let seconds) = base,
           let completed = record?.completedDate,
           puzzleProvider.weekIndex(for: completed) == puzzleProvider.weekIndex() {
            return .solvedToday(seconds: seconds)
        }
        return base
    }

    /// Packs available today (seasonal ones only surface in-window), ordered so
    /// the timely ones lead the carousel: closing seasons first, then anything
    /// that has just arrived, then the standing shelf.
    ///
    /// A "New" badge on the fifth tile of a horizontal carousel is a badge
    /// nobody sees — it takes three swipes to reach, which is exactly the
    /// discovery problem the badge exists to solve. Same reasoning that already
    /// put seasonal packs at the front.
    private var collectionPacks: [PuzzlePack] {
        let available = puzzleProvider.availablePacks()
        let seasonal = available.filter(\.isSeasonal)
        let rest = available.filter { !$0.isSeasonal }
        return seasonal + rest.filter { $0.isNew() } + rest.filter { !$0.isNew() }
    }

    /// The first Journey with steps left, in authored order (the free quest is
    /// authored first, so a new player's card always begins there). Nil once
    /// every quest is walked — the card earns its slot or gives it back.
    private var activeQuest: QuestLine? {
        puzzleProvider.quests.first {
            !QuestProgress(quest: $0, recordsByID: recordsByID).isComplete
        }
    }

    /// Shared record lookup for pack-progress calculation in the carousel.
    private var recordsByID: [String: PuzzleRecord] {
        Dictionary(records.map { ($0.puzzleID, $0) }, uniquingKeysWith: { a, _ in a })
    }

    /// Offer the daily reminder once there's a streak worth protecting — the
    /// moment "a nudge tomorrow" stops being the app's want and becomes the
    /// player's. Comeback days are excluded: that card owns the moment, and a
    /// second ask under a broken streak reads as blame.
    private func maybeShowStreakAsk() {
        #if DEBUG
        // Same family as -uiForceReminderPrompt — a 2-day streak with an
        // unanswered permission takes two real days to reach.
        if ProcessInfo.processInfo.arguments.contains("-uiForceStreakAsk") {
            showStreakAsk = true
            analytics.log(.reminderAskShown(source: ReminderAsk.Surface.streakCard.rawValue))
            return
        }
        #endif
        guard pendingStreakBreak == 0 else { return }
        let state = ReminderAsk.State(
            remindersEnabled: remindersEnabled,
            permissionUndetermined: notifications.authorizationStatus == .notDetermined,
            totalCompleted: profile.totalPuzzlesCompleted,
            currentStreak: profile.currentStreak,
            completionAsksShown: completionReminderAsksShown,
            streakAskShown: streakReminderAskShown,
            lastAskDay: reminderAskLastDay == 0 ? nil : Date(timeIntervalSinceReferenceDate: reminderAskLastDay),
            askedThisSession: ReminderAskSession.asked
        )
        guard ReminderAsk.decide(.streakCard, state) else { return }

        showStreakAsk = true
        streakReminderAskShown = true
        reminderAskLastDay = Calendar.current.startOfDay(for: Date()).timeIntervalSinceReferenceDate
        ReminderAskSession.asked = true
        analytics.log(.reminderAskShown(source: ReminderAsk.Surface.streakCard.rawValue))
    }

    // MARK: - Comeback

    /// The mini restarts a streak as well as the daily does and asks far less of
    /// someone who just lost one, so it leads when there is one.
    private var comebackPuzzle: Puzzle? { dailyMini ?? dailyPuzzle }

    private var comebackPlayLabel: String {
        dailyMini != nil ? "Play today's Mini" : "Play today's puzzle"
    }

    /// Opens the comeback puzzle and marks where the attempt came from. The card
    /// stays until something is actually solved — clearing it on the tap would
    /// lose the offer for anyone who opens the puzzle and backs out.
    private func startComeback() {
        guard let puzzle = comebackPuzzle else { return }
        comebackSource = "home_card"
        path.append(puzzle)
    }

    /// True when a streak freeze was spent today, so the streak card can show a
    /// one-time reassurance instead of the idle freeze count.
    private var freezeSavedToday: Bool {
        guard let used = profile.lastFreezeUsedDate else { return false }
        return Calendar.current.isDateInToday(used)
    }

    /// Weekdays with a completed puzzle in the current week, for the streak
    /// card's week row.
    private var completedWeekdaysThisWeek: Set<Int> {
        let calendar = Calendar.current
        guard let week = calendar.dateInterval(of: .weekOfYear, for: Date()) else { return [] }
        return Set(records.compactMap { record in
            guard record.isCompleted, let date = record.completedDate, week.contains(date) else { return nil }
            return calendar.component(.weekday, from: date)
        })
    }

    var body: some View {
        // Resolve the daily puzzle + its record once per body pass; the verse
        // card derives from the puzzle so it never spoils today's answer.
        let daily = dailyPuzzle
        let record = daily.flatMap { d in records.first { $0.puzzleID == d.id } }
        let mini = dailyMini
        let miniRecord = mini.flatMap { m in records.first { $0.puzzleID == m.id } }
        let leadsWithMini = profile.totalPuzzlesCompleted < 3 && mini != nil

        return NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: Theme.Spacing.l) {
                    TodayHeader(verse: verseOfTheDay(excluding: daily))

                    // A player still inside their first three finishes leads
                    // with the Mini; everyone else leads with the daily.
                    //
                    // Finishing one puzzle on the first day is what separates a
                    // player who comes back from one who doesn't — measured at
                    // 61% next-day return against 21%. The Mini is finished by
                    // two thirds of the people who start it and the 15×15 by
                    // fewer than half, but 92% of first-ever puzzle starts were
                    // the 15×15, because it owns the hero card and the Mini sat
                    // in a row underneath it. New players came out of a
                    // two-letter tutorial and were handed a 19-clue grid.
                    //
                    // Originally only the literal first solve; extended to the
                    // first three because one Mini finish was handing players
                    // straight back to the 19-clue cliff on day two, before the
                    // habit existed. After three finishes the screen is the one
                    // everybody else has, permanently — the daily is the habit,
                    // the Mini is just a gentler way in.
                    if leadsWithMini, let mini {
                        LeadPuzzleCard(
                            puzzle: mini,
                            billing: .mini,
                            presentation: .of(record: miniRecord, on: Date()),
                            progress: inProgressFraction(mini, record: miniRecord)
                        )
                        if let daily {
                            CompactPuzzleCard(
                                puzzle: daily,
                                billing: .daily,
                                presentation: .of(record: record, on: Date())
                            )
                        }
                    } else {
                        if let daily {
                            LeadPuzzleCard(
                                puzzle: daily,
                                billing: .daily,
                                presentation: .of(record: record, on: Date()),
                                progress: inProgressFraction(daily, record: record)
                            )
                        } else {
                            emptyDailyCard
                        }

                        if let mini {
                            CompactPuzzleCard(
                                puzzle: mini,
                                billing: .mini,
                                presentation: .of(record: miniRecord, on: Date())
                            )
                        }
                    }

                    // The week's peak, Sunday through Saturday. Below the two
                    // dailies: the Special is a sitting you choose, not the
                    // habit the streak depends on.
                    if let sunday = sundaySpecial {
                        CompactPuzzleCard(
                            puzzle: sunday,
                            billing: .sunday,
                            presentation: sundayPresentation(
                                records.first { $0.puzzleID == sunday.id }
                            )
                        )
                    }

                    // Instead of, not above: a comeback card stacked on a flame
                    // card reading 0 would state the loss twice and answer it
                    // once. The two are mutually exclusive by construction
                    // anyway — a freeze save means the streak survived, so it
                    // can't also have broken.
                    if pendingStreakBreak > 0 {
                        ComebackCard(
                            previousStreak: pendingStreakBreak,
                            playLabel: comebackPlayLabel,
                            onPlay: startComeback,
                            onDismiss: { pendingStreakBreak = 0 }
                        )
                    } else {
                        StreakCard(
                            current: profile.currentStreak,
                            best: profile.bestStreak,
                            freezes: profile.streakFreezes,
                            savedRecently: freezeSavedToday,
                            completedWeekdays: completedWeekdaysThisWeek
                        )

                        // Right under the streak it protects. Once ever, and
                        // never on a day any other surface already asked.
                        if showStreakAsk {
                            ReminderAskCard(
                                profile: profile,
                                surface: .streakCard,
                                kicker: "Protect your streak",
                                headline: "A daily nudge keeps it alive.",
                                onFinish: { withAnimation { showStreakAsk = false } }
                            )
                        }
                    }

                    // Under the habit surfaces (puzzles, streak), above the
                    // discovery ones. This card lived at the very bottom and
                    // reached 21 users/25 taps in 30 days — about 6.5% of
                    // actives ever saw it. Here it's one short scroll away
                    // instead of a full one. `source: "home_card"` is
                    // unchanged on purpose: the move is measured as a lift on
                    // the same PostHog event, not a new one.
                    if !store.isPremium {
                        UpgradeCard(
                            totalPuzzles: puzzleProvider.totalPuzzleCount,
                            solvedPuzzles: records.count { $0.isCompleted }
                        )
                    }

                    if !collectionPacks.isEmpty {
                        CollectionsCarousel(
                            packs: collectionPacks,
                            recordsByID: recordsByID,
                            isPremium: store.isPremium
                        )
                    }

                    // The first unfinished Journey, hidden once they're all
                    // walked. A locked premium quest still shows — the card is
                    // a discovery surface, and its detail screen carries the
                    // paywall.
                    if let quest = activeQuest {
                        QuestHomeCard(
                            quest: quest,
                            progress: QuestProgress(quest: quest, recordsByID: recordsByID)
                        )
                    }

                    NextAchievementCard(profile: profile)

                    // Below the achievement card: the mode earns attention
                    // through its due badge, not its position.
                    MemoryVerseCard(
                        dueCount: memoryVerses.dueCount,
                        activeCount: memoryVerses.entries.count
                    )
                }
                .padding(Theme.Spacing.m)
                .frame(maxWidth: 560)
                // The scroll content's width is pinned to the scroll
                // container, not left to the column's own measurement. Left
                // to itself the column came out two-thirds of a point wider
                // than the screen (fractional layout out of the readable-width
                // chain), which made the vertical scroller horizontally
                // scrollable — the whole page could be dragged and bounced
                // left and right.
                .containerRelativeFrame(.horizontal)
            }
            .background(Theme.background)
            .onAppear { maybeShowStreakAsk() }
            // Inline, because the greeting below is the screen's real title —
            // a large "Today" on top of it would be two headings for one page.
            .navigationTitle("Today")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Puzzle.self) { puzzle in
                CrosswordGameView(puzzle: puzzle, profile: profile, entrySource: "home")
            }
            .navigationDestination(for: PackRoute.self) { route in
                PackDetailView(pack: route.pack, profile: profile, source: route.source)
            }
            .navigationDestination(for: QuestRoute.self) { route in
                QuestDetailView(quest: route.quest, profile: profile, source: route.source)
            }
            .navigationDestination(for: MemoryRoute.self) { _ in
                MemoryVerseListView()
            }
            .navigationDestination(for: MemoryPracticeRoute.self) { route in
                MemoryPracticeView(referenceKey: route.referenceKey)
            }
        }
    }

    // MARK: - Empty state (only reachable if the bundled puzzle set is missing)

    private var emptyDailyCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Label("DAILY PUZZLE", systemImage: "calendar").kicker()
            Text("Today's puzzle is on its way")
                .font(.scripture(.title3, weight: .bold))
            Text("In the meantime, you can replay any puzzle from the Archive.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.l)
        .elevatedCard()
        .accessibilityElement(children: .combine)
    }

    // MARK: - Derived state

    /// Fraction of playable cells filled, or nil when the puzzle isn't mid-solve.
    private func inProgressFraction(_ puzzle: Puzzle, record: PuzzleRecord?) -> Double? {
        guard let record, !record.isCompleted, record.hasPlayerEntries else { return nil }
        let total = puzzle.grid.reduce(0) { $0 + $1.filter { $0 != "." }.count }
        guard total > 0 else { return nil }
        return min(1.0, Double(record.entries.count) / Double(total))
    }

    /// A daily inspirational verse, rotated deterministically and chosen from a
    /// puzzle other than today's so it never spoils the daily answer.
    private func verseOfTheDay(excluding daily: Puzzle?) -> Puzzle? {
        let pool = puzzleProvider.puzzles.filter { $0.id != daily?.id }
        guard !pool.isEmpty else { return nil }
        let day = Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0
        return pool[((day % pool.count) + pool.count) % pool.count]
    }
}

// MARK: - Today header
//
// The page's opening: the day's verse, set on the bare paper rather than in a
// card. Scripture is the one thing here that isn't a module, and taking the
// white box away is what says so — a card would file it alongside "Next
// Achievement".
//
// The date and the "Good afternoon" salutation that used to sit above it are
// gone. Between them they cost about 70pt — a kicker, a title2 line and the
// spacing under it — to say nothing a returning player needs: the navigation
// title already reads "Today", and a fresh puzzle below says the rest. The
// verse keeps its place at the top, which is a positioning decision rather
// than a layout one, so the space came out of the chrome around it instead.

private struct TodayHeader: View {
    /// Nil only if the bundled puzzle set is missing.
    let verse: Puzzle?

    @Environment(\.readerRouter) private var readerRouter
    @Environment(\.analytics) private var analytics

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            if let verse {
                scripture(verse)
            }
        }
        .padding(.horizontal, Theme.Spacing.xs)
        .padding(.top, Theme.Spacing.s)
    }

    /// Scripture, set plainly. No rule, no box, no quote glyph: the serif is
    /// the only serif in the header, and that is the whole signal. An ornament
    /// here would be decoration standing in for a typographic distinction that
    /// the type is already making.
    ///
    /// It is labelled, though. Removing the card removed the kicker with it,
    /// which left an unexplained quotation under the greeting — the VoiceOver
    /// label named it all along, so only sighted readers lost the answer to
    /// "what is this?".
    private func scripture(_ verse: Puzzle) -> some View {
        Button {
            analytics.log(.scriptureOpened(reference: verse.reference, source: "verse_of_the_day"))
            readerRouter.open(reference: verse.reference)
        } label: {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    Text("Verse of the Day")
                        .kicker()
                    // Three lines, then truncate. Verses run from one line to
                    // six, and an unbounded header pushed the daily card's CTA
                    // below the fold on a 667pt screen while landing it in a
                    // different place every day. The reference below is the
                    // affordance for reading the whole passage.
                    // No line limit: the verse is the top of the app by
                    // decision, and a three-line clamp cut it mid-word
                    // ("…heard his praye…"). The longest in rotation is five.
                    Text(verse.verse)
                        .font(.scripture(.title3))
                        .lineSpacing(6)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 4) {
                    Text(verse.reference)
                        .font(.headline)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                }
                .foregroundStyle(Theme.accent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Verse of the day. \(verse.verse). \(verse.reference)")
        .accessibilityHint("Opens this passage in the reader")
    }
}

// MARK: - Billing

/// How a puzzle is introduced on Today: which one it is, not which slot it
/// happens to be filling.
///
/// The two cards below are *treatments* — a tinted hero and a compact row — and
/// either of the day's two puzzles can occupy either one, so neither card can
/// name its own occupant any more.
private enum PuzzleBilling {
    case daily, mini, sunday

    var kicker: String {
        switch self {
        case .daily: "DAILY PUZZLE"
        case .mini: "DAILY MINI"
        case .sunday: "SUNDAY SPECIAL"
        }
    }

    var symbol: String {
        switch self {
        case .daily: "calendar"
        case .mini: "square.grid.3x3"
        case .sunday: "sparkles"
        }
    }

    /// The noun VoiceOver leads with.
    var spoken: String {
        switch self {
        case .daily: "Daily puzzle"
        case .mini: "Daily mini"
        case .sunday: "Sunday Special"
        }
    }

    /// The one-line description the compact row shows when the puzzle is
    /// unplayed. "A quick two-minute puzzle" is a promise only the Mini keeps.
    func blurb(_ puzzle: Puzzle) -> String {
        switch self {
        case .daily: "\(puzzle.size)×\(puzzle.size) · \(puzzle.clueCount) clues"
        case .mini: "\(puzzle.size)×\(puzzle.size) · A quick two-minute puzzle"
        case .sunday: "\(puzzle.size)×\(puzzle.size) · This week's big grid"
        }
    }
}

// MARK: - Lead puzzle card
//
// The hero of the screen. It is the only tinted card on Today — every other
// module is white — so the eye lands here first without any of them shouting.
// A larger serif title and roomier padding carry the rest; the accent wash is
// the same device the completion screen uses to mark its one important card.
// When solved it becomes a quiet win moment (the time you earned) rather than
// a dead "done" tile.
//
// Which puzzle it carries is decided by the caller — see `leadsWithMini`.

private struct LeadPuzzleCard: View {
    let puzzle: Puzzle
    let billing: PuzzleBilling
    let presentation: DailyPresentation
    var progress: Double? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var celebrate = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            info
            actionButton
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .elevatedCard(fill: Theme.accent.opacity(0.10))
        .onAppear {
            // Only a puzzle finished *today* is worth celebrating. The rotation
            // repeat is also `isCompleted`, and bouncing a seal at it is exactly
            // the message that ends streaks.
            if case .solvedToday = presentation, !reduceMotion { celebrate.toggle() }
        }
    }

    // Non-interactive content, grouped as one VoiceOver element; the action
    // button stays a separate focusable control below.
    private var info: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            // No kicker: the card is the hero, its title names the puzzle and
            // the meta row says the size; the compact card below names the
            // other one. Seven uppercase labels on Today was two too many.
            HStack {
                Spacer()
                DifficultyBadge(difficulty: puzzle.difficulty)
            }

            HStack(alignment: .top, spacing: Theme.Spacing.m) {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    Text(puzzle.title)
                        .font(.scripture(.title, weight: .bold))
                        .fixedSize(horizontal: false, vertical: true)

                    switch presentation {
                    case .solvedToday(let seconds):
                        solvedReward(seconds)
                    case .playedBefore(let previous):
                        // Presented as playable, because it is: the meta row is
                        // what an unsolved puzzle shows, and the pill turns the
                        // old time into a target rather than a full stop.
                        metaRow
                        replayPrompt(previous)
                    case .play:
                        metaRow
                        if let progress {
                            ProgressView(value: progress)
                                .tint(Theme.accent)
                        }
                    }
                }

                Spacer(minLength: 0)

                // Today's actual grid shape, in miniature. Ornament that happens
                // to be true — and the first thing that makes one day's card
                // look different from the next. Dropped at accessibility sizes,
                // where the title needs the whole width.
                if !typeSize.isAccessibilitySize {
                    GridThumbnail(grid: puzzle.grid)
                        .frame(width: 72, height: 72)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private var metaLabels: some View {
        Label("\(puzzle.clueCount) clues", systemImage: "list.bullet")
        Label("\(puzzle.size)×\(puzzle.size)", systemImage: "square.grid.3x3")
    }

    private var metaRow: some View {
        // Stacks vertically when the labels can't fit side by side (large Dynamic Type).
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Theme.Spacing.m) { metaLabels }
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) { metaLabels }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }

    // The win moment: leads with the time the user just earned, echoing the
    // CompletionView language (green seal + monospaced clock).
    // A compact success pill that hugs its content (not a full-width bar).
    private func solvedReward(_ seconds: Int?) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(.green)
                .symbolEffect(.bounce, value: celebrate)
            Text("Solved").foregroundStyle(.green)
            if let secs = seconds, secs > 0 {
                Text("in \(TimeFormat.clock(secs))")
                    .foregroundStyle(.primary)
                    .monospacedDigit()
            }
        }
        .font(.subheadline.weight(.semibold))
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, Theme.Spacing.s)
        .background(Color.green.opacity(0.12), in: .capsule)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The rotation has come back around to a puzzle this player finished on an
    /// earlier day. Accent, not green: green is this app's word for "done", and
    /// today is not.
    private func replayPrompt(_ previous: Int?) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: "arrow.triangle.2.circlepath")
            // Concatenated rather than two views in the stack: as one `Text` it
            // wraps as a phrase instead of breaking between "beat" and the time.
            if let previous, previous > 0 {
                Text("Played before · beat ")
                    + Text(TimeFormat.clock(previous)).monospacedDigit()
            } else {
                Text("You've played this one before")
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(Theme.accent)
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, Theme.Spacing.s)
        .background(Theme.accent.opacity(0.14), in: .capsule)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var actionButton: some View {
        switch presentation {
        case .solvedToday:
            // Full-width but secondary (tonal) — replay stays available without
            // out-shouting the ink pill used for unsolved puzzles.
            NavigationLink(value: puzzle) {
                Label("Play again", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.pillTonal)
        case .playedBefore:
            // Prominent, unlike the solved-today replay: this *is* the day's
            // action, and the streak depends on it being taken.
            NavigationLink(value: puzzle) {
                Label("Play again", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.pillProminent)
        case .play(let status):
            NavigationLink(value: puzzle) {
                Label(status.actionTitle, systemImage: status.actionSymbol)
            }
            .buttonStyle(.pillProminent)
        }
    }

    private var accessibilityLabel: String {
        switch presentation {
        case .solvedToday(let seconds):
            if let secs = seconds, secs > 0 {
                return "\(billing.spoken). \(puzzle.title). Solved in \(TimeFormat.clock(secs))."
            }
            return "\(billing.spoken). \(puzzle.title). Completed."
        case .playedBefore(let previous):
            let base = "\(billing.spoken). \(puzzle.title). \(puzzle.difficulty.label) difficulty. You've played this one before"
            if let previous, previous > 0 {
                return base + ", in \(TimeFormat.clock(previous)). Play again to beat it."
            }
            return base + ". Play again."
        case .play(.inProgress):
            return "\(billing.spoken). \(puzzle.title). \(puzzle.difficulty.label) difficulty. In progress. \(puzzle.clueCount) clues, \(puzzle.size) by \(puzzle.size) grid."
        case .play:
            return "\(billing.spoken). \(puzzle.title). \(puzzle.difficulty.label) difficulty. \(puzzle.clueCount) clues, \(puzzle.size) by \(puzzle.size) grid."
        }
    }
}

// MARK: - Collections carousel
//
// A horizontal strip of themed packs, so collections are discoverable from the
// daily feed rather than only via the Packs tab. Each tile pushes the pack's
// detail onto the Today stack.

private struct CollectionsCarousel: View {
    let packs: [PuzzlePack]
    let recordsByID: [String: PuzzleRecord]
    let isPremium: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Label("COLLECTIONS", systemImage: "square.stack.3d.up").kicker()
                .padding(.horizontal, Theme.Spacing.xs)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.m) {
                    ForEach(packs) { pack in
                        NavigationLink(value: PackRoute(pack: pack, source: .home)) {
                            PackTile(
                                pack: pack,
                                progress: PackProgress(pack: pack, recordsByID: recordsByID),
                                isLocked: pack.isPremium && !isPremium
                            )
                        }
                        .buttonStyle(PressableCardStyle())
                    }
                }
                .padding(.horizontal, Theme.Spacing.xs)
                // Give the row breathing room so the last tile's shadow/press
                // scale isn't clipped by the ScrollView edge.
                .padding(.vertical, 2)
            }
        }
    }
}

/// A compact, fixed-width pack card sized for the horizontal carousel.
private struct PackTile: View {
    let pack: PuzzlePack
    let progress: PackProgress
    let isLocked: Bool

    @ScaledMetric(relativeTo: .title) private var coverSize = 44

    /// The tile is a fixed size so the carousel's rows line up, which means the
    /// tallest combination has to fit: a two-line title *and* a badge under it.
    /// At 150 that combination overflowed the card — "Women of the Bible" with a
    /// New badge pushed its puzzle count out past the bottom edge. Scaled rather
    /// than a larger constant, because the text inside it scales.
    @ScaledMetric(relativeTo: .subheadline) private var tileHeight = 176

    /// The one badge this tile shows, if any. The tile's own `Spacer` absorbs
    /// the extra line, so the carousel's fixed height still holds.
    private var packBadge: PackBadge? { PackBadge.forPack(pack) }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack {
                Image(systemName: pack.coverSymbol)
                    .font(.title3)
                    .foregroundStyle(pack.accent)
                    .frame(width: coverSize, height: coverSize)
                    .background(pack.accent.opacity(0.14), in: .rect(cornerRadius: 12, style: .continuous))
                Spacer(minLength: 0)
                if isLocked {
                    Image(systemName: "crown.fill")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                }
            }

            Text(pack.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let packBadge {
                packBadge
            }

            Spacer(minLength: 0)

            // Same rule as `PackCard`: a locked collection states its size, not
            // the player's progress through it. This tile was missed when that
            // landed, so the carousel could still show a crowned pack as
            // "Complete" — the one surface where it sat on the home screen.
            if isLocked {
                Text("\(progress.total) puzzle\(progress.total == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            } else if progress.isComplete {
                Label("Complete", systemImage: "checkmark.seal.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.green)
            } else {
                ProgressView(value: progress.fraction).tint(pack.accent)
                Text("\(progress.solved)/\(progress.total)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(Theme.Spacing.m)
        .frame(width: 160, height: tileHeight, alignment: .topLeading)
        .elevatedCard()
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        var parts = [pack.title]
        if isLocked { parts.append("Premium") }
        if let packBadge { parts.append(packBadge.label) }
        parts.append(isLocked
            ? "\(progress.total) puzzle\(progress.total == 1 ? "" : "s")"
            : (progress.isComplete ? "Complete" : "\(progress.solved) of \(progress.total) solved"))
        return parts.joined(separator: ". ")
    }
}

// MARK: - Next achievement card

private struct NextAchievementCard: View {
    let profile: PlayerProfile

    @ScaledMetric(relativeTo: .title) private var iconSize = 52

    var body: some View {
        if let next = Achievements.all.first(where: { !$0.isUnlocked(by: profile) }) {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                Label("NEXT ACHIEVEMENT", systemImage: "target").kicker()
                HStack(spacing: Theme.Spacing.m) {
                    iconTile(next.symbol)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(next.title).font(.headline)
                        Text(next.detail).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Text(next.progressText(for: profile))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: next.progress(for: profile))
                    .tint(Theme.accent)
            }
            .padding(Theme.Spacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .elevatedCard()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Next achievement: \(next.title), \(next.detail), \(next.progressText(for: profile)) complete")
        } else {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                Label("ACHIEVEMENTS", systemImage: "star.circle.fill").kicker()
                HStack(spacing: Theme.Spacing.m) {
                    iconTile("star.circle.fill")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("All achievements unlocked").font(.headline)
                        Text("You've completed every milestone.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(Theme.Spacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .elevatedCard()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("All achievements unlocked. You've completed every milestone.")
        }
    }

    private func iconTile(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.title2)
            .foregroundStyle(Theme.accent)
            .frame(width: iconSize, height: iconSize)
            .background(Theme.accent.opacity(0.14), in: .circle)
    }
}

// MARK: - Upgrade card

private struct UpgradeCard: View {
    /// How many puzzles exist, and how many this player has finished. Both are
    /// passed in rather than queried here: the counts already sit in HomeView,
    /// and a second `@Query` for a number would re-fetch every record on a
    /// screen that has them in hand.
    let totalPuzzles: Int
    let solvedPuzzles: Int

    @ScaledMetric(relativeTo: .title) private var iconSize = 44
    @State private var showPaywall = false

    /// The player's own progress when they have some, and what's behind the
    /// wall when they don't.
    ///
    /// "You've solved 0" is a discouragement rather than a nudge — the same
    /// reason the paywall hides its progress line at zero.
    private var subtitle: String {
        guard solvedPuzzles > 0 else {
            return "Every themed pack, and hints whenever you need them."
        }
        return "You've solved \(solvedPuzzles) — the rest are waiting."
    }

    var body: some View {
        // A sheet, as every other entry point presents it. Pushed onto the
        // Today stack instead, the paywall arrived with a navigation back
        // button colliding with its own close button and the tab bar sitting
        // over its legal text.
        Button {
            showPaywall = true
        } label: {
            // Top-aligned, and the pill sits under the copy rather than on the
            // trailing edge. Beside a fixed-width pill the text column was left
            // about 110pt, which broke the headline across "Unlock all" /
            // "177 puzzles" and the subtitle across two more — four cramped
            // lines next to a pill floating in whitespace. Below the copy, both
            // lines fit, and the card is no taller than the wrapped version was.
            HStack(alignment: .top, spacing: Theme.Spacing.m) {
                // Accent, not secondary grey. A greyed-out crown on a grey disc
                // reads as a disabled control rather than an invitation, which
                // is a poor look on the one card asking for money.
                Image(systemName: "crown.fill")
                    .font(.title3)
                    .foregroundStyle(Theme.accent)
                    .frame(width: iconSize, height: iconSize)
                    .background(Theme.accent.opacity(0.14), in: .circle)
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    VStack(alignment: .leading, spacing: 2) {
                        // Was "Go Premium": the app's own word for its SKU, which
                        // says nothing about what the player gets. The count comes
                        // from the bundle so it can't go stale as puzzles are added.
                        Text("Unlock all \(totalPuzzles) puzzles")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.primary)
                        Text(subtitle)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    // A pill, not a chevron. The chevron is this screen's "tap to
                    // see more" — shared with Collections and Next Achievement — so
                    // the one card asking for money read as another navigation row.
                    // A filled pill is the app's own language for an action (Start
                    // Puzzle, the paywall CTA, Library's unlock button).
                    //
                    // Still hugging its text rather than the full-width pill
                    // Profile's upsell uses: this card sits under the daily
                    // puzzle and a full-width ink capsule here would compete
                    // with that hero's own Continue button.
                    //
                    // "See plans", not "Unlock": this opens the paywall, it doesn't
                    // buy anything, and a button that overstates what it does is
                    // how a tap becomes a back-out.
                    Text("See plans")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.onInk)
                        .padding(.horizontal, Theme.Spacing.m)
                        .padding(.vertical, Theme.Spacing.s)
                        .background(Theme.ink, in: .capsule)
                        .fixedSize()
                }
                Spacer(minLength: 0)
            }
            .padding(Theme.Spacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Plain white like every other module: the upsell was the only
            // tinted card on the screen, which made it louder than the puzzle.
            // That tint now belongs to the daily card.
            .elevatedCard()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Unlock all \(totalPuzzles) puzzles")
            .accessibilityHint(subtitle)
        }
        .buttonStyle(PressableCardStyle())
        .sheet(isPresented: $showPaywall) {
            PaywallView(source: "home_card")
        }
    }
}

// MARK: - Daily Mini card
//
// A compact companion to the hero card: the quick 7×7 for days (or moments)
// the full puzzle is too big. Kept visually lighter than the daily so it
// reads as the second course, not a competing headline.

private struct CompactPuzzleCard: View {
    let puzzle: Puzzle
    let billing: PuzzleBilling
    let presentation: DailyPresentation

    /// Only a puzzle finished today wears the green check. Each pool wraps on
    /// its own schedule — the mini's eight days after the daily's — and a repeat
    /// there tells the same streak-ending lie.
    private var isSolvedToday: Bool {
        if case .solvedToday = presentation { return true }
        return false
    }

    var body: some View {
        NavigationLink(value: puzzle) {
            HStack(spacing: Theme.Spacing.m) {
                Image(systemName: leadingSymbol)
                    .font(.title)
                    .foregroundStyle(isSolvedToday ? .green : Theme.accent)

                VStack(alignment: .leading, spacing: 2) {
                    Label(billing.kicker, systemImage: billing.symbol).kicker()
                    Text(puzzle.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(Theme.Spacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .elevatedCard()
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    /// Solved wears the green check; unsolved leads with the billing's own
    /// mark, so the Special's row reads as an occasion rather than a second
    /// bolt of the same kind.
    /// The bolt means "quick", which is the Mini's trait; the daily gets the
    /// calendar it's billed under. Both used to share the bolt.
    private var leadingSymbol: String {
        if isSolvedToday { return "checkmark.circle.fill" }
        switch billing {
        case .mini: return "bolt.circle.fill"
        case .daily: return "calendar.circle.fill"
        case .sunday: return "star.circle.fill"
        }
    }

    private var subtitle: String {
        switch presentation {
        case .solvedToday(let seconds):
            if let secs = seconds, secs > 0 {
                return "Solved in \(TimeFormat.clock(secs))"
            }
            return "Solved"
        case .playedBefore(let previous):
            if let previous, previous > 0 {
                return "Played before · beat \(TimeFormat.clock(previous))"
            }
            return "Played before · go again"
        case .play(.inProgress):
            return "In progress · \(puzzle.size)×\(puzzle.size)"
        case .play:
            return billing.blurb(puzzle)
        }
    }

    private var accessibilityLabel: String {
        switch presentation {
        case .solvedToday, .playedBefore, .play(.inProgress):
            return "\(billing.spoken). \(puzzle.title). \(subtitle)."
        case .play:
            return "\(billing.spoken). \(puzzle.title). \(billing.blurb(puzzle))."
        }
    }
}

