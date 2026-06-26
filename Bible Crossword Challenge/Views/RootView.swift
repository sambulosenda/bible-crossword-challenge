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
    @Query private var profiles: [PlayerProfile]
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
            Task {
                await notifications.reschedule(for: profile, enabled: remindersEnabled, minutes: reminderMinutes)
            }
        }
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
