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
doing so silently reassigns players' completions to the wrong puzzles. (Daily
rotation order and `publishDate` are cosmetic and may shift; ids must not.)

## Daily rotation
`PuzzleProvider.dailyPuzzle(for:)` shows `puzzles[(daysSinceEpoch) % count]`,
epoch = 2026-07-01. With 82 puzzles the daily puzzle is unique for ~82 days
before repeating.

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
