//
//  HomeView.swift
//  Bible Crossword Challenge
//
//  The "Today" tab. The screen opens like a page rather than a dashboard: the
//  day's verse set in serif on the bare paper, and only then the daily puzzle
//  — the one card that carries a tint and the one pill, so the hero is
//  unmistakable among the white cards below it: the day's other puzzles, the
//  streak, "Keep going" (plan, Journey, memory verses, next badge), the
//  Bible link, the Premium row, then the packs shelf when there's a shelf. Uppercase labels are section headers
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
    /// The solved hero's locked Next button was on screen this visit — the
    /// impression logs once (CLAUDE.md: once-per-visit guard on Today, whose
    /// identity is stable; the card itself sits in an if/else).
    @State private var didLogHeroNext = false

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

    /// Daily Bread (`DailyRitual`). The verse sheet lives here, not on the
    /// card: the card is in an `if`, and a sheet it owned would go with it.
    @State private var ritualVerse: DailyRitual.Verse?
    /// The day the card's impression was logged this launch — once per day,
    /// not once per pop back (CLAUDE.md).
    @State private var ritualShownDay: Date?
    /// The last row tapped, for `daily_ritual_completed.last_beat`.
    @State private var lastRitualBeat: DailyRitual.Beat?
    /// The day beat two was done, as seconds since 1970 (0 = never). The only
    /// stored part of the ritual — see `DailyRitual`.
    @AppStorage("dailyRitualVerseDay") private var ritualVerseDay = 0.0
    /// The day `daily_ritual_completed` last logged, so the ring closing logs
    /// once per day however many times Today reappears.
    @AppStorage("dailyRitualCompletedDay") private var ritualCompletedDay = 0.0

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

    /// Where the solved hero points next: the first Journey with steps left
    /// (`activeQuest`), unless a step of it was already taken today — a
    /// Journey is a step a day, and its own card says "back tomorrow".
    ///
    /// Theme B, 2026-11: once the day's puzzle is solved the hero was a dead
    /// end with a Play again button, on the screen every daily player sees.
    /// In-app paywall sources that showed specific content sold (Today's
    /// Premium row 4 of 13, a locked Journey 2 of 14); a locked Journey here
    /// opens its page, which carries the paywall (`quest_locked`).
    private func heroNextJourney(_ presentation: DailyPresentation) -> QuestLine? {
        guard case .solvedToday = presentation,
              let quest = activeQuest(recordsByID) else { return nil }
        let progress = QuestProgress(quest: quest, recordsByID: recordsByID)
        return progress.steppedToday ? nil : quest
    }

    private func logHeroNextIfLocked() {
        guard !didLogHeroNext, let quest = activeQuest(recordsByID),
              quest.isPremium, !store.isPremium else { return }
        didLogHeroNext = true
        analytics.log(.upsellShown(source: "today_hero"))
    }

    /// The first Journey with steps left, in authored order (the free quest is
    /// authored first, so a new player's card always begins there). Nil once
    /// every quest is walked — the card earns its slot or gives it back.
    private func activeQuest(_ recordsByID: [String: PuzzleRecord]) -> QuestLine? {
        puzzleProvider.quests.first {
            $0.id != BeginnerPath.questID &&
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

    /// The badge Today names, when one is close: a counted goal two or
    /// fewer short, nearest first. Never on the day the player joined, and
    /// never a time goal, which is met or not and so is never "close".
    private var badgeWithinReach: Achievement? {
        guard !Calendar.current.isDate(profile.createdAt, inSameDayAs: currentDay) else { return nil }
        return Achievements.withinReach(for: profile)
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
        // Orange means there is a streak. A paused one at 0 takes the grey
        // outline, as Fitness draws an empty ring, rather than celebrating
        // nothing.
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

        let ritual = dailyRitual()

        return NavigationStack(path: $path) {
            CardColumns {
                leadColumn(today, lead: lead, recordsByID: byID, ritual: ritual)
            } more: {
                moreColumn(byID, heroPuzzleID: today.puzzle(lead)?.puzzle.id,
                           heroNextQuestID: heroNextQuestID(today, lead: lead, recordsByID: byID))
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
                // A beat finished on a pushed screen closes the ring here,
                // on the way back.
                logRitualCompletedIfNeeded(ritual)
            }
            .onChange(of: ritual?.isComplete) { logRitualCompletedIfNeeded(ritual) }
            .sheet(item: $ritualVerse, onDismiss: { markRitualVerseRead(learned: false) }) { verse in
                RitualVerseSheet(
                    verse: verse,
                    canLearn: canLearn(verse),
                    onLearn: { learnRitualVerse(verse) },
                    onDone: { ritualVerse = nil }
                )
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
                // From day two, when there is a run to lose; a 1 said
                // nothing and took the bar's one slot (2026-10-25). A
                // broken run keeps it, greyed, while its comeback waits.
                if profile.currentStreak >= 2 || pendingStreakBreak > 0 {
                    ToolbarItem(placement: .topBarTrailing) { streakButton }
                }
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
            .navigationDestination(for: BeginnerPuzzleRoute.self) { route in
                CrosswordGameView(puzzle: route.puzzle, profile: profile, entrySource: route.entrySource)
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
            .navigationDestination(for: DailyRitualPuzzleRoute.self) { route in
                CrosswordGameView(puzzle: route.puzzle, profile: profile, entrySource: "daily_ritual")
            }
            .navigationDestination(for: JourneyPuzzleRoute.self) { route in
                CrosswordGameView(puzzle: route.puzzle, profile: profile, entrySource: "journey")
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
    private func leadColumn(_ today: TodayPuzzles, lead: TodayLead, recordsByID: [String: PuzzleRecord],
                            ritual: DailyRitual?) -> some View {
        let beginnerQuest = puzzleProvider.quest(id: BeginnerPath.questID)
        let beginnerProgress = beginnerQuest.map {
            QuestProgress(quest: $0, recordsByID: recordsByID, now: currentDay, calendar: calendar)
        }
        let beginner = beginnerProgress.flatMap { progress in
            BeginnerPath.shouldFeature(totalCompleted: profile.totalPuzzlesCompleted, progress: progress)
                ? BeginnerPath.next(provider: puzzleProvider, recordsByID: recordsByID) : nil
        }
        TodayHeader(verse: verseOfTheDay(excluding: beginner ?? today.daily))

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
        if let beginner, let beginnerProgress {
            BeginnerPathCard(puzzle: beginner, progress: beginnerProgress,
                             hasEntries: recordsByID[beginner.id]?.hasPlayerEntries == true)
        } else if let hero = today.puzzle(lead) {
            let next = heroNextJourney(hero.presentation)
            LeadPuzzleCard(
                puzzle: hero.puzzle,
                billing: hero.billing,
                presentation: hero.presentation,
                progress: inProgressFraction(hero.puzzle, record: today.record(lead)),
                next: next,
                nextLocked: next.map { $0.isPremium && !store.isPremium } ?? false,
                onNextSeen: logHeroNextIfLocked
            )
        } else {
            emptyDailyCard
        }

        // The day's other puzzles as rows of one card, not a card each:
        // they are one idea ("also today"), and two white cards stacked
        // under the hero read as two more headlines.
        let companions = beginner == nil
            ? companionPuzzles(today, lead: lead)
            : [TodayLead.mini, .daily, .sunday].compactMap { today.puzzle($0) }
                .filter { $0.puzzle.id != beginner?.id }
        if !companions.isEmpty {
            CompanionPuzzlesCard(rows: companions)
        }

        // Daily Bread, right under the day's puzzles: the puzzle is its first
        // beat, so it reads as what the day's solve is part of.
        if let ritual {
            let play = beginner ?? today.puzzle(lead)?.puzzle
            DailyRitualCard(
                ritual: ritual,
                puzzleTitle: play?.title,
                onBeat: { beat in tapRitualBeat(beat, ritual: ritual, play: play) },
                onSeen: { logRitualShown(ritual) }
            )
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
    /// The Journey the solved hero is pointing at, when the hero is the lead
    /// card (not Your First Seven's) — so Keep going can leave it out rather
    /// than list it a second time right under the button.
    private func heroNextQuestID(_ today: TodayPuzzles, lead: TodayLead,
                                 recordsByID: [String: PuzzleRecord]) -> String? {
        let beginnerFeatured = puzzleProvider.quest(id: BeginnerPath.questID).map {
            BeginnerPath.shouldFeature(
                totalCompleted: profile.totalPuzzlesCompleted,
                progress: QuestProgress(quest: $0, recordsByID: recordsByID, now: currentDay, calendar: calendar)
            )
        } ?? false
        guard !beginnerFeatured, let hero = today.puzzle(lead) else { return nil }
        return heroNextJourney(hero.presentation)?.id
    }

    @ViewBuilder
    private func moreColumn(_ recordsByID: [String: PuzzleRecord], heroPuzzleID: String?,
                            heroNextQuestID: String? = nil) -> some View {
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
        // Cover rows in one grouped card (2026-11-03). They were bare on the
        // paper from 2026-10-24, when each cover was its feature's colour
        // and read as artwork; grey since the one-colour pass, they read
        // as unfinished without a card around them.
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            // On the page's one content edge (32pt), where the verse and the
            // hero's title start; the cards below sit on the cards' edge.
            Text("Keep going").sectionHeader()
                .padding(.horizontal, Theme.Spacing.m)

            // One white grouped card since 2026-11-03, as Profile's rows are:
            // with the covers grey (one-colour pass) the bare rows read as
            // grey squares floating on the system grey.
            CardGroup(dividerInset: Theme.Spacing.m + CoverRow.coverSide + Theme.Spacing.m) {
                // A habit surface like the streak: only while a plan is
                // running, one row, checked once today's chapter is read.
                // `readingPlans` needs no Bible decode — the plan recorded
                // its chapter count at start.
                ReadingPlanCard(compact: true, onRead: openPlanChapter)

                // The first unfinished Journey, hidden once they're all
                // walked. A locked premium quest still shows — the card is
                // a discovery surface, and its detail screen carries the
                // paywall.
                if let quest = activeQuest(recordsByID), quest.id != heroNextQuestID {
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
                // screen longer. Only when one is in reach (2026-10-24): as a
                // standing row it asked a new player for five puzzles before
                // their first. Badges stays a tap away in Profile.
                if let next = badgeWithinReach {
                    Button {
                        path.append(AchievementsRoute())
                    } label: {
                        NextAchievementRow(achievement: next, profile: profile)
                    }
                    .buttonStyle(PressableCardStyle())
                    .accessibilityHint("Opens your badges")
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
            .padding(.horizontal, Theme.Spacing.m)
            .accessibilityHint("Opens search, reading and reading plans")

            // The offer as one row, last on the page (2026-10-24). It was a
            // card of its own under the shelf — chip, headline, three benefits
            // and a blue button, the biggest thing on Today after the daily,
            // opened by 22 players in the 30 days to 2026-10-03. Not in Keep
            // going: that list is the player's own progress, and an offer
            // inside it read as one more badge. Set apart by space, and by the
            // solid gold the Premium mark wears everywhere.
            if !store.isPremium {
                // A one-row card of its own (2026-11-03), apart from the
                // group above so the offer doesn't read as one more item
                // of the player's progress.
                CardGroup {
                    UpgradeRow(
                        currentStreak: profile.currentStreak,
                        onOpen: { paywall = PaywallRequest(source: $0) }
                    )
                }
                .padding(.top, Theme.Spacing.s)
            }
        }

        // Locked packs show again (2026-11-04), after the ones the player can
        // open — `collectionPacks` ranks them there. Hidden since 2026-10-24
        // as "a second pitch", but the 30-day readout says wanting a locked
        // collection is what sells: locked pack/journey/archive pages tap
        // through at ~21% against 1% for the hint wall, and they were opened
        // only 38 times because Today never showed one. The tile's lock says
        // Premium; its page carries the trial button. A shelf of nothing but
        // finished packs is still a dead end, and a shelf of one still goes.
        let packs = collectionPacks(recordsByID)
        if packs.count > 1,
           packs.contains(where: { !PackProgress(pack: $0, recordsByID: recordsByID).isComplete }) {
            CollectionsCarousel(
                packs: packs,
                recordsByID: recordsByID,
                isPremium: store.isPremium,
                onShowAll: onShowPacks
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

    // MARK: - Daily Bread

    /// Nil before the first finished puzzle: the first sitting belongs to the
    /// onboarding hand-off and the first real grid (plan, Bet 1), and a
    /// checklist there is one more thing to read before typing. From the
    /// first finish on it's for everyone, free or Premium.
    private func dailyRitual() -> DailyRitual? {
        guard profile.totalPuzzlesCompleted >= 1 else { return nil }
        let solves: [DailyRitual.Solve] = records.compactMap { record in
            guard record.isCompleted, let at = record.completedDate,
                  calendar.isDate(at, inSameDayAs: currentDay),
                  let puzzle = puzzleProvider.puzzle(id: record.puzzleID),
                  !puzzle.verse.isEmpty, !puzzle.reference.isEmpty else { return nil }
            return DailyRitual.Solve(reference: puzzle.reference, verse: puzzle.verse, completedAt: at)
        }
        return DailyRitual.make(
            day: currentDay,
            calendar: calendar,
            solvesToday: solves,
            verseReadDay: ritualVerseDay > 0 ? Date(timeIntervalSince1970: ritualVerseDay) : nil,
            memory: memoryVerses
        )
    }

    private func logRitualShown(_ ritual: DailyRitual) {
        guard ritualShownDay.map({ !calendar.isDate($0, inSameDayAs: currentDay) }) ?? true else { return }
        ritualShownDay = currentDay
        analytics.log(.dailyRitualShown(beatsDone: ritual.doneCount))
    }

    private func logRitualCompletedIfNeeded(_ ritual: DailyRitual?) {
        guard let ritual, ritual.isComplete else { return }
        let last = Date(timeIntervalSince1970: ritualCompletedDay)
        guard ritualCompletedDay == 0 || !calendar.isDate(last, inSameDayAs: currentDay) else { return }
        ritualCompletedDay = currentDay.timeIntervalSince1970
        analytics.log(.dailyRitualCompleted(lastBeat: lastRitualBeat?.rawValue ?? "elsewhere"))
    }

    private func tapRitualBeat(_ beat: DailyRitual.Beat, ritual: DailyRitual, play: Puzzle?) {
        lastRitualBeat = beat
        analytics.log(.dailyRitualBeatTapped(beat: beat.rawValue))
        switch beat {
        case .puzzle:
            if let play { path.append(DailyRitualPuzzleRoute(puzzle: play)) }
        case .verse:
            ritualVerse = ritual.verse
        case .review:
            switch ritual.review {
            case .practice(let key, _, _):
                path.append(MemoryPracticeRoute(referenceKey: key, source: "daily_ritual"))
            case .learn(let verse):
                startRitualVerse(verse)
            case .choose:
                path.append(MemoryRoute(source: "daily_ritual"))
            case .waitingForVerse, nil:
                break
            }
        }
    }

    /// The verse can go on the shelf from beat two: it fits the grid, isn't
    /// there already, and a free player has room (`freeVerseLimit`).
    private func canLearn(_ verse: DailyRitual.Verse) -> Bool {
        MemoryCloze.isEligible(verseText: verse.text)
            && memoryVerses.entry(for: verse.id) == nil
            && memoryVerses.canStartNewVerse(isPremium: store.isPremium)
    }

    /// Beat two done. Idempotent per day: the sheet's buttons and its
    /// dismissal both land here, and a re-read logs nothing new.
    private func markRitualVerseRead(learned: Bool) {
        guard let verse = dailyRitual()?.verse else { return }
        let read = Date(timeIntervalSince1970: ritualVerseDay)
        guard ritualVerseDay == 0 || !calendar.isDate(read, inSameDayAs: currentDay) else { return }
        ritualVerseDay = currentDay.timeIntervalSince1970
        analytics.log(.dailyRitualVerseRead(reference: verse.reference, learned: learned))
    }

    /// "Learn it by heart" on beat two: read, shelved, and the review beat now
    /// points at it (`DailyRitual.reviewPick` puts a verse started today first).
    private func learnRitualVerse(_ verse: DailyRitual.Verse) {
        if canLearn(verse) {
            memoryVerses.start(reference: verse.reference, verseText: verse.text)
            analytics.log(.memoryVerseAdded(reference: verse.reference, source: "daily_ritual"))
        }
        markRitualVerseRead(learned: true)
        ritualVerse = nil
    }

    /// Beat three with nothing on the shelf: today's verse goes on and opens
    /// as its first grid.
    private func startRitualVerse(_ verse: DailyRitual.Verse) {
        if memoryVerses.entry(for: verse.id) == nil {
            memoryVerses.start(reference: verse.reference, verseText: verse.text)
            analytics.log(.memoryVerseAdded(reference: verse.reference, source: "daily_ritual"))
        }
        path.append(MemoryPracticeRoute(referenceKey: verse.id, source: "daily_ritual"))
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
        return puzzleProvider.verseOfTheDay(on: currentDay, excluding: daily?.id, calendar: calendar)
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
        // Flush in a split, so "Verse of the day" starts level with the
        // first card at the top of the other column.
        .padding(.top, inSplit ? 0 : Theme.Spacing.s)
    }

    /// Scripture in a plain card, labelled. No rule or quote glyph: the
    /// serif is the only serif on the page, and that is the signal.
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
                    // Sentence case, as every other label on Today: the
                        // uppercase eyebrow was the last one on the page.
                    Text("Verse of the day")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
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

                // Ink, not blue: the whole card is the tap target, and
                // Start Puzzle below should be the only blue on the screen.
                HStack(spacing: 4) {
                    Text(verse.reference)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Image(systemName: "chevron.forward")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // A card like every other section: bare on the grouped canvas
            // the verse read as stray text, not part of the page.
            .padding(Theme.Spacing.l)
            .elevatedCard()
        }
        .buttonStyle(PressableCardStyle())
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
        // Clues only: "15×15 · 20 clues" broke after the dot on a third-
        // width tile, and the kind above it already says it's the big grid.
        case .daily: "\(puzzle.clueCount) clues"
        case .mini: "About 2 min"
        // How long this one stays: "Every Sunday" was a schedule, and on a
        // Thursday told the player nothing. One phrase — "21×21 · this week"
        // broke after the dot on a third-width tile.
        case .sunday: "This week"
        }
    }
}

// MARK: - Lead puzzle card
//
// The hero of the screen: a white card with ink type and the page's one blue
// pill. It was a solid fill in its puzzle's colour (blue daily, teal Mini,
// rust Special) with a crossword motif until 2026-11-02 — too much colour for
// an Apple-plain screen; the button alone carries the blue now.
// When solved it becomes a quiet win moment (the time you earned) rather than
// a dead "done" tile.
//
// Which puzzle it carries is decided by the caller — see `TodayLead`.

private struct LeadPuzzleCard: View {
    let puzzle: Puzzle
    let billing: PuzzleBilling
    let presentation: DailyPresentation
    var progress: Double? = nil
    /// Once solved today, the Journey to carry on with — see
    /// `HomeView.heroNextJourney`. Nil keeps Play again.
    var next: QuestLine? = nil
    var nextLocked = false
    var onNextSeen: () -> Void = {}

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
        // White with ink type since 2026-11-02, not a solid fill in the
        // puzzle's colour: Today keeps one colour, and it's the button's.
        .elevatedCard(cornerRadius: Theme.featureCornerRadius)
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
                    .foregroundStyle(.secondary)
                Text(puzzle.title)
                    .font(.title2.bold())
                    .fixedSize(horizontal: false, vertical: true)
            }
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
                        .tint(Theme.progressBar)
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
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var metaLine: String {
        "\(puzzle.difficulty.label) · \(puzzle.clueCount) clues · \(puzzle.size)×\(puzzle.size)"
    }

    // The win moment: leads with the time the user just earned, echoing the
    // CompletionView language (seal + monospaced clock), the seal in the
    // app's solved green.
    private func solvedReward(_ seconds: Int?) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(FeatureTint.solved)
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
            if let next {
                // Instead of Play again, not beside it: one action per card,
                // and replaying a puzzle solved minutes ago is the weaker one
                // (it stays a tap away in Puzzles). Tonal like the replay it
                // replaces; the crown says Premium, the page says the rest.
                NavigationLink(value: QuestRoute(quest: next, source: .todayHero)) {
                    Label("Next: \(next.title)",
                          systemImage: nextLocked ? "crown.fill" : next.coverSymbol)
                }
                .buttonStyle(.pillTonal)
                .accessibilityIdentifier("heroNextJourney")
                .onScrollVisibilityChange(threshold: 0.6) { visible in
                    if visible { onNextSeen() }
                }
            } else {
                // Full-width but secondary (tonal) — replay stays available without
                // out-shouting the ink pill used for unsolved puzzles.
                NavigationLink(value: puzzle) {
                    Label("Play again", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.pillTonal)
            }
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
            .buttonStyle(.pillAccent)
        case .play(let status):
            NavigationLink(value: puzzle) {
                Label(status.actionTitle, systemImage: status.actionSymbol)
            }
            .buttonStyle(.pillAccent)
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

    @Environment(\.puzzleProvider) private var puzzleProvider
    @Environment(\.dynamicTypeSize) private var typeSize

    /// 160 holds a two-line title at standard sizes; at accessibility sizes
    /// the tile widens instead of clipping. Still a carousel, so a wider tile
    /// costs a swipe, not the layout.
    private var tileWidth: CGFloat { typeSize.isAccessibilitySize ? 280 : 160 }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            // "Packs", as the paywall and Settings call them (the shelf is on the
            // Puzzles tab since 2026-11-03). The
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
                HStack(alignment: .top, spacing: Theme.Spacing.m) {
                    ForEach(packs) { pack in
                        NavigationLink(value: PackRoute(pack: pack, source: .home)) {
                            tile(pack, progress: PackProgress(pack: pack, recordsByID: recordsByID))
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

    /// The same cover the Puzzles tab shelves a pack with (2026-11-04): ink
    /// mark and the pack's first grid on a white card. The tinted symbol band
    /// this replaced was the last colour block left on Today.
    private func tile(_ pack: PuzzlePack, progress: PackProgress) -> some View {
        let locked = pack.isPremium && !isPremium
        let size = "\(progress.total) puzzle\(progress.total == 1 ? "" : "s")"
        // A locked or unstarted pack states its size, never progress.
        let meta = locked ? size
            : progress.isComplete ? "Complete"
            : progress.solved > 0 ? "\(progress.solved) of \(progress.total) solved"
            : size
        let puzzles = puzzleProvider.puzzles(in: pack)
        return ShelfTile(
            title: pack.title,
            meta: meta,
            label: PackCoverLabel(puzzles: puzzles),
            grid: puzzles.first?.grid,
            fallbackSymbol: pack.coverSymbol,
            isLocked: locked,
            badge: PackBadge.forPack(pack)
        )
        .frame(width: tileWidth)
    }
}


// MARK: - Next achievement row

/// The next badge, in the same row shape as the Journey and memory verses
/// above it.
private struct NextAchievementRow: View {
    let achievement: Achievement
    let profile: PlayerProfile

    var body: some View {
        // No bar (2026-11-04): Today's rows say where things stand in
        // words, and the subtitle already counts it.
        CoverRow(
            symbol: achievement.symbol,
            tint: FeatureTint.badge,
            title: achievement.title,
            subtitle: subtitle
        )
        .cardRowPadding()
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Next badge: \(achievement.title). \(achievement.detail). \(progress)")
    }

    /// "Badge · Complete 5 puzzles · 2 to go". It leads with what the row
    /// is: titled "First Journey" under a Journey row, "Next badge" at the
    /// end of the line read as a second Journey (2026-11-04). The goal names
    /// what earns it; the count only when there's more than one left.
    private var subtitle: String {
        var parts = ["Badge", achievement.detail]
        if let left = achievement.remaining(for: profile) {
            if left > 1 { parts.append("\(left) to go") }
        } else if case .fastSolve = achievement.goal, let best = profile.bestSolveSeconds {
            parts.append("best \(TimeFormat.clock(best))")
        }
        return parts.joined(separator: " · ")
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

// MARK: - Upgrade row

/// Premium, as one row at the foot of Today: the solid gold crown, what it
/// is, and the trial. It was a card of its own — see `moreColumn`.
private struct UpgradeRow: View {
    /// The player's current run. At a week or more the row speaks to the
    /// habit rather than the catalogue, and opens the paywall under its own
    /// label (`streak_card`), so the two series carry on from the card.
    let currentStreak: Int
    /// Opens the paywall under this row's source. HomeView presents it, so
    /// the sheet outlives the row a purchase removes.
    let onOpen: (PaywallSource) -> Void

    /// A week, the run length where the habit is a fact rather than a start.
    static let streakThreshold = 7
    private var isStreakVariant: Bool { currentStreak >= Self.streakThreshold }

    /// Read here rather than passed in: the row names the trial only when
    /// the product actually carries one — see `PremiumCopy.cardCTA`.
    @Environment(StoreService.self) private var store

    private var hasTrial: Bool {
        store.yearly.map { store.introOffer(for: $0) != nil } ?? false
    }

    private var title: String {
        isStreakVariant ? "\(currentStreak) days in a row" : "Premium"
    }

    /// The trial when there is one, never "Unlock": the row opens the
    /// paywall, it doesn't buy anything.
    private var subtitle: String {
        let offer = hasTrial ? PremiumCopy.cardCTA(store) : "See plans"
        return isStreakVariant
            ? "Go further with Premium · \(offer.lowercased())"
            : "\(offer) · every pack and Journey"
    }

    var body: some View {
        Button {
            onOpen(isStreakVariant ? .streakCard : .homeCard)
        } label: {
            CoverRow(symbol: "crown.fill", tint: Theme.badgeRim, title: title, subtitle: subtitle)
                .cardRowPadding()
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("\(title). \(subtitle)")
        .accessibilityHint("Opens Premium plans")
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

/// Daily Bread's first row: the hero's puzzle, opened with its own
/// `daily_puzzle_started.source` so the card's pull reads apart from the hero.
private struct DailyRitualPuzzleRoute: Hashable {
    let puzzle: Puzzle
}

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
                    presentation: row.presentation,
                    // Three across (a Sunday): a third of the width needs a
                    // third line for the title.
                    isNarrow: rows.count > 2 && !typeSize.isAccessibilitySize
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
    /// A tile a third wide (three across): the title gets a third line.
    var isNarrow = false

    /// Only a puzzle finished today wears the green check. Each pool wraps on
    /// its own schedule — the mini's eight days after the daily's — and a repeat
    /// there tells the same streak-ending lie.
    private var isSolvedToday: Bool {
        if case .solvedToday = presentation { return true }
        return false
    }

    /// The state, green with a check once today's is solved — the only
    /// colour on the tile, and only when it means "done".
    @ViewBuilder private var stateLine: some View {
        if isSolvedToday {
            Label(state, systemImage: "checkmark.circle.fill")
                .labelStyle(.titleAndIcon)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(FeatureTint.solved)
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(state)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    var body: some View {
        NavigationLink(value: puzzle) {
            // Kind, then the puzzle's own name, then where the player
            // stands (2026-11-04). It led with a grey icon chip over the kind
            // alone, so three tiles said "Mini / Daily / Sunday" and nothing
            // about today: the chip was in the title's place. The solved
            // check moved into the state line, the one place it means
            // something.
            VStack(alignment: .leading, spacing: 2) {
                Text(billing.shortName)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(puzzle.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(isNarrow ? 3 : 2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Theme.Spacing.s)
                stateLine
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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

    private var state: String {
        switch presentation {
        case .solvedToday(let seconds):
            if let secs = seconds, secs > 0 {
                // The time alone: the green check already says solved, and
                // "Solved in 2:34" wrapped in a third-width tile. VoiceOver
                // still hears "Solved in".
                return TimeFormat.clock(secs)
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
            // The size went (2026-10-25): "In progress · 7×7" wrapped on a
            // 17e, and the row's kind already says which grid it is.
            return "In progress"
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

