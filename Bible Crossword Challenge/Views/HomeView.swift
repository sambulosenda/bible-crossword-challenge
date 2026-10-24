//
//  HomeView.swift
//  Bible Crossword Challenge
//
//  The "Today" tab. The screen opens like a page rather than a dashboard: the
//  day's verse set in serif on the bare paper, and only then the daily puzzle
//  — the one card that carries a tint and the one pill, so the hero is
//  unmistakable among the white cards below it: the day's other puzzles, the
//  streak, "Keep going" (plan, Journey, memory verses, next badge), the packs
//  shelf, and the upgrade card last. Uppercase labels are section headers
//  only; cards name themselves.
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
    /// Switches to the Packs tab — the Packs shelf header's "See all".
    var onShowPacks: () -> Void = {}

    @Environment(\.puzzleProvider) private var puzzleProvider
    @Environment(StoreService.self) private var store
    @Environment(\.analytics) private var analytics
    @Environment(\.memoryVerses) private var memoryVerses
    @Environment(\.readingPlans) private var readingPlans
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
    /// The streak's detail — week row, best, freezes — opened from the flame
    /// in the bar. See `streakButton`.
    @State private var showStreak = false
    /// The streak sheet's height, measured from its card.
    @State private var streakSheetHeight: CGFloat = 320
    /// Every paywall Today opens: the trial re-offer (see `TrialReoffer`,
    /// opening on the plan the player backed out of) and the upgrade card.
    /// Presented here rather than by the card: a purchase removes the card,
    /// and a sheet it owned was torn away mid-flow instead of showing the
    /// paywall's own "you're Premium" state, as every other entry does.
    @State private var paywall: PaywallRequest?

    /// The day Today is showing — see `TodayClock`. Read here so the screen
    /// redraws at midnight instead of holding yesterday's puzzle as Solved.
    @Environment(\.today) private var currentDay
    @Environment(\.calendar) private var calendar

    private var dailyPuzzle: Puzzle? { puzzleProvider.dailyPuzzle() }
    private var dailyMini: Puzzle? { puzzleProvider.dailyMini() }
    private var sundaySpecial: Puzzle? { puzzleProvider.sundaySpecial() }

    /// A Special solved any day of its own week stays "solved", because the
    /// card lingers Sunday through Saturday — day-based presentation would
    /// demote Sunday's win to "played before" by Monday morning.
    private func sundayPresentation(_ record: PuzzleRecord?) -> DailyPresentation {
        let base = DailyPresentation.of(record: record, on: currentDay)
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
    private func collectionPacks(_ records: [String: PuzzleRecord]) -> [PuzzlePack] {
        // Same shadowing rule as the Packs tab: a collection that ships as a
        // Journey is not also a collection. Home carries a Journey card of its
        // own, so without this the carousel offered "The Life of David" a few
        // hundred points below the Journey promoting the same nine puzzles.
        let available = PuzzlePack.notShadowedByQuests(
            puzzleProvider.availablePacks(), quests: puzzleProvider.quests
        )
        let seasonal = available.filter(\.isSeasonal)
        let rest = available.filter { !$0.isSeasonal }
        let timely = seasonal + rest.filter { $0.isNew() } + rest.filter { !$0.isNew() }

        // Then by what the player can do with each, keeping the timely order
        // within a group: one they're partway through, one they can start,
        // one behind Premium, and last one they've finished. The carousel
        // used to open on "First Steps — Complete" for anyone past the
        // tutorial, a dead end in the first slot with every tile after it
        // locked.
        func rank(_ pack: PuzzlePack) -> Int {
            let progress = PackProgress(pack: pack, recordsByID: records)
            let locked = pack.isPremium && !store.isPremium
            if locked { return 2 }
            if progress.isComplete { return 3 }
            return progress.solved > 0 ? 0 : 1
        }
        return timely.enumerated()
            .sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }
            .map(\.element)
    }

    /// The first Journey with steps left, in authored order (the free quest is
    /// authored first, so a new player's card always begins there). Nil once
    /// every quest is walked — the card earns its slot or gives it back.
    private func activeQuest(_ recordsByID: [String: PuzzleRecord]) -> QuestLine? {
        puzzleProvider.quests.first {
            !QuestProgress(quest: $0, recordsByID: recordsByID).isComplete
        }
    }

    /// Record lookup for pack and quest progress. Built once per body pass
    /// and handed down: as a property read in each consumer it was rebuilt
    /// five times a pass, once per quest inside `activeQuest` alone.
    private var recordsByID: [String: PuzzleRecord] {
        records.byPuzzleID
    }

    /// Offer the daily reminder once there's a streak worth protecting — the
    /// moment "a nudge tomorrow" stops being the app's want and becomes the
    /// player's. Comeback days are excluded: that card owns the moment, and a
    /// second ask under a broken streak reads as blame.
    /// Offer the trial again to a player who backed out of Apple's sheet in
    /// an earlier sitting. Returns whether it did, so the caller can hold the
    /// other asks this appear.
    private func maybeShowTrialReoffer() -> Bool {
        #if DEBUG
        // Same family as -uiForceStreakAsk: the real path needs a cancelled
        // sheet and a relaunch.
        if ProcessInfo.processInfo.arguments.contains("-uiForceTrialReoffer"),
           !TrialReofferSession.forced {
            TrialReofferSession.forced = true
            paywall = PaywallRequest(source: TrialReoffer.source, planID: StoreService.yearlyID)
            return true
        }
        #endif
        guard let planID = store.trialReofferPlanID else { return false }
        store.markTrialReofferShown()
        paywall = PaywallRequest(source: TrialReoffer.source, planID: planID)
        return true
    }

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

    /// The comeback card's play action, or nil when the hero card already
    /// plays the same puzzle.
    private func comebackAction(heroPuzzleID: String?) -> (() -> Void)? {
        guard let puzzle = comebackPuzzle, puzzle.id != heroPuzzleID else { return nil }
        return { startComeback() }
    }

    /// Opens the comeback puzzle and marks where the attempt came from. The card
    /// stays until something is actually solved — clearing it on the tap would
    /// lose the offer for anyone who opens the puzzle and backs out.
    private func startComeback() {
        guard let puzzle = comebackPuzzle else { return }
        comebackSource = "home_card"
        path.append(puzzle)
    }

    private var streakCard: some View {
        StreakCard(
            current: profile.currentStreak,
            best: profile.bestStreak,
            freezes: profile.streakFreezes,
            savedRecently: freezeSavedToday,
            completedWeekdays: completedWeekdaysThisWeek,
            endedRun: pendingStreakBreak > 0 ? pendingStreakBreak : nil
        )
    }

    /// Flame and day count beside the title — where streak apps keep it.
    /// Outline and grey while a broken streak waits for its comeback, the
    /// same treatment as `ComebackCard`'s icon.
    private var streakButton: some View {
        let paused = pendingStreakBreak > 0
        // Orange means there is a streak. At 0 there isn't one, so the flame
        // takes the paused treatment — outline and grey, as Fitness draws an
        // empty ring — rather than celebrating nothing.
        let idle = paused || profile.currentStreak == 0
        return Button {
            showStreak = true
        } label: {
            // An HStack, not a Label: the bar draws a toolbar Label icon-only,
            // which dropped the count — the one thing this is for. Tried
            // again 2026-10-23 with `.labelStyle(.titleAndIcon)`: the bar
            // still drew the flame alone, and in ink rather than orange. The
            // cost is iPhone Duo's vertical bar, which only takes Labels.
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: idle ? "flame" : "flame.fill")
                Text("\(profile.currentStreak)")
            }
                .font(.headline)
                .monospacedDigit()
                .foregroundStyle(idle ? Color.secondary : FeatureTint.streak)
        }
        .accessibilityLabel(paused ? "Streak paused" : "\(profile.currentStreak) day streak")
        .accessibilityHint("Shows this week and your best streak")
    }

    /// True when a streak freeze was spent today, so the streak card can show a
    /// one-time reassurance instead of the idle freeze count.
    private var freezeSavedToday: Bool {
        guard let used = profile.lastFreezeUsedDate else { return false }
        return calendar.isDate(used, inSameDayAs: currentDay)
    }

    /// Weekdays with a completed puzzle in the current week, for the streak
    /// card's week row. Off `currentDay`, not `Date()`, so the row turns over
    /// with the rest of Today at midnight.
    private var completedWeekdaysThisWeek: Set<Int> {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: currentDay) else { return [] }
        return Set(records.compactMap { record in
            guard record.isCompleted, let date = record.completedDate, week.contains(date) else { return nil }
            return calendar.component(.weekday, from: date)
        })
    }

    var body: some View {
        // Resolve the daily puzzle + its record once per body pass; the verse
        // card derives from the puzzle so it never spoils today's answer.
        // One index for every lookup in the pass (`byPuzzleID`, the project's
        // duplicate-safe lookup), instead of a linear scan per puzzle.
        let byID = recordsByID
        let daily = dailyPuzzle
        let record = daily.flatMap { byID[$0.id] }
        let mini = dailyMini
        let miniRecord = mini.flatMap { byID[$0.id] }
        // The Mini also leads on a repeat day — the daily rotation has come
        // round to a puzzle this player already finished, and today's Mini is
        // one they haven't. A repeat in the hero is the weakest first thing
        // Today can say to someone who has been here three months; any finish
        // keeps the streak (`Streaks.registerCompletion`), so leading with the
        // new puzzle costs the habit nothing. The repeat stays one row down.
        //
        // Each presentation is worked out once and reused by the hero and
        // the rows: it decodes the record's entries to tell played from
        // fresh, and was being decoded six times a pass.
        let dailyState = DailyPresentation.of(record: record, on: currentDay)
        let miniState = DailyPresentation.of(record: miniRecord, on: currentDay)
        let dailyIsRepeat: Bool = {
            if case .playedBefore = dailyState { return true }
            return false
        }()
        let dailySolvedToday: Bool = {
            if case .solvedToday = dailyState { return true }
            return false
        }()
        let miniIsNew: Bool = {
            if case .play = miniState { return true }
            return false
        }()
        // Withheld inside the learning window — see `companionPuzzles`.
        let sunday = profile.isStillLearning ? nil : sundaySpecial
        let sundayRecord = sunday.flatMap { byID[$0.id] }
        let sundayState = sundayPresentation(sundayRecord)
        let sundayIsNew: Bool = {
            if sunday != nil, case .play = sundayState { return true }
            return false
        }()
        let lead: TodayLead = {
            if mini != nil && (profile.isStillLearning || (dailyIsRepeat && miniIsNew)) { return .mini }
            // Once today's daily is solved, the hero hands the day on to the
            // Mini if it's still waiting. A solved daily in the hero made the
            // loudest card on the screen a "Play again" — a dead end at the
            // top of the page — while the one new puzzle sat in a half-width
            // card under it. The solved daily drops into that card instead,
            // with its time.
            if dailySolvedToday && miniIsNew { return .mini }
            // Past the Mini, the week's Special is the other puzzle that can be
            // new on a repeat day. Both rotations wrapped on 2026-10-04 and the
            // Special — unplayed — sat third on the screen under two "best
            // time" rows. It's a bigger sitting than the habit asks for, but
            // it is the only new thing Today has, and any finish keeps the
            // streak. The Mini still goes first when it's new: it's the gentler
            // way to keep the day.
            if dailyIsRepeat && sundayIsNew { return .sunday }
            return .daily
        }()
        let today = TodayPuzzles(
            daily: daily, dailyRecord: record, dailyPresentation: dailyState,
            mini: mini, miniRecord: miniRecord, miniPresentation: miniState,
            sunday: sunday, sundayRecord: sundayRecord, sundayPresentation: sundayState
        )

        return NavigationStack(path: $path) {
            CardColumns {
                leadColumn(today, lead: lead)
            } more: {
                moreColumn(byID, heroPuzzleID: today.puzzle(lead)?.puzzle.id)
            }
            .background(Theme.background)
            // One ask per sitting, in order of how much the player has already
            // told us. The trial re-offer answers intent they actually showed
            // (they read the price and pressed the button), and the streak card
            // asks for something free — and it retries on the next appear anyway.
            // The proactive premium ask that sat between them was removed on
            // 2026-10-03: 75 players saw it in 30 days and none tapped.
            .onAppear {
                if !maybeShowTrialReoffer() { maybeShowStreakAsk() }
            }
            .sheet(item: $paywall) { request in
                PaywallView(source: request.source, initialPlanID: request.planID)
            }
            // Large, as a tab's root title is. It was inline while a greeting
            // sat under it as the page's real title; the greeting went on
            // 2026-07-28 and left a small centred "Today" over nothing. The
            // large title collapses into the bar on scroll, so it costs its
            // height only at the top of the page.
            .navigationTitle("Today")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { streakButton }
            }
            .sheet(isPresented: $showStreak) {
                // Sized to the card: at `.medium` half the sheet was empty
                // paper under it.
                streakCard
                    .padding(Theme.Spacing.m)
                    .padding(.top, Theme.Spacing.m)
                    // Plus the bottom safe area: a height detent counts the
                    // home-indicator strip, and without it the card's last
                    // line sat under the edge of the sheet.
                    .onGeometryChange(for: CGFloat.self) {
                        $0.size.height + $0.safeAreaInsets.bottom
                    } action: {
                        streakSheetHeight = $0
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                    .background(Theme.background)
                    .presentationDetents([.height(streakSheetHeight)])
                    .presentationDragIndicator(.visible)
            }
            .navigationDestination(for: Puzzle.self) { puzzle in
                CrosswordGameView(puzzle: puzzle, profile: profile, entrySource: "home")
            }
            .navigationDestination(for: PackRoute.self) { route in
                PackDetailView(pack: route.pack, profile: profile, source: route.source)
            }
            .navigationDestination(for: QuestRoute.self) { route in
                QuestDetailView(quest: route.quest, profile: profile, source: route.source)
            }
            // Routes on `path`, not `isPresented` flags: a deep link that
            // replaces the path clears these too, and the plan route carries
            // the day it was opened on. Built from the live `nextDay`, the
            // reader re-rendered as day + 1 while it closed after marking a
            // chapter read — and blank on a plan's last day, where it is nil.
            .navigationDestination(for: AchievementsRoute.self) { _ in
                AchievementsView(profile: profile, source: "home_card")
            }
            .navigationDestination(for: PlanChapterRoute.self) { route in
                ChapterReaderView(
                    startBook: route.book,
                    startChapter: route.day,
                    source: "read_plan",
                    planChapter: PlanChapter(book: route.book, chapter: route.day),
                    onPlanChapterRead: { markPlanRead(planID: route.planID, day: route.day) }
                )
            }
            .navigationDestination(for: MemoryRoute.self) { route in
                MemoryVerseListView(source: route.source)
            }
            .navigationDestination(for: VersesRoute.self) { _ in
                ReadView()
            }
            .navigationDestination(for: MemoryPracticeRoute.self) { route in
                MemoryPracticeView(referenceKey: route.referenceKey, source: route.source)
            }
        }
    }

    // MARK: - Empty state (only reachable if the bundled puzzle set is missing)

    /// Today's puzzles: the verse, the lead card and the ones under it.
    @ViewBuilder
    private func leadColumn(_ today: TodayPuzzles, lead: TodayLead) -> some View {
        TodayHeader(verse: verseOfTheDay(excluding: today.daily))

        // A player still inside their first three finishes leads
        // with the Mini; everyone else leads with the daily — or, on a
        // repeat day, with whichever of the day's puzzles is new.
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
        if let hero = today.puzzle(lead) {
            LeadPuzzleCard(
                puzzle: hero.puzzle,
                billing: hero.billing,
                presentation: hero.presentation,
                progress: inProgressFraction(hero.puzzle, record: today.record(lead))
            )
        } else {
            emptyDailyCard
        }

        // The day's other puzzles as rows of one card, not a card each:
        // they are one idea ("also today"), and two white cards stacked
        // under the hero read as two more headlines.
        let companions = companionPuzzles(today, lead: lead)
        if !companions.isEmpty {
            CompanionPuzzlesCard(rows: companions)
        }
    }

    /// What sits under the hero: the day's puzzles it isn't carrying, the
    /// dailies first and then the Sunday Special.
    ///
    /// The Special is the week's peak, Sunday through Saturday — below the two
    /// dailies because it's a sitting you choose, not the habit the streak
    /// depends on (it leads only on a repeat day, when it's the new one).
    ///
    /// Absent inside the learning window, on the same threshold that hands
    /// those players the Mini above (`today.sunday` is nil there). It was the
    /// one puzzle surface on this screen with no such gate, and it is the
    /// worst thing a first-day player can open: of 17 who started one on
    /// their install day (2.5+, 45 days to 2026-09-08) 5 finished, and 22% of
    /// those starts were abandoned under 10% fill within 15 seconds — against
    /// 3% on the Mini. A 21×21 handed to someone who has just solved a
    /// two-letter tutorial is a wall with a card around it. It comes back at
    /// three finishes, with everything else the window withholds.
    private func companionPuzzles(_ today: TodayPuzzles, lead: TodayLead) -> [CompanionPuzzle] {
        [TodayLead.daily, .mini, .sunday]
            .filter { $0 != lead }
            .compactMap { today.puzzle($0) }
    }

    /// The habit and the shelf: streak, plan, upgrade, packs, quest,
    /// achievements, memory verses.
    @ViewBuilder
    private func moreColumn(_ recordsByID: [String: PuzzleRecord], heroPuzzleID: String?) -> some View {
        // Instead of, not above: a comeback card stacked on a flame
        // card reading 0 would state the loss twice and answer it
        // once. The two are mutually exclusive by construction
        // anyway — a freeze save means the streak survived, so it
        // can't also have broken.
        if pendingStreakBreak > 0 {
            // Only when it offers a quicker puzzle than the hero's. Otherwise
            // the grey flame in the bar already says the streak is paused,
            // and its sheet says the rest (`StreakCard.endedRun`).
            if let play = comebackAction(heroPuzzleID: heroPuzzleID) {
                ComebackCard(
                    previousStreak: pendingStreakBreak,
                    playLabel: comebackPlayLabel,
                    // Its button started 12 of ~100 comebacks in the 30 days
                    // to 2026-10-13 — worth a card when it's a quicker puzzle.
                    onPlay: play,
                    onDismiss: { pendingStreakBreak = 0 }
                )
            }
        } else {
            // The streak is status, so it lives in the bar (`streakButton`)
            // rather than as a card mid-page, where it pushed Keep going
            // below the fold on every visit. Inline only on the day a
            // freeze saved it: that reassurance is one-time, and a sheet
            // nobody opens would swallow it.
            if freezeSavedToday {
                streakCard
            }

            // Where the streak card stood. Once ever, and never on a day
            // any other surface already asked.
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

        // Ordered by what players actually open, not by what the app
        // wants opened. 30 days to 2026-10-03: packs carousel 76
        // players, Journey 66, next achievement 63, memory verses 35
        // (348 opens), the Premium card 22. The Premium card sat
        // directly under the streak, above all of it; it now closes
        // the column. `source: "home_card"` is unchanged on purpose,
        // so the move reads as a change on the same event.
        //
        // One header for the things that carry on from day to day, instead
        // of an uppercase kicker on each card — Today had seven of those,
        // and a label per card is a label nobody reads.
        //
        // Cover rows on the paper, as YouVersion lists plans (2026-10-24):
        // each thing in its own colour with where the player stands, and
        // space between rows rather than a card, dividers and chevrons. As
        // a grouped list it read as the Settings app — a Journey halfway
        // done looked like a menu item. The colour is per feature, which
        // reverses the neutral icons of 2026-10-13: at 52pt a cover is
        // artwork, where a 36pt tinted square in a list was decoration.
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            // On the page's one content edge, with the covers below it.
            Text("Keep going").sectionHeader()

            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                // A habit surface like the streak: only while a plan is
                // running, one row, checked once today's chapter is read.
                // `readingPlans` needs no Bible decode — the plan recorded
                // its chapter count at start.
                ReadingPlanCard(compact: true, onRead: openPlanChapter)

                // The first unfinished Journey, hidden once they're all
                // walked. A locked premium quest still shows — the card is
                // a discovery surface, and its detail screen carries the
                // paywall.
                if let quest = activeQuest(recordsByID) {
                    QuestHomeCard(
                        quest: quest,
                        progress: QuestProgress(quest: quest, recordsByID: recordsByID)
                    )
                }

                MemoryVerseCard(
                    dueCount: memoryVerses.dueCount,
                    activeCount: memoryVerses.entries.count,
                    masteredCount: memoryVerses.entries.count(where: \.isMastered),
                    nextReview: memoryVerses.entries
                        .compactMap { memoryVerses.dueDate($0) }
                        .filter { $0 > Date() }
                        .min(),
                    hasUnpracticed: memoryVerses.entries.contains { $0.lastPracticedAt == nil },
                    showsKicker: false
                )

                // A row like its neighbours rather than a card of its own with an
                // uppercase label and a progress bar: the badge is one more thing
                // to keep going at, and a full card for it made the column a
                // screen longer. Gone once every badge is earned.
                if let next = Achievements.all.first(where: { !$0.isUnlocked(by: profile) }) {
                    Button {
                        path.append(AchievementsRoute())
                    } label: {
                        NextAchievementRow(achievement: next, profile: profile)
                    }
                    .buttonStyle(PressableCardStyle())
                    .accessibilityHint("Opens every achievement")
                }
            }

            // The Bible: search, reading, plans and the books map, which had
            // a tab of their own until 2026-10-13 — about 1 in 20 actives did
            // anything there. A link under the list, not a row of it: Keep
            // going is progress, and a place to read isn't. A one-row card of
            // its own (tried 2026-10-24) read as stranded.
            Button {
                path.append(VersesRoute())
            } label: {
                Label("Open your Bible", systemImage: "book")
                    .font(.headline)
                    .foregroundStyle(Theme.accent)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, Theme.Spacing.s)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens search, reading and reading plans")
        }
        // The covers start on the page's one content edge — 32pt, where the
        // verse, the hero's title and the headers start.
        .padding(.horizontal, Theme.Spacing.m)

        // Only packs the player can open. For a free player every tile here
        // used to be locked behind a crown, a second pitch right above the
        // Premium card; locked packs keep their offer on the Packs tab. A
        // shelf of nothing but finished packs is a dead end, so it goes too.
        let packs = collectionPacks(recordsByID).filter { !$0.isPremium || store.isPremium }
        if packs.contains(where: { !PackProgress(pack: $0, recordsByID: recordsByID).isComplete }) {
            CollectionsCarousel(
                packs: packs,
                recordsByID: recordsByID,
                isPremium: store.isPremium,
                onShowAll: onShowPacks
            )
        }

        if !store.isPremium {
            UpgradeCard(
                totalPuzzles: puzzleProvider.totalPuzzleCount,
                solvedPuzzles: records.count { $0.isCompleted },
                currentStreak: profile.currentStreak,
                onOpen: { paywall = PaywallRequest(source: $0) }
            )
        }
    }

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

    // MARK: - Reading plan

    private func openPlanChapter() {
        guard let plan = readingPlans.activePlan, let day = readingPlans.nextDay else { return }
        analytics.log(.scriptureOpened(reference: "\(plan.book) \(day)", source: "read_plan"))
        path.append(PlanChapterRoute(planID: plan.id, book: plan.book, day: day))
    }

    private func markPlanRead(planID: String, day: Int) {
        // The plan the chapter was opened under — not one started since.
        guard let plan = readingPlans.activePlan, plan.id == planID,
              readingPlans.markRead(day: day) else { return }
        analytics.log(.planChapterRead(plan: plan.id, day: day))
        if readingPlans.isComplete {
            analytics.log(.planCompleted(plan: plan.id, days: day))
        }
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
        #if DEBUG
        // Screenshot helper: `-uiVerseID daily-091` pins the verse to that
        // puzzle's — same family as -uiRotationDate.
        let args = ProcessInfo.processInfo.arguments
        if let flag = args.firstIndex(of: "-uiVerseID"), flag + 1 < args.count,
           let pinned = puzzleProvider.puzzles.first(where: { $0.id == args[flag + 1] }) {
            return pinned
        }
        #endif
        let pool = puzzleProvider.puzzles.filter { $0.id != daily?.id }
        guard !pool.isEmpty else { return nil }
        // Counted from noon, not from `currentDay` itself: at local midnight
        // in BST `ordinality(of: .day, in: .era)` still returns the previous
        // day's number, so midnight would shift the whole rotation back a
        // day. Noon is inside the right day in every time zone, and matches
        // what `Date()` gave for most of the day before this moved off it.
        let noon = calendar.date(byAdding: .hour, value: 12, to: currentDay) ?? currentDay
        let day = calendar.ordinality(of: .day, in: .era, for: noon) ?? 0
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
    @Environment(\.inCardColumnSplit) private var inSplit

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            if let verse {
                scripture(verse)
            }
        }
        // The page's one content edge — the cards' inner edge — so the verse
        // starts where the headers and the hero's title do.
        .padding(.horizontal, Theme.Spacing.m)
        // Flush in a split, so "Verse of the day" starts level with the
        // first card at the top of the other column.
        .padding(.top, inSplit ? 0 : Theme.Spacing.s)
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
            readerRouter.open(reference: verse.reference, source: "verse_of_the_day")
        } label: {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    // A small label, not a section header: the verse and the
                    // puzzle title under it were two big serif headlines
                    // back to back, and the page had no one place to land.
                    Text("Verse of the day")
                        .kicker()
                    // Three lines, then truncate. Verses run from one line to
                    // six, and an unbounded header pushed the daily card's CTA
                    // below the fold on a 667pt screen while landing it in a
                    // different place every day. The reference below is the
                    // affordance for reading the whole passage.
                    // No line limit: the verse is the top of the app by
                    // decision, and a three-line clamp cut it mid-word
                    // ("…heard his praye…"). The longest in rotation is five.
                    // A step smaller in a split column: at title3 in half an
                    // opened iPhone Duo the verse ran five lines and pushed
                    // the day's puzzle halfway down. It keeps the top; it
                    // just stops taking the whole column to say it.
                    Text(verse.verse)
                        // Body, not title3: it keeps the top of the page but
                        // no longer outranks the day's puzzle beneath it.
                        .font(.scripture(.body))
                        .lineSpacing(6)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 4) {
                    Text(verse.reference)
                        .font(.headline)
                    Image(systemName: "chevron.forward")
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

    /// The kind of puzzle, as the hero's label names it.
    var name: String {
        switch self {
        case .daily: "Daily Puzzle"
        case .mini: "Daily Mini"
        case .sunday: "Sunday Special"
        }
    }

    /// The kind in a half-width card's title, where "Daily" on both would
    /// say nothing.
    var shortName: String {
        switch self {
        case .daily: "Daily"
        case .mini: "Mini"
        case .sunday: "Sunday"
        }
    }

    /// The solid fill when this puzzle leads Today, and its icon square in the
    /// row under the hero — see `Theme.heroDaily`.
    var heroFill: Color {
        switch self {
        case .daily: Theme.heroDaily
        case .mini: Theme.heroMini
        case .sunday: Theme.heroSunday
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
        case .mini: "\(puzzle.size)×\(puzzle.size) · two minutes"
        case .sunday: "\(puzzle.size)×\(puzzle.size) · this week's big grid"
        }
    }
}

// MARK: - Lead puzzle card
//
// The hero of the screen: a solid feature card in its puzzle's colour — blue
// for the daily, teal for the Mini, rust for the Special — with white type, a
// white pill and a faint crossword in the corner. Every other module is white,
// so the eye lands here first. It was a 10% accent wash until 2026-10-24: the
// palest card on the page carried the most important thing on it, while
// Journeys and memory practice elsewhere had already gone solid.
// When solved it becomes a quiet win moment (the time you earned) rather than
// a dead "done" tile.
//
// Which puzzle it carries is decided by the caller — see `TodayLead`.

private struct LeadPuzzleCard: View {
    let puzzle: Puzzle
    let billing: PuzzleBilling
    let presentation: DailyPresentation
    var progress: Double? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var celebrate = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            info
            actionButton
        }
        // 20 all round, the feature-card padding. The title keeps clear of
        // the motif in the corner (see `info`).
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(.white)
        .background(alignment: .topTrailing) {
            CrosswordMotif()
                .padding(20)
        }
        .elevatedCard(fill: billing.heroFill, cornerRadius: Theme.featureCornerRadius)
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
            // The kind, in sentence case — not an uppercase kicker, which
            // Today keeps for nothing. Now the hero changes colour by
            // occupant, it says which colour means what. The difficulty rides
            // in the meta row.
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(billing.name)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
                Text(puzzle.title)
                    .font(.title2.bold())
                    .fixedSize(horizontal: false, vertical: true)
            }
            // Clear of the motif in the corner: its five squares plus a gap.
            .padding(.trailing, 76)
            .frame(maxWidth: .infinity, alignment: .leading)

            switch presentation {
            case .solvedToday(let seconds):
                solvedReward(seconds)
            case .playedBefore(let previous):
                // Presented as playable, because it is: the meta row is
                // what an unsolved puzzle shows. With a time on record
                // the button ("Beat 4:24") already says both that it's
                // a repeat and what to aim for — a line above it saying
                // "Played before · your best 4:24" said it twice.
                metaRow
                if previous ?? 0 <= 0 {
                    replayPrompt
                }
            case .play:
                metaRow
                if let progress {
                    ProgressView(value: progress)
                        .tint(.white)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isHeader)
    }

    /// One line of plain text. It was a difficulty capsule and two icon
    /// labels, and with the status pill and the button under it the card
    /// stacked four capsule shapes — the button is the only one that should
    /// look like something to press.
    private var metaRow: some View {
        Text(metaLine)
            .font(.subheadline)
            // Explicit, not `.secondary`: the hierarchical style dims white
            // too far on the fill, under 4.5:1 at this size.
            .foregroundStyle(.white.opacity(0.9))
            .fixedSize(horizontal: false, vertical: true)
    }

    private var metaLine: String {
        "\(puzzle.difficulty.label) · \(puzzle.clueCount) clues · \(puzzle.size)×\(puzzle.size)"
    }

    // The win moment: leads with the time the user just earned, echoing the
    // CompletionView language (seal + monospaced clock). White on the fill:
    // green on blue or teal failed contrast and fought the card's colour.
    private func solvedReward(_ seconds: Int?) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: "checkmark.seal.fill")
                .symbolEffect(.bounce, value: celebrate)
            Text("Solved")
            if let secs = seconds, secs > 0 {
                Text("in \(TimeFormat.clock(secs))")
                    .monospacedDigit()
            }
        }
        .font(.subheadline.weight(.semibold))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The rotation has come back around to a puzzle this player finished on an
    /// earlier day, with no time on record — the button can only say "Play
    /// again", so this line says why.
    /// Plain text under the meta row, not an accent capsule: the card keeps a
    /// single pill — the button.
    private var replayPrompt: some View {
        Text("You've played this one before")
            .font(.subheadline.weight(.semibold))
            .fixedSize(horizontal: false, vertical: true)
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
            .buttonStyle(.pillOnColorTonal)
        case .playedBefore(let previous):
            // Prominent, unlike the solved-today replay: this *is* the day's
            // action, and the streak depends on it being taken. It names the
            // time to beat — a repeat offered as a target, not a rerun.
            NavigationLink(value: puzzle) {
                if let previous, previous > 0 {
                    Label("Beat \(TimeFormat.clock(previous))", systemImage: "stopwatch")
                } else {
                    Label("Play again", systemImage: "arrow.clockwise")
                }
            }
            .buttonStyle(.pillOnColor)
        case .play(let status):
            NavigationLink(value: puzzle) {
                Label(status.actionTitle, systemImage: status.actionSymbol)
            }
            .buttonStyle(.pillOnColor)
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
    /// Opens the Packs tab, where the whole shelf lives.
    let onShowAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            // "Packs", as the tab, the paywall and Settings call them. The
            // header is the way to the rest of the shelf, App Store–style:
            // the section title with a grey chevron after it.
            Button(action: onShowAll) {
                HStack(spacing: Theme.Spacing.xs) {
                    Text("Packs").sectionHeader()
                    Image(systemName: "chevron.forward")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // Taller to the finger than to the eye.
                .contentShape(.rect.inset(by: -10))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, Theme.Spacing.m)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("See all packs")
            .accessibilityAddTraits([.isHeader, .isButton])

            // Edge to edge: the scroll view reaches out through the column's
            // padding to the screen's sides, and the content margin puts the
            // first tile back in line with the cards above. Clipped at the
            // column inset instead, the third tile was cut off by an invisible
            // edge a few points short of the screen's. The negative padding
            // keeps the column's measured width unchanged.
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
                .scrollTargetLayout()
                // Give the row breathing room so the press scale isn't
                // clipped by the ScrollView edge.
                .padding(.vertical, 2)
            }
            // The column's own 16pt, so the first tile's edge sits on the cards'
            // edge above it. It was 20, four points in from every card.
            .contentMargins(.horizontal, Theme.Spacing.m, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .padding(.horizontal, -Theme.Spacing.m)
            // A scroll view draws its content on into the safe area, so with
            // the bars on a side rail (iPhone Duo closed) the third tile ran on
            // under the rail and its title showed through the glass. Clipped
            // at the frame, the row stops at the rail; with no rail the frame
            // already reaches the screen's edge, so nothing changes there.
            .clipped()
        }
    }
}

/// A compact, fixed-width pack card sized for the horizontal carousel.
private struct PackTile: View {
    let pack: PuzzlePack
    let progress: PackProgress
    let isLocked: Bool

    /// The cover band across the top of the tile. Scaled with the text so a
    /// larger size doesn't squeeze the title beneath it.
    @ScaledMetric(relativeTo: .subheadline) private var coverHeight = 72

    /// The tile is a fixed size so the carousel's rows line up, which means the
    /// tallest combination has to fit: the cover and a two-line title over the
    /// count. The badge rides on the cover, so it no longer adds a line — at
    /// 150, with the badge under the title, "Women of the Bible" pushed its
    /// puzzle count out past the bottom edge, and the height reserved for that
    /// line left every badgeless tile with a gap under its title. Scaled
    /// rather than a constant, because the text inside it scales.
    @ScaledMetric(relativeTo: .subheadline) private var tileHeight = 172
    @Environment(\.dynamicTypeSize) private var typeSize

    /// 160 holds a two-line title at standard sizes. At accessibility sizes the
    /// tile widens instead of clipping — at 160 the largest type cut every
    /// title to "She…" and broke "puzzles" across two lines. Still a
    /// carousel, so a wider tile costs a swipe, not the layout.
    private var tileWidth: CGFloat { typeSize.isAccessibilitySize ? 280 : 160 }

    /// The one badge this tile shows, if any, on the cover band.
    private var packBadge: PackBadge? { PackBadge.forPack(pack) }

    var body: some View {
        // Cover-led, as the App Store's and Books' shelves are: the pack's own
        // symbol and tint across the top, then the title and where you are.
        // It was a small chip above the title with about 60pt of empty card
        // under it — the tile's height was spent on nothing.
        VStack(alignment: .leading, spacing: 0) {
            cover

            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Text(pack.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 0)

                // Same rule as `PackCard`: a locked collection states its size, not
                // the player's progress through it. This tile was missed when that
                // landed, so the carousel could still show a crowned pack as
                // "Complete" — the one surface where it sat on the home screen.
                // An unstarted pack states its size too: an empty bar over "0/5"
                // is a gauge with nothing to measure.
                if isLocked || progress.solved == 0 {
                    Text("\(progress.total) puzzle\(progress.total == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                } else if progress.isComplete {
                    Label("Complete", systemImage: "checkmark.seal.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                } else {
                    ProgressView(value: progress.fraction).tint(pack.accent)
                    Text("\(progress.solved)/\(progress.total)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .padding(Theme.Spacing.m)
        }
        .frame(width: tileWidth, height: tileHeight, alignment: .topLeading)
        .elevatedCard()
        // The band runs to the tile's edge, so the tile clips it to its own
        // rounded shape rather than letting square corners show.
        .clipShape(.rect(cornerRadius: Theme.cornerRadius, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(accessibilityLabel)
    }

    /// The pack's symbol on a band of its own tint. Neutral while locked —
    /// colour means "you can open this" on every surface that lists a
    /// collection — with the crown in the corner. The fills match
    /// `CollectionCover`'s, so a pack is the same colour everywhere.
    private var cover: some View {
        Image(systemName: pack.coverSymbol)
            .font(.title)
            .foregroundStyle(isLocked ? AnyShapeStyle(.secondary) : AnyShapeStyle(pack.accent))
            .frame(maxWidth: .infinity)
            .frame(height: coverHeight)
            .background(isLocked ? Color.primary.opacity(0.06) : pack.accent.opacity(0.14))
            .overlay(alignment: .topTrailing) {
                if isLocked {
                    Image(systemName: "crown.fill")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                        .padding(Theme.Spacing.s)
                }
            }
            // "New" or "Closing soon" in the corner opposite the crown.
            .overlay(alignment: .topLeading) {
                if let packBadge {
                    packBadge
                        .padding(Theme.Spacing.s)
                }
            }
    }

    private var accessibilityLabel: String {
        var parts = [pack.title]
        if isLocked { parts.append("Premium") }
        if let packBadge { parts.append(packBadge.label) }
        parts.append(isLocked || progress.solved == 0
            ? "\(progress.total) puzzle\(progress.total == 1 ? "" : "s")"
            : (progress.isComplete ? "Complete" : "\(progress.solved) of \(progress.total) solved"))
        return parts.joined(separator: ". ")
    }
}

// MARK: - Next achievement row

/// The next badge, in the same row shape as the Journey and memory verses
/// above it.
private struct NextAchievementRow: View {
    let achievement: Achievement
    let profile: PlayerProfile

    var body: some View {
        // A time goal is met or not, so it gets no bar — an empty one would
        // sit there until the day it jumped to full.
        let fraction = achievement.progress(for: profile)
        let isTimeGoal: Bool = {
            if case .fastSolve = achievement.goal { return true }
            return false
        }()
        CoverRow(
            symbol: achievement.symbol,
            tint: FeatureTint.badge,
            title: achievement.title,
            subtitle: subtitle,
            progress: isTimeGoal || fraction <= 0 ? nil : fraction
        )
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Next badge: \(achievement.title). \(achievement.detail). \(progress)")
    }

    /// "Next badge · 3 / 5", or for a time goal the player's best against it —
    /// a time goal is met or not, so a bar for it sat empty until the day it
    /// jumped to full.
    ///
    /// Before the first step it names the goal instead: "Next badge · 0 / 5"
    /// told a new player only that they had done nothing yet.
    private var subtitle: String {
        guard achievement.progress(for: profile) > 0 else { return achievement.detail }
        return "Next badge · \(progress)"
    }

    private var progress: String {
        if case .fastSolve(let max) = achievement.goal {
            let goal = "under \(TimeFormat.clock(max))"
            guard let best = profile.bestSolveSeconds else { return goal }
            return "best \(TimeFormat.clock(best)), goal \(goal)"
        }
        return achievement.progressText(for: profile)
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
    /// The player's current run. At a week or more the card speaks to the
    /// habit rather than the catalogue — the moment the daily has proved its
    /// worth — and opens the paywall under its own label. A copy change on
    /// the card that's already here, not a new card: the last proactive
    /// Today offer was 75 opens and no taps.
    var currentStreak: Int = 0
    /// Opens the paywall under this card's source. HomeView presents it, so
    /// the sheet outlives the card a purchase removes.
    let onOpen: (PaywallSource) -> Void

    /// A week, the run length where the habit is a fact rather than a start.
    static let streakThreshold = 7
    private var isStreakVariant: Bool { currentStreak >= Self.streakThreshold }

    /// Read here rather than passed in: the CTA names the trial only when the
    /// product actually carries one — see `PremiumCopy.cardCTA`.
    @Environment(StoreService.self) private var store

    /// The player's own progress when they have some, and what's behind the
    /// wall when they don't.
    ///
    /// "You've solved 0" is a discouragement rather than a nudge — the same
    /// reason the paywall hides its progress line at zero.
    private var title: String {
        // What you get, with no number to parse.
        isStreakVariant ? "\(currentStreak) days in a row" : "Every puzzle. Every pack."
    }

    /// The one personal line, and the only place the count appears.
    private var subtitle: String {
        let left = max(totalPuzzles - solvedPuzzles, 0)
        if isStreakVariant {
            return "Keep it going with \(left) more puzzles and every hint."
        }
        guard solvedPuzzles > 0 else {
            return "\(totalPuzzles) puzzles, and hints whenever you need them."
        }
        return "You've solved \(solvedPuzzles). \(left) more are waiting."
    }

    var body: some View {
        // Redesigned 2026-10-13 after Apple's own subscription cards (Music,
        // iCloud+): a label, a headline about what you get, three benefits,
        // one full-width accent button and the price under it. The ink pill
        // it replaced was Continue's own style, so the offer read as one more
        // step in the game. Accent here, ink for play.
        //
        // Still a sheet on tap, as every other entry point presents it, and
        // never "Unlock" on the button: it opens the paywall, it doesn't buy
        // anything (see `PremiumCopy.cardCTA`).
        Button {
            onOpen(isStreakVariant ? .streakCard : .homeCard)
        } label: {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Label("Premium", systemImage: "crown.fill")
                        .font(.caption.weight(.bold))
                        .textCase(.uppercase)
                        .foregroundStyle(Theme.accent)
                    Text(title)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Color.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    benefit("square.grid.3x3", "Every daily, back to the first")
                    benefit("square.stack.3d.up", "All packs and Journeys")
                    benefit("lightbulb", "Hints whenever you need them")
                }

                PremiumOfferCTA()
            }
            .padding(Theme.Spacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .elevatedCard()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Premium. \(title) \(subtitle) Every daily, all packs and Journeys, and hints whenever you need them.\(terms.map { " \($0)" } ?? "")")
            .accessibilityHint(PremiumCopy.cardCTA(store))
        }
        .buttonStyle(PressableCardStyle())
    }

    private var terms: String? { PremiumCopy.terms(store) }

    /// Grey icons: blue is kept for the label and the button, the two things
    /// on the card that say "this is the offer".
    private func benefit(_ symbol: String, _ text: String) -> some View {
        Label {
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Color.primary)
        } icon: {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.secondary)
                .frame(width: 22)
        }
    }
}

// MARK: - Companion puzzles
//
// The day's other puzzles under the hero — the quick 7×7 for days (or
// moments) the full puzzle is too big, and the week's Sunday Special. Rows of
// one card rather than a card each: kept visually lighter than the hero so
// they read as the second course, not competing headlines.

/// A paywall Today presents, and the plan it should open on.
private struct PaywallRequest: Identifiable {
    let id = UUID()
    let source: PaywallSource
    var planID: String?
}

/// The trophy list, pushed from the next-achievement row.
private struct AchievementsRoute: Hashable {}

/// A reading-plan chapter, with the day it was opened on.
private struct PlanChapterRoute: Hashable {
    let planID: String
    let book: String
    let day: Int
}

/// Which of the day's puzzles takes the hero card.
private enum TodayLead {
    case daily, mini, sunday
}

/// The day's puzzles and their records, resolved once per body pass, so the
/// hero and the rows under it read the same state.
private struct TodayPuzzles {
    let daily: Puzzle?
    let dailyRecord: PuzzleRecord?
    let dailyPresentation: DailyPresentation
    let mini: Puzzle?
    let miniRecord: PuzzleRecord?
    let miniPresentation: DailyPresentation
    /// Nil inside the learning window.
    let sunday: Puzzle?
    let sundayRecord: PuzzleRecord?
    /// Week-based rather than day-based — see `HomeView.sundayPresentation`.
    let sundayPresentation: DailyPresentation

    func record(_ slot: TodayLead) -> PuzzleRecord? {
        switch slot {
        case .daily: dailyRecord
        case .mini: miniRecord
        case .sunday: sundayRecord
        }
    }

    func puzzle(_ slot: TodayLead) -> CompanionPuzzle? {
        switch slot {
        case .daily:
            daily.map { CompanionPuzzle(puzzle: $0, billing: .daily, presentation: dailyPresentation) }
        case .mini:
            mini.map { CompanionPuzzle(puzzle: $0, billing: .mini, presentation: miniPresentation) }
        case .sunday:
            sunday.map { CompanionPuzzle(puzzle: $0, billing: .sunday, presentation: sundayPresentation) }
        }
    }
}

/// One row of `CompanionPuzzlesCard`.
private struct CompanionPuzzle: Identifiable {
    let puzzle: Puzzle
    let billing: PuzzleBilling
    let presentation: DailyPresentation

    var id: String { puzzle.id }
}

private struct CompanionPuzzlesCard: View {
    let rows: [CompanionPuzzle]

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // Side by side, each led by a band in its own colour — the shape the
        // pack tiles below already have, and how YouVersion sets out the
        // day's pieces. As settings-style rows under the hero they read as
        // a menu. Stacked at accessibility sizes, where half the width can't
        // hold a title. AnyLayout keeps each card's identity across the swap.
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: Theme.Spacing.s))
            : AnyLayout(HStackLayout(alignment: .top, spacing: Theme.Spacing.s))
        layout {
            ForEach(rows) { row in
                CompactPuzzleRow(
                    puzzle: row.puzzle,
                    billing: row.billing,
                    presentation: row.presentation
                )
            }
        }
        // The pair shares a bottom edge however their titles wrap.
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct CompactPuzzleRow: View {
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

    @ScaledMetric(relativeTo: .headline) private var iconSize: CGFloat = 36

    var body: some View {
        NavigationLink(value: puzzle) {
            // The billing's mark in a square of its hero colour — the colour
            // the card above wears when this puzzle leads — beside the kind
            // and where the player stands. It was a 64pt band over the text
            // until 2026-10-24: two cards each nearly as tall as the hero.
            // The title is in the VoiceOver label; on the card the kind says
            // enough to choose by.
            HStack(spacing: Theme.Spacing.s + 4) {
                Image(systemName: leadingSymbol)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: iconSize, height: iconSize)
                    .background(billing.heroFill, in: .rect(cornerRadius: iconSize * 0.28, style: .continuous))

                VStack(alignment: .leading, spacing: 0) {
                    Text(billing.shortName)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    // Wraps rather than truncates at large type.
                    Text(state)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .elevatedCard()
            .contentShape(.rect)
        }
        .buttonStyle(PressableCardStyle())
        // Ignoring the children drops the link's button trait with them.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
    }

    /// Solved wears the green check; unsolved leads with the billing's own
    /// mark, so the Special's row reads as an occasion rather than a second
    /// bolt of the same kind.
    /// The bolt means "quick", which is the Mini's trait; the daily gets the
    /// calendar it's billed under. Both used to share the bolt.
    private var leadingSymbol: String {
        if isSolvedToday { return "checkmark" }
        switch billing {
        case .mini: return "bolt.fill"
        case .daily: return "calendar"
        case .sunday: return "star.fill"
        }
    }

    private var state: String {
        switch presentation {
        case .solvedToday(let seconds):
            if let secs = seconds, secs > 0 {
                return "Solved in \(TimeFormat.clock(secs))"
            }
            return "Solved"
        case .playedBefore(let previous):
            // "Your best" alone says it's a repeat; "Played before" in front
            // of it was the third time the first screen said so.
            if let previous, previous > 0 {
                return "Your best \(TimeFormat.clock(previous))"
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
            return "\(billing.spoken). \(puzzle.title). \(state)."
        case .play:
            return "\(billing.spoken). \(puzzle.title). \(billing.blurb(puzzle))."
        }
    }
}

