//
//  ProfileView.swift
//  Bible Crossword Challenge
//
//  Local profile and settings. No authentication in v1 — everything is on device.
//

import SwiftUI
import UIKit

struct ProfileView: View {
    @Bindable var profile: PlayerProfile

    @Environment(StoreService.self) private var store
    @Environment(\.analytics) private var analytics
    @Environment(\.notifications) private var notifications
    @Environment(\.openURL) private var openURL
    @AppStorage("appTheme") private var appTheme: AppTheme = .system
    @AppStorage("remindersEnabled") private var remindersEnabled = false
    @AppStorage("reminderMinutes") private var reminderMinutes = ReminderTime.defaultMinutes
    @State private var showPaywall = false

    private var reminderTime: Binding<Date> {
        Binding(
            get: { ReminderTime.date(fromMinutes: reminderMinutes) },
            set: { reminderMinutes = ReminderTime.minutes(from: $0) }
        )
    }

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

                Section {
                    Toggle("Daily reminder", isOn: $remindersEnabled)
                        .onChange(of: remindersEnabled) { _, enabled in
                            handleReminderToggle(enabled)
                        }
                    if remindersEnabled && notifications.authorizationStatus == .authorized {
                        DatePicker(
                            "Time",
                            selection: reminderTime,
                            displayedComponents: .hourAndMinute
                        )
                        .onChange(of: reminderMinutes) { _, _ in
                            rescheduleReminders()
                        }
                    }
                } header: {
                    Text("Reminders")
                } footer: {
                    if notifications.authorizationStatus == .denied {
                        Text("Notifications are turned off for this app. Enable them in Settings to receive your daily reminder.")
                    }
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
            .task { await notifications.refreshStatus() }
        }
    }

    // MARK: - Reminders

    private func handleReminderToggle(_ enabled: Bool) {
        guard enabled else {
            analytics.log(.reminderSettingChanged(enabled: false))
            notifications.cancelAll()
            return
        }
        Task {
            switch notifications.authorizationStatus {
            case .notDetermined:
                let granted = await notifications.requestAuthorization()
                analytics.log(.notificationPermission(granted: granted))
                if granted {
                    analytics.log(.reminderSettingChanged(enabled: true))
                    rescheduleReminders()
                } else {
                    remindersEnabled = false
                }
            case .denied:
                // Can't grant from inside the app — bounce to Settings, leave off.
                remindersEnabled = false
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            default:
                analytics.log(.reminderSettingChanged(enabled: true))
                rescheduleReminders()
            }
        }
    }

    private func rescheduleReminders() {
        Task {
            await notifications.reschedule(for: profile, enabled: remindersEnabled, minutes: reminderMinutes)
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
