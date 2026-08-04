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
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab: RootTab = .today
    /// A challenge accepted before onboarding finished — opened once the player
    /// is set up (see the onboarding-finish closure).
    @State private var pendingNavChallenge: ChallengeService.Challenge?
    /// A challenge link from a newer app version or for an unknown puzzle.
    @State private var showChallengeUpdateAlert = false
    /// Navigation stack for the Today tab. Held here so a widget deep-link can
    /// push the daily puzzle onto it. Type-erased so the Today feed can push both
    /// puzzles and pack details.
    @State private var todayPath = NavigationPath()
    // Sorted so `first` is the oldest profile — the survivor SyncMerge keeps
    // when CloudKit sync delivers a duplicate from another device.
    @Query(sort: \PlayerProfile.createdAt) private var profiles: [PlayerProfile]
    @AppStorage("hasOnboarded") private var hasOnboarded = false
    @AppStorage("remindersEnabled") private var remindersEnabled = false
    @AppStorage("reminderMinutes") private var reminderMinutes = ReminderTime.defaultMinutes
    /// Set the first time the day-2 reminder prompt is shown, whatever the
    /// answer. One second ask is a nudge; a recurring one is nagging.
    @AppStorage("didAskReminderAgain") private var didAskReminderAgain = false
    @State private var showReminderPrompt = false

    var body: some View {
        Group {
            if let profile = profiles.first {
                if !hasOnboarded {
                    OnboardingView(profile: profile) {
                        context.saveLogged("onboarding finish")
                        withAnimation { hasOnboarded = true }
                        // A challenge link that arrived mid-onboarding was stashed;
                        // now that the tabs exist, jump into it.
                        if let challenge = pendingNavChallenge {
                            pendingNavChallenge = nil
                            openChallenge(challenge)
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
            #endif
            Streaks.normalize(profile)
            reconcilePackCompletions(profile)
            context.saveLogged("launch normalise")
            WidgetBridge.publish(profile)
            gameCenter.authenticate()
            analytics.log(.appOpen)
            await notifications.reschedule(for: profile, enabled: remindersEnabled, minutes: reminderMinutes)
            // Status has to be read before deciding, because the whole point of
            // the second ask is that it only makes sense while the system
            // prompt is still unspent.
            await notifications.refreshStatus()
            showReminderPrompt = shouldAskAgain(profile)
        }
        .onChange(of: scenePhase) { _, phase in
            // Returning to the foreground may cross midnight or land after a solve
            // elsewhere — recompute streak-aware copy from the latest state.
            guard phase == .active, let profile = profiles.first else { return }
            mergeSyncDuplicates()
            WidgetBridge.publish(profile)
            Task {
                await notifications.reschedule(for: profile, enabled: remindersEnabled, minutes: reminderMinutes)
            }
        }
        .onOpenURL { url in
            handleDeepLink(url)
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
        .sheet(isPresented: $showReminderPrompt) {
            if let profile = profiles.first {
                DailyReminderPrompt(profile: profile) {
                    // Marked on the way out rather than on the way in, so a
                    // launch that never finished presenting doesn't burn the
                    // single ask this player gets.
                    didAskReminderAgain = true
                    showReminderPrompt = false
                }
            }
        }
    }

    /// Whether to make the second reminder ask on this launch.
    ///
    /// Every condition is a reason the ask would otherwise be wasted or unwanted:
    /// they already have a reminder; they already answered the system dialog, so
    /// a prompt would show nothing (Settings is the only route left, and that is
    /// a separate job); they've been asked a second time already; or they're
    /// still on the day they installed, which is not a return visit.
    private func shouldAskAgain(_ profile: PlayerProfile) -> Bool {
        guard hasOnboarded,
              !remindersEnabled,
              !didAskReminderAgain,
              notifications.authorizationStatus == .notDetermined,
              // A challenge link is taking them somewhere; don't interrupt it.
              pendingNavChallenge == nil
        else { return false }
        #if DEBUG
        // Same family as -uiSeedShowcase. The day-2 clause is otherwise only
        // reachable by waiting a day or moving the device clock, which makes
        // the one screen a player sees least the one hardest to look at.
        if ProcessInfo.processInfo.arguments.contains("-uiForceReminderPrompt") { return true }
        #endif
        return !Calendar.current.isDateInToday(profile.createdAt)
    }

    /// Deep-link entry: friend challenges (`challenge`) and widget taps
    /// (`play-daily`, see `StreakEntry.deepLinkURL`).
    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "biblecrossword" else { return }

        // Friend challenge. Accept the payload even before onboarding completes
        // so an invite that prompts a fresh install still lands afterwards.
        if url.host() == "challenge" {
            switch challengeService.parse(url) {
            case .valid(let challenge):
                challengeService.accept(challenge)
                analytics.log(.challengeOpened(puzzleID: challenge.puzzleID))
                if hasOnboarded {
                    openChallenge(challenge)
                } else {
                    pendingNavChallenge = challenge
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

        selectedTab = .today
        if url.host() == "play-daily", let daily = puzzleProvider.dailyPuzzle() {
            todayPath = NavigationPath([daily])
        } else {
            todayPath = NavigationPath()
        }
    }

    /// Push the challenged puzzle onto the Today stack. Pushing the `Puzzle`
    /// directly plays it via `HomeView`'s destination — bypassing the Archive
    /// gate, so a free player can always take a friend's single challenge.
    private func openChallenge(_ challenge: ChallengeService.Challenge) {
        guard let puzzle = puzzleProvider.puzzle(id: challenge.puzzleID) else { return }
        selectedTab = .today
        todayPath = NavigationPath([puzzle])
    }

    /// Credits any fully-solved packs not yet on the profile — solves that
    /// predate `completedPackIDs`, or that finished a pack on another device.
    private func reconcilePackCompletions(_ profile: PlayerProfile) {
        guard !puzzleProvider.packs.isEmpty else { return }
        do {
            let records = try context.fetch(FetchDescriptor<PuzzleRecord>())
            let solvedIDs = Set(records.filter(\.isCompleted).map(\.puzzleID))
            PackCompletion.record(packs: puzzleProvider.packs, profile: profile) {
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
                PacksView(profile: profile)
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

/// Modal host for a deep-linked passage. Opens straight to the chapter reader
/// (browsing is reachable from the reader's own "Jump to"); a Close button
/// dismisses back to the tab the reference was tapped from.
private struct ReaderModal: View {
    let target: ReaderRouter.Target
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ChapterReaderView(
                startBook: target.book,
                startChapter: target.chapter,
                highlightVerse: target.verse
            )
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}
