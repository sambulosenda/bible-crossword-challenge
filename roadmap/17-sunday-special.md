# 17 — Sunday Special (weekly 21×21)

**Priority:** high (calendar peak + Premium headline at one puzzle/week content cost)
**Status:** `[ ]` planned
**Type:** eng (zoomable grid) + content cadence
**Estimate:** M–L (T1 is the bulk; everything else is S)
**Related:** `14-premium-content-value.md` (visible cadence of exclusives),
`01-seasonal-packs-content-cadence.md`, `13-daily-rotation-wrap.md` (wrap-date
bookkeeping), `16-notification-opt-in.md` (Sunday morning is the natural push)

## Goal

One bigger themed grid (**21×21**) every Sunday. Gives the week a peak, gives
Premium a headline ("the Sunday Special archive"), costs one puzzle/week of
content.

## Decisions (settled)

- **True 21×21, zoomable.** Not "XL at 15". iPhone gets pinch-zoom + pan;
  iPad renders full-bleed (21 cols ≈ comfortable at iPad widths).
- **Current week free, archive Premium.** Same soft-gate philosophy as
  `PuzzleAccess` — the free tier always has *this* Sunday; the back catalog is
  the Premium claim. Rule 2 (started stays yours) applies unchanged via
  `PuzzleRecord`.
- **Lingers all week.** Card appears Sunday, stays through Saturday as "This
  week's Sunday Special". A Sunday-only surface would waste the content on
  anyone who doesn't open the app that day.
- **Additive, not a replacement.** Sunday still serves its normal daily + mini;
  the Special is a third card. Streak math untouched.

## Constraints found in code (why T1 exists)

- `CrosswordGridView.swift:24–28` fits the grid to width: `side = available /
  size`, no zoom or pan anywhere in the app. 21 cols on a 390pt iPhone ≈ 17pt
  cells — unusable. This is the engineering center of the epic.
- Generator caps `ALLOWED_SIZES = [10, 12, 15]`, `max_word_len = 9`, and pads
  to a fixed canvas (`tools/generate_puzzles.py:29`). All 138 shipped dailies
  are 15×15.
- Rotation pools wrap (`RotationWrapTests` records sizes + wrap dates); a new
  pool needs its own row in the README Dated table and its own recorded wrap.

## Tickets

### T1 — Zoomable grid mode (the real work)
- [ ] `CrosswordGridView` gains a zoom/pan mode, active when `vm.size >
      zoomThreshold` (15 stays fit-to-width — don't touch the shipped feel)
- [ ] Pinch to zoom (clamped ~1×–3×), drag to pan; double-tap toggles
      fit ↔ comfortable
- [ ] Selected cell auto-scrolls into view on selection/typing — typing at the
      edge must never leave the cursor off-screen, including above the letter
      keyboard overlay
- [ ] iPad: fit-to-width if cells ≥ ~30pt, zoom mode otherwise
- [ ] Reduce Motion: no animated zoom flourishes
- [ ] VoiceOver pass — zoom must not break cell accessibility frames

### T2 — Generator 21×21 profile
- [ ] `sunday` profile: size 21 allowed, canvas bumped, `max_word_len` raised
      (long themed spanners are the point), `min_words` raised (~28–40) so the
      grid doesn't feel empty
- [ ] `validate_content.py` covers the new size; accident/overlap checks hold
- [ ] Specs ship with **no `id`** (generator assigns `sunday-NNN`; ids are
      content-stable forever — same rule as dailies)

### T3 — Content bank
- [ ] 4–6 Sunday specs banked before launch (buffer > cadence panic)
- [ ] Themes worthy of a headline slot (big narratives: Exodus, Passion Week,
      Acts, Revelation…) — not padded dailies

### T4 — Provider + rotation + access
- [ ] `PuzzleKind.sunday`; new pool alongside `puzzles`/`minis` in
      `PuzzleProvider`
- [ ] `sundaySpecial(for:)` — deterministic by weeks-since-epoch %
      pool.count (mirror `dailyPuzzle`, `PuzzleProvider.swift:138`)
- [ ] `PuzzleAccess`: sunday pool window = current week only (length 1);
      archive Premium
- [ ] `RotationWrapTests` + README Dated table: record sunday pool size + wrap

### T5 — Surfaces
- [ ] Today card, featured styling, Sun–Sat: "Sunday Special — <theme>"
      (`HomeView.swift`); post-solve state mirrors daily card
- [ ] Library: Sunday Specials section/filter; locked rows route to paywall
      like other premium content
- [ ] Week strip: Sunday gets its marker only if Special *and* daily semantics
      stay honest — streak counts daily only (no change)

### T6 — Premium story
- [ ] Paywall benefit line gains the archive claim once ≥4 exist ("Every
      Sunday Special, back to the first")
- [ ] No CloudKit schema change — progress is existing `PuzzleRecord` by id

### T7 — Analytics + follow-ups
- [ ] Events in current vocabulary: `sunday_special_started`,
      `sunday_special_completed`, source (today_card / library / paywall)
- [ ] Later, not launch: Sunday-morning notification (needs 16), widget slot,
      Game Center 21×21 leaderboard

## Open questions

1. Backfill: seed launch with the banked specs as an instant archive (Premium
   sees 4–6 on day one) or let it accumulate weekly? Leaning **seed** — the
   paywall claim needs a shelf, not a promise.
2. Zen/timer defaults for a big grid — respect existing toggles, or default
   the timer hidden on Sundays?
