//
//  RootView.swift
//  Bible Crossword Challenge
//
//  Ensures a single local profile exists, normalises the streak on launch, and
//  hosts the main tab navigation.
//

import SwiftUI
import SwiftData
import os

/// The main tab bar's selectable tabs.
enum RootTab: Hashable {
    case today, packs, library, achievements, profile
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.analytics) private var analytics
    @Environment(\.notifications) private var notifications
    @Environment(\.gameCenter) private var gameCenter
    @Environment(\.readerRouter) private var readerRouter
    @Environment(\.puzzleProvider) private var puzzleProvider
    @Environment(\.challengeService) private var challengeService
    @Environment(\.familyBoard) private var familyBoard
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab: RootTab = .today
    /// A puzzle a challenge or family board asked for before onboarding
    /// finished — opened once the player is set up (see the onboarding-finish
    /// closure). The payload is already stored by its own service; all that's
    /// deferred is the navigation.
    @State private var pendingNavPuzzleID: String?
    /// A challenge link from a newer app version or for an unknown puzzle.
    @State private var showChallengeUpdateAlert = false
    /// Navigation stack for the Today tab. Held here so a widget deep-link can
    /// push the daily puzzle onto it. Type-erased so the Today feed can push both
    /// puzzles and pack details.
    @State private var todayPath = NavigationPath()
    /// Navigation stack for the Packs tab, held here for the same reason as
    /// `todayPath`: a season-opening notification deep-links into a pack.
    @State private var packsPath = NavigationPath()
    // Sorted so `first` is the oldest profile — the survivor SyncMerge keeps
    // when CloudKit sync delivers a duplicate from another device.
    @Query(sort: \PlayerProfile.createdAt) private var profiles: [PlayerProfile]
    @AppStorage("hasOnboarded") private var hasOnboarded = false
    @AppStorage("remindersEnabled") private var remindersEnabled = false
    @AppStorage("reminderMinutes") private var reminderMinutes = ReminderTime.defaultMinutes
    /// Set the first time the day-2 reminder prompt is shown, whatever the
    /// answer. One second ask is a nudge; a recurring one is nagging.
    /// Start-of-day stamp of the last reminder ask on any surface (this sheet,
    /// completion card, streak card) — the shared one-ask-per-day budget.
    /// Set by ProfileView when it hands the player to Settings to allow
    /// notifications; cleared here once they come back with an answer.
    @AppStorage("pendingReminderOptIn") private var pendingReminderOptIn = false
    /// The streak length lost on a launch where it broke, or 0 for none —
    /// what Today's comeback card is keyed on. `UserDefaults` rather than a
    /// field on `PlayerProfile`: it's a transient piece of UI state, and a new
    /// synced field would mean a CloudKit schema deploy before this could ship.
    @AppStorage("pendingStreakBreak") private var pendingStreakBreak = 0

    var body: some View {
        Group {
            if let profile = profiles.first {
                if !hasOnboarded {
                    OnboardingView(profile: profile) {
                        context.saveLogged("onboarding finish")
                        withAnimation { hasOnboarded = true }
                        // A challenge or board link that arrived mid-onboarding
                        // was stashed; now that the tabs exist, jump into it.
                        if let id = pendingNavPuzzleID {
                            pendingNavPuzzleID = nil
                            openPuzzle(id: id)
                        } else if let mini = puzzleProvider.dailyMini() {
                            // Straight into the Mini rather than onto Today.
                            //
                            // Finishing one puzzle on day one is what predicts
                            // coming back — 61% next-day return against 21% —
                            // and the Mini is finished by two thirds of the
                            // people who open it against fewer than half for the
                            // 15×15. This is the highest-intent moment the app
                            // gets, so it spends it on the puzzle most likely to
                            // be finished instead of a screen of choices.
                            //
                            // Not a trap: it pushes onto the Today stack, so the
                            // back button lands exactly where they'd have been.
                            openPuzzle(id: mini.id)
                        }
                    }
                } else {
                    mainTabs(profile)
                }
            } else {
                ProgressView()
            }
        }
        .task {
            mergeSyncDuplicates()
            let profile = ensureProfile()
            #if DEBUG
            // Screenshot helper, same family as -uiFillSolved / -uiAutoSolve in
            // CrosswordGameView. Runs before normalize, which is then a no-op
            // because the seed dates the last solve to today.
            if ProcessInfo.processInfo.arguments.contains("-uiSeedShowcase") {
                seedShowcase(profile)
            }
            if ProcessInfo.processInfo.arguments.contains("-uiSeedStreakBreak") {
                seedStreakBreak(profile)
            }
            if ProcessInfo.processInfo.arguments.contains("-uiSeedRotationRepeat") {
                seedRotationRepeat()
            }
            #endif
            // A break is announced once, by the pass that causes it — see
            // `Streaks.Outcome`. A freeze save needs nothing here: the streak
            // survived, and StreakCard already carries its own reassurance.
            if case .broken(let previous) = Streaks.normalize(profile) {
                pendingStreakBreak = previous
                analytics.log(.streakBroken(previousLength: previous))
            }
            reconcilePackCompletions(profile)
            context.saveLogged("launch normalise")
            WidgetBridge.publish(profile, context: context)
            gameCenter.authenticate()
            analytics.log(.appOpen)
            await notifications.reschedule(for: profile, enabled: remindersEnabled, minutes: reminderMinutes)
            // Read before any ask surface decides: the asks only make sense
            // while the system prompt is still unspent.
            await notifications.refreshStatus()
            // A cold launch from a notification tap sets `pendingURL` before
            // this view exists, so the change never lands on `onChange` —
            // whatever is already waiting has to be drained by hand.
            drainPendingNotificationURL()
        }
        .onChange(of: scenePhase) { _, phase in
            // Going to the background ends the sitting: the per-session ask
            // flag exists to stop two asks in one sitting, and with iOS
            // keeping the process suspended for days, a flag that only resets
            // on relaunch was blocking every re-ask a returning player was
            // otherwise due.
            if phase == .background { ReminderAskSession.asked = false }
            // Returning to the foreground may cross midnight or land after a solve
            // elsewhere — recompute streak-aware copy from the latest state.
            guard phase == .active, let profile = profiles.first else { return }
            mergeSyncDuplicates()
            WidgetBridge.publish(profile, context: context)
            Task {
                // Unconditionally, and before anything reads it. Notification
                // permission is the one setting that can change while the app
                // is in the background, and `reschedule` only refreshes after
                // its own `enabled` guard — so a player who allowed
                // notifications in Settings came back to a cached `.denied`,
                // and the Profile toggle sent them straight back to Settings.
                await notifications.refreshStatus()
                completePendingReminderOptIn()
                await notifications.reschedule(for: profile, enabled: remindersEnabled, minutes: reminderMinutes)
            }
        }
        .onOpenURL { url in
            handleDeepLink(url)
        }
        // A tapped notification arrives through the notification-centre
        // delegate rather than `onOpenURL`, so it's handed here as a URL and
        // routed by the same code — one definition of where a link goes.
        .onChange(of: notifications.pendingURL) { _, _ in
            drainPendingNotificationURL()
        }
        // Universal links (https://biblecrosswordchallenge.com/challenge/…)
        // arrive as a web-browsing activity rather than through onOpenURL.
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
            if let url = activity.webpageURL { handleDeepLink(url) }
        }
        .alert("Update Needed", isPresented: $showChallengeUpdateAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This challenge was made with a newer version of the app. Update to play it.")
        }
    }

    /// Finishes an opt-in that was interrupted by a trip to Settings.
    ///
    /// The player asked for a reminder, the switch went back off because
    /// permission was missing, and they were handed to Settings. If they come
    /// back having allowed notifications, honouring what they already asked for
    /// is the whole point of sending them; making them flip the switch a second
    /// time reads as the app having ignored them.
    private func completePendingReminderOptIn() {
        guard pendingReminderOptIn else { return }
        switch notifications.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            pendingReminderOptIn = false
            remindersEnabled = true
            analytics.log(.reminderSettingChanged(enabled: true))
        case .denied:
            // They looked at Settings and left notifications off. That's an
            // answer; stop waiting for one.
            pendingReminderOptIn = false
        default:
            // Still undetermined — Settings may not have been opened yet.
            break
        }
    }

    // The day-2 reminder sheet no longer opens here. It moved to the
    // completion screen of a return-day solve (`CompletionView`), where the
    // habit it asks about has just been demonstrated — see
    // `ReminderAsk.Surface.returnDaySheet`.

    /// Routes whatever a notification tap left behind, exactly once.
    private func drainPendingNotificationURL() {
        guard let url = notifications.pendingURL else { return }
        notifications.pendingURL = nil
        handleDeepLink(url)
    }

    /// Deep-link entry: friend challenges (`challenge`), widget taps
    /// (`play-daily`, see `StreakEntry.deepLinkURL`), and notification taps
    /// (`pack`, from a season opening).
    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "biblecrossword" else { return }

        // Friend challenge. Accept the payload even before onboarding completes
        // so an invite that prompts a fresh install still lands afterwards.
        if url.host() == "challenge" {
            // A family board rides the same path and is told apart by its query,
            // so it has to be offered the link first: to the one-to-one parser a
            // board reads as a version it doesn't understand.
            switch familyBoard.parse(url, title: { puzzleProvider.puzzle(id: $0)?.title }) {
            case .valid(let board):
                let merged = familyBoard.accept(board)
                analytics.log(.familyBoardOpened(puzzleID: merged.puzzleID, size: merged.standings.count))
                if hasOnboarded {
                    openPuzzle(id: merged.puzzleID)
                } else {
                    pendingNavPuzzleID = merged.puzzleID
                }
                return
            case .needsUpdate:
                showChallengeUpdateAlert = true
                return
            case .notABoard:
                break
            }

            switch challengeService.parse(url) {
            case .valid(let challenge):
                challengeService.accept(challenge)
                analytics.log(.challengeOpened(puzzleID: challenge.puzzleID))
                if hasOnboarded {
                    openPuzzle(id: challenge.puzzleID)
                } else {
                    pendingNavPuzzleID = challenge.puzzleID
                }
            case .needsUpdate:
                showChallengeUpdateAlert = true
            case .notAChallenge:
                break
            }
            return
        }

        // Widget targets require a set-up player.
        guard hasOnboarded else { return }

        // A specific puzzle (`biblecrossword://puzzle?id=…`) — used by the
        // completion screen's "next in pack" to jump straight into play.
        if url.host() == "puzzle",
           let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?
               .queryItems?.first(where: { $0.name == "id" })?.value,
           let puzzle = puzzleProvider.puzzle(id: id) {
            selectedTab = .today
            todayPath = NavigationPath([puzzle])
            return
        }

        // A collection (`biblecrossword://pack?id=…`) — the season-opening
        // notification's target. Gated on the pack being in season, since a
        // notification can outlive its window (scheduled, then opened days
        // later) and the pack it names would be nowhere else in the app.
        if url.host() == "pack",
           let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?
               .queryItems?.first(where: { $0.name == "id" })?.value,
           let pack = puzzleProvider.pack(id: id), pack.isAvailable() {
            selectedTab = .packs
            packsPath = NavigationPath([PackRoute(pack: pack, source: .notification)])
            return
        }

        // Widget taps carry `src=widget` so their opens are attributable —
        // the same hosts are reachable from notification taps, and a
        // destination funnel that mixes the two channels reads as neither.
        let fromWidget = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.contains { $0.name == "src" && $0.value == "widget" } ?? false

        selectedTab = .today
        if url.host() == "play-daily", let daily = puzzleProvider.dailyPuzzle() {
            todayPath = NavigationPath([daily])
            if fromWidget { analytics.log(.widgetOpened(destination: "daily")) }
        } else if url.host() == "play-mini", let mini = puzzleProvider.dailyMini() {
            // The widget offers the Mini once the daily is done. A missing
            // mini pool falls through to Home rather than a dead tap.
            todayPath = NavigationPath([mini])
            if fromWidget { analytics.log(.widgetOpened(destination: "mini")) }
        } else {
            todayPath = NavigationPath()
            if fromWidget { analytics.log(.widgetOpened(destination: "today")) }
        }
    }

    /// Push a linked-to puzzle onto the Today stack. Pushing the `Puzzle`
    /// directly plays it via `HomeView`'s destination — bypassing the Archive
    /// gate, so a free player can always take a friend's single challenge or
    /// join the family's board.
    private func openPuzzle(id: String) {
        guard let puzzle = puzzleProvider.puzzle(id: id) else { return }
        selectedTab = .today
        todayPath = NavigationPath([puzzle])
    }

    /// Credits any fully-solved packs and Journeys not yet on the profile —
    /// solves that predate `completedPackIDs`/`completedQuestIDs`, or that
    /// finished one on another device.
    private func reconcilePackCompletions(_ profile: PlayerProfile) {
        guard !puzzleProvider.packs.isEmpty || !puzzleProvider.quests.isEmpty else { return }
        do {
            let records = try context.fetch(FetchDescriptor<PuzzleRecord>())
            let solvedIDs = Set(records.filter(\.isCompleted).map(\.puzzleID))
            PackCompletion.record(packs: puzzleProvider.packs, profile: profile) {
                solvedIDs.contains($0)
            }
            QuestCompletion.record(quests: puzzleProvider.quests, profile: profile) {
                solvedIDs.contains($0)
            }
        } catch {
            Log.persistence.error("Pack reconciliation fetch failed: \(error, privacy: .public)")
        }
    }

    /// CloudKit sync can land duplicate profiles/records created on another
    /// device before the two stores first converged — collapse them.
    private func mergeSyncDuplicates() {
        if profiles.count > 1 {
            SyncMerge.mergeProfiles(profiles, context: context)
        }
        SyncMerge.mergeDuplicateRecords(in: context)
        context.saveLogged("sync merge")
    }

    private func mainTabs(_ profile: PlayerProfile) -> some View {
        @Bindable var router = readerRouter
        return TabView(selection: $selectedTab) {
            Tab("Today", systemImage: "calendar", value: RootTab.today) {
                HomeView(profile: profile, path: $todayPath)
            }
            Tab("Packs", systemImage: "square.stack.3d.up", value: RootTab.packs) {
                PacksView(profile: profile, path: $packsPath)
            }
            Tab("Library", systemImage: "books.vertical", value: RootTab.library) {
                LibraryView(profile: profile)
            }
            Tab("Achievements", systemImage: "trophy", value: RootTab.achievements) {
                AchievementsView(profile: profile)
            }
            Tab("Profile", systemImage: "person", value: RootTab.profile) {
                ProfileView(profile: profile)
            }
        }
        // The reader is a deep-link target only — a puzzle's verse reference sets
        // the router target and we present it modally over the current tab.
        .fullScreenCover(item: $router.target) { target in
            ReaderModal(target: target)
        }
    }

    private func ensureProfile() -> PlayerProfile {
        if let existing = profiles.first { return existing }
        let profile = PlayerProfile()
        context.insert(profile)
        context.saveLogged("create profile")
        return profile
    }

    #if DEBUG
    /// Development-only: fill a fresh install with the history of someone who
    /// has been playing for a few weeks, so App Store captures don't advertise
    /// an abandoned app. A real first launch shows `0 day streak`, `0/5` on
    /// every pack and `0/5` on the next achievement, which reads as "nobody
    /// uses this" in a screenshot — the numbers below are ordinary for a
    /// returning player, not a flex.
    ///
    /// Idempotent: keyed off `totalPuzzlesCompleted`, so relaunching with the
    /// flag doesn't stack records. Wipe the app to reseed from scratch.
    /// Dates a long streak into the past so the next `Streaks.normalize` breaks
    /// it, which is the only way to reach the comeback card without waiting two
    /// real days. Runs before normalize, same as `-uiSeedShowcase`.
    private func seedStreakBreak(_ p: PlayerProfile) {
        let calendar = Calendar.current
        p.currentStreak = 14
        p.bestStreak = max(p.bestStreak, 14)
        p.streakFreezes = 0     // a freeze would bridge the gap instead
        p.lastCompletedDate = calendar.date(byAdding: .day, value: -4, to: Date())
        pendingStreakBreak = 0  // let normalize be the thing that reports it
    }

    /// Marks today's daily and mini as solved on an earlier day — which is what
    /// the rotation wrap does to the whole cohort on 2026-09-21 and 2026-09-29.
    ///
    /// Same family as `-uiForceReminderPrompt`: the state is otherwise only
    /// reachable by moving the device clock two months forward, which makes the
    /// card that decides a streak one of the hardest in the app to look at.
    private func seedRotationRepeat() {
        let earlier = Calendar.current.date(byAdding: .day, value: -60, to: Date()) ?? Date()
        let existing = (try? context.fetch(FetchDescriptor<PuzzleRecord>())) ?? []
        let byID = Dictionary(existing.map { ($0.puzzleID, $0) }, uniquingKeysWith: { a, _ in a })

        for puzzle in [puzzleProvider.dailyPuzzle(), puzzleProvider.dailyMini()].compactMap({ $0 }) {
            // Update in place when a record exists, so re-running the flag can't
            // leave two records for one puzzle.
            let record = byID[puzzle.id] ?? {
                let fresh = PuzzleRecord(puzzleID: puzzle.id)
                context.insert(fresh)
                return fresh
            }()
            record.isCompleted = true
            record.completedDate = earlier
            record.elapsedSeconds = 272
            record.updatedAt = earlier
        }
        context.saveLogged("seed rotation repeat")
    }

    private func seedShowcase(_ p: PlayerProfile) {
        guard p.totalPuzzlesCompleted == 0 else { return }
        let calendar = Calendar.current
        let now = Date()

        p.currentStreak = 12
        p.bestStreak = 21
        p.totalPuzzlesCompleted = 47
        // Today, so `Streaks.normalize` treats the streak as current and the
        // weekday row marks today rather than resetting the whole thing to 0.
        p.lastCompletedDate = now
        p.bestSolveSeconds = 214
        p.noHintSolves = 9
        p.hardCompleted = 6
        p.streakFreezes = 2
        // Earned, not everything — a full trophy case leaves the Achievements
        // screen with nothing left to show as in-progress.
        p.unlockedAchievementIDs = ["bible-beginner", "disciple", "unaided", "quick-wit", "pathfinder"]
        p.completedPackIDs = ["first-steps"]

        // Back-dated records: the last 12 days for the streak's weekday row,
        // plus First Steps' own puzzles so that pack reads 5/5 and The Life of
        // David sits part-done at 2/4 — a finished pack and a live one.
        var ids = (1...12).map { String(format: "daily-%03d", $0) }
        ids += ["mini-001", "mini-003", "daily-014", "daily-004", "daily-013"]
        for (offset, id) in ids.enumerated() {
            let day = calendar.date(byAdding: .day, value: -offset, to: now) ?? now
            let record = PuzzleRecord(puzzleID: id)
            record.isCompleted = true
            record.completedDate = day
            record.elapsedSeconds = 230 + (offset * 17) % 400
            record.usedHint = offset % 3 == 0
            record.updatedAt = day
            context.insert(record)
        }
        context.saveLogged("seed showcase")
    }
    #endif
}
