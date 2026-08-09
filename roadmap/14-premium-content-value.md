# Ticket 14 — Premium content value (earn the paywall claim)

**Priority:** high (conversion *after* craft is done)  
**Status:** `[ ]`  
**Type:** content + light eng  
**Estimate:** L (ongoing cadence, not one PR)  
**Related:** `01-seasonal-packs-content-cadence.md`, paywall `PremiumBenefit` (“All N packs, and every new one”), `docs/themed-packs-spec.md`  
**Files:** `Resources/packs.json`, `Resources/puzzles.json`, `tools/puzzle_specs.json`, generator

## Problem

Paywall craft is strong (~9/10). **What Premium *is* is still the weak leg (~7/10).**

Benefit line today:

> All \(packCount\) packs, and every new one

That only converts if packs feel like **real exclusive depth**, not a thin shelf.

### Snapshot (2026-08-09)

| Metric | Count | Note |
|--------|------:|------|
| Total packs | 8 | 1 free starter + 7 Premium |
| Premium packs | 7 | David, Parables, Psalm 23, Lent, Easter, Advent, Christmas |
| Unique puzzle ids in packs | ~39 | Mix of dailies + exclusives |
| Dedicated `pack-*` puzzles | ~26 | True exclusives |
| Overlay packs | David, Parables | ~~Mostly~~ **entirely** existing dailies — see measured table below |
| Total puzzles in app | ~208 | Archive is large; packs are the *named* Premium reason |

**Gap:** Player pays for “collections,” but two evergreen Premium packs are curation of free rotation. Seasonal packs help; **evergreen exclusive depth** and a **visible cadence of “new packs”** still under-deliver vs the claim.

This is not fixed by another paywall rewrite. It’s fixed by **shipping content that makes the claim true and heavy**.

### Measured membership (2026-08-09, from `packs.json`)

| Pack | ids | exclusive `pack-*` | overlay `daily-*` | window |
|------|----:|------:|------:|--------|
| The Life of David | 4 | **0** | 4 | evergreen |
| Parables of Jesus | 4 | **0** | 4 | evergreen |
| The Shepherd's Psalm | 5 | 5 | 0 | evergreen |
| Lent | 5 | 5 | 0 | seasonal |
| Easter | 5 | 5 | 0 | seasonal |
| Advent | 6 | 6 | 0 | seasonal |
| Christmas | 5 | 5 | 0 | seasonal |

**Worse than the prose above assumed.** David and Parables are not
overlay-*heavy*, they are overlay-*only*: `daily-004/013/022/035` and
`daily-021/024/038/056`. Every id in both packs is in free rotation. Of three
evergreen Premium packs, exactly one has any exclusive content.

Exclusive share across Premium packs is **26/34 ≈ 76%** — which passes the ≥70%
success metric below while completely hiding the real problem, because all the
exclusives are concentrated in the packs that were already fine. **The metric
should be per-pack, not aggregate** (see Success metrics).

### Two consequences found on 2026-08-09

**1. The paywall strip now names the weakest packs.** Ticket 08's locked-pack
strip ships as of `62e3db1`, and it excludes out-of-season packs. From roughly
January to Lent, and from Easter to Advent, the three evergreen packs are the
*entire* strip — so for most of the year the paywall's named evidence for
Premium is David, Parables, Psalm 23, and two of those three contain nothing a
free player can't already play. The strip made the shelf more visible, which is
right, but it means T2 is no longer a tidy-up: it is the content behind the
main sales surface.

**2. Locked packs could render "Complete".** `PackCard` and `PackDetailView`
both drew progress from the player's own records with no lock branch. Because
David and Parables are built from dailies, a free player who worked through
daily rotation accumulated genuine progress *inside collections they cannot
open* — and on solving all four, the card rendered **"Complete" with a green
seal beside the crown**, and pack detail rendered **"Pack complete — every
puzzle solved"** directly above an Unlock Premium button. Fixed in T0 below.
Note this was only reachable *because* of the overlay problem: fixing the
display stops it being shown, T2 stops it being true.

## Goal

Make Premium feel worth yearly/lifetime **on content alone** (hints + archive remain secondary benefits):

1. Every Premium pack has a clear **exclusive** core (prefer `pack-*` over overlay-only).
2. Evergreen shelf is deep enough that off-season players still see value.
3. Cadence of **new packs** is real and marketable (“new this month”), not vapor.
4. Paywall pack strip + benefit counts stay accurate as content grows (already live-counted).

**Out of scope:** Paywall UI redesign (08/07 largely done), free-tier rule changes (09), ads (12), journey map UI (05) except book tags if cheap.

**Relationship to 01:** 01 is seasonal *calendar + process*. **This ticket is the quality bar + catalog targets** so Premium isn’t “four thin packs.” Execute seasonal work *against* the targets here; don’t treat 01 as “ship any pack JSON.”

---

## Success metrics

- Premium packs with **≥5 dedicated `pack-*` puzzles** (or ≥5 exclusive-only ids)
- ~~Share of Premium pack membership that is **exclusive** (target: **≥70%** of ids across Premium packs are `pack-*` or never free-rotated)~~
  **Replaced — this metric is broken.** Measured across the shelf it reads 76%
  today, i.e. already passing, while two of seven packs are 0% exclusive. An
  aggregate hides exactly the failure mode this ticket exists to fix.
  **Use instead: every Premium pack is individually ≥50% exclusive, and no
  Premium pack is 0% exclusive.** Today: 5 of 7 pass, 2 fail outright.
- Paywall `packCount` and strip feel “library,” not “handful” (soft target: **10+ Premium packs** evergreen+seasonal available in a typical month, or **8+ evergreen** always)
- Qualitative: trial users who open Packs tab see **≥3 full rows of Premium collections** they can’t finish free
- Optional analytics: `pack_opened` / `pack_completed` among trial starts; trial→paid correlated with pack starts

---

## Targets (definition of “enough value”)

### Catalog floor (v1 done when)

- [ ] **≥5 evergreen Premium packs** that are not pure overlays  
  Today solid exclusive: Psalm 23. David + Parables need exclusive expansion or demotion from “hero” sell.
- [ ] **≥4 seasonal packs** with windows (Lent/Easter/Advent/Christmas exist — verify density + quality, not just presence)
- [ ] **≥40 dedicated `pack-*` puzzles** total (from ~26)
- [ ] No Premium pack ships with **&lt;4 puzzles**
- [ ] At least **2 new packs per quarter** after floor (cadence), announced in release notes / Today surface

### Quality bar (every new pack)

- [ ] Dedicated ids (`pack-<slug>-NNN`) for exclusives — never enter daily rotation
- [ ] Clue references on pack puzzles (feeds 03)
- [ ] Difficulty mix (not all hard)
- [ ] Completion verse + pack “next” flow still works
- [ ] Specs reviewed for spoiler/overlap (see backlog content QA)

---

## Tasks

### T0 — Stop locked packs reporting the player's own progress

**Status:** `[x]`  
**Estimate:** S

Display-only, shipped ahead of the content work because it was live and visible
to precisely the engaged free players most likely to convert.

- [x] `PackCard`: locked packs show "N puzzles" instead of a progress bar, and
      can no longer render "Complete"
- [x] `PackDetailView`: same in the header, replacing "Pack complete — every
      puzzle solved" appearing above an Unlock Premium button
- [x] VoiceOver labels follow the same branch — otherwise the contradiction
      survives in the one place a sighted player can't see it to report it
- [x] Unlocked packs keep progress and completion exactly as before

**Acceptance**
- [x] Locked pack card and detail state size, never progress — verified on device
- [x] Free pack (First Steps) still shows "0 of 5 solved" and its bar
- [~] The "Complete" case itself not reproduced on device — it needs a player
      who has solved all four David dailies. Structurally unreachable now: the
      `isLocked` branch precedes the `isComplete` branch in both views.

**This is a plaster, not the fix.** It stops the app *saying* the quiet part.
T2 is what stops it being true.

---

### T1 — Audit current Premium shelf

**Status:** `[x]` for the exclusive/overlay question — see **Measured membership**
above, which answers it for all 7 packs from `packs.json` directly. Remaining
work is quality notes, which belongs with T3.

- [x] Table: pack id → exclusive vs overlay count → seasonal window
- [x] Flag packs that over-promise on paywall — **David and Parables, both 0%
      exclusive**, and both named in the paywall strip for most of the year
- [x] Decide per pack: David + Parables → **expand exclusives** (T2). Not
      "reposition blurb": the blurbs are accurate, it's the membership that
      doesn't earn a lock. Not "keep as free-friendly overlay" either, while
      they're two-thirds of the evergreen shelf and the paywall names them.
- [ ] Quality notes on the 5 exclusive packs — folded into T3
- [ ] Clear list of next 4 packs to author — still open, see T4

**Acceptance**
- [x] Written audit in this file
- [ ] Next 4 packs named (T4 has 5 candidates, none chosen)

---

### T2 — Upgrade overlay Premium packs (David, Parables)

**Status:** `[ ]`  
**Estimate:** M each

For each of Life of David + Parables of Jesus:

- [ ] Add **≥3 dedicated** `pack-*` puzzles (keep existing dailies as optional extras or migrate membership toward exclusives)
- [ ] Prefer pack membership majority exclusive
- [ ] Update blurb if needed (“exclusive journeys” not “themes you already met in daily”)

**Acceptance**
- Paywall strip packs are not “4 free dailies with a lock”
- Pack detail progress reflects new exclusives

---

### T3 — Expand exclusive depth on existing dedicated packs

**Status:** `[ ]`  
**Estimate:** M

- [ ] Psalm 23: already 5 — optional +1–2 if thin; or leave and focus elsewhere
- [ ] Lent / Easter / Advent / Christmas: ensure each **≥5** solid exclusives (Advent has 6 — good; audit quality)
- [ ] Fill any stub/weak clues found in audit

**Acceptance**
- Every seasonal Premium pack meets ≥5 exclusive puzzles
- Seasonal gates still correct (`season` in packs.json)

---

### T4 — Ship 2 new evergreen Premium packs

**Status:** `[ ]`  
**Estimate:** L

Suggested themes (pick 2; faith + crossword-friendly):

| Idea | Why |
|------|-----|
| Names of God / “I AM” | High search, clear answer set |
| Women of the Bible | Underserved, strong share |
| Exodus / Wilderness | Narrative arc pack |
| Acts / Early Church | NT depth beyond Gospels |
| Proverbs wisdom | Short answers, good minis hybrid |

- [ ] Spec → generate → edit → `packs.json` entry `isPremium: true`
- [ ] 5–7 `pack-*` puzzles each
- [ ] Home carousel / Packs tab discovery (existing UI)
- [ ] Release notes: “New collection: …”

**Acceptance**
- Two new packs live in production build
- Not seasonal-gated (always available)
- Appear in paywall locked strip

---

### T5 — “New packs” is real (cadence + surface)

**Status:** `[ ]`  
**Estimate:** S eng + process

- [ ] Quarterly content calendar (can merge with 01): Q target = 2 packs
- [ ] Optional Home/Profile line when a pack is new (e.g. 14 days after `availableFrom` or a `newUntil` field — only if cheap; else release-notes only)
- [ ] App Store “What’s New” always names new packs when shipping

**Acceptance**
- Next two quarters have named pack slots before the quarter starts
- Players can discover “what’s new” without reading the App Store only

---

### T6 — Align marketing claims with shelf

**Status:** `[ ]`  
**Estimate:** S

- [ ] When pack count &lt; target, avoid marketing “dozens of collections” elsewhere
- [ ] Keep paywall live count (honest)
- [ ] ASC / website descriptions: packs + archive + hints, not inflated pack numbers
- [ ] Revisit benefit string only if needed: e.g. “Themed collections, growing every season” if count still small — prefer **shipping packs** over watering down copy

**Acceptance**
- No external claim exceeds actual Premium pack count by hand-wavy “100+ collections”

---

### T7 — Optional: free teaser puzzle in each Premium pack

**Status:** `[ ]`  
**Estimate:** S eng

- [ ] First puzzle of each Premium pack playable free (taste) → rest locked
- [ ] Or one shared free teaser pack only  
**Only if** conversion data shows pack_locked underperforms; default is full pack lock + First Steps free.

---

## Phasing

| Phase | Deliverable | Done when |
|-------|-------------|-----------|
| **P0** | ~~T1 audit~~ **done** + T0 display fix **done** | Next packs prioritized |
| **P1** | T2 David + Parables exclusive expansion | Overlay packs earn the lock |
| **P2** | T3 seasonal density check/fix | Seasonal Premium not thin |
| **P3** | T4 two new evergreen packs | Catalog floor met |
| **P4** | T5 cadence + T6 claims | Sustainable, honest growth |

## Dependencies

- Generator / `tools/` pipeline stable
- No CloudKit schema needed (bundled JSON only)
- Paywall strip already shows available Premium packs — content just appears

## Test plan

- [ ] Free user: First Steps playable; Premium packs locked; paywall strip lists them
- [ ] Premium user: all pack puzzles open; completion “next in pack” works for new ids
- [ ] New `pack-*` ids **absent** from daily/mini rotation
- [ ] Seasonal packs hide outside window (existing behavior)
- [ ] Pack completion achievements still reconcile
- [ ] Total puzzle count on paywall kicker still correct

## Done when (v1)

- [ ] Catalog floor metrics above met  
- [ ] David + Parables are majority-exclusive  
- [ ] Two new evergreen Premium packs shipped  
- [ ] Quarterly cadence documented for next 2 packs  
- [ ] Paywall claim “all packs + every new one” is **felt** in Packs tab, not only counted  

## Open questions

1. Expand overlay packs vs replace their membership entirely with exclusives (dailies stay in archive either way)?
2. One-time IAP per pack later (06 stretch) — does that change how many free teasers we want?
3. Target yearly sub price vs content volume — is 10 Premium packs the floor for a price increase later?
