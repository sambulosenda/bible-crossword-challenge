//
//  RootView.swift
//  Bible Crossword Challenge
//
//  Ensures a single local profile exists, normalises the streak on launch, and
//  hosts the main tab navigation.
//

import SwiftUI
import SwiftData

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
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab: RootTab = .today
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
    }

    /// Widget taps land here (see `StreakEntry.deepLinkURL`). `play-daily` jumps
    /// straight into today's puzzle; any other target just surfaces the Today tab.
    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "biblecrossword", hasOnboarded else { return }
        selectedTab = .today
        if url.host() == "play-daily", let daily = puzzleProvider.dailyPuzzle() {
            todayPath = NavigationPath([daily])
        } else {
            todayPath = NavigationPath()
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
