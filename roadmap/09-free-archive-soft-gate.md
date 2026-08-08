# Ticket 09 — Free archive soft gate

**Priority:** high (fairness + reviews + long-term conversion)  
**Status:** `[x]`  
**Type:** eng / product  
**Estimate:** M  
**Files:** `Views/LibraryView.swift`, possibly `PlayerProfile` / free-tier helpers, paywall sources  
**Related:** 08 main paywall, free daily/mini model

## Problem

Free users hit a **hard lock** on Library: no archive play at all — only locked preview + Unlock Premium.

That maximizes `archive` paywall pressure but risks:

- “Everything is locked” 1-stars before day 3
- Players never sample enough content to *want* Premium
- Contradicts marketing “80+ puzzles / revisit Library anytime” for free users who take it literally

Daily + mini free is good; **zero** back catalog is harsh.

## Goal

Give free players a **small, honest** archive allowance so they feel the library, while Premium still unlocks the full catalog.

**Out of scope:** Changing pack Premium flags, hint limits, ads (12), full free archive.

---

## Product decision (pick one before build)

Document the choice in this file when decided:

| Option | Rule | Pros | Cons |
|--------|------|------|------|
| **A — Rolling window** | Free: last N calendar dailies + today’s (e.g. N=7) | Simple mental model | Old favorites still locked |
| **B — Lifetime free slots** | Free: first K archive opens or K distinct puzzles ever (e.g. K=5) | Samples more of catalog | Bookkeeping; “used up” frustration |
| **C — Difficulty slice** | Free: all Easy dailies in archive | Clear | Content-dependent; may be too many/few |

**DECIDED: A (N=7), amended.** Two changes, both forced by what the code actually does:

1. **Framed by rotation position, not dates.** The daily is `puzzles[daysSinceEpoch % 82]`
   — a rotation, not a dated archive. Puzzles carry a `publishDate` that *currently*
   lines up with the rotation, but the pool wraps on **2026-09-21**, after which
   "last 7 days" would mean "seven you already solved". The free set is the seven
   currently in rotation; copy says "This week's seven are free", claims no dates,
   and respects the note at the top of `LibraryView` ("never a day to go back to").
2. **Started stays unlocked.** A sliding window alone can lock a puzzle mid-solve
   with the player's own progress inside it — worse than never offering it. Anything
   with a `PuzzleRecord` stays open.

Both rules are stateless: the window is arithmetic on the rotation, "started" is the
record the game already writes. **No new `PlayerProfile` fields, so no CloudKit schema
deploy** — which is what ruled out option B. Option C was ruled out on content: the
82-puzzle pool is 28 easy / 35 medium / 19 hard, so "all Easy free" gives away a third
of the archive.

Also decide:

- [x] Free minis in archive? (Recommend: same window or all past minis free — minis are growth hooks)
- [x] Pack-only `pack-*` puzzles stay Premium-gated via packs (don’t leak via Library)

---

## Tasks

### T1 — Free-tier access helper

**Status:** `[x]`

- [x] Single source of truth, e.g. `PuzzleAccess` or methods on provider/profile:  
  `func canPlay(_ puzzle: Puzzle, isPremium: Bool) -> Bool`
- [x] Daily **today** + **today’s mini** always playable free (already true via Home)
- [x] Archive eligibility per chosen option
- [x] Challenges: keep free users able to open challenged puzzle id (RootView already bypasses archive gate — don’t break)

**Acceptance**
- Unit tests for window/slot edge cases (timezone midnight, premium true, pack ids)

---

### T2 — Library UI for free users

**Status:** `[x]`

- [x] Replace all-or-nothing `lockedState` with a **list**: playable free rows + locked rows
- [x] Locked rows: lock icon → paywall `source: "archive"` (or `archive_locked_row`)
- [x] Header copy: honest, e.g. “Free this week: last 7 dailies. Premium unlocks all \(n).”
- [x] Empty/search/filter still make sense when mixed free/locked

**Acceptance**
- Free user can start and complete at least one non-today archive puzzle under the rule
- Premium list behavior unchanged

---

### T3 — Home / marketing consistency

**Status:** `[x]`

- [x] Any copy that says free users can’t use Library at all — update
- [x] Paywall `archive` headline (`PremiumCopy.archive`) still true (“Every puzzle, back to the first”) — Premium differentiates **full** history
- [x] Don’t break Library → paywall conversion entirely: keep a clear Upgrade path when tapping locked items

**Acceptance**
- No UI string claims free users get zero archive if they now get some

---

### T4 — Analytics

**Status:** `[x]`

- [x] Optional: `archive_puzzle_opened(free: Bool)` or reuse existing start events with a `access` param — only if low cost
- [x] At minimum: watch `paywall_opened(source: archive)` rate pre/post — expect volume drop but **higher** convert % possible

**Acceptance**
- Can tell post-ship whether soft gate hurt or helped purchase from archive

---

## Risks

- Soft gate too generous → less Premium pressure (mitigate: N=7 not N=90)
- Soft gate too stingy → still feel locked (mitigate: show free rows first)
- CloudKit: if counting “free slots used,” new profile fields need defaults (prefer option A to avoid new synced state)

## Test plan

- [x] Free: today daily + mini playable from Home
- [x] Free: archive shows free subset playable; older locked → paywall
- [x] Premium: full list
- [x] Challenge link to locked-for-archive puzzle still plays free
- [x] Pack exclusive puzzles not free via Library
- [x] Tests for date boundary (complete at 11:50pm / 12:10am)

## Done when

Free players can **sample the archive** under a documented rule; Premium remains the only way to **full** library; challenges and packs still behave.
