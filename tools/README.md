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

## Daily rotation
`PuzzleProvider.dailyPuzzle(for:)` shows `puzzles[(daysSinceEpoch) % count]`,
epoch = 2026-07-01. With 82 puzzles the daily puzzle is unique for ~82 days
before repeating.
