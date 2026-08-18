# 15 — Verse hint ("Show the verse")

**Goal:** turn a hint from a mechanical reveal into a moment of Bible study. A
third hint type opens the passage the answer comes from; the player finds the
word themselves. Scripture moves *into* the solving loop instead of waiting for
the completion screen.

**Why:** hints today (Reveal Letter / Reveal Word) feel like cheating. For this
audience, "go look it up in Scripture" is the hint they *wish* they were taking
— it converts hint spend from guilt into engagement, and gives clue references
(currently write-only decoration after solve) a live in-game job.

## Player experience

- Hint menu (`CrosswordGameView.swift:251`) gains a first-position row:
  **"Show the Verse"** (`book` SF symbol), above Reveal Letter.
- Tap → reader opens at the clue's referenced verse (existing flash/scroll-to-
  verse behavior in `ChapterReaderView`). The answer word is right there in the
  BSB text; the player reads, dismisses, types it in.
- Costs **1 hint** from the same daily quota (3/day free, unlimited Premium,
  `Persistence.hintsRemaining`). Quota exhausted → same `hint_limit` paywall.
- Row only appears when the **selected clue** has a `reference` — never shown
  disabled, never teased. (Coverage today: 267/3,072 clues, 8.7% — see
  Content dependency.)
- One charge per clue: re-opening the verse for a clue you already
  verse-hinted this session is free (don't bill twice for re-reading).

## Design decisions

- **Inverts the "reference is never a hint" rule** (`CrosswordModels.swift:80`)
  *deliberately and only here* — pre-solve reference display is exactly the
  product: it costs a hint credit, so it isn't a leak, it's a purchase. Clue
  list behavior (reference hidden until solved) is unchanged.
- **Sets `usedHint = true`** like other hints — the no-hint achievements keep
  meaning "unassisted." (Open question 1 below.)
- **Solve timer must not run while reading.** The clock only advances from
  visible-timer render ticks gated by `isAttachedToWindow`
  (`GameViewModel.swift:54`); a `fullScreenCover` may keep the underlying view
  attached. Explicitly `vm.pauseTimer()` on present, resume on dismiss — a
  verse hint must never make your time *worse*.
- **Presentation — local sheet, not `ReaderRouter`** (changed from first
  draft while building): the router's cover hangs off the tab bar and detaches
  the game view from its window, which fires `pauseTimer` *and the abandonment
  log* — a verse hint would pollute the 2.1 abandonment telemetry. The game
  presents `ReaderModal` as its own sheet (the clue-list pattern); a sheet
  keeps the grid attached and ticking, so a `GameViewModel.isTimerSuppressed`
  flag gates `tick(now:)` while the reader is up.

## Tickets

### T1 — Engine + UI (done 2026-08-18)
- [x] `HintType.verse` case; no grid mutation — reveal path untouched
      (asserted by `verseHintTouchesNoCells`)
- [x] `useVerseHint()` in `CrosswordGameView`: quota check → `rec.usedHint` →
      `markVerseHinted` → `consumeHint` (free tier) → local `ReaderModal`
      sheet; no-op (and no charge) if `Target(reference:)` resolves nil
- [x] Per-clue session memo (`hasVerseHinted`/`markVerseHinted`) — repeat
      opens free, verified on device ("Hints left: 2" stayed 2)
- [x] Menu row gated on `vm.activeSlot?.reference != nil`, absent not disabled
- [x] `isTimerSuppressed` gates `tick(now:)`; verified on device (17 s in the
      reader, clock advanced 0) and by `suppressedTimerAccruesNothing`

### T2 — Analytics (done 2026-08-18)
- [x] `hintUsed(type: "verse")` (existing event, new type value); verse hints
      also count into `puzzleAbandoned.hintsUsed` via `vm.hintsUsed`
- [x] `scriptureOpened(reference:, source: "hint")` — logged on every open,
      including free re-reads
- [ ] Funnel to watch post-ship: verse-hint share of all hints; hint→solve
      completion delta vs letter/word; `hint_limit` paywall rate change

### T3 — Content dependency (the real work)
- [ ] Referencing push, ordered by exposure: today's rotation window first,
      then minis, then packs — a hint type 91% of clues can't offer is a
      broken promise. Target: 100% of the next 60 rotation days referenced
- [ ] `tools/` QA check: for each referenced clue, does the answer word
      literally appear in the BSB verse text (normalized)? Report misses —
      a paraphrase reference makes a weak verse hint; fix or flag
- [ ] Generator: new specs require references on ≥90% of clues (warn, not fail,
      until backfill lands)

### T4 — Verification
- [x] Free user, 3 hints: verse hint decrements to 2 — on device (daily-001,
      1 Kings 17 opened, verse 6 highlighted, RAVEN typed from it)
- [ ] 0 hints → paywall — code path shared with reveal hints, not exercised
- [ ] Premium: no decrement, "Unlimited" label unchanged — not exercised
- [x] Referenced clue → row present; unreferenced gate is code-verified only
      (today's rotation puzzle has no refs — row absent by `reference != nil`)
- [ ] Verse hint → full solve → completion screen `usedHint` — not exercised
- [x] Timer frozen while reader open — 0:11 on the clock after ~32 s wall
- [x] Unresolvable reference → nothing opens, no charge (guard order:
      `Target(reference:)` resolves before any charge)

## Open questions

1. Should a verse hint set `usedHint` (blocks no-hint achievements)? Spec says
   yes for honesty; the growth argument says no (don't punish the behavior we
   want most). Could also add a separate "Berean" achievement — solved N
   puzzles using *only* verse hints ("they examined the Scriptures daily").
2. Price: 1 hint (spec'd) vs free-but-limited (e.g. 1 free verse hint/day even
   at 0 hints) as a paywall softener and habit hook?
3. Does the reader open at chapter with verse flashed (current behavior — more
   reading, answer needs finding) or should we add a single-verse card first
   (less friction, less Scripture)? Spec'd: current chapter behavior, no new UI.
