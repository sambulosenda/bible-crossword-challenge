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

/// The main tab bar's selectable tabs. `read` took the slot Achievements
/// held until 2.8 — the trophy list now lives inside Profile (and behind
/// Today's next-achievement card), and the scripture surfaces got the tab.
enum RootTab: Hashable {
    case today, packs, library, read, profile
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.analytics) private var analytics
    @Environment(\.notifications) private var notifications
    @Environment(\.gameCenter) private var gameCenter
    @Environment(\.readerRouter) private var readerRouter
    @Environment(\.memoryVerses) private var memoryVerses
    @Environment(\.puzzleProvider) private var puzzleProvider
    @Environment(\.challengeService) private var challengeService
    @Environment(\.familyBoard) private var familyBoard
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab: RootTab = .today
    /// Settings, presented over whichever tab is showing: Profile's gear opens
    /// it, and so does ⌘, on a hardware keyboard.
    @State private var showSettings = false
    /// A puzzle a challenge or family board asked for before onboarding
    /// finished — opened once the player is set up (see the onboarding-finish
    /// closure). The payload is already stored by its own service; all that's
    /// deferred is the navigation.
    @State private var pendingNavPuzzleID: String?
    /// Whether the clipboard looked like it held a web URL when this
    /// not-yet-onboarded install launched. Decided prompt-free up front so the
    /// one read that shows a banner happens only at the end of onboarding, and
    /// only when there's something worth reading — see `DeferredChallenge`.
    @State private var pasteboardMayHoldChallenge = false
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
    @AppStorage("packNewsEnabled") private var packNewsEnabled = false
    /// Set the first time the day-2 reminder prompt is shown, whatever the
    /// answer. One second ask is a nudge; a recurring one is nagging.
    /// Start-of-day stamp of the last reminder ask on any surface (this sheet,
    /// completion card, streak card) — the shared one-ask-per-day budget.
    /// Set by SettingsView when it hands the player to the Settings app to allow
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
                        } else if pasteboardMayHoldChallenge {
                            // The challenge that prompted this install, carried
                            // across the App Store on the clipboard by the web
                            // landing page. Reading it asks iOS's paste
                            // permission, and the answer arrives asynchronously
                            // — "Don't Allow", or anything that isn't a
                            // challenge link, is simply the Mini path.
                            pasteboardMayHoldChallenge = false
                            Task {
                                if let url = await DeferredChallenge.claimPastedLink() {
                                    handleDeepLink(url, via: "pasteboard")
                                } else {
                                    openFirstPuzzle()
                                }
                            }
                        } else {
                            openFirstPuzzle()
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
            // `-uiSeedJourney beginnings 2`: the first 2 steps solved, the rest
            // not, so the path reads in order.
            let args = ProcessInfo.processInfo.arguments
            if let flag = args.firstIndex(of: "-uiSeedJourney"), flag + 2 < args.count,
               let done = Int(args[flag + 2]) {
                seedJourney(id: args[flag + 1], done: done)
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
            // Seed the auto-check default once, here, so the game and the
            // Settings toggle agree whichever is seen first.
            GameViewModel.seedAutoCheckIfNeeded(totalCompleted: profile.totalPuzzlesCompleted)
            context.saveLogged("launch normalise")
            WidgetBridge.publish(profile, context: context)
            gameCenter.authenticate()
            analytics.log(.appOpen)
            await notifications.reschedule(
                for: profile, enabled: remindersEnabled,
                minutes: reminderMinutes, packNews: packNewsEnabled
            )
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
                // is in the background, and `reschedule` only refreshes once
                // something is switched on — so a player who allowed
                // notifications in Settings came back to a cached `.denied`,
                // and the reminder toggle sent them straight back to Settings.
                await notifications.refreshStatus()
                completePendingReminderOptIn()
                await notifications.reschedule(
                    for: profile, enabled: remindersEnabled,
                    minutes: reminderMinutes, packNews: packNewsEnabled
                )
            }
        }
        .onOpenURL { url in
            handleDeepLink(url)
        }
        .task {
            // Fresh installs only. The classification is prompt-free; the
            // clipboard itself is read once, at the end of onboarding.
            guard !hasOnboarded else { return }
            pasteboardMayHoldChallenge = await DeferredChallenge.pasteboardLooksLikeLink()
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
        if notifications.canDeliver {
            pendingReminderOptIn = false
            remindersEnabled = true
            analytics.log(.reminderSettingChanged(enabled: true))
        } else if notifications.authorizationStatus == .denied {
            // They looked at Settings and left notifications off. That's an
            // answer; stop waiting for one.
            pendingReminderOptIn = false
        }
        // Otherwise still undetermined — Settings may not have been opened yet.
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

    /// Deep-link entry: friend challenges (`challenge`, on the custom scheme or
    /// the https universal link), widget taps (`play-daily`, see
    /// `StreakEntry.deepLinkURL`), and notification taps (`pack`, from a
    /// season opening).
    ///
    /// `via` is how a challenge got here — `link` for a tapped link,
    /// `pasteboard` for one carried across an App Store install (see
    /// `DeferredChallenge`) — and rides on `challenge_opened`.
    private func handleDeepLink(_ url: URL, via: String = "link") {
        // Friend challenge or family board. Matched on the whole URL, not the
        // scheme: the link the app actually shares is the https universal link,
        // and until 2026-09-07 it fell at a `scheme == "biblecrossword"` guard
        // here before the parser ever saw it. 23 challenges sent in the 60 days
        // to 2026-09-04, none opened — this line was why. Accept the payload
        // even before onboarding completes so an invite that prompts a fresh
        // install still lands afterwards.
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           ChallengeService.isChallengeLink(url, components: components) {
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
                analytics.log(.challengeOpened(puzzleID: challenge.puzzleID, via: via))
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

        // Everything below is the app's own scheme.
        guard url.scheme == "biblecrossword" else { return }

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

        // A memory verse (`biblecrossword://memory?ref=…&src=…`) — the
        // completion screen's "Try it from memory". A link rather than a
        // direct path write for the reason the chain above is one: the cover
        // is coming down and the grid popping in the same beat, and a path
        // replaced inside that beat pushed a practice screen that rendered
        // blank. The URL lands a turn later, once the stack has settled.
        // Only a verse already on the shelf: the link doesn't add.
        if url.host() == "memory",
           let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
           let key = items.first(where: { $0.name == "ref" })?.value,
           memoryVerses.entry(for: key) != nil {
            let source = items.first(where: { $0.name == "src" })?.value ?? "link"
            selectedTab = .today
            todayPath = NavigationPath([MemoryPracticeRoute(referenceKey: key, source: source)])
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
    /// Where a new player lands when onboarding ends with nothing more
    /// specific to open: straight into the Mini rather than onto Today.
    ///
    /// Straight into the Mini rather than onto Today.
    ///
    /// Finishing one puzzle on day one is what predicts
    /// coming back — 61% next-day return against 21% —
    /// and the Mini is finished by two thirds of the
    /// people who open it against fewer than half for the
    /// 15×15. This is the highest-intent moment the app
    /// gets, so it spends it on the puzzle most likely to
    /// be finished instead of a screen of choices.
    ///
    /// Not a trap: it pushes onto the Today stack, so the
    /// back button lands exactly where they'd have been.
    private func openFirstPuzzle() {
        guard let mini = puzzleProvider.dailyMini() else { return }
        openPuzzle(id: mini.id)
    }

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
                // "Packs ›" asks for the shelf, not whichever pack the tab
                // was last left open on.
                HomeView(profile: profile, path: $todayPath) {
                    packsPath = NavigationPath()
                    selectedTab = .packs
                }
            }
            Tab("Packs", systemImage: "square.stack.3d.up", value: RootTab.packs) {
                PacksView(profile: profile, path: $packsPath)
            }
            // A grid, not a bookshelf: the Library is the puzzle archive, and a
            // shelf of books beside the Read tab's book made the two read as one.
            Tab("Library", systemImage: "square.grid.3x3", value: RootTab.library) {
                LibraryView(profile: profile)
            }
            // "Verses" since 2026-10-03: the tab leads with the verses the
            // player is memorizing and the ones their puzzles gave them; the
            // reader sits underneath. The case keeps its old name.
            Tab("Verses", systemImage: "text.quote", value: RootTab.read) {
                ReadView()
            }
            // The HIG's standard symbol for Account, User and Profile.
            Tab("Profile", systemImage: "person.crop.circle", value: RootTab.profile) {
                ProfileView(profile: profile) { showSettings = true }
            }
        }
        // Hardware keyboard on iPad: ⌘, is where people reach for an app's
        // settings. It opens them over whatever tab is showing, the way it
        // does in a Mac app, rather than switching to Profile first. A
        // zero-opacity button rather than a Scene `.commands` block — the
        // sheet is this view's state, and lifting it into the App to register
        // one shortcut would be the larger change. `.opacity(0)` rather than
        // `.hidden()`, which would take the button out of the hierarchy and
        // the shortcut with it.
        .background {
            // Zero-sized as well as transparent: `.accessibilityHidden` alone
            // left a 63×20pt "Settings" button mid-screen in the accessibility
            // tree on every tab, where VoiceOver could land on it.
            Button("Settings") { showSettings = true }
                .keyboardShortcut(",", modifiers: .command)
                .opacity(0)
                .frame(width: 0, height: 0)
                .clipped()
                .accessibilityHidden(true)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(profile: profile)
        }
        // A verse reference tapped anywhere sets the router target and the
        // reader is presented modally over the current tab; the Read tab hosts
        // the same reader for browsing.
        .fullScreenCover(item: $router.target) { target in
            ReaderModal(target: target)
        }
        // One day for every tab — see `TodayClock`.
        .tracksToday()
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
        let byID = existing.byPuzzleID

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

    private func seedJourney(id: String, done: Int) {
        guard let quest = puzzleProvider.quests.first(where: { $0.id == id }) else { return }
        let existing = (try? context.fetch(FetchDescriptor<PuzzleRecord>())) ?? []
        let byID = existing.byPuzzleID
        let earlier = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        for (index, puzzleID) in quest.puzzleIDs.enumerated() {
            let record = byID[puzzleID] ?? {
                let fresh = PuzzleRecord(puzzleID: puzzleID)
                context.insert(fresh)
                return fresh
            }()
            let solved = index < done
            record.isCompleted = solved
            record.completedDate = solved ? earlier : nil
            record.elapsedSeconds = solved ? 300 + index * 41 : 0
            record.updatedAt = earlier
        }
        context.saveLogged("seed journey")
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
