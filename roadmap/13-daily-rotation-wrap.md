# Ticket 13 — Daily rotation wrap (streak-break event, dated)

**Priority:** critical (dated: **2026-09-21**) — retention of the most engaged cohort
**Status:** `[ ]`
**Type:** eng / content
**Estimate:** S (safety net) + ongoing (content)
**Files:** `Views/HomeView.swift` (`DailyPuzzleCard`), `Services/PuzzleProvider.swift`, `Resources/puzzles.json`
**Related:** 01 seasonal packs + content cadence (the real fix), 11 streak comeback (adjacent, different trigger)

## Problem

The daily is a rotation, not a dated archive:

```swift
// PuzzleProvider.rotated
index = daysSinceEpoch % pool.count      // epoch 2026-07-01
```

Both pools wrap this September:

| Pool | Size | Wraps on | Serves |
|------|------|----------|--------|
| Dailies | 82 | **2026-09-21** | `daily-001` again |
| Minis | 90 | **2026-09-29** | `mini-…` #1 again |

On 21 Sep every player who has solved daily since launch is served a puzzle they
already completed. `DailyPuzzleCard` handles a completed puzzle by swapping the
clue count and CTA for `solvedReward` (`HomeView.swift`, `status == .completed`):

> ✅ **Solved** in 4:32

…with a green seal that bounces on appear. The hero card celebrates a puzzle
finished on 1 July. The rational read is "today is already done" — so the player
closes the app, completes nothing, and **the streak breaks**.

This lands on the whole daily cohort on the same day, some with 80-day streaks.
A freeze buys one day; day 83 serves `daily-002`, also solved, so it collapses
within a day or two.

### What is *not* broken

Worth stating, because it narrows the fix:

- **The streak mechanism is fine.** `Streaks.registerCompletion` is date-based and
  is not gated on `firstCompletion`, so replaying *does* advance the streak. The
  problem is purely that nothing invites the replay.
- **Achievement side-stats are guarded.** `noHintSolves`, `hardCompleted` and pack
  completion are all behind `firstCompletion`.
- **Progress is safe.** Ids are content-stable; the record for `daily-001` is
  reused, not duplicated.

## Goal

No player loses a streak because the app told them a fresh day was already done.

**Out of scope:** changing the rotation formula or the epoch (would move "today's
puzzle" for every existing player); per-player daily selection (breaks the shared
daily that challenges and "did you do today's?" depend on).

---

## Tasks

### T1 — Know when today's daily is a repeat

**Status:** `[ ]`

- [ ] Distinguish *solved today* (correct, celebrate it) from *solved on an earlier
      day* (a rotation repeat) — the condition is `record.completedDate` not being
      today, not `isCompleted`
- [ ] Same for the mini
- [ ] Keep it a pure function of (puzzle, record, date) so it's testable without a
      wall clock

**Acceptance**
- Unit tests: solved-today, solved-earlier, never-solved, and the exact wrap dates
  above driven through `dailyPuzzle(for:calendar:)`

---

### T2 — Card treatment for a repeat

**Status:** `[ ]`

- [ ] A repeat must not present the day as finished: no `solvedReward` as the
      card's whole state, no celebratory bounce
- [ ] Offer the replay explicitly — "Play again", with their previous time as the
      thing to beat (the app already has this language on the completion screen)
- [ ] Keep the daily shared: everyone still gets the same puzzle, so challenges
      and social copy still hold
- [ ] Consider a secondary route to something unsolved (Library's free window
      already gives free players seven, per 09)

**Acceptance**
- On a wrap date, the daily card shows a playable action, not a finished state
- Solving it still advances the streak (unchanged behaviour, worth asserting)
- A puzzle solved *earlier today* still shows the existing solved treatment

---

### T3 — Push the wrap out with content

**Status:** `[ ]`

This is the actual fix; T2 is the permanent safety net, because any finite pool
wraps eventually.

- [ ] Decide the cadence in 01 — how many dailies per month, and the buffer to
      keep ahead of the rotation
- [ ] Add dailies before **2026-09-21**; every puzzle added moves the wrap a day
- [ ] Ids are content-stable and append-only — new specs get no `id`, the
      generator assigns; `puzzles.json` diff must show additions only

**Acceptance**
- Wrap date is beyond the next planned release cycle, with the current date and
  pool size recorded here when it changes

---

### T4 — Replays inflate the solved count

**Status:** `[ ]`

Secondary, surfaced while tracing the above. `registerCompletion` does
`totalPuzzlesCompleted += 1` on *every* completion, replays included. Pre-existing
(premium could already replay from Library), but the wrap makes it systematic:
the whole cohort re-solves the whole pool.

- [ ] Decide whether "Solved" means completions or distinct puzzles
- [ ] If distinct: it feeds the puzzle-count achievements, so changing it changes
      unlock timing — check `Achievements` thresholds before touching
- [ ] Whatever is decided, Profile's "Solved" tile and the achievement thresholds
      must agree

**Acceptance**
- One documented definition, used by both surfaces

---

## Risks

- Reframing the daily card touches the app's most-seen view — keep the
  solved-today path byte-identical
- Serving unsolved-instead-of-daily would break the shared daily; explicitly
  rejected above, don't let it back in via T2's secondary route
- Changing `totalPuzzlesCompleted` semantics can retroactively lock or unlock
  achievements for existing players

## Test plan

- [ ] `dailyPuzzle(for: 2026-09-20)` and `(for: 2026-09-21)` — the second is
      `puzzles.first`
- [ ] Same for minis at 2026-09-28 / 2026-09-29
- [ ] Repeat + completed-earlier → card offers play, not a finished state
- [ ] Completed-today → unchanged solved treatment
- [ ] Completing a repeat advances the streak
- [ ] Free player: a repeat is still playable under 09's gate (it will be — they
      have progress on it, so the grandfather clause covers it)

## Done when

A player opening the app on 21 Sep is offered something to play, their streak
survives the week, and the wrap date is far enough out that the safety net is
insurance rather than the daily experience.
