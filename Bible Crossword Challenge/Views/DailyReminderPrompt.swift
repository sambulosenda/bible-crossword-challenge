//
//  DailyReminderPrompt.swift
//  Bible Crossword Challenge
//
//  The second ask for a daily reminder, shown once, over the completion screen
//  of a solve on a later day than the install (see
//  `ReminderAsk.Surface.returnDaySheet`). It used to open at launch on that
//  day; 29 of the 34 players who met it there tapped it away to reach the
//  puzzle. Now the puzzle is done and the sheet asks about a habit the player
//  has just demonstrated.
//
//  Why a second ask exists at all: of 66 players who reached the onboarding
//  reminder step, 48 tapped "Not now" and 8 more declined the system dialog —
//  10 ended up with a reminder. The Profile toggle that could fix that has, on
//  the same period's data, never been used once. Retention is the app's binding
//  constraint, and a reminder is the only mechanism that brings anyone back, so
//  leaving 48 players with no second chance was the largest fixable gap.
//
//  The 48 who tapped "Not now" never called `requestAuthorization()`, so iOS
//  has not spent their one system prompt. That is what makes this worth doing:
//  the re-ask can be the real thing, not a plea to visit Settings. Players who
//  reached the system dialog and denied it are deliberately excluded — for them
//  a prompt does nothing, and Settings is a separate piece of work.
//

import SwiftUI

/// A mock of the reminder being asked for. Shared with onboarding so both asks
/// show the same notification: the player agrees to a thing they have seen,
/// rather than to "notifications".
struct NotificationPreviewCard: View {
    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color(red: 0.29, green: 0.47, blue: 0.96),
                             Color(red: 0.13, green: 0.25, blue: 0.78)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
                .frame(width: 38, height: 38)
                .overlay {
                    Image(systemName: "book.closed.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                }

            VStack(alignment: .leading, spacing: 1) {
                Text("Bible Crossword")
                    .font(.footnote.weight(.semibold))
                Text("Today’s puzzle is ready — keep your streak alive.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Text("now")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(Theme.Spacing.m)
        .elevatedCard(cornerRadius: 18)
    }
}

struct DailyReminderPrompt: View {
    let profile: PlayerProfile
    /// Called when the sheet should close, whichever way it ended. The caller
    /// records that the ask has happened — this view never asks twice.
    let onFinish: () -> Void

    @Environment(\.analytics) private var analytics
    @Environment(\.notifications) private var notifications
    @AppStorage("remindersEnabled") private var remindersEnabled = false
    @AppStorage("reminderMinutes") private var reminderMinutes = ReminderTime.defaultMinutes

    @State private var working = false

    private var reminderTimeText: String {
        ReminderTime.date(fromMinutes: reminderMinutes)
            .formatted(date: .omitted, time: .shortened)
    }

    private var reminderTime: Binding<Date> {
        Binding(
            get: { ReminderTime.date(fromMinutes: reminderMinutes) },
            set: { reminderMinutes = ReminderTime.minutes(from: $0) }
        )
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.l) {
            Spacer(minLength: 0)

            VStack(spacing: Theme.Spacing.m) {
                Text("You came back and solved it")
                    .kicker()
                // Names what they already did rather than what the app wants:
                // they returned of their own accord and finished — the
                // reminder is for repeating that, not for starting it.
                Text("Same time\ntomorrow?")
                    .font(.scripture(.largeTitle, weight: .semibold))
                    .multilineTextAlignment(.center)
            }

            NotificationPreviewCard()

            HStack {
                Text("Every day at")
                    .font(.body)
                Spacer()
                DatePicker("Reminder time", selection: reminderTime,
                           displayedComponents: .hourAndMinute)
                    .labelsHidden()
            }
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.vertical, Theme.Spacing.s)
            .elevatedCard()

            Spacer(minLength: 0)

            VStack(spacing: Theme.Spacing.s) {
                Button {
                    enable()
                } label: {
                    Group {
                        if working {
                            ProgressView().tint(Theme.onInk)
                        } else {
                            Text("Remind me at \(reminderTimeText)")
                        }
                    }
                }
                .buttonStyle(.pillProminent)
                .disabled(working)

                // Same weight as onboarding's. A second ask is already pushing
                // it; a hard-to-refuse one would be worse than not asking.
                Button("No thanks") {
                    // Same event as onboarding's decline, so the two asks can be
                    // compared directly — see `Analytics.reminderDeclined`.
                    analytics.log(.reminderDeclined(source: "prompt"))
                    onFinish()
                }
                .font(.subheadline.weight(.semibold))
                .tint(.secondary)
                .padding(.top, Theme.Spacing.xs)
                .disabled(working)
            }
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.vertical, Theme.Spacing.xl)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .interactiveDismissDisabled(working)
        // This sheet appears right after a solve, so "now" is the play hour
        // worth reminding them at — see `seedSuggestionIfUnset`.
        .onAppear { ReminderTime.seedSuggestionIfUnset() }
    }

    private func enable() {
        working = true
        Task {
            // Same events as onboarding, so the two asks can be compared
            // directly rather than needing a separate funnel.
            let granted = await ReminderOptIn.enable(
                source: "prompt", profile: profile,
                notifications: notifications, analytics: analytics,
                minutes: reminderMinutes
            )
            if granted { remindersEnabled = true }
            working = false
            onFinish()
        }
    }
}

// MARK: - Shared accept flow

/// The one place a reminder ask reaches the system dialog. Every surface
/// (day-2 sheet, completion card, streak card) funnels through here so the
/// grant is logged with its source and the schedule lands the same way.
enum ReminderOptIn {
    /// Returns whether permission was granted. The caller flips its own
    /// `remindersEnabled` @AppStorage on true — this writes the shared default
    /// so out-of-view readers agree, but SwiftUI bindings refresh from the
    /// caller's wrapper.
    @MainActor
    static func enable(
        source: String,
        profile: PlayerProfile,
        notifications: NotificationService,
        analytics: AnalyticsService,
        minutes: Int
    ) async -> Bool {
        let granted = await notifications.requestAuthorization()
        analytics.log(.notificationPermission(granted: granted, source: source))
        if granted {
            UserDefaults.standard.set(true, forKey: "remindersEnabled")
            analytics.log(.reminderSettingChanged(enabled: true))
            await notifications.reschedule(
                for: profile, enabled: true, minutes: minutes,
                // Granting a reminder never turns on pack news: that is a
                // separate, explicit opt-in in Settings.
                packNews: UserDefaults.standard.bool(forKey: "packNewsEnabled")
            )
        }
        return granted
    }
}

// MARK: - Inline ask row

/// The smallest form of the ask: one row for a card the player is already
/// looking at (the completion scorecard, under the week row). No preview, no
/// kicker — the surrounding card supplies the context, and the row's job is
/// to be seen. Same accept path and analytics as the other surfaces.
struct ReminderAskRow: View {
    let profile: PlayerProfile
    let surface: ReminderAsk.Surface
    /// Called once the ask is answered either way, so the owner can remove
    /// the row. Impressions are recorded by the owner when it decides to show.
    let onFinish: () -> Void

    @Environment(\.analytics) private var analytics
    @Environment(\.notifications) private var notifications
    @AppStorage("remindersEnabled") private var remindersEnabled = false
    @AppStorage("reminderMinutes") private var reminderMinutes = ReminderTime.defaultMinutes
    @State private var working = false

    private var reminderTimeText: String {
        ReminderTime.date(fromMinutes: reminderMinutes)
            .formatted(date: .omitted, time: .shortened)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(spacing: Theme.Spacing.s) {
                Image(systemName: "bell.badge")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Same time tomorrow?")
                        .font(.subheadline.weight(.semibold))
                    // Not "one a day": a player with a streak also gets the
                    // 9 PM last call, so the old line promised a quota the
                    // scheduler was never going to keep.
                    Text("A nudge at \(reminderTimeText), plus a last call if your streak is about to break. Change it any time.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }

            HStack(spacing: Theme.Spacing.m) {
                // Quiet, same weight as the other asks' declines.
                Button("Not now") {
                    analytics.log(.reminderDeclined(source: surface.rawValue))
                    onFinish()
                }
                .font(.subheadline.weight(.semibold))
                .tint(.secondary)
                .disabled(working)

                Spacer(minLength: 0)

                Button {
                    enable()
                } label: {
                    Group {
                        if working {
                            ProgressView().tint(.white)
                        } else {
                            Text("Remind me")
                                .foregroundStyle(.white)
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, Theme.Spacing.xs)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .tint(Theme.accent)
                .disabled(working)
                .accessibilityLabel("Remind me at \(reminderTimeText)")
                .accessibilityHint("Asks for notification permission")
            }
        }
        // Mid-play, so "now" is the play hour the button should offer — see
        // `seedSuggestionIfUnset`.
        .onAppear { ReminderTime.seedSuggestionIfUnset() }
    }

    private func enable() {
        working = true
        Task {
            let granted = await ReminderOptIn.enable(
                source: surface.rawValue, profile: profile,
                notifications: notifications, analytics: analytics,
                minutes: reminderMinutes
            )
            if granted { remindersEnabled = true }
            working = false
            onFinish()
        }
    }
}

// MARK: - Inline ask card

/// Today's form of the ask, where the streak card used to stand: one row on
/// its own card — a bell, the time, why, Turn on and a close. It was a card
/// with a kicker, a headline, a mock notification and a full-width pill
/// (2026-10-24): the tallest thing on Today for one yes/no question. The
/// completion screen uses `ReminderAskRow` inside its scorecard instead.
struct ReminderAskCard: View {
    let profile: PlayerProfile
    let surface: ReminderAsk.Surface
    /// Called once the ask is answered either way, so the owner can remove the
    /// card. Impressions are recorded by the owner when it decides to show.
    let onFinish: () -> Void

    @Environment(\.analytics) private var analytics
    @Environment(\.notifications) private var notifications
    @AppStorage("remindersEnabled") private var remindersEnabled = false
    @AppStorage("reminderMinutes") private var reminderMinutes = ReminderTime.defaultMinutes
    @State private var working = false

    private var reminderTimeText: String {
        ReminderTime.date(fromMinutes: reminderMinutes)
            .formatted(date: .omitted, time: .shortened)
    }

    /// The reason, in the player's own numbers when there are any. Short
    /// enough to stay on one line beside the button on a 17e.
    private var why: String {
        let streak = profile.currentStreak
        // A non-breaking hyphen, so a wrap never leaves "12-" on its own.
        return streak >= 2 ? "For your \(streak)\u{2011}day streak" : "Before the day runs out"
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            RowIcon(symbol: "bell.fill", tint: FeatureTint.streak)

            VStack(alignment: .leading, spacing: 1) {
                Text("Remind me at \(reminderTimeText)")
                    .font(.subheadline.weight(.semibold))
                Text(why)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)

            Button {
                enable()
            } label: {
                Group {
                    if working {
                        ProgressView().tint(Theme.onInk)
                    } else {
                        Text("Turn on")
                    }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.onInk)
                .padding(.horizontal, Theme.Spacing.s + 4)
                .padding(.vertical, 7)
                .background(Theme.ink, in: .capsule)
            }
            .buttonStyle(.plain)
            .disabled(working)
            .accessibilityLabel("Remind me at \(reminderTimeText)")
            .accessibilityHint("Asks for notification permission")

            // The decline, as the other asks' "Not now" — logged the same.
            Button {
                analytics.log(.reminderDeclined(source: surface.rawValue))
                onFinish()
            } label: {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(working)
            .accessibilityLabel("Not now")
        }
        .padding(.leading, Theme.Spacing.m)
        .padding(.trailing, Theme.Spacing.s)
        .padding(.vertical, Theme.Spacing.s)
        .elevatedCard()
        // The card shows mid-play, so "now" is the play hour the button
        // should offer — see `seedSuggestionIfUnset`.
        .onAppear { ReminderTime.seedSuggestionIfUnset() }
    }

    private func enable() {
        working = true
        Task {
            let granted = await ReminderOptIn.enable(
                source: surface.rawValue, profile: profile,
                notifications: notifications, analytics: analytics,
                minutes: reminderMinutes
            )
            if granted { remindersEnabled = true }
            working = false
            onFinish()
        }
    }
}
