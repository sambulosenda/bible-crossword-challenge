//
//  SettingsView.swift
//  Bible Crossword Challenge
//
//  The app's settings, as a sheet behind the gear on Profile — and ⌘, on a
//  hardware keyboard, over whichever tab is showing.
//
//  A native inset-grouped Form, on purpose. Until 2026-10 these rows were
//  hand-built cards at the foot of the Profile tab, styled to match the cards
//  above them: more than a screen down, under the stats and an upsell, with
//  nothing on screen saying they were there. In a sheet titled Settings,
//  looking like Settings is the point — the system's rows bring their own
//  press states, metrics and large-text reflow, and the paper canvas behind
//  them keeps the app's warmth.
//
//  Row language: navigation and outbound rows read in the primary colour with
//  a trailing glyph saying where the tap goes (a chevron stays here, the
//  outbound arrow leaves the app); the actions — the Premium offer, restore —
//  keep the system's tinted button text.
//

import SwiftUI
import UIKit
import StoreKit

struct SettingsView: View {
    let profile: PlayerProfile

    @Environment(StoreService.self) private var store
    @Environment(\.analytics) private var analytics
    @Environment(\.notifications) private var notifications
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appTheme") private var appTheme: AppTheme = .system
    @AppStorage("remindersEnabled") private var remindersEnabled = false
    /// Set when the player is sent to the Settings app to allow notifications;
    /// RootView finishes the opt-in if they come back having allowed them.
    @AppStorage("pendingReminderOptIn") private var pendingReminderOptIn = false
    @AppStorage("reminderMinutes") private var reminderMinutes = ReminderTime.defaultMinutes
    /// Seasonal pack announcements. Promotional, so it is its own opt-in and
    /// starts off — see `NotificationService.scheduleSeasonOpenings`.
    @AppStorage("packNewsEnabled") private var packNewsEnabled = false
    /// Mirrors the in-game hint-menu toggle; seeded per player at launch
    /// (see `GameViewModel.seedAutoCheckIfNeeded`, called from RootView).
    @AppStorage("autoCheckErrors") private var autoCheckErrors = false
    /// Zen mode, inverted: off hides the in-solve clock. Time is still
    /// recorded — challenges and records need honest seconds.
    @AppStorage("showSolveTimer") private var showSolveTimer = true
    @State private var showPaywall = false

    private var reminderTime: Binding<Date> {
        Binding(
            get: { ReminderTime.date(fromMinutes: reminderMinutes) },
            set: { reminderMinutes = ReminderTime.minutes(from: $0) }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                premiumSection
                gameplaySection
                remindersSection
                packNewsSection
                appearanceSection
                supportSection
                aboutSection
                #if DEBUG
                developerSection
                #endif
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            // Blue switches, as the hand-built rows had — the system's green
            // would be the one other colour on the screen.
            .tint(Theme.accent)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView(source: .profile)
            }
            .purchaseNoticeAlert(store)
            .task { await notifications.refreshStatus() }
        }
    }

    // MARK: - Premium

    /// One row, not a card. On Profile this was a full-width ink pill, the
    /// loudest thing on the tab, and in the 60 days to 2026-10-03 it opened the
    /// paywall 7 times for 1 purchase. It keeps its place at the top here —
    /// where an account's standing goes in a settings list — at a row's volume.
    ///
    /// `source` stays `.profile` so the paywall's attribution reads on from
    /// the data before the move.
    @ViewBuilder
    private var premiumSection: some View {
        // Free players only. Premium players got a "Manage subscription"
        // row until 2026-10-13; iOS Settings › Apple ID › Subscriptions is
        // where that lives, and a row they rarely need isn't worth a section.
        if !store.isPremium {
            Section("Premium") {
                Button {
                    showPaywall = true
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        // Never "Unlock": this opens the paywall, it doesn't
                        // buy anything. Same string as Today's card — one
                        // offer, said one way. `.headline` because the accent
                        // only clears contrast on paper at that weight.
                        Text(PremiumCopy.cardCTA(store))
                            .font(.headline)
                        Text("Every themed pack, and hints whenever you need them.")
                            .font(.subheadline)
                            // The colour, not the hierarchical `.secondary`:
                            // inside a Form button that one derives from the
                            // tint and came out a faint blue.
                            .foregroundStyle(Color.secondary)
                    }
                }
                Button("Restore purchase") {
                    Task { await store.restore() }
                }
            }
        }
    }

    // MARK: - Gameplay

    private var gameplaySection: some View {
        Section("Gameplay") {
            // Each row explains itself; a shared footer explaining two
            // settings in one paragraph made the reader match sentences to
            // switches. The auto-check default is seeded at launch (RootView).
            Toggle(isOn: $autoCheckErrors) {
                Text("Auto-check mistakes")
                Text("Marks wrong letters as you type.")
            }
            Toggle(isOn: $showSolveTimer) {
                Text("Show solve timer")
                Text("Your times are recorded either way.")
            }
        }
    }

    // MARK: - Notifications

    private var remindersSection: some View {
        Section {
            // A binding whose setter is the user's tap: code paths that turn
            // the reminder off (permission denied, bounced to the Settings app) write
            // `remindersEnabled` directly and never re-enter the handler, so a
            // refused permission can't log a phantom "reminder disabled".
            Toggle("Daily reminder", isOn: Binding(
                get: { remindersEnabled },
                set: { handleReminderToggle($0) }
            ))

            if remindersEnabled && notifications.canDeliver {
                DatePicker("Time", selection: reminderTime, displayedComponents: .hourAndMinute)
                    .onChange(of: reminderMinutes) { _, _ in
                        rescheduleReminders()
                    }
            }

            if notifications.authorizationStatus == .denied {
                // A door, not a sentence. The switch above can't be turned on
                // from inside the app once permission is refused, so the
                // player needs somewhere to tap, not only a footer saying so.
                // "Turn on notifications" rather than "Open Settings": inside a
                // screen called Settings, that would read as going nowhere.
                SettingsLinkRow(
                    title: "Turn on notifications", external: true,
                    hint: "Opens this app's page in the Settings app"
                ) {
                    openNotificationSettings()
                }
            }
        } header: {
            Text("Notifications")
        } footer: {
            Text(remindersFooterText)
        }
    }

    /// What the daily reminder will actually send, said plainly.
    ///
    /// The last call is conditional because the scheduler's is: a reminder set
    /// at 9 PM or later leaves no room for it and none is scheduled (see
    /// `NotificationService.scheduleStreakRiskNudge`), and a settings screen
    /// describing a notification that will never arrive is its own small lie.
    private var remindersFooterText: String {
        if notifications.authorizationStatus == .denied {
            return "Notifications are turned off for this app. Turn them on in the Settings app to get your daily reminder."
        }
        guard remindersEnabled && notifications.canDeliver else {
            return "One reminder a day, at a time you choose."
        }
        guard reminderMinutes < NotificationService.streakRiskMinutes else {
            return "One reminder a day, at the time above."
        }
        let lastCall = ReminderTime.date(fromMinutes: NotificationService.streakRiskMinutes)
            .formatted(date: .omitted, time: .shortened)
        return "One reminder a day, at the time above. On an evening a streak is about to break, a last call at \(lastCall)."
    }

    /// Pack news is app news, not the daily nudge, so it needs its own yes —
    /// and its own section, so the switch and the sentence about it sit
    /// together. It used to appear only while the daily reminder was on, and
    /// switching the reminder off took the pack notices with it.
    ///
    /// Hidden while notifications are refused: nothing it schedules could
    /// arrive, and the section above already holds the way back.
    @ViewBuilder
    private var packNewsSection: some View {
        if notifications.authorizationStatus != .denied {
            Section {
                Toggle("New puzzle packs", isOn: Binding(
                    get: { packNewsEnabled },
                    set: { handlePackNewsToggle($0) }
                ))
            } footer: {
                Text("A note the morning a seasonal pack opens — a few times a year.")
            }
        }
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        Section {
            // A row showing its current value, the way Settings shows a
            // choice — not a label row with a segmented control under it,
            // which took two rows to say one thing.
            Picker("Appearance", selection: $appTheme) {
                ForEach(AppTheme.allCases) { theme in
                    Text(theme.label).tag(theme)
                }
            }
            .pickerStyle(.menu)
        }
    }

    // MARK: - Support

    /// Rate, share, and reach us.
    private var supportSection: some View {
        Section("Support") {
            SettingsLinkRow(title: "Rate the app", external: true) {
                openURL(AppLinks.review)
            }
            ShareLink(item: AppLinks.appStore) {
                HStack {
                    Text("Share with a friend")
                        .foregroundStyle(SettingsRowColor.title)
                    Spacer(minLength: Theme.Spacing.s)
                    Image(systemName: "square.and.arrow.up")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(SettingsRowColor.glyph)
                        .accessibilityHidden(true)
                }
            }
            SettingsLinkRow(title: "Contact support", external: true) {
                openURL(AppLinks.support)
            }
        }
    }

    /// The legal pair App Review expects a subscription app to expose. The
    /// version lives in the footer: a static fact doesn't earn a row of its own.
    private var aboutSection: some View {
        Section {
            SettingsLinkRow(title: "Privacy policy", external: true) {
                openURL(AppLinks.privacy)
            }
            SettingsLinkRow(title: "Terms of use", external: true) {
                openURL(AppLinks.terms)
            }
        } footer: {
            Text("Version \(appVersion) · Learn Scripture one puzzle a day.")
        }
    }

    #if DEBUG
    private var developerSection: some View {
        Section("Developer") {
            Button("Grant premium") { store.grantForTesting() }
            Button("Reset premium", role: .destructive) { store.resetForTesting() }
        }
    }
    #endif

    // MARK: - Reminder plumbing

    /// The user flipped the switch. Off is immediate; on depends on
    /// permission, so the switch moves first and comes back if iOS says no.
    private func handleReminderToggle(_ enabled: Bool) {
        guard enabled else {
            remindersEnabled = false
            analytics.log(.reminderSettingChanged(enabled: false))
            // A reschedule, not a cancel-everything: pack news is its own
            // switch and outlives the daily reminder.
            rescheduleReminders()
            return
        }
        Task {
            switch notifications.authorizationStatus {
            case .notDetermined:
                remindersEnabled = true
                let granted = await notifications.requestAuthorization()
                analytics.log(.notificationPermission(granted: granted, source: "profile"))
                if granted {
                    analytics.log(.reminderSettingChanged(enabled: true))
                    rescheduleReminders()
                } else {
                    remindersEnabled = false
                }
            case .denied:
                // Can't grant from inside the app — bounce to the Settings app, leave off.
                remindersEnabled = false
                openNotificationSettings()
            default:
                remindersEnabled = true
                analytics.log(.reminderSettingChanged(enabled: true))
                rescheduleReminders()
            }
        }
    }

    /// Hands the player to this app's page in the Settings app, remembering that
    /// they meant to turn the reminder on. The switch is off because permission is
    /// missing, not because they changed their mind, and without the flag they
    /// come back having allowed notifications only to find it still off and
    /// have to ask a second time — see `RootView.completePendingReminderOptIn`.
    private func openNotificationSettings() {
        pendingReminderOptIn = true
        if let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url)
        }
    }

    /// The player asked for (or declined) seasonal pack news. On needs
    /// permission the way the daily reminder does now that the switch stands
    /// on its own — it is no longer only reachable once a reminder had already
    /// been granted. There's no Settings bounce: the section is hidden while
    /// notifications are refused.
    private func handlePackNewsToggle(_ enabled: Bool) {
        guard enabled else {
            packNewsEnabled = false
            analytics.log(.packNewsSettingChanged(enabled: false))
            rescheduleReminders()
            return
        }
        Task {
            packNewsEnabled = true
            if notifications.authorizationStatus == .notDetermined {
                let granted = await notifications.requestAuthorization()
                analytics.log(.notificationPermission(granted: granted, source: "pack_news"))
                guard granted else {
                    packNewsEnabled = false
                    return
                }
            }
            analytics.log(.packNewsSettingChanged(enabled: true))
            rescheduleReminders()
        }
    }

    private func rescheduleReminders() {
        Task {
            await notifications.reschedule(
                for: profile, enabled: remindersEnabled,
                minutes: reminderMinutes, packNews: packNewsEnabled
            )
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
}

// MARK: - Rows

/// A row that goes somewhere: the title in the primary colour — in a list of
/// settings the tint would read every row as a link — and a trailing glyph
/// saying where. A chevron opens something here; the outbound arrow leaves
/// the app (web, Mail, App Store, the Settings app).
private struct SettingsLinkRow: View {
    let title: LocalizedStringKey
    var external = false
    var hint: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .foregroundStyle(SettingsRowColor.title)
                Spacer(minLength: Theme.Spacing.s)
                Image(systemName: external ? "arrow.up.forward" : "chevron.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(SettingsRowColor.glyph)
                    // Decorative — without this VoiceOver appends the symbol's
                    // name ("arrow up forward") to the row's label.
                    .accessibilityHidden(true)
            }
        }
        .accessibilityHint(hint ?? (external ? "Opens outside the app" : ""))
    }
}

/// Concrete label colours for rows inside Form buttons. The hierarchical
/// `.primary` / `.tertiary` styles resolve against a button's tint there, so
/// every title came out blue and every glyph a faint blue.
private enum SettingsRowColor {
    static let title = Color.primary
    static let glyph = Color(uiColor: .tertiaryLabel)
}

// MARK: - Links

/// Everywhere Settings can send someone. One place, so the App Store id and
/// site host can't drift between rows.
private enum AppLinks {
    static let appStore = URL(string: "https://apps.apple.com/app/id6783034270")!
    static let review = URL(string: "https://apps.apple.com/app/id6783034270?action=write-review")!
    static let privacy = URL(string: "https://biblecrosswordchallenge.com/privacy/")!
    /// Apple's standard EULA — the app has no bespoke terms page.
    static let terms = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    static let support = URL(string: "mailto:sambulosendas@gmail.com")!
}
