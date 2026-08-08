# Ticket 11 — Streak break / comeback

**Priority:** medium (D1–D7 retention)  
**Status:** `[x]`  
**Type:** eng / copy  
**Estimate:** M  
**Files:** `Models/Persistence.swift` (`Streaks`), `Views/HomeView.swift`, `NotificationService.swift`, Completion / Profile streak UI  
**Related:** streak freezes, daily mini, reminders

## Problem

Streak system already has:

- Daily advance on completion
- Freezes that auto-spend for **exactly one** missed day (`Streaks.normalize`)
- Home card note when freeze saved you
- Freeze earned celebrations
- Evening streak-risk notification path in `NotificationService`

**Gaps after a real break** (freeze spent or streak → 0):

- No dedicated **comeback** moment — Home just shows 0 / cold flame
- No guided **easy win** (mini) to restart without facing a hard daily first
- Risk copy exists late-day, but **post-break** re-engagement is weak
- Players who lose a long streak may churn instead of starting streak=1 again

## Goal

When a streak dies (or is one freeze from dying), make the next open feel like **recovery**, not failure — with a clear, low-friction path to start again.

**Out of scope:** Changing freeze max/economy globally (unless a tiny tweak); backend; guilt-heavy dark patterns; paying to restore streak.

---

## Tasks

### T1 — Detect break vs freeze-save (surface state)

**Status:** `[x]`

- [x] On launch after `Streaks.normalize`, distinguish:
  - **Freeze saved** (already: `lastFreezeUsedDate` today)
  - **Streak reset this launch** (was >0, now 0) — may need a one-shot flag written during normalize, e.g. `streakBrokenAt` or UserDefaults `pendingStreakBreakBanner`
- [x] Don’t re-show break banner every launch forever — once until dismissed or until streak > 0 again

**Acceptance**
- Tests: freeze path doesn’t fire “streak broken”; multi-day gap does; single show

---

### T2 — Home comeback card

**Status:** `[x]`

When pending break (streak 0 after loss):

- [x] Card on Home above or instead of empty flame energy: calm copy  
  e.g. “Streak paused — one mini starts a new one.”
- [x] Primary: **Play today’s mini** (or daily if mini missing)
- [x] Secondary dismiss
- [x] If freeze saved: keep existing cyan reassurance (don’t stack break + save)

**Acceptance**
- After artificial streak break in debug/seed, Home shows comeback CTA
- Completing mini/daily clears break state and starts streak 1 normally

---

### T3 — Notifications

**Status:** `[~]` — first bullet done, second deliberately not (see ship notes)

- [x] **At-risk (existing):** ensure copy mentions freeze if `streakFreezes > 0` (“A freeze can cover you tonight”)
- [ ] **Day after break (new, optional):** one notification if reminders enabled and streak hit 0 yesterday — “New streak starts with today’s puzzle” — not spammy (once)
- [x] Respect auth + `remindersEnabled`; no notify if Premium-only nonsense

**Acceptance**
- No notification storms; reschedule logic still centralized in `NotificationService`

---

### T4 — Completion copy when restarting

**Status:** `[x]`

- [x] When completion advances streak from 0 → 1 after a break, light celebration: “New streak — day 1” (not only for big milestones)
- [x] Don’t steal thunder from achievements / pack complete

**Acceptance**
- First solve after break feels acknowledged

---

### T5 — Analytics

**Status:** `[x]`

- [x] `streak_broken(previousLength: Int)` (bucket or cap length if needed)
- [x] `streak_comeback_started(source: home_card|notification|organic)`
- [x] Existing `streak_updated` remains source of truth for length

**Acceptance**
- Can measure break → return-within-7d in analytics

---

## Product rules (do not violate)

- **Never** sell “restore your 40-day streak for $X”
- Freezes stay the only miss-protection
- Comeback is encouragement + mini path, not a second freeze economy

## Test plan

- [x] Miss one day with freeze > 0 → freeze save UI, streak intact, no comeback card
- [x] Miss one day with freeze = 0 → streak 0, comeback card once
- [x] Miss many days → streak 0, comeback once
- [x] Complete mini from card → streak 1, card gone
- [x] Reminder schedule with/without freezes at risk

## Done when

Losing a streak produces a **clear, kind path back** (especially via mini), with analytics on break and comeback — without paywalling grief.

---

## Ship notes

**No new persisted model state.** `Streaks.normalize` returns a `Streaks.Outcome`
(`unchanged` / `freezeSaved` / `broken(previous:)`) and the break is held in
`@AppStorage("pendingStreakBreak")`. T1 suggested a `streakBrokenAt` field on
`PlayerProfile`; that would be a synced SwiftData field, so it would need a
CloudKit schema deploy to Production before release — for a transient piece of UI
state. `broken` is reported only by the pass that actually resets a running
streak, so repeat launches report `unchanged` and the card can't re-fire.

**The card replaces StreakCard rather than sitting above it.** Stacking a comeback
card on a flame card reading 0 states the loss twice and answers it once. The two
can't collide anyway: a freeze save means the streak survived.

**The offer is owed until something is solved.** `pendingStreakBreak` clears on the
solve, not on the card's tap — opening a puzzle and backing out shouldn't spend it.
Any solve counts, not just one launched from the card; `source` records which.

**T3's second bullet is deliberately not done.** A separate day-after-break
notification would land on top of the existing daily reminder, which already fires
that morning with "Today's puzzle is ready". Two notifications the day after a
player lapses is the spam the ticket warns about, and the second one carries no
information the first doesn't. The at-risk copy now names an available freeze
(first bullet) — withholding it to keep the threat sharp would be a lie by
omission about something the player earned.

**Debug affordance:** launch with `-uiSeedStreakBreak` to date a 14-day streak into
the past with no freezes, so the next normalize breaks it. The test plan needs an
artificial break and there is no other way to reach the card without waiting two
real days.

**Verified end to end on device:** break detected on launch → card shown → mini
played from the card → "New streak — day 1" on completion → card gone, streak card
back at 1 with best 14. Unit tests cover freeze-vs-break, multi-day gaps, the
report-once rule, break after a spent freeze, and restart-at-1.
