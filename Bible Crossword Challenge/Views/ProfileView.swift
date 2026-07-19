//
//  ProfileView.swift
//  Bible Crossword Challenge
//
//  Local profile and settings. No authentication in v1 — everything is on device.
//

import SwiftUI
import UIKit
import StoreKit

struct ProfileView: View {
    @Bindable var profile: PlayerProfile

    @Environment(StoreService.self) private var store
    @Environment(\.analytics) private var analytics
    @Environment(\.notifications) private var notifications
    @Environment(\.gameCenter) private var gameCenter
    @Environment(\.openURL) private var openURL
    @AppStorage("appTheme") private var appTheme: AppTheme = .system
    @AppStorage("remindersEnabled") private var remindersEnabled = false
    @AppStorage("reminderMinutes") private var reminderMinutes = ReminderTime.defaultMinutes
    @State private var showPaywall = false
    @State private var showManageSubscriptions = false

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
                    VStack(spacing: Theme.Spacing.m) {
                        HStack {
                            Image(systemName: "person.crop.circle.fill")
                                .font(.largeTitle)
                                .imageScale(.large)
                                .foregroundStyle(Theme.accent)
                                .accessibilityHidden(true)
                            TextField("Your name", text: $profile.username)
                                .font(.title2.weight(.bold))
                                .textInputAutocapitalization(.words)
                        }

                        HStack(spacing: 0) {
                            heroStat(value: "\(profile.currentStreak)", label: "Day Streak", symbol: "flame.fill", tint: .orange)
                            Divider().frame(height: 44)
                            heroStat(value: "\(profile.totalPuzzlesCompleted)", label: "Solved", symbol: "checkmark.circle.fill", tint: .green)
                            Divider().frame(height: 44)
                            heroStat(value: "\(profile.bestStreak)", label: "Best", symbol: "trophy.fill", tint: .yellow)
                        }
                    }
                    .padding(.vertical, Theme.Spacing.xs)
                }

                Section("Stats") {
                    stat("Streak Freezes", value: "\(profile.streakFreezes)", symbol: "snowflake", tint: .cyan)
                    stat("Achievements", value: "\(unlockedCount)/\(Achievements.all.count)", symbol: "star.fill", tint: .indigo)
                    // Persistent way back to this week's Mini standings — the
                    // only other entry point is the post-solve completion screen.
                    // Hidden when the player isn't signed in to Game Center.
                    if gameCenter.isAuthenticated {
                        Button {
                            gameCenter.showWeeklyMiniLeaderboard()
                        } label: {
                            Label {
                                Text("Weekly Leaderboard")
                            } icon: {
                                Image(systemName: "trophy.fill").foregroundStyle(.yellow)
                            }
                        }
                        .accessibilityHint("Opens this week's fastest Mini times")
                    }
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
                        Label {
                            Text("Premium unlocked")
                        } icon: {
                            Image(systemName: "crown.fill").foregroundStyle(.yellow)
                        }
                        Button("Manage Subscription") {
                            showManageSubscriptions = true
                        }
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
                    Button("Grant Premium") {
                        store.grantForTesting()
                    }
                    Button("Reset Premium", role: .destructive) {
                        store.resetForTesting()
                    }
                }
                #endif
            }
            // Native form rows on the app's warm paper canvas instead of the
            // cool system-grouped grey, keeping the tabs on one palette.
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Profile")
            .sheet(isPresented: $showPaywall) {
                PaywallView(source: "profile")
            }
            .manageSubscriptionsSheet(isPresented: $showManageSubscriptions)
            .purchaseNoticeAlert(store)
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

    private func heroStat(value: String, label: String, symbol: String, tint: Color) -> some View {
        VStack(spacing: Theme.Spacing.xs) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(tint)
            Text(value)
                .font(.title.weight(.bold))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }

    private func stat(_ title: String, value: String, symbol: String, tint: Color) -> some View {
        LabeledContent {
            Text(value).monospacedDigit().fontWeight(.semibold)
        } label: {
            Label {
                Text(title)
            } icon: {
                Image(systemName: symbol).foregroundStyle(tint)
            }
        }
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return v
    }
}
