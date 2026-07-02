//
//  RootView.swift
//  Bible Crossword Challenge
//
//  Ensures a single local profile exists, normalises the streak on launch, and
//  hosts the main tab navigation.
//

import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.analytics) private var analytics
    @Environment(\.notifications) private var notifications
    @Environment(\.scenePhase) private var scenePhase
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
                        try? context.save()
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
            try? context.save()
            analytics.log(.appOpen)
            await notifications.reschedule(for: profile, enabled: remindersEnabled, minutes: reminderMinutes)
        }
        .onChange(of: scenePhase) { _, phase in
            // Returning to the foreground may cross midnight or land after a solve
            // elsewhere — recompute streak-aware copy from the latest state.
            guard phase == .active, let profile = profiles.first else { return }
            mergeSyncDuplicates()
            Task {
                await notifications.reschedule(for: profile, enabled: remindersEnabled, minutes: reminderMinutes)
            }
        }
    }

    /// CloudKit sync can land duplicate profiles/records created on another
    /// device before the two stores first converged — collapse them.
    private func mergeSyncDuplicates() {
        if profiles.count > 1 {
            SyncMerge.mergeProfiles(profiles, context: context)
        }
        SyncMerge.mergeDuplicateRecords(in: context)
        try? context.save()
    }

    private func mainTabs(_ profile: PlayerProfile) -> some View {
        TabView {
            Tab("Today", systemImage: "calendar") {
                HomeView(profile: profile)
            }
            Tab("Archive", systemImage: "books.vertical") {
                ArchiveView(profile: profile)
            }
            Tab("Achievements", systemImage: "trophy") {
                AchievementsView(profile: profile)
            }
            Tab("Profile", systemImage: "person") {
                ProfileView(profile: profile)
            }
        }
    }

    private func ensureProfile() -> PlayerProfile {
        if let existing = profiles.first { return existing }
        let profile = PlayerProfile()
        context.insert(profile)
        try? context.save()
        return profile
    }
}
