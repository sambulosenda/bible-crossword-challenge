# spec/ — the cross-platform contract

`spec/vectors/*.json` is the executable specification shared by the iOS app and
the Android port. There is no shared code between the platforms; there is shared
**data** instead.

## How it works

- **iOS generates.** `Bible Crossword ChallengeTests/SpecVectorsTests.swift`
  evaluates every rule across a corpus of inputs and writes the results here.
  On each run it regenerates, compares with the checked-in file, and **fails if
  anything changed** (after rewriting the file). The change lands in `git diff
  spec/vectors` and has to be committed on purpose.
- **Android verifies.** The Kotlin test suite reads the same files and asserts
  the port produces identical outputs. A rule that changes on iOS turns Android
  red until it follows.

Regenerate:

```bash
xcodebuild test -project "Bible Crossword Challenge.xcodeproj" \
  -scheme "Bible Crossword Challenge" \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:'Bible Crossword ChallengeTests/SpecVectorsTests'
```

## File shape

```json
{
  "family": "hint_quota",
  "description": "…",
  "source": ["Models/Persistence.swift — …"],
  "constants": { … },            // constants.json only
  "cases": [
    { "name": "…", "given": { … }, "expect": { … } }
  ]
}
```

`source` names the Swift the family was derived from, so a surprising case can
be traced to the rule that produced it.

## Determinism rules

Every case must reproduce on either platform, in any time zone, on any day.

- **No absolute dates in outputs.** Time is a day offset from an unemitted fixed
  "now" (`…DaysAgo`, `…HoursAgo`), evaluated on a **UTC** calendar. `null` means
  "never". The Kotlin side reconstructs real instants from its own fixed now.
- Inputs that are genuinely calendar dates (`rotation`, `puzzle_access`) are
  ISO day strings evaluated at noon on the **local** calendar, not UTC —
  `PuzzleProvider`'s epoch is local midnight on 2026-07-01, so date and epoch
  must share a zone for day 0 to be July 1. Because both sides use the same
  zone the outputs are zone-independent; on Android use `LocalDate` (no zone)
  and the same epoch.
- `-1` for a hint count means unlimited (Swift `Int.max`).
- No randomness, no bundle-specific paths, no `Date()`.

## Families

| File | Pins |
|---|---|
| `constants.json` | Every magic number: hint limits and costs, freeze cap, stall-nudge thresholds, ask floors, review milestones, rotation epoch and pool sizes, feature-flag defaults, challenge-link scheme/host, the achievement catalogue |
| `hint_quota.json` | `hintsRemaining` at both pool sizes × learning window × premium × day rollover; `consumeHint` transitions |
| `streaks.json` | `Streaks.normalize` (freeze bridging, break reporting) and `registerCompletion` (advance, replay, 7-day freeze milestones) |
| `achievements.json` | `newlyUnlocked` plus per-achievement `progress` / `progressText` for profile shapes |
| `rotation.json` | `dayIndex`, `weekIndex`, which daily/mini/sunday a date serves, and the rolling windows |
| `puzzle_access.json` | `canPlay` / `isInWindow` truth table over puzzle kind × premium × progress × challenged |
| `reminder_ask.json` | `ReminderAsk.decide` per surface |
| `review_ask.json` | `ReviewAsk.decide` trigger selection and both time floors |
| `trial_reoffer.json` | `TrialReoffer.decide` same-sitting vs later-sitting |
| `sync_merge.json` | `SyncMerge` profile and record merging — most generous value survives |
| `challenge_links.json` | `ChallengeService.parse` outcomes and the outgoing URL builders |
| `engine_traces.json` | `GameViewModel` driven by input scripts against bundled puzzles; state after every step |
| `engine_timer.json` | `tick(now:)` — the 1.5 s cap, fraction carry, detached/suppressed gating |

## Engine trace ops

`engine_traces.json` scripts use these inputs, mapped one-to-one onto
`GameViewModel` methods:

| op | args | Swift |
|---|---|---|
| `tap` | `row`, `col` | `tapCell(GridPos)` |
| `enter` | `letter` | `enter(Character)` |
| `delete` | | `delete()` |
| `toggleDirection` | | `toggleDirection()` |
| `pencilMode` | `on` | `isPencilMode = on` |
| `selectSlot` | `id` (`"3-across"`) | `select(slot:)` |
| `advanceClue` | `by` | `advanceClue(by:)` |
| `revealLetter` / `revealWord` / `revealPuzzle` | | returns `result: Bool` |
| `check` | `scope` | `check(_:)` → `result: Int?` (wrong count, `null` = nothing judged) |
| `giftStarterWord` | | `giftStarterWord()` → `result: slot id or null` |
| `restore` | `entries`, `pencil` | `restore(_:pencil:)` |
| `moveSelection` | `rowDelta`, `colDelta` | `moveSelection(rowDelta:colDelta:)` |

Entries encoding is the persisted one: `{"row,col": "A"}`, **lowercase letter =
hint-locked cell**. It is the same encoding Room stores on Android, and it must
stay byte-identical across platforms.

## Adding a family

Add a `@Test` to `SpecVectorsTests.swift` that builds a `VectorFile` and calls
`emit`. Keep inputs as plain values, keep dates relative, and name each case so
a failing assertion on the other platform reads as a sentence.
