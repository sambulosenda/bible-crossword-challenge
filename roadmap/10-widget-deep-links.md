# Ticket 10 — Widget deep links (complete the habit loop)

**Priority:** medium (cheap retention)  
**Status:** `[ ]`  
**Type:** eng  
**Estimate:** S–M  
**Files:** `BibleCrosswordWidget/`, `Services/WidgetBridge.swift`, `Views/RootView.swift`  
**Related:** daily + mini rotation, streaks

## Current baseline (partially shipped)

Widget already deep-links:

| State | URL | App handling |
|-------|-----|----------------|
| Streak at stake / fresh | `biblecrossword://play-daily` | Opens Today tab + pushes **daily** puzzle |
| Solved today | `biblecrossword://today` | Today tab, empty path (Home) |

Also exists: `biblecrossword://puzzle?id=…` (pack next), challenge URLs.

**Gaps**

- No **`play-mini`** path — mini is the faster habit / Game Center board entry
- Solved-today tap only parks on Home — no “do the mini if still open” intelligence
- No analytics on widget open
- Snapshot may not include “mini completed today” so widget can’t choose best CTA
- Interactive / App Intent buttons (iOS 17+) not used — single `widgetURL` only

## Goal

Tapping the widget always lands on the **most useful next action**: unfinished daily → daily; daily done but mini open → mini; both done → Home (or streak celebration). Instrument so we know it works.

**Out of scope:** New widget designs/sizes beyond what’s needed for links; Live Activities; Android.

---

## Tasks

### T1 — Extend app-group snapshot

**Status:** `[ ]`

In `WidgetBridge` + widget `StreakSnapshot`:

- [ ] `dailyCompletedToday: Bool` (or derive from last completed + puzzle ids if already enough)
- [ ] `miniCompletedToday: Bool`
- [ ] Write from app whenever completion / launch normalize updates widget timeline
- [ ] Reload timelines after write (`WidgetCenter.shared.reloadAllTimelines()` — if not already)

**Acceptance**
- Widget process can read both flags without SwiftData

---

### T2 — Deep link hosts

**Status:** `[ ]`

| URL | Behavior |
|-----|----------|
| `biblecrossword://play-daily` | Push today’s full daily (existing) |
| `biblecrossword://play-mini` | Push today’s mini if present |
| `biblecrossword://today` | Home on Today tab (existing) |
| Optional: `biblecrossword://play` | **Smart:** unfinished daily → daily; else unfinished mini → mini; else today |

- [ ] Implement `play-mini` + preferred smart `play` in `RootView.handleDeepLink`
- [ ] Guard `hasOnboarded` like other widget targets
- [ ] If mini missing from bundle, fall back to daily or today

**Acceptance**
- Manual open of each URL in Simulator does the right navigation
- Free user can open mini via link (not archive-gated)

---

### T3 — Widget chooses best URL

**Status:** `[ ]`

Update `StreakEntry.deepLinkURL` (and any other widget families):

- [ ] Not solved daily → `play-daily` (or smart `play`)
- [ ] Daily done, mini not done → `play-mini`
- [ ] Both done → `today` (or keep mild streak display without forcing a puzzle)
- [ ] Copy/accessibility on widget reflects action (“Play today’s mini”) when relevant — if layout allows

**Acceptance**
- Mid-day after daily only: tap opens mini
- After both: tap opens Home, not a completed daily again

---

### T4 — Analytics

**Status:** `[ ]`

- [ ] Log e.g. `widget_opened(destination: daily|mini|today)` on handle (new `AnalyticsEvent` case)
- [ ] Low cardinality destinations only

**Acceptance**
- Event fires once per open handling, not on every Home redraw

---

### T5 — Optional stretch

**Status:** `[ ]`

- [ ] Lock Screen / circular widget same URL rules
- [ ] iOS 17+ `Button` with `OpenURLIntent` for dual actions (Play daily | Play mini) if family has space
- [ ] Document URL scheme in `docs/` or widget file header

---

## Test plan

- [ ] Fresh day, nothing solved: widget → daily
- [ ] Daily solved, mini not: widget → mini
- [ ] Both solved: widget → Home
- [ ] Cold start from killed app via widget URL
- [ ] Before onboarding complete: link doesn’t crash (ignore or queue)
- [ ] Timeline rolls at midnight: flags reset with day

## Done when

Widget tap is a **one-tap path into the right puzzle**, including mini; snapshot + analytics support it.
