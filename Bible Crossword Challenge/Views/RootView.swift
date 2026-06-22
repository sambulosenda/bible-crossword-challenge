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
    @Query private var profiles: [PlayerProfile]
    @AppStorage("hasOnboarded") private var hasOnboarded = false

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
