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

**1. The paywall strip now names the weakest packs.** ~~Ticket 08's locked-pack
strip ships as of `62e3db1`, and it excludes out-of-season packs. From roughly
January to Lent, and from Easter to Advent, the three evergreen packs are the
*entire* strip — so for most of the year the paywall's named evidence for
Premium is David, Parables, Psalm 23, and two of those three contain nothing a
free player can't already play.~~ **Resolved by T2 + T4.** The out-of-season
months now have five evergreen packs to draw on, all majority-exclusive, and
the strip names three of them plus "and 2 more" instead of being the whole
shelf. The observation stands as a rule though: **the strip is only ever as
good as the evergreen shelf**, because for most of the calendar year that is
all it can show.

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

- [x] **≥5 evergreen Premium packs** that are not pure overlays — **5 of 5**:
      Psalm 23, plus David and Parables fixed in T2, plus Out of Egypt and Women
      of the Bible added in T4
- [~] **≥4 seasonal packs** with windows — all four exist and are 100% exclusive;
      **density verified, quality not** (T3 still open)
- [x] **≥40 dedicated `pack-*` puzzles** total — **46**, from 26
- [x] No Premium pack ships with **&lt;4 puzzles** — smallest is 5
- [ ] At least **2 new packs per quarter** after floor (cadence), announced in release notes / Today surface — T5

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

**Status:** `[x]`  
**Estimate:** M each

- [x] Added **5 dedicated `pack-*` puzzles each** (target was ≥3), so both packs
      also clear the ≥5-exclusives success metric rather than only the T2 floor
- [x] Membership is majority exclusive: **9 puzzles, 5 exclusive (56%)** per pack
- [ ] Blurbs unchanged — **not needed.** "From the sheepfold to the throne of
      Israel" and "The stories that carry the kingdom" describe the collection,
      which is what a blurb is for here; neither ever claimed exclusivity, so
      there was no overclaim to walk back. The membership was the problem.

**Life of David** (1 & 2 Samuel, Psalms) — the arc the four dailies skip:

| id | title | source |
|----|-------|--------|
| `pack-life-of-david-002` | The Arrow and the Oath | 1 Samuel 18–20 |
| `pack-life-of-david-004` | The Cave of Adullam | 1 Samuel 22–24 |
| `pack-life-of-david-001` | The Ark Comes Home | 2 Samuel 6 |
| `pack-life-of-david-005` | Thou Art the Man | 2 Samuel 12 |
| `pack-life-of-david-003` | Create in Me a Clean Heart | Psalm 51 |

**Parables of Jesus** — five parables none of the dailies touch:

| id | title | source |
|----|-------|--------|
| `pack-parables-of-jesus-001` | The Rich Fool | Luke 12 |
| `pack-parables-of-jesus-003` | Seventy Times Seven | Matthew 18 |
| `pack-parables-of-jesus-005` | Two Men Went Up to Pray | Luke 18 |
| `pack-parables-of-jesus-004` | The Persistent Widow | Luke 18 |
| `pack-parables-of-jesus-002` | The Ten Virgins | Matthew 25 |

**Kept the dailies rather than migrating membership out.** Two reasons found
while doing it:

1. `PlayerProfile.completedPackIDs` is **append-only** and never recomputed
   from membership (`PuzzlePack.swift:350`), so neither adding nor removing
   revokes Pathfinder/Collector. That freed the decision from achievement risk —
   but pack *progress* is derived, so dropping membership would still have reset
   the bars of Premium players part-way through either pack.
2. The overlap is narrower than this ticket assumed. The free tier is a rolling
   **7-day window per pool** plus anything already started (`PuzzleAccess`), so
   those four dailies are Premium-gated for 85 of every 92 days. They are not
   "four free puzzles" — they are four puzzles that were each free for a week.

So the fix isn't removing the dailies, it's that the pack now contains five
puzzles that are **never** free on any day. Membership only ever grew; the
`puzzleIDs` writer asserts the old set is a subset of the new one.

**Ordering is narrative, not id order** — `puzzleIDs` is the play order, so
David reads sheepfold → Jonathan → exile → ark → Nathan → Psalm 51, with the
dailies sitting where they belong in the life rather than bunched at the front.

**Acceptance**
- [x] Paywall strip packs are no longer "4 free dailies with a lock" — each is
      majority never-free
- [x] Pack detail lists 9 puzzles and progress reflects them (verified on device)
- [x] New `pack-*` ids absent from daily and mini rotation — both pools byte
      identical before/after (92 dailies, 90 minis), zero content changes to any
      previously shipped puzzle
- [x] `validate_content.py` OK; 170 tests pass
- [x] Played `pack-life-of-david-002` on device: real interlocked grid, 15 clues,
      answers accept and advance
- [x] Journey tags picked up 2 Samuel automatically from the new content

> **Generator note for the next pack — the README's diff gate is unreliable
> here, in both directions.** Adding a *new pack slug* moves the pack block in
> `puzzles.json`, because `main()` iterates `sorted(by_slug)`, and where the new
> slug lands alphabetically decides how big the churn looks. T2 and T4 landed on
> opposite sides of it:
>
> | | new slugs | `git diff --numstat` | gate says |
> |---|---|---|---|
> | **T2** | `life-of-david`, `parables-of-jesus` (after `lent`) | 1568 ins, **0 del** | pass |
> | **T4** | `exodus` (before `lent`), `women-of-the-bible` | 3482 ins, **1922 del** | **fail** |
>
> Both were equally safe. T4 only looks worse because `exodus` sorts early and
> git could not match the displaced block as context. So the gate **misses a
> real move** (T2) and **false-alarms on a harmless one** (T4) — it is a proxy
> for "did a shipped puzzle move", and a poor one once packs are in the file.
>
> It stays useful for *dailies and minis*, which is what it was written for.
> For pack work, check the invariant directly instead, as both tickets did:
> **the daily and mini id sequences are unchanged, no shipped id is dropped, and
> no shipped puzzle's content differs** — compared against `HEAD`, not inferred
> from the diff. Pack puzzles are excluded from both rotation pools
> (`PuzzleProvider` filters `id.hasPrefix("pack-")` and `isMini`), so their file
> position is inert by construction.

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

**Status:** `[x]`  
**Estimate:** L

Chose **Exodus / Wilderness** (`exodus`, "Out of Egypt") and **Women of the
Bible** (`women-of-the-bible`), 5 puzzles each, 16 clues each.

| Idea | Verdict |
|------|---------|
| Exodus / Wilderness | **Shipped.** Best-known narrative arc in the OT, and the vocabulary interlocks better than anything else on the list — plagues, sea, manna, Sinai are all short and common-lettered |
| Women of the Bible | **Shipped.** The ticket's "underserved, strong share" holds, and it was the only candidate that adds *four* books nothing else covers (Ruth, Esther, Judges, and Hannah's 1 Samuel) |
| Names of God / “I AM” | Skipped. Best ASO case of the five, but the answers are abstract and repetitive, and the strongest ones (EL SHADDAI, JEHOVAH JIREH) are multi-word — the generator takes single A–Z runs of 3–9. Revisit as a *mini* pack, where short answers suit |
| Acts / Early Church | Skipped for now. Good NT depth, but proper-noun heavy, so clues lean on recall rather than reading |
| Proverbs wisdom | Skipped. Short answers, but no narrative spine — it would read as a word list rather than a collection |

- [x] Spec → generate → ids written back → `packs.json` entry `isPremium: true`
- [x] 5 `pack-*` puzzles each (46 dedicated total, from 36)
- [x] Packs tab discovery — both render with cover, blurb and size
- [ ] Release notes "New collection: …" — **not done**, belongs with the release

**Books added to the journey map:** Exodus (from Out of Egypt), and Ruth, Esther,
Judges, Luke, 1 Samuel across Women of the Bible. Verified on device: the pack
detail's "Finishing this adds Exodus to your journey" picked the tag up with no
extra wiring.

**Acceptance**
- [x] Both packs live in the build, `season: null`, always available
- [x] Both appear in the paywall locked strip — verified: opening the paywall
      from Out of Egypt lists it first, then David and Parables, then **"and 2
      more"**. That remainder line had never been reachable before (three
      evergreen packs meant it never had a surplus to count).
- [x] Live counts followed: paywall kicker 208 → **228 puzzles**, benefit line
      "All 7 packs" → **"All 9 packs, and every new one"**
- [x] Daily and mini pools byte-identical against `HEAD`; zero shipped puzzles
      changed; `validate_content.py` OK; 170 tests pass
- [x] Played `pack-exodus-002` on device — AARON accepted, advanced to JETHRO

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
| **P1** | ~~T2 David + Parables exclusive expansion~~ **done** | Overlay packs earn the lock |
| **P2** | T3 seasonal density check/fix | Seasonal Premium not thin |
| **P3** | ~~T4 two new evergreen packs~~ **done** | Catalog floor met |
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
