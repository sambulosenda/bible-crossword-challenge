# Per-clue scripture references

Show a player where a clue's answer comes from, **after they solve it**.

Status: built 2026-08-04, first batch only. Written the same day; the
"Sequencing" advice below to wait for a conversion baseline was overridden — see
"What was built".

## Why

The scripture reader is the devotional payload and almost nobody reaches it.
Measured over 30 days: `scripture_opened` fires 27 times from the Verse of the
Day (19 people) and **4 times from the post-solve verse (3 people)**. All
scripture engagement sits in one passive surface at the top of Today; none of it
comes from actually playing.

There are 2,149 clues. Each one is a fact drawn from a passage, and right now
the app never says which. Naming the passage after the solve is the strongest
available answer to "why is this devotional rather than Bible trivia" — the
claim the App Store listing and marketing site already rest on.

## Why not as a hint

Rejected deliberately.

- **It would undercut the best-converting paywall trigger.** "No hint limits" is
  one of three premium benefits and `hint_limit` is the highest-intent source —
  17 people hit it, and the only purchase recorded under the current event
  vocabulary came from there. A free reference is a free hint.
- **It collapses difficulty.** "Saul's father who owned the lost donkeys" plus
  *1 Samuel 9:1* is the answer, or one tap from it.

Post-solve, the same content is a reward instead of a giveaway: it costs nothing
monetarily and strengthens the promise rather than competing with it.

## Model

`ClueData` gains one optional field:

```swift
struct ClueData: Codable, Hashable {
    let number: Int
    let direction: ClueDirection
    let row: Int
    let col: Int
    let text: String
    let answer: String
    /// Where this clue's answer comes from, e.g. "1 Samuel 9:1". Optional
    /// because references land pack by pack — a puzzle without them decodes and
    /// plays exactly as before.
    let reference: String?
}
```

**No migration of any kind.** `ClueData` is a plain `Codable` struct decoded from
bundled JSON, not a SwiftData `@Model` — so there is no store migration and no
CloudKit schema re-deploy, which is the usual release risk here. Swift's
synthesised decoder uses `decodeIfPresent` for optionals, so every existing
puzzle in `puzzles.json` decodes unchanged with `reference == nil`.

## Authoring

References are authored in `tools/puzzle_specs.json`, alongside the clue text,
and carried through by `generate_puzzles.py`:

```json
{
  "answer": "LIGHT",
  "clue": "What God made on the first day, dividing it from darkness",
  "reference": "Genesis 1:3"
}
```

Validation worth adding to the generator:

- The reference must parse with the existing `ScriptureReference` parser
  (`Models/ScriptureModels.swift`) — a citation the reader can't open is worse
  than none.
- It should fall inside the puzzle's own `theme` range where one is given
  ("The Creation (Genesis 1-2)"). A clue citing Revelation in a Genesis puzzle
  is almost certainly wrong, and this catches it cheaply.
- Absent is valid. Never emit a guessed reference to fill the field.

After regenerating, **the `puzzles.json` diff must contain only added
`reference` keys**. Any id churn means the generator renumbered something, which
breaks saved progress — see the puzzle-ids-content-stable rule.

## UI

### Clue list (`Clues` sheet) — the main surface

A solved row gains one line beneath the clue text. An unsolved row shows
nothing.

```
┌────────────────────────────────────────────┐
│  2   Prophet who anointed Israel's      ✓  │
│      first monarch                         │
│      1 Samuel 10:1  ›                      │  ← new, solved rows only
├────────────────────────────────────────────┤
│  3   Saul's father who owned the           │
│      lost donkeys                          │  ← unsolved: nothing
└────────────────────────────────────────────┘
```

- Accent-coloured, `.caption`, tappable — opens the reader via
  `readerRouter.open(reference:)`, same as the Verse of the Day.
- **Absent, not greyed, when unsolved.** A dimmed placeholder still tells you the
  answer lives in 1 Samuel, which is a hint by the back door.
- Rows without a reference at all look exactly as they do today, so a partially
  referenced library is not visibly broken.

### Deliberately not

- **The clue bar above the keyboard.** That is the solving surface; anything
  there is a hint.
- **The grid.** Same reason.

### Optional second surface

The completion screen already shows the puzzle's closing verse. A collapsed
"where these came from" list of the solved clues' references would fit there and
costs no new content — worth considering only after the clue list proves people
tap these at all.

## Analytics

No new event. `scriptureOpened(reference:source:)` already exists; add a source:

```swift
analytics.log(.scriptureOpened(reference: reference, source: "clue"))
```

`source` already separates `verse_of_the_day` from `puzzle_completion`, so the
new value slots into the same breakdown with no dashboard work. The question it
answers: does per-clue referencing move scripture engagement out of the passive
top-of-Today surface and into gameplay?

## Sequencing

**Do not start until the current build has shipped and roughly two weeks of
conversion data has landed.** Six commits are already unshipped and the purchase
baseline does not exist yet; adding a content system on top means nothing can be
attributed again.

Then scope it to **one pack first** — 4–5 puzzles, ~100 clues. Ship, and watch
`scripture_opened` with `source = clue`:

- Near-zero tap rate → stop. 2,000 references not written.
- Healthy → the rest of the library has earned the investment.

Writing all 2,149 up front to find out is the mistake to avoid. In a Bible app a
wrong citation is a credibility problem, not a typo, so every one needs
verifying — which is exactly why the sample should come first.

## What was built

Three things came out differently from the sketch above.

**The first batch is First Steps, not a `pack:` pack.** The only puzzles with
their own pack specs are `psalm-23`, and that pack is `isPremium: true`. Putting
the entire pilot behind the paywall would have made the one thing it exists to
measure — tap rate — unmeasurable, and its citations would nearly all have read
"Psalm 23:x", which the completion screen already shows. First Steps is the free
onboarding pack every new player meets: 5 puzzles, 68 referenced clues, drawn
from Genesis, Acts, the Gospels and the Epistles, so a reference actually tells
you something you didn't know.

**The clue list presents the reader itself.** `readerRouter.open(reference:)`
does not work from inside a sheet: the router's cover hangs off the tab bar, and
UIKit silently drops the request while the clue sheet is on top — the tap
appeared to do nothing. `ClueListView` now owns a `ReaderModal` of its own
(extracted from `RootView`). Closing it returns to the clue list rather than the
grid, which is the better loop anyway.

**Every citation is validated twice.** `generate_puzzles.py` refuses to build if
a reference doesn't resolve against the bundled `bsb.json` — right book
spelling, chapter and verse that exist — and warns when one falls outside a
spec's own `theme`. `ClueReferenceTests` re-checks the shipped `puzzles.json`,
since that file can be hand-edited after generation.

Sequencing was overridden deliberately: this ships alongside the unshipped
commits rather than after them. The measurement question is unchanged — watch
`scripture_opened` with `source = clue` before writing the other ~2,000.
