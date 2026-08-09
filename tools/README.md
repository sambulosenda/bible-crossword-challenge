# Puzzle content tooling

These scripts live **outside** the Xcode target — they author the bundled
`Bible Crossword Challenge/Resources/puzzles.json`. They are not compiled into
the app.

## Files
- `puzzle_specs.json` — the source content: an array of
  `{ title, theme, difficulty, verse, reference, words: [{answer, clue}] }`.
  Verses are King James Version (public domain). Each puzzle lists ~16–20
  candidate words; the generator only uses the ones that interlock.
- `generate_puzzles.py` — deterministically builds valid crossword grids from
  the specs and writes the app's `puzzles.json`.
- `validate_content.py` — checks what actually shipped: every clue's answer
  matches the letters in its solution grid, pack membership resolves, seasonal
  windows parse, pack-exclusive puzzles stay out of the daily pool, every
  shipped id is written back into its spec. Run it before every content commit.
  (The app's own tests build a synthetic puzzle, so this is the only thing that
  reads the bundled grids.)

## Regenerate the bundled puzzles
```bash
python3 tools/generate_puzzles.py tools/puzzle_specs.json \
  "Bible Crossword Challenge/Resources/puzzles.json"
```
The generator:
- places words so they only touch at real crossings (no accidental words),
- pads/centers each grid to a PRD size (10/12/15),
- assigns sequential `id` (`daily-001`…) and `publishDate` (from 2026-07-01),
- prints a summary and any puzzles it had to drop.

Then check the result:
```bash
python3 tools/validate_content.py
```
It reads `puzzles.json`, `packs.json` and `puzzle_specs.json` and exits non-zero
on anything the app would swallow silently. Warnings (answer overlap inside a
pack) are advisory.

## Add more puzzles
Append new objects to `puzzle_specs.json` (give each ~16–20 distinct A–Z
answers, 3–9 letters, rich in common letters so they interlock), then rerun the
command above. Validate consistency afterwards if you like — every answer's
letters must match the solution grid and no maximal run may be an unintended
word (the generator already enforces this).

**Do NOT set an `id` on new specs — leave it off.** The generator assigns the
next free `daily-NNN` automatically, above the current maximum.

## Puzzle IDs are permanent (do not edit)
Each existing spec carries an explicit `"id"` (`daily-NNN`). That id is the
ONLY link between a puzzle and a player's saved progress
(`PuzzleRecord.puzzleID`). The generator uses a spec's `id` verbatim and only
auto-assigns ids to specs that lack one, so adding new puzzles never renumbers
existing ones.

Never change or remove an existing spec's `id`, and never reuse a retired id —
doing so silently reassigns players' completions to the wrong puzzles.
`publishDate` is cosmetic and may shift.

## Rotation order is NOT cosmetic

This file used to say it was. It is the second thing, after ids, that must not
move.

The app serves the daily by **position**, not by id:

```swift
index = daysSinceEpoch % pool.count   // PuzzleProvider.rotated
```

`pool` is the array in `puzzles.json`, in file order. Reorder it and every
existing player is served a different puzzle on every future day, with the
rotation no longer lining up with what they have already solved. No id changed,
no test failed, nothing looked wrong in review — the whole pool just quietly
shifted under everyone.

The generator used to sort every spec by (difficulty, title), which is stable
only while the bank never grows: the first new easy puzzle with an early title
sorted to index 0 and pushed all 82 dailies down one. It now orders by the
previous `puzzles.json` — whatever already shipped keeps its position, new specs
append after it.

So the step-2 check is a real safety gate, not a formality:

```bash
git diff --numstat "Bible Crossword Challenge/Resources/puzzles.json"
```

**Deletions must be zero.** Anything else means a shipped puzzle moved. Stop.

Two consequences worth knowing:
- **Don't delete `puzzles.json` and regenerate from scratch.** It is the record
  of the order players are living in; without it the generator has nothing to
  preserve and will fall back to sorting.
- `RotationWrapTests` asserts both pool sizes and both wrap dates, so adding
  content fails the suite until the new dates are recorded in
  `roadmap/README.md`. That failure is the feature.

## Daily rotation
`PuzzleProvider.dailyPuzzle(for:)` shows `puzzles[(daysSinceEpoch) % count]`,
epoch = 2026-07-01. With 82 puzzles the daily puzzle is unique for ~82 days
before repeating.

## Ship a pack

The whole checklist, in order. Nothing here needs knowledge that isn't in this
file — that's the point. The calendar of what to ship and when is
`docs/seasonal-pack-calendar.md`; how packs work is `docs/themed-packs-spec.md`.

1. **Author the specs.** Append one object per puzzle to `puzzle_specs.json`,
   each with `"pack": "<slug>"` and **no** `"id"`. Same shape as a daily
   otherwise: ~16–20 answers, 3–9 letters, rich in common letters. Keep the
   slug identical across every puzzle in the pack — it becomes the id prefix.
2. **Generate.**
   ```bash
   python3 tools/generate_puzzles.py tools/puzzle_specs.json \
     "Bible Crossword Challenge/Resources/puzzles.json"
   ```
   Dailies and minis are built first with unchanged parameters, so `git diff`
   on `puzzles.json` must show **only added lines**. Anything else means an
   existing puzzle moved — stop and find out why before committing.
3. **Write the ids back.** The generator assigned `pack-<slug>-001`… Copy each
   into its spec's `"id"` field. This is not optional: a spec without an id is
   renumbered the next time the bank is reordered, and the id is the only link
   to a player's saved progress.
4. **Add the pack to `Resources/packs.json`:**
   ```json
   {
     "id": "easter",
     "title": "Easter",
     "blurb": "One line. What the collection is, not why it's good.",
     "coverSymbol": "sunrise",
     "accentHex": "#C8912B",
     "isPremium": true,
     "puzzleIDs": ["pack-easter-001", "pack-easter-002"],
     "season": { "kind": "easter", "from": -7, "to": 7 }
   }
   ```
   `puzzleIDs` is the membership *and* the play order. `season` is `null` for an
   evergreen collection; see the season shapes below.
5. **Validate.** `python3 tools/validate_content.py` — must print `OK`.
6. **Test.** `xcodebuild test -scheme "Bible Crossword Challenge" \
   -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`. `PacksTests`
   covers pack resolution, pool isolation and every season shape against the
   bundled files, so a bad pack fails there rather than on a device.
7. **Look at it.** Run the app, open the Packs tab, confirm the pack renders
   with its cover, blurb and progress bar. A seasonal pack out of window is
   *hidden by design* — to see it, move the simulator's date into the window.
8. **Update the calendar.** Tick the row in `docs/seasonal-pack-calendar.md`.

### Season shapes

`season` on a pack is one of three rules (`PackSeason` in
`Models/PuzzlePack.swift`). Two of them recur for ever; only the first expires.

| Shape | JSON | Use for |
|---|---|---|
| One-off | `{"kind":"dates","from":"2026-07-01","to":"2026-07-07"}` | A launch event. Expires permanently. |
| Every year | `{"kind":"annual","from":"12-01","to":"12-26"}` | A fixed feast. May wrap the new year (`"12-26"` → `"01-06"`). |
| Relative to Easter | `{"kind":"easter","from":-46,"to":-1}` | Anything that moves with Easter: Lent `-46…-1`, Holy Week `-7…0`, Eastertide `0…7`. |

**Never use `dates` for a recurring season.** It will work for one year and then
the pack disappears for good, with nothing in the app to say so.

Out-of-window seasonal packs are hidden everywhere — Home, Collections, search.
That is the intended behaviour, not a bug to report.

## Minis
Specs with `"kind": "mini"` build the Daily Mini pool: 7x7 grids, words 3-7
letters, 5+ placed. Ids are `mini-NNN` (same permanence rule as dailies — never
edit or reuse) with their own publishDate sequence.

Mini specs carry explicit `id`s for the same reason dailies do. They did not
until the bank grew past the original 30: ids were auto-assigned in
(difficulty, title) order, so inserting a mini whose title sorted early
renumbered every mini after it and silently reassigned players' saved progress.
New mini specs still go in **without** an `id` — the generator assigns the next
free one — but an id, once shipped, must be written back into its spec. Dailies are processed first
with unchanged parameters, so adding minis never changes the daily output —
verify with `git diff` showing only added lines in puzzles.json.
