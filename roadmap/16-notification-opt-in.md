# 16 — Notification opt-in: attribute every ask, add two high-intent surfaces

**Goal:** raise the 18%-of-installs notification grant rate that caps every
notification channel and the push roadmap.

**The funnel (2026-08-11, pre-fix baseline):** 52% swiped past the onboarding
reminders page unanswered — but 67% of those who reached the system dialog said
yes. The ask converts; almost nobody was asked.

## What already existed

- **The primary fix was already built:** commit `1515532` swipe-locks the
  onboarding reminders page — shipping in 2.1 (12). The 18% baseline predates it.
- Day-2 re-ask sheet (`DailyReminderPrompt`), live since 2.0, once-ever for
  "Not now" decliners only.
- Profile toggle handles `.denied` → Settings deep-link. Unchanged; `.denied`
  players get no new prompts (a prompt does nothing for them).

## Built 2026-08-18 (this epic)

- [x] **T1 Attribution** — `notification_permission` gains `source`
      (`onboarding | prompt | completion | streak_card | profile`), and every
      surface logs `reminder_ask_shown(source:)` on impression, so each ask has
      its own funnel.
- [x] **T2 Completion ask** — `ReminderAskCard` ("Make it a habit / Same time
      tomorrow?") on the completion screen, first 3 solves until answered.
      Never alongside another ask: challenge result, review sheet, today's
      auto paywall, or the mini upsell all suppress it.
- [x] **T3 Streak ask** — same card under Home's streak card ("Protect your
      streak") at streak ≥ 2, once ever, never on comeback days.
- [x] **T4 Guardrails** — `ReminderAsk.decide` (pure, `DailyPresentation`
      pattern): one ask per day across ALL surfaces incl. the day-2 sheet, one
      per session, silence once granted/enabled or the system prompt is spent.
      9 unit tests (`ReminderAskTests`).
- [x] All surfaces reach the dialog through one shared `ReminderOptIn.enable`,
      which logs the sourced grant and schedules the reminder.
- [x] Debug seams: `-uiForceReminderAsk`, `-uiForceStreakAsk` (family of
      `-uiForceReminderPrompt`).

Verified on simulator: onboarding "Not now" → completion card → system dialog →
`notification_permission(granted: true, source: completion)`; day-2 sheet grant
(`source: prompt`); streak card render; decline logging (`reminder_declined`).

## Measure (after 2.1 ships + ~2 weeks)

- Onboarding funnel first: what did the swipe-lock alone recover? (memory:
  `notification-optin-leak` — re-measure before quoting any reach number)
- Per-surface: `reminder_ask_shown` → `notification_permission.granted` by
  `source`. Kill any surface that shows impressions and no grants.
- Guardrail check: `reminder_ask_shown` count per player per day must be ≤ 1.

## Deliberately not built

- Provisional notifications (quiet delivery would burn the one real ask).
- New `.denied` recovery surfaces (Profile-only stays).
- Any server push — reach must earn the infrastructure first.
