//
//  ProfileView.swift
//  Bible Crossword Challenge
//
//  Local profile and settings. No authentication in v1 — everything is on device.
//
//  Built as a ScrollView of elevated cards rather than a Form: every other tab
//  (Today, Packs, Library, Achievements) already speaks that language, and an
//  inset-grouped Form with its background hidden still reads as a different app
//  — system separators, its own row metrics, blue-text buttons. The settings
//  rows below are hand-rolled so they sit on the same white-card-on-paper
//  surface as the rest of the app.
//

import SwiftUI
import SwiftData
import UIKit
import StoreKit

struct ProfileView: View {
    @Bindable var profile: PlayerProfile

    @Environment(StoreService.self) private var store
    @Environment(\.analytics) private var analytics
    @Environment(\.notifications) private var notifications
    @Environment(\.gameCenter) private var gameCenter
    @Environment(\.openURL) private var openURL
    @Environment(\.challengeHistory) private var challengeHistory
    @AppStorage("appTheme") private var appTheme: AppTheme = .system
    @AppStorage("remindersEnabled") private var remindersEnabled = false
    /// Set when the player is sent to Settings to allow notifications; RootView
    /// finishes the opt-in if they come back having allowed them.
    @AppStorage("pendingReminderOptIn") private var pendingReminderOptIn = false
    @AppStorage("reminderMinutes") private var reminderMinutes = ReminderTime.defaultMinutes
    /// Mirrors the in-game hint-menu toggle; seeded per player at launch
    /// (see `GameViewModel.seedAutoCheckIfNeeded`, called from RootView).
    @AppStorage("autoCheckErrors") private var autoCheckErrors = false
    /// Zen mode, inverted: off hides the in-solve clock. Time is still
    /// recorded — challenges and records need honest seconds.
    @AppStorage("showSolveTimer") private var showSolveTimer = true
    @State private var showPaywall = false
    @State private var showManageSubscriptions = false
    @State private var showRename = false
    @State private var draftName = ""
    @State private var showChallengeHistory = false

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
            ScrollView {
                VStack(spacing: Theme.Spacing.l) {
                    identityCard
                    ProfileStatsCard(
                        streak: profile.currentStreak,
                        solved: profile.totalPuzzlesCompleted,
                        bestStreak: profile.bestStreak,
                        bestSolveSeconds: profile.bestSolveSeconds,
                        freezes: profile.streakFreezes,
                        unlocked: unlockedCount,
                        totalAchievements: Achievements.all.count
                    )
                    AchievementsCard(
                        profile: profile,
                        unlocked: unlockedCount,
                        total: Achievements.all.count
                    )
                    challengesSection
                    premiumSection
                    preferencesSection
                    gameplaySection
                    remindersSection
                    supportSection
                    #if DEBUG
                    developerSection
                    #endif
                }
                .padding(Theme.Spacing.m)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .background(Theme.background)
            .navigationTitle("Profile")
            .navigationDestination(isPresented: $showChallengeHistory) {
                ChallengeHistoryView(profile: profile)
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView(source: .profile)
            }
            .manageSubscriptionsSheet(isPresented: $showManageSubscriptions)
            .purchaseNoticeAlert(store)
            .alert("Your name", isPresented: $showRename) {
                TextField("Your name", text: $draftName)
                    .textInputAutocapitalization(.words)
                Button("Cancel", role: .cancel) {}
                Button("Save") { commitRename() }
            } message: {
                Text("This is only stored on your device.")
            }
            .task { await notifications.refreshStatus() }
        }
    }

    // MARK: - Identity

    /// Avatar, name, and one quiet line of context. The name was previously a
    /// bare always-editable `TextField` sitting in a form row, which reads as an
    /// unfinished field rather than an identity — it's a display line with an
    /// explicit edit affordance now, and the rename happens in an alert.
    private var identityCard: some View {
        VStack(spacing: Theme.Spacing.m) {
            Avatar(name: profile.username)

            VStack(spacing: 2) {
                Text(displayName)
                    // Serif, as the app sets every hero title and scripture line.
                    .font(.scripture(.title, weight: .semibold))
                    .multilineTextAlignment(.center)
                Text(membershipLine)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Button {
                draftName = profile.username
                showRename = true
            } label: {
                Label("Edit name", systemImage: "pencil")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, Theme.Spacing.m)
                    .padding(.vertical, Theme.Spacing.s)
                    .background(Color.primary.opacity(0.06), in: .capsule)
                    // The capsule stays compact; the hit region meets the 44pt
                    // HIG minimum.
                    .frame(minHeight: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit name")
            .accessibilityHint("Currently \(displayName)")
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.Spacing.l)
        .elevatedCard()
    }

    private var displayName: String {
        let trimmed = profile.username.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Friend" : trimmed
    }

    /// Premium status when there is some, otherwise how long they've been here.
    /// Both come from data already on the profile — no new persistence.
    private var membershipLine: String {
        if store.isPremium { return "Premium member" }
        return "Playing since \(profile.createdAt.formatted(.dateTime.month(.wide).year()))"
    }

    private func commitRename() {
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        profile.username = trimmed
    }

    // MARK: - Stats

    // MARK: - Premium

    @ViewBuilder
    private var premiumSection: some View {
        if store.isPremium {
            SettingsSection("Premium") {
                SettingsRow(title: "Premium unlocked", symbol: "crown.fill", tint: .yellow) {
                    Image(systemName: "checkmark")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                RowDivider()
                SettingsButtonRow(title: "Manage subscription", symbol: "creditcard.fill", tint: Theme.accent) {
                    showManageSubscriptions = true
                }
            }
        } else {
            VStack(spacing: Theme.Spacing.s) {
                upsellCard
                Button("Restore purchase") {
                    Task { await store.restore() }
                }
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
            }
        }
    }

    /// The one card on this screen asking for money — tinted crown badge and a
    /// solid ink CTA, the app's own language for an offer.
    ///
    /// Stacked rather than the side-by-side row Today uses. That layout leaves
    /// roughly 110pt for the copy once the badge and a fixed-width pill have
    /// taken their share, which wraps the headline mid-phrase. Today needs the
    /// compact row because the card sits under a hero puzzle it mustn't
    /// outshout; here there is no competing hero, so the offer gets a full-width
    /// `.pillProminent` — the token Theme already reserves for the single loud
    /// action on a screen.
    private var upsellCard: some View {
        VStack(spacing: Theme.Spacing.m) {
            Image(systemName: "crown.fill")
                .font(.title3)
                .foregroundStyle(Theme.accent)
                .frame(width: upsellIconSize, height: upsellIconSize)
                .background(Theme.accent.opacity(0.14), in: .circle)

            VStack(spacing: 4) {
                Text("Unlock every puzzle")
                    .font(.headline.weight(.bold))
                Text("Every themed pack, and hints whenever you need them.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)

            // "See plans", not "Unlock": this opens the paywall, it doesn't buy
            // anything, and a button that overstates what it does is how a tap
            // becomes a back-out.
            Button("See plans") { showPaywall = true }
                .buttonStyle(.pillProminent)
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity)
        .elevatedCard()
    }

    @ScaledMetric(relativeTo: .title) private var upsellIconSize: CGFloat = 44

    // MARK: - Preferences

    private var preferencesSection: some View {
        SettingsSection("Preferences") {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                SettingsRowLabel(title: "Appearance", symbol: "circle.lefthalf.filled", tint: .purple)
                Picker("Appearance", selection: $appTheme) {
                    ForEach(AppTheme.allCases) { theme in
                        Text(theme.label).tag(theme)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.vertical, Theme.Spacing.s + 2)

            // Persistent way back to this week's Mini standings — the only other
            // entry point is the post-solve completion screen. Hidden when the
            // player isn't signed in to Game Center.
            if gameCenter.isAuthenticated {
                RowDivider()
                SettingsButtonRow(
                    title: "Weekly leaderboard",
                    symbol: "trophy.fill",
                    tint: .yellow,
                    hint: "Opens this week's fastest Mini times"
                ) {
                    gameCenter.showWeeklyMiniLeaderboard()
                }
            }
        }
    }

    // MARK: - Gameplay

    private var gameplaySection: some View {
        SettingsSection("Gameplay") {
            // Each row explains itself; a shared footer explaining two
            // settings in one paragraph made the reader match sentences to
            // switches. The auto-check default is seeded at launch (RootView).
            Toggle(isOn: $autoCheckErrors) {
                SettingsRowLabel(
                    title: "Auto-check mistakes",
                    subtitle: "Marks wrong letters as you type.",
                    symbol: "checkmark.seal.fill", tint: .green
                )
            }
            .settingsRowInsets()
            .tint(Theme.accent)
            RowDivider()
            Toggle(isOn: $showSolveTimer) {
                SettingsRowLabel(
                    title: "Show solve timer",
                    subtitle: "Off hides the clock. Times are still recorded.",
                    symbol: "timer", tint: .blue
                )
            }
            .settingsRowInsets()
            .tint(Theme.accent)
        }
    }

    // MARK: - Reminders

    private var remindersSection: some View {
        SettingsSection("Reminders") {
            // The control carries the row's label rather than sitting beside a
            // separate `Text`. Split apart, VoiceOver reads "Daily reminder"
            // twice — once as static text, once as the switch's own label —
            // where the Form this replaced gave one element for the pair.
            // A binding whose setter is the user's tap: code paths that turn
            // the reminder off (permission denied, bounced to Settings) write
            // `remindersEnabled` directly and never re-enter the handler, so a
            // refused permission can't log a phantom "reminder disabled".
            Toggle(isOn: Binding(
                get: { remindersEnabled },
                set: { handleReminderToggle($0) }
            )) {
                SettingsRowLabel(title: "Daily reminder", symbol: "bell.fill", tint: .orange)
            }
            .settingsRowInsets()
            .tint(Theme.accent)

            if remindersEnabled && notifications.authorizationStatus == .authorized {
                RowDivider()
                DatePicker(selection: reminderTime, displayedComponents: .hourAndMinute) {
                    SettingsRowLabel(title: "Time", symbol: "clock.fill", tint: Theme.accent)
                }
                .settingsRowInsets()
                .onChange(of: reminderMinutes) { _, _ in
                    rescheduleReminders()
                }
            }
        } footer: {
            if notifications.authorizationStatus == .denied {
                Text("Notifications are turned off for this app. Enable them in Settings to receive your daily reminder.")
            }
        }
    }

    // MARK: - Challenges

    /// The friend-challenge ledger, previewed. Hidden until there is something
    /// to show: a "Recent challenges" heading over an empty card advertises a
    /// feature by its absence, and the completion screen is where the invitation
    /// to send one actually belongs.
    @ViewBuilder
    private var challengesSection: some View {
        let recent = Array(challengeHistory.entries.prefix(3))
        if !recent.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Text("Recent challenges").kicker()
                    .padding(.horizontal, Theme.Spacing.xs)

                // Every row leads to the same place — the full list is where
                // replay and rematch live.
                ChallengeHistoryList(entries: recent) { _ in
                    showChallengeHistory = true
                }

                Button {
                    showChallengeHistory = true
                } label: {
                    Text(challengeHistory.entries.count > recent.count
                         ? "See all \(challengeHistory.entries.count)"
                         : "See all")
                        .font(.caption.weight(.semibold))
                        // Bare caption text alone is a ~16pt target; the frame
                        // brings the hit region to the 44pt HIG minimum.
                        .frame(minHeight: 44, alignment: .leading)
                        .contentShape(.rect)
                }
                .padding(.horizontal, Theme.Spacing.xs)
            }
        }
    }

    // MARK: - Support

    /// Rate, share, and reach us — plus the legal pair App Review expects a
    /// subscription app to expose. The version lives in the footer: a static
    /// fact doesn't earn a row of its own.
    private var supportSection: some View {
        SettingsSection("Support") {
            SettingsButtonRow(title: "Rate the app", symbol: "star.fill", tint: .yellow, external: true) {
                openURL(AppLinks.review)
            }
            RowDivider()
            ShareLink(item: AppLinks.appStore) {
                HStack(spacing: Theme.Spacing.s) {
                    SettingsRowLabel(title: "Share with a friend", symbol: "square.and.arrow.up", tint: Theme.accent)
                    Spacer(minLength: Theme.Spacing.s)
                }
                .settingsRowInsets()
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            RowDivider()
            SettingsButtonRow(title: "Contact support", symbol: "envelope.fill", tint: .green, external: true) {
                openURL(AppLinks.support)
            }
            RowDivider()
            SettingsButtonRow(title: "Privacy policy", symbol: "hand.raised.fill", tint: .indigo, external: true) {
                openURL(AppLinks.privacy)
            }
            RowDivider()
            SettingsButtonRow(title: "Terms of use", symbol: "doc.text.fill", tint: .secondary, external: true) {
                openURL(AppLinks.terms)
            }
        } footer: {
            Text("Version \(appVersion) · Learn Scripture one puzzle a day.")
        }
    }

    #if DEBUG
    private var developerSection: some View {
        SettingsSection("Developer") {
            SettingsButtonRow(title: "Grant premium", symbol: "wand.and.stars", tint: .purple) {
                store.grantForTesting()
            }
            RowDivider()
            SettingsButtonRow(title: "Reset premium", symbol: "trash.fill", tint: .red) {
                store.resetForTesting()
            }
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
            notifications.cancelAll()
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
                // Can't grant from inside the app — bounce to Settings, leave off.
                remindersEnabled = false
                // Remember that turning it on was the intent. The switch above
                // is off because permission is missing, not because the player
                // changed their mind, and without this they come back from
                // Settings having allowed notifications only to find the toggle
                // still off and have to ask a second time.
                pendingReminderOptIn = true
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            default:
                remindersEnabled = true
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

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return v
    }
}

// MARK: - Stats

/// One card, two rows. The three headline numbers lead at title size; the three
/// supporting ones sit below a divider at a smaller scale. Previously three were
/// hero stats and the other two were buried as list rows in a separate section,
/// which split one idea across two places.
///
/// Its own type, taking plain values, rather than a computed property on
/// `ProfileView` — the six tiles are the densest thing on the screen, and as a
/// computed property they shared the parent's invalidation boundary and rebuilt
/// every time an unrelated bit of profile state changed (opening the paywall
/// sheet, flipping the reminder switch, typing in the rename alert). With only
/// value inputs and no property wrappers SwiftUI can compare the whole view and
/// skip its body outright. `HomeView`'s cards are built the same way and say so.
private struct ProfileStatsCard: View {
    let streak: Int
    let solved: Int
    let bestStreak: Int
    let bestSolveSeconds: Int?
    let freezes: Int
    let unlocked: Int
    let totalAchievements: Int

    var body: some View {
        VStack(spacing: Theme.Spacing.m) {
            HStack(spacing: 0) {
                heroStat(value: "\(streak)", label: "Day Streak", symbol: "flame.fill", tint: .orange)
                heroStat(value: "\(solved)", label: "Solved", symbol: "checkmark.circle.fill", tint: .green)
                heroStat(value: "\(bestStreak)", label: "Best Streak", symbol: "trophy.fill", tint: .yellow)
            }

            Divider()

            HStack(spacing: 0) {
                minorStat(value: bestTimeValue, label: "Best Time", symbol: "stopwatch.fill", tint: Theme.accent)
                minorStat(value: "\(freezes)", label: "Freezes", symbol: "snowflake", tint: .cyan)
                minorStat(value: "\(unlocked)/\(totalAchievements)", label: "Badges", symbol: "star.fill", tint: .indigo)
            }
        }
        .padding(Theme.Spacing.l)
        .elevatedCard()
    }

    /// An em dash until the first solve — "0:00" would read as a real record.
    private var bestTimeValue: String {
        guard let bestSolveSeconds else { return "—" }
        return TimeFormat.clock(bestSolveSeconds)
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
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }

    private func minorStat(value: String, label: String, symbol: String, tint: Color) -> some View {
        VStack(spacing: Theme.Spacing.xs) {
            Label {
                Text(value)
                    .font(.subheadline.weight(.bold))
                    .monospacedDigit()
            } icon: {
                Image(systemName: symbol)
                    .font(.caption)
                    .foregroundStyle(tint)
            }
            .labelStyle(.titleAndIcon)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }
}

// MARK: - Achievements

/// The way into the trophy list, in the row the journey card held until 2.8
/// (the map moved to the Read tab). Plain values only, for the same
/// invalidation reason as `ProfileStatsCard`.
private struct AchievementsCard: View {
    let profile: PlayerProfile
    let unlocked: Int
    let total: Int

    var body: some View {
        NavigationLink {
            AchievementsView(profile: profile, source: "profile")
        } label: {
            HStack(spacing: Theme.Spacing.m) {
                Image(systemName: "trophy.fill")
                    .font(.title)
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Achievements")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(Theme.Spacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .elevatedCard()
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Achievements. \(summary)")
        .accessibilityHint("Opens every badge and its progress")
    }

    private var summary: String {
        guard unlocked > 0 else { return "Solve puzzles to earn your first badge" }
        return "\(unlocked) of \(total) badges earned"
    }
}

// MARK: - Avatar

/// The player's initial on an accent disc. A generic SF person glyph said
/// nothing about whose profile this is; the initial makes it theirs, and falls
/// back to the glyph only when there's no name to draw from.
private struct Avatar: View {
    let name: String

    @ScaledMetric(relativeTo: .largeTitle) private var size: CGFloat = 72

    private var initial: String? {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .first
            .map { String($0).uppercased() }
    }

    var body: some View {
        ZStack {
            Circle().fill(Theme.accent.opacity(0.14))
            if let initial {
                Text(initial)
                    .font(.scripture(.largeTitle, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            } else {
                Image(systemName: "person.fill")
                    .font(.largeTitle)
                    .foregroundStyle(Theme.accent)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - Settings scaffolding

/// A titled group of rows: an uppercase kicker over one white card, matching
/// the eyebrow/card rhythm the rest of the app already uses.
private struct SettingsSection<Content: View, Footer: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder var content: Content
    @ViewBuilder var footer: Footer

    init(
        _ title: LocalizedStringKey,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) {
        self.title = title
        self.content = content()
        self.footer = footer()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text(title).kicker()
                .padding(.horizontal, Theme.Spacing.xs)

            VStack(spacing: 0) { content }
                .frame(maxWidth: .infinity)
                .elevatedCard()

            footer
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, Theme.Spacing.xs)
        }
    }
}

extension SettingsSection where Footer == EmptyView {
    init(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.init(title, content: content, footer: { EmptyView() })
    }
}

/// Hairline between rows, inset past the icon chip so the chips read as one
/// column rather than the divider cutting under them. The inset lands exactly
/// on the row title's leading edge — row inset + chip + label gap — and scales
/// with the same metric as the chip so they stay aligned at every type size.
private struct RowDivider: View {
    @ScaledMetric(relativeTo: .body) private var chipSize: CGFloat = 30

    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(height: 1)
            .padding(.leading, Theme.Spacing.m + chipSize + Theme.Spacing.s + 4)
    }
}

/// Tinted rounded-square chip. Circles are the app's idiom for the large hero
/// badges (streak flame, upgrade crown); at list-row scale a rounded square
/// holds a small glyph better and keeps the settings rows visually distinct
/// from those hero moments.
private struct IconChip: View {
    let symbol: String
    let tint: Color

    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 30

    var body: some View {
        Image(systemName: symbol)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.14), in: .rect(cornerRadius: 8, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// The row's padding, shared by `SettingsRow` and by controls that carry their
/// own label (`Toggle`, `DatePicker`) so both sit on the same rhythm.
private extension View {
    func settingsRowInsets() -> some View {
        padding(.horizontal, Theme.Spacing.m)
            .padding(.vertical, Theme.Spacing.s + 2)
    }
}

/// Chip + title, the shared leading half of every settings row.
private struct SettingsRowLabel: View {
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey? = nil
    let symbol: String
    let tint: Color

    var body: some View {
        HStack(spacing: Theme.Spacing.s + 4) {
            IconChip(symbol: symbol, tint: tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// A row with a trailing control (toggle, picker, value).
private struct SettingsRow<Trailing: View>: View {
    let title: LocalizedStringKey
    let symbol: String
    let tint: Color
    @ViewBuilder var trailing: Trailing

    init(
        title: LocalizedStringKey,
        symbol: String,
        tint: Color,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.symbol = symbol
        self.tint = tint
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            SettingsRowLabel(title: title, symbol: symbol, tint: tint)
            Spacer(minLength: Theme.Spacing.s)
            trailing
        }
        .settingsRowInsets()
    }
}

/// A tappable row. Primary-coloured with a chevron rather than blue text — in a
/// card-based list the blue tint reads as a link, while a chevron is the shared
/// "this goes somewhere" cue used by every other card in the app.
private struct SettingsButtonRow: View {
    let title: LocalizedStringKey
    let symbol: String
    let tint: Color
    var hint: String? = nil
    /// True for rows that leave the app (web, Mail, App Store). The trailing
    /// glyph switches to the outbound arrow so a chevron keeps meaning
    /// "pushes a screen here".
    var external: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.s) {
                SettingsRowLabel(title: title, symbol: symbol, tint: tint)
                Spacer(minLength: Theme.Spacing.s)
                Image(systemName: external ? "arrow.up.right" : "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    // Decorative — without this VoiceOver appends the symbol's
                    // name ("arrow up right") to the row's label.
                    .accessibilityHidden(true)
            }
            .settingsRowInsets()
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint(hint ?? (external ? "Opens outside the app" : ""))
    }
}

// MARK: - Links

/// Everywhere the profile screen can send someone. One place, so the App Store
/// id and site host can't drift between rows.
private enum AppLinks {
    static let appStore = URL(string: "https://apps.apple.com/app/id6783034270")!
    static let review = URL(string: "https://apps.apple.com/app/id6783034270?action=write-review")!
    static let privacy = URL(string: "https://biblecrosswordchallenge.com/privacy/")!
    /// Apple's standard EULA — the app has no bespoke terms page.
    static let terms = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    static let support = URL(string: "mailto:sambulosendas@gmail.com")!
}
