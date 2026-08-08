# Epic 04 — Pencil/check + larger grid / a11y

**Priority:** 4  
**Goal:** Audience expansion (seniors, casual solvers, classic crossword fans)  
**Status:** `[ ]`  
**Depends on:** `GameViewModel`, grid/clue views, Theme  
**Related:** Game UI under `Views/Game/`

## Why

Core loop is solid but limited modes. Pencil + check is classic crossword literacy; larger type/grid + a11y unlocks a major faith demographic without new content.

## Success metrics

- Retention / completion rate on hard puzzles
- Hint usage rate down when check/pencil available
- Accessibility audit pass (VoiceOver core path)
- Support tickets / reviews mentioning “too hard / too small” trend down

---

## Tickets

### P4-T1 — Check puzzle (no reveal)

**Status:** `[ ]`  
**Type:** eng  
**Estimate:** S

- [ ] Toolbar action: Check — marks incorrect filled cells (or shakes / red flash) without revealing answers
- [ ] Correct cells optionally confirm gently
- [ ] Does **not** count as hint; does **not** set `usedHint`
- [ ] Analytics: optional `check_used`

**Acceptance**
- Player can validate progress without spending hints
- Empty cells ignored

---

### P4-T2 — Pencil mode (notes)

**Status:** `[ ]`  
**Type:** eng  
**Estimate:** L

- [ ] Toggle pencil vs pen
- [ ] Pencil entries: lighter style, multi-candidate per cell **or** provisional letter (start with single provisional letter — simpler)
- [ ] Pen overwrites pencil; reveal/hint clears pencil marks as needed
- [ ] Persist pencil state in `PuzzleRecord` (or extend entries encoding) so resume works
- [ ] CloudKit: default-safe new fields

**Acceptance**
- Resume restores pencil marks
- Completing puzzle requires pen/correct letters only (pencil alone doesn’t complete)

**Note:** Full multi-candidate pencil is harder UI on phone — ship single provisional letter first if multi is too heavy.

---

### P4-T3 — Larger grid / comfort size

**Status:** `[ ]`  
**Type:** eng / design  
**Estimate:** M

- [ ] Setting: Comfortable / Standard grid (or Dynamic Type–driven cell min size)
- [ ] Clue bar + list scale with content size category
- [ ] Avoid horizontal letter clipping; scroll grid if needed on small phones + large type
- [ ] Persist preference (`AppStorage`)

**Acceptance**
- Extra Large accessibility text still playable end-to-end on daily mini and a sample daily

---

### P4-T4 — VoiceOver + accessibility pass

**Status:** `[ ]`  
**Type:** eng  
**Estimate:** M

- [ ] Grid cells: labels “Row r, Column c, empty/letter X, across clue…”
- [ ] Keyboard keys announced; hints have clear labels + hints
- [ ] Reduce Motion: respect for celebrations / Lottie
- [ ] Contrast: wrong-cell / selected / blocked meet WCAG-ish contrast on light + dark
- [ ] Focus order: clue bar ↔ grid ↔ keyboard sensible

**Acceptance**
- Can start daily, enter letters, use one hint, complete mini using VoiceOver only (manual QA checklist)

---

### P4-T5 — Zen mode (no timer pressure)

**Status:** `[ ]`  
**Type:** eng  
**Estimate:** S

- [ ] Setting or per-puzzle: hide timer UI (still record elapsed for challenges optionally)
- [ ] Or: “Practice” from archive never shows timer
- [ ] Don’t break challenge fairness — challenges still need honest seconds when accepted

**Acceptance**
- Timer can be hidden without breaking completion / streaks

---

## Out of scope

- Full desktop-class rebus / circles
- Colorblind-only mode as separate product (use shapes + color)
- Android a11y

## Open questions

- Pencil: multi-letter candidates vs single provisional?
- Check free forever or soft-gate frequency? (Recommend free — differentiates from hints.)
