# Epic 05 — Bible journey map

**Priority:** 5  
**Goal:** Long-term engagement  
**Status:** `[ ]`  
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

**Status:** `[ ]`  
**Type:** eng + content  
**Estimate:** M

- [ ] Derive or author primary `books: [String]` (or testament + book) per puzzle
- [ ] Prefer data-driven from clue refs / pack themes where possible; fallback manual tags on packs + puzzle titles
- [ ] Provider API: `booksTouched(from records:)` → Set of books

**Acceptance**
- Completing a known puzzle contributes ≥1 book when taggable
- Untagged puzzles don’t crash progress

---

### P5-T2 — Journey map UI (v1)

**Status:** `[ ]`  
**Type:** eng / design  
**Estimate:** L

- [ ] New Profile entry or tab section: “Your journey”
- [ ] Visual: OT / NT sections or simple book grid (not a full illustrated Bible map required for v1)
- [ ] States: untouched / touched / “deep” (e.g. ≥3 puzzles in that book)
- [ ] Tap book → list related completed / available puzzles or packs

**Acceptance**
- Map reflects real completions after relaunch
- Looks calm; matches Theme (paper, not gamer battle-pass)

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

**Status:** `[ ]`  
**Type:** eng  
**Estimate:** S

- [ ] Completing a pack fills obvious books (David → Samuel/Psalms, Parables → Gospels)
- [ ] Pack detail shows “Books in this collection”

**Acceptance**
- Pack completion visibly advances map

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

- Canonical Protestant 66 only, or note Catholic deuterocanon later?
- Map art: pure SwiftUI shapes vs illustrated asset?
