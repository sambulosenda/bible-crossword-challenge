//
//  DailyReminderPrompt.swift
//  Bible Crossword Challenge
//
//  The second ask for a daily reminder, shown once to players who declined
//  during onboarding and then came back on a later day.
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
                Text("You came back")
                    .kicker()
                // Names what they already did rather than what the app wants.
                // On day one "keep the streak" was an abstraction; to someone
                // who has returned of their own accord it's a description.
                Text("Make it two\ndays running.")
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
            await notifications.reschedule(for: profile, enabled: true, minutes: minutes)
        }
        return granted
    }
}

// MARK: - Inline ask card

/// The compact form of the ask for surfaces that are already a screen of their
/// own (completion, Home). Same preview, same buttons, no time picker — the
/// stored default time is offered in the button and adjustable in Profile.
struct ReminderAskCard: View {
    let profile: PlayerProfile
    let surface: ReminderAsk.Surface
    let kicker: String
    let headline: String
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

    var body: some View {
        VStack(spacing: Theme.Spacing.m) {
            VStack(spacing: Theme.Spacing.xs) {
                Text(kicker)
                    .kicker()
                Text(headline)
                    .font(.headline)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)

            NotificationPreviewCard()

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
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.pillProminent)
            .disabled(working)

            // Quiet, same weight as the other asks' declines — see the day-2
            // sheet's note on hard-to-refuse buttons.
            Button("Not now") {
                analytics.log(.reminderDeclined(source: surface.rawValue))
                onFinish()
            }
            .font(.subheadline.weight(.semibold))
            .tint(.secondary)
            .disabled(working)
        }
        .padding(Theme.Spacing.m)
        .elevatedCard()
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
