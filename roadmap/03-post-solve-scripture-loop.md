# Epic 03 — Deeper post-solve scripture loop

**Priority:** 3  
**Goal:** Positioning (devotional, not trivia)  
**Status:** `[ ]`  
**Depends on:** Scripture reader, clue references (partial), Completion verse  
**Related:** `docs/clue-references-spec.md`

## Why

Measured: almost all `scripture_opened` from Verse of the Day, almost none from play. Post-solve refs fix “where did this clue come from?” without giving free hints. Next step: make solving *lead into* reading as a habit.

## Success metrics

- `scripture_opened` from post-solve / clue-ref sources (not only VOTD)
- % of completions that open at least one reference
- Optional: chapters touched / month (if instrumented)

---

## Tickets

### P3-T1 — Finish clue-reference coverage

**Status:** `[ ]`  
**Type:** content + eng  
**Estimate:** L (content-heavy)

- [ ] Audit how many of ~2k clues have `reference` populated
- [ ] Batch author refs for remaining high-traffic puzzles (daily rotation first)
- [ ] Keep rule: **never** show ref as a hint — only after word/puzzle solved
- [ ] Tests already exist (`ClueReferenceTests`) — extend coverage as needed

**Acceptance**
- Top N daily puzzles fully referenced; generator/docs explain how to add refs

---

### P3-T2 — In-game post-word scripture chip

**Status:** `[ ]`  
**Type:** eng  
**Estimate:** M

- [ ] When a word completes correctly and has a ref → subtle chip / toast “1 Sam 9:1 — Read”
- [ ] Tap opens `ReaderRouter` / chapter reader at that passage
- [ ] Dismissible; don’t interrupt rapid solve flow (delay slightly or only on pause)
- [ ] Analytics: `scripture_opened(reference, source: "clue_solved")`

**Acceptance**
- Correct word with ref can open reader without finishing whole puzzle
- Wrong / incomplete words never reveal ref

---

### P3-T3 — Completion “Why this verse” card

**Status:** `[ ]`  
**Type:** content + eng  
**Estimate:** M

- [ ] Completion already shows a verse — add optional 1–2 sentence devotion blurb per puzzle (bundled field or pack-level)
- [ ] CTA: Read full chapter
- [ ] Secondary: Challenge friend (don’t bury growth)

**Acceptance**
- At least all dedicated pack puzzles + recent dailies have blurbs OR graceful fallback to verse only

---

### P3-T4 — “Chapters touched” light progress

**Status:** `[ ]`  
**Type:** eng  
**Estimate:** M

- [ ] On scripture open / puzzle complete with refs, record unique book+chapter ids (local profile field or derived)
- [ ] Profile stat: “12 chapters explored”
- [ ] No full Bible reading plan required

**Acceptance**
- Stat updates when user opens reader from puzzle context
- CloudKit-safe defaults if stored on `PlayerProfile`

---

### P3-T5 — Evening reflect (optional)

**Status:** `[ ]`  
**Type:** eng  
**Estimate:** S  
**Depends on:** P3-T1 or completion verse

- [ ] If daily solved + reminder enabled, optional evening notification: “Revisit today’s verse”
- [ ] Deep link to completion verse / reader, not a new game mode

**Acceptance**
- Opt-in only; respects existing notification prefs

---

## Out of scope

- Free pre-solve scripture as hint (kills paywall + difficulty)
- Full in-app curriculum / courses
- Multiple Bible translations (separate epic later)

## Open questions

- Blurbs editorial voice: pastoral vs scholarly?
- Show ref after *word* solve or only full puzzle for denser grids?
