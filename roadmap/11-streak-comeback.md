# Ticket 11 — Streak break / comeback

**Priority:** medium (D1–D7 retention)  
**Status:** `[ ]`  
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

**Status:** `[ ]`

- [ ] On launch after `Streaks.normalize`, distinguish:
  - **Freeze saved** (already: `lastFreezeUsedDate` today)
  - **Streak reset this launch** (was >0, now 0) — may need a one-shot flag written during normalize, e.g. `streakBrokenAt` or UserDefaults `pendingStreakBreakBanner`
- [ ] Don’t re-show break banner every launch forever — once until dismissed or until streak > 0 again

**Acceptance**
- Tests: freeze path doesn’t fire “streak broken”; multi-day gap does; single show

---

### T2 — Home comeback card

**Status:** `[ ]`

When pending break (streak 0 after loss):

- [ ] Card on Home above or instead of empty flame energy: calm copy  
  e.g. “Streak paused — one mini starts a new one.”
- [ ] Primary: **Play today’s mini** (or daily if mini missing)
- [ ] Secondary dismiss
- [ ] If freeze saved: keep existing cyan reassurance (don’t stack break + save)

**Acceptance**
- After artificial streak break in debug/seed, Home shows comeback CTA
- Completing mini/daily clears break state and starts streak 1 normally

---

### T3 — Notifications

**Status:** `[ ]`

- [ ] **At-risk (existing):** ensure copy mentions freeze if `streakFreezes > 0` (“A freeze can cover you tonight”)
- [ ] **Day after break (new, optional):** one notification if reminders enabled and streak hit 0 yesterday — “New streak starts with today’s puzzle” — not spammy (once)
- [ ] Respect auth + `remindersEnabled`; no notify if Premium-only nonsense

**Acceptance**
- No notification storms; reschedule logic still centralized in `NotificationService`

---

### T4 — Completion copy when restarting

**Status:** `[ ]`

- [ ] When completion advances streak from 0 → 1 after a break, light celebration: “New streak — day 1” (not only for big milestones)
- [ ] Don’t steal thunder from achievements / pack complete

**Acceptance**
- First solve after break feels acknowledged

---

### T5 — Analytics

**Status:** `[ ]`

- [ ] `streak_broken(previousLength: Int)` (bucket or cap length if needed)
- [ ] `streak_comeback_started(source: home_card|notification|organic)`
- [ ] Existing `streak_updated` remains source of truth for length

**Acceptance**
- Can measure break → return-within-7d in analytics

---

## Product rules (do not violate)

- **Never** sell “restore your 40-day streak for $X”
- Freezes stay the only miss-protection
- Comeback is encouragement + mini path, not a second freeze economy

## Test plan

- [ ] Miss one day with freeze > 0 → freeze save UI, streak intact, no comeback card
- [ ] Miss one day with freeze = 0 → streak 0, comeback card once
- [ ] Miss many days → streak 0, comeback once
- [ ] Complete mini from card → streak 1, card gone
- [ ] Reminder schedule with/without freezes at risk

## Done when

Losing a streak produces a **clear, kind path back** (especially via mini), with analytics on break and comeback — without paywalling grief.
