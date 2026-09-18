# Share result block — spec

Status: implemented, 2026-09-18
Related: [friend-challenge-spec.md](friend-challenge-spec.md)

## Problem

The share artifact carries no information about the solve, so there is nothing
to send.

`ShareGrid.emoji(for:)` (`Theme/Formatting.swift:35`) renders `puzzle.grid` —
the *authored silhouette*. Every player who solves a given puzzle produces a
byte-identical grid. It does not encode time, hints, order, struggle, or
anything else that differs between two people. Wordle's grid is shareable
because it is a fingerprint of *your* game; this one is clip art.

Measured over the 21 days to 2026-09-18, across ~280 active users and ~730
completed puzzles:

| Event | Count | Users |
|---|---|---|
| `challenge_sent` | 3 | 3 |
| `share_opened` | 3 | 3 |
| `challenge_share_cancelled` | 6 | 5 |
| `challenge_completed` | 2 | 1 |

Twice as many people open the share sheet and back out as go through with it.
The Sep 7 scheme-guard fix (`c76e37c`) worked — the plumbing is fine. People
reach the sheet, look at what they are about to post, and cancel.

### What ships today, per kind

Simulated against `Resources/puzzles.json` with the current algorithm
(`targetSize = 8`, filled if *any* source cell in the block holds a letter):

```
daily-001   15×15 → 8×8, 42% black      mini-031    7×7 → 1:1, 55% black
  ..X.....                                ...XXXX
  .XXX.XXX                                ...X...
  XXXXXXXX                                X..X.X.
  X.XXXXX.                                XXXXXXX
  XXXXX...                                X..X.X.
  XXX.XX..                                X....X.
  XXX..XXX                                X....X.
  ........

sunday-001  21×21 → 7×7, 2% black
  XXXXXX.
  XXXXXXX     ← a solid green rectangle
  XXXXXXX
  XXXXXXX
  XXXXXXX
  XXXXXXX
  XXXXXXX
```

The Sunday Special shares as a 7×7 block of solid green. The Daily is mush.
Only the Mini, which escapes downsampling at `scale = 1`, reads as a crossword
— and that is the one new players solve on day 0.

The empty top and bottom rows in `daily-001` are authored padding, not a
rendering bug: 39 of 138 dailies have an all-block last row. They still waste
two of eight rows of a scarce artifact.

## Design

Four parts, in this order:

```
Bible Crossword · Mini · The Writing on the Wall

⬛⬛⬛🟦🟦🟦🟦
⬛⬛⬛🟦⬛⬛⬛
🟦⬛⬛🟨⬛🟦⬛
🟦🟦🟨🟨🟨🟦🟦
🟦⬛⬛🟦⬛🟦⬛
🟦⬛⬛⬛⬛🟦⬛
⬜⬜⬜⬜⬛🟦⬛

2:14 · no hints · 🔥 12

https://biblecrossword.app/go?s=share_card
```

1. **Header** — app, kind, puzzle title. The title is the hook and is
   spoiler-free (it is already shown on the Today card before you play).
2. **Grid** — the silhouette, coloured by how each cell was filled.
3. **Stat line** — time, hint usage, streak.
4. **Link** — existing `ShareConfig.storeURL(kind:)`.

### Cell provenance

Derived from the final grid state at completion:

| Provenance | Emoji | Condition |
|---|---|---|
| Solved by the player | 🟦 | `entry != nil && !isRevealed` |
| Hint-revealed | 🟨 | `isRevealed` via `revealLetter` / `revealWord` / `revealPuzzle` |
| Starter gift | ⬜ | `isRevealed` and part of the gifted slot |
| Block | ⬛ | `isBlock` |

🟦 rather than 🟩 keeps the artifact on the system-blue accent the app uses.

**The gift/hint distinction is the one piece of real work in this spec.**
`giftStarterWord()` sets `isRevealed = true` on every gifted cell
(`GameViewModel.swift:731`) but deliberately does *not* bump `hintsUsed`
(`GameViewModel.swift:677`). So `isRevealed` alone conflates a hint the player
asked for with a gift the app forced on them. Rendering both as 🟨 would paint
every learning-window player's first share with help they never requested —
exactly the players whose shares matter most.

Fix: carry the gift explicitly. Either add `isGift: Bool = false` to
`CellState` and set it alongside `isRevealed` in `placeNextStarterLetter()`, or
keep a `giftedPositions: Set<GridPos>` on the view model. The former survives
the snapshot round-trip more cleanly — note that persistence currently encodes
`isRevealed` as letter case (`GameViewModel.swift:1081`, `:1125`), so a third
state needs its own key rather than another case trick.

### Downsampling

Keep `targetSize = 8`. When a coarse cell covers a mix, **worst case wins**:

```
hint 🟨  >  gift ⬜  >  clean 🟦  >  block ⬛
```

Never overstate the solve. This only bites the Daily (scale 2, 4 source cells
per coarse cell) and the Sunday (scale 3, 9 cells). The Mini renders 1:1 and is
exact.

### Trim before rendering

Drop all-block rows and columns from the outside in, *then* downsample. This
recovers the two wasted rows on ~28% of dailies and tightens every grid. It
changes the Sunday not at all — that one needs the provenance colouring to
become legible, which is the point.

## Placement

The pinned bar already carries Challenge (primary), Share (icon), and "…"
(`CompletionView.swift:1207`). No new control. Change what the existing Share
path *produces*:

- `shareCaption` (`CompletionView.swift:126`) currently emits title + time +
  streak + `ShareGrid.emoji` + URL. Replace the grid call and the stat line;
  keep the shape of the function.
- `presentCard()` (`:1332`) appends `shareUIImage` then `shareCaption`. **Drop
  the image from the items array for this path.** An image plus text makes
  iMessage render a photo attachment and bury the text; the copyable block is
  the entire mechanic. Keep `renderShareCard()` for the "…" menu if you still
  want an image option.

`CompletionView` does not currently receive per-cell data — it takes `puzzle`,
`seconds`, `streak`, and counters (`:11-24`). The provenance grid has to be
computed in `CrosswordGameView` where `vm` is in scope and passed in, or the
rendered string passed in whole. Prefer passing the string: the completion
screen has no other use for the grid, and `CrosswordGameView.swift:270` already
threads eight parameters.

## Analytics

Existing `share_opened` carries a `kind` property — reuse it with
`kind: "result_block"`. Add to the event:

| Property | Why |
|---|---|
| `puzzle_id` | matches every other share event |
| `puzzle_kind` | mini / daily / sunday — which shape actually gets sent |
| `hints_used` | does a clean solve share more than a hinted one |
| `seconds` | correlate with send rate |
| `grid_cells` | post-trim coarse size, to confirm trimming helps |

The send/cancel split already exists via `ShareSheet.onComplete`
(`Views/Components/ShareSheet.swift`) — wire the result-block path into the
same `completed` callback so cancels stay measurable. **Cancel rate is the
metric**, not send count: today it is 6 cancels to 3 sends, and the whole
premise is that a better artifact inverts that.

Install attribution rides the existing `/go?s=` token (`s=share_card`), read in
ASC Acquisition → Campaigns.

## Readout

Ship it and read at 14 days:

- **Primary:** cancel rate on the share sheet — target under 30%, from ~67%.
- **Secondary:** shares per completion — currently 0.004 (3 sends / ~730
  completions). Anything above 0.05 is a working loop.
- **The one that matters:** `s=share_card` installs in ASC. At ~12 installs/day
  flat since Aug 28, even 2–3/day is a 20% lift.

If cancel rate does not move, the artifact is still not worth sending and the
next lever is not a better grid — it is the fact that only 12 people a day
arrive at all.

## Out of scope

- **A new share button.** The bar has two share affordances already; a third
  competes with Challenge, which is the higher-value action when it works.
- **Images.** See placement above — an image defeats paste-anywhere.
- **Spoiler risk.** Answers never appear; the grid is shape plus provenance.
  The title is already public on the Today card.
- **Web parity.** The link lands on the existing `/go` redirect. A rendered web
  version of a shared result is a separate, larger piece of work.

## As built

Deviations from the spec above, decided during implementation:

- **The gift flag rides inside `entriesData`, not a new field.** `CellState`
  gained `isGift`, and `snapshot()` appends `GameViewModel.giftMarker` (`~`) to
  a gifted cell's lowercase value. A new `PuzzleRecord` property would have
  meant a CloudKit schema deploy, and a missing `CD_` column is precisely what
  broke fleet sync on 2026-08-29 (`CD_pencilData`). `restore` reads the lock
  from `value.first` and the letter from `value.uppercased().first`, so the
  suffix is invisible to both, and `hasPlayerEntries` still sees no uppercase.
- **The campaign token stays `share_card`.** The spec floated `result_block`;
  keeping the old token preserves the ASC Campaigns series the readout compares
  against. The distinguishing detail moved into a new `resultShareOpened` case
  that logs as `share_opened` with `puzzle_kind`, `hints_used`, `seconds` and
  `grid_cells` alongside.
- **`ShareGrid.result` takes the grid, not the puzzle.** `CellState` already
  carries `isBlock`, so the puzzle argument was redundant.
- **`ShareCardView` is now unused.** `renderShareCard()` and its `onAppear` call
  are gone, which also removes a synchronous `ImageRenderer` pass from every
  completion. The view file is left in place rather than deleted, in case the
  image path is wanted back for the "…" menu.

Known gaps:

- **In-flight saves lose the distinction once.** A puzzle saved before this
  ships restores its gifted cells as plain reveals, so a solve finished across
  the update renders the starter word as a hint. One-time, self-correcting.
- **The Sunday Special is still dense.** Trimming and colour help, but a 21x21
  at scale 3 is mostly filled. Better than the old solid rectangle; not yet a
  shape worth sending.
