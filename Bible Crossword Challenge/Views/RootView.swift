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
    case today, packs, archive, achievements, profile
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
            Streaks.normalize(profile)
            reconcilePackCompletions(profile)
            context.saveLogged("launch normalise")
            WidgetBridge.publish(profile)
            gameCenter.authenticate()
            analytics.log(.appOpen)
            await notifications.reschedule(for: profile, enabled: remindersEnabled, minutes: reminderMinutes)
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
            Tab("Archive", systemImage: "books.vertical", value: RootTab.archive) {
                ArchiveView(profile: profile)
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
