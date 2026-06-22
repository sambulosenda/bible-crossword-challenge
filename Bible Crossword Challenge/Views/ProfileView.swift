//
//  ProfileView.swift
//  Bible Crossword Challenge
//
//  Local profile and settings. No authentication in v1 — everything is on device.
//

import SwiftUI

struct ProfileView: View {
    @Bindable var profile: PlayerProfile

    @Environment(StoreService.self) private var store
    @AppStorage("appTheme") private var appTheme: AppTheme = .system
    @State private var showPaywall = false

    private var unlockedCount: Int {
        Achievements.all.filter { $0.isUnlocked(by: profile) }.count
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(Theme.accent)
                        TextField("Your name", text: $profile.username)
                            .font(.title3.weight(.semibold))
                            .textInputAutocapitalization(.words)
                    }
                    .padding(.vertical, Theme.Spacing.xs)
                }

                Section("Stats") {
                    stat("Puzzles Completed", value: "\(profile.totalPuzzlesCompleted)", symbol: "checkmark.circle")
                    stat("Current Streak", value: "\(profile.currentStreak)", symbol: "flame")
                    stat("Best Streak", value: "\(profile.bestStreak)", symbol: "trophy")
                    stat("Achievements", value: "\(unlockedCount)/\(Achievements.all.count)", symbol: "star")
                }

                Section("Appearance") {
                    Picker("Appearance", selection: $appTheme) {
                        ForEach(AppTheme.allCases) { theme in
                            Text(theme.label).tag(theme)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Premium") {
                    if store.isPremium {
                        Label("Premium unlocked", systemImage: "crown.fill")
                            .foregroundStyle(.yellow)
                    } else {
                        Button {
                            showPaywall = true
                        } label: {
                            Label("Upgrade to Premium", systemImage: "crown")
                        }
                        Button("Restore Purchase") {
                            Task { await store.restore() }
                        }
                    }
                }

                Section {
                    LabeledContent("Version", value: appVersion)
                } footer: {
                    Text("Bible Crossword Challenge — learn Scripture one puzzle a day.")
                }

                #if DEBUG
                Section("Developer") {
                    Button("Reset Premium", role: .destructive) {
                        store.resetForTesting()
                    }
                }
                #endif
            }
            .navigationTitle("Profile")
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
        }
    }

    private func stat(_ title: String, value: String, symbol: String) -> some View {
        LabeledContent {
            Text(value).monospacedDigit().fontWeight(.semibold)
        } label: {
            Label(title, systemImage: symbol)
        }
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return v
    }
}
