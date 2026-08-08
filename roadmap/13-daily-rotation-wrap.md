# Ticket 13 — Daily rotation wrap (streak-break event, dated)

**Priority:** critical (dated: **2026-09-21**) — retention of the most engaged cohort
**Status:** `[~]` — T1, T2 shipped (the safety net). T3 (content) and T4
(replay counting) open; T3 is the actual fix.
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

**Status:** `[x]`

- [x] `DailyPresentation.of(record:on:calendar:)` — `.solvedToday`,
      `.playedBefore`, or `.play(status)`, keyed on `completedDate`, not
      `isCompleted`
- [x] Same type drives the mini
- [x] Pure in `(record, date, calendar)`

Kept **separate from `PuzzleStatus`** rather than adding a case to it. "Repeat"
only means anything where the app claims a puzzle is *today's*; in Archive and
pack lists a completed puzzle is simply completed, and a fourth case would have
forced every one of those call sites to answer a question it doesn't have.

An undated completion (pre-dating the field, or arrived through sync without it)
is treated as a repeat: a needless replay costs nothing, a false "done" costs a
streak.

**Acceptance**
- [x] Unit tests: solved-today, solved-earlier, same-day-different-hour,
      yesterday-by-an-hour, never-solved, in-progress, undated, zero-time
- [x] Wrap dates driven through `dailyPuzzle(for:)` / `dailyMini(for:)`

**The tests count in `Calendar.current`, not UTC** — `PuzzleProvider` builds its
epoch from `Calendar.current`, so pinning a date in UTC puts the index a day out.
Worth knowing beyond the test: **the exact wrap date is the device's, not a
universal one.** A player east of the line sees it first.

---

### T2 — Card treatment for a repeat

**Status:** `[x]`

- [x] A repeat shows the meta row an unsolved puzzle shows — no green seal, no
      bounce (the bounce is now gated on `.solvedToday`, not `isCompleted`)
- [x] An accent pill turns the old time into a target: "Played before · beat 4:32"
- [x] The CTA is **prominent** for a repeat, where solved-today keeps its tonal
      replay: on a wrap day this *is* the day's action and the streak depends on
      it being taken
- [x] Daily stays shared — nothing about the rotation changed
- [x] Same treatment on the mini card, which wraps eight days later
- [ ] Secondary route to something unsolved — not built; the prominent replay
      answers the streak risk on its own, and a second CTA on the hero card is a
      bigger design change than the safety net warrants

**Green is this app's word for "done", so a repeat doesn't get any.** The pill is
accent, the mini keeps its blue bolt instead of the green check.

**Acceptance**
- [x] On a wrap date the card shows a playable action, not a finished state
- [x] Solving a repeat still advances the streak — asserted, since the whole fix
      rests on a mechanism that was never broken
- [x] Solved *today* is unchanged — verified on device with both states on one
      screen at once (daily solved today, mini a repeat)

**Testing it** — `-uiSeedRotationRepeat` marks today's daily and mini as solved
60 days ago, which is what the wrap does to the cohort. Same family as
`-uiForceReminderPrompt`: the state is otherwise two months of clock-moving away,
which made the card that decides a streak one of the hardest in the app to look
at.

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
