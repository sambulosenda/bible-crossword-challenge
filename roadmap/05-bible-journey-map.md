# Epic 05 — Bible journey map

**Priority:** 5  
**Goal:** Long-term engagement  
**Status:** `[~]` — T1, T2, T4 shipped; T3 open; T5 blocked on Epic 03  
**Depends on:** Puzzle metadata (themes/books), completion records, optional clue refs  
**Related:** Achievements, packs, Profile stats

## Why

Achievements are discrete; a **journey** shows continuous progress across Scripture (“I’ve touched 12 books”). More sticky and shareable than badge lists alone.

## Success metrics

- Profile / map screen visits
- Return visits after pack completion
- Share rate of journey milestones

---

## Tickets

### P5-T1 — Book tagging model

**Status:** `[x]`  
**Type:** eng + content  
**Estimate:** M

- [x] Every puzzle anchors to one book, derived from its verse `reference`
- [x] `BibleJourney.booksTouched(completedPuzzleIDs:puzzles:)` → Set of books,
      plus `progress(…)` for the per-book rows
- [x] No content authoring needed — nothing manual to tag or keep in sync

**Clue refs were the wrong source.** The ticket preferred them, but only **69 of
2553 clues (2%)** carry a reference, where **198 of 198 puzzles** carry a verse
reference and all 198 resolve to a real BSB book. Anchoring on the verse costs
one book per puzzle instead of several, and buys 100% coverage with zero content
work. `BibleJourney.book(for:)` is the one place to widen if clue coverage grows.

**Acceptance**
- [x] Completing a puzzle contributes exactly 1 book
- [x] An unrecognised reference costs that puzzle its place and nothing else —
      no crash, no zeroed progress (tested)

**Content shape** — 32 of 66 books have puzzles; OT 21/39, NT 11/27. Eighteen
books have ≥3 puzzles; fourteen have only 1–2. Both numbers drive T2's design.

---

### P5-T2 — Journey map UI (v1)

**Status:** `[x]`  
**Type:** eng / design  
**Estimate:** L

- [x] Profile entry: “Your journey” → `JourneyView`
- [x] OT / NT sections, adaptive book grid, pure SwiftUI (no illustrated asset —
      it scales with Dynamic Type and needs no art pipeline)
- [x] Four states, not three — see below
- [x] Tap book → its puzzles, with difficulty, reference and solved state

**A fourth state: `empty`.** Thirty-four books have no puzzle written for them
and can't be reached however much anyone plays. Drawn as untouched, two thirds
of the map would read as the player's unfinished business rather than the
content backlog — the battle-pass tone this epic rules out. Empty books are
drawn as absent and aren't tappable, and the headline counts against the 32
books that *have* puzzles, not 66.

**“Deep” is now “explored everything available, or ≥3”.** A flat ≥3 was
unreachable in the fourteen books that ship 1–2 puzzles: solve all of Ruth and it
would still have read as less explored than Genesis at 3 of 20.

**Explored carries a ring, not just a stronger tint** — two opacities of one hue
is a distinction that survives neither an 11pt legend swatch nor greyscale nor a
colour-blind reader.

**Acceptance**
- [x] Map reflects real completions, recomputed when records change
- [x] Calm: paper canvas, accent washes, no progress bars or trophies
- [x] Not a paywall bypass — book detail answers to `PuzzleAccess`, and a locked
      puzzle opens the paywall (`source: "journey"`) rather than the grid

---

### P5-T3 — Journey milestones + share

**Status:** `[ ]`  
**Type:** eng  
**Estimate:** S

- [ ] Milestones: first book, 5 books, all Gospels, OT+NT both touched, etc.
- [ ] Reuse achievement system or parallel journey badges
- [ ] Share card: “I’ve explored 12 books of the Bible in Bible Crossword Challenge”

**Acceptance**
- Unlock celebration once; share produces image/text

---

### P5-T4 — Pack → journey linkage

**Status:** `[x]`  
**Type:** eng  
**Estimate:** S

- [x] Completing a pack fills its books — **already true from T1**, nothing built
- [x] Pack detail shows “Books in this collection”

**No pack → book mapping exists, deliberately.** Every puzzle already anchors to
a book through its verse reference, so a pack covers whatever its puzzles cover
and the two can't fall out of step. The ticket's own examples hold without any
authored data: David → 1 Samuel + Psalm, Parables → Luke + Matthew. A hand-kept
table would have been a second source of truth with nothing to gain.

Measured coverage per pack:

| Pack | Books |
|---|---|
| First Steps | Genesis, Isaiah, Matthew, Acts |
| The Life of David | 1 Samuel, Psalm |
| Parables of Jesus | Matthew, Luke |
| The Shepherd's Psalm | Psalm |
| Lent | Joel, Matthew, Luke, John |
| Easter | Matthew, Luke, John |
| Advent | Isaiah, Matthew, Luke |
| Christmas | Matthew, Luke, John |

**Acceptance**
- [x] Pack completion visibly advances the map
- [x] The card names what finishing would *add* ("Finishing this adds Isaiah and
      Acts to your journey"), skipping books already explored — which is the
      linkage the ticket was after, stated before the player commits
- [x] Shown on locked packs too: which books a collection covers is part of
      deciding whether to buy it

---

### P5-T5 — Chapters explored (if Epic 03 done)

**Status:** `[ ]`  
**Type:** eng  
**Estimate:** S  
**Depends on:** P3-T4

- [ ] Secondary metric under map: chapters opened in reader
- [ ] Distinguish *solved about* vs *read*

**Acceptance**
- Both metrics shown without confusing them

---

## Out of scope

- Forced reading plans with guilt streaks
- Full 1189-chapter checklist UI
- Gamified “unlock the Bible” paywalls on books

## Open questions

- ~~Canonical Protestant 66 only?~~ Settled by the bundled Bible: `bsb.json` is
  the 66-book canon, so `BibleCanon` matches it exactly (a test pins the two
  together). Deuterocanon would need the translation to carry it first.
- ~~Map art: pure SwiftUI vs illustrated asset?~~ Pure SwiftUI. Scales with
  Dynamic Type, themes with the app, and needs no art pipeline for 66 books.
- **Still open:** T3's milestones can't reuse `Achievement` — its goals read
  counters off `PlayerProfile`, and books-touched comes from records. A
  `booksExplored` field on the profile would mean a CloudKit Production schema
  re-deploy before release. Parallel journey badges computed from records avoid
  that; decide before starting T3.
