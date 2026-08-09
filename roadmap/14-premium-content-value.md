# Ticket 14 — Premium content value (earn the paywall claim)

**Priority:** high (conversion *after* craft is done)  
**Status:** `[x]` — T0–T6 done, T7 checked and declined on data. The catalog
work is finished; whether it moves trial→paid is unproven until it ships and a
month of clean data exists (see T7's caveat on internal traffic).  
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
- [x] **≥4 seasonal packs** with windows — all four exist, 100% exclusive,
      gates verified as recurring shapes, and clue quality audited in T3
- [x] **≥40 dedicated `pack-*` puzzles** total — **46**, from 26
- [x] No Premium pack ships with **&lt;4 puzzles** — smallest is 5
- [x] At least **2 new packs per quarter** after floor (cadence), announced in release notes / Today surface — ledger, named slots and the New badge shipped in T5; the cadence itself is only proven by keeping it

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

> **T0 shipped incomplete — corrected in T5.** It fixed the two surfaces it
> went looking for and missed a third: `PackTile`, the Home carousel, which had
> the identical unguarded progress branch. So for four commits a crowned pack
> could still read "Complete" on the home screen — the most visible of the
> three. Found only because T5 touched the same view for the New badge, not by
> any check here. The lesson is cheap to state: **`isLocked` progress rules
> belong to every surface that draws a pack**, and there are three
> (`PackCard`, `PackDetailView`, `PackTile`).

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

**Status:** `[x]`  
**Estimate:** M

The counts were never the problem — every pack already met ≥5. This turned into
the clue-quality audit the task actually asked for, run over all **46 exclusive
puzzles / 802 clues**.

- [x] **Seasonal gates verified.** All four use recurring shapes — Lent
      `easter -46…-1`, Easter `easter -7…7`, Advent `annual 12-01…12-26`,
      Christmas `annual 12-26…01-06`. **None uses `kind: "dates"`**, which is
      the shape the README warns expires permanently after one year.
- [x] **Counts confirmed:** Lent 5, Easter 5, Advent 6, Christmas 5, Psalm 23 5.
- [x] **Difficulty mix** — every Premium pack now carries a hard, except Out of
      Egypt (see below).
- [x] **Stub/weak clues fixed — 16 edits across 12 puzzles.**

**What the audit found**

| Issue | Count | Where |
|---|---:|---|
| Clue duplicated verbatim elsewhere in the bank | 6 | 5 self-inflicted in T2/T4, 1 pre-existing |
| Clue containing its own answer's stem | 1 | `pack-parables-of-jesus-003` SEVENTY |
| Dictionary definitions with no anchor in the text | 8 | all in Psalm 23 |

1. **Six duplicated clues.** Five were mine, written in T2/T4 without sight of
   the mini bank and converging on the same KJV phrasing — e.g. SINAI "the mount
   that was altogether on a smoke" already existed word-for-word as `mini-030`.
   The sixth is pre-existing and worse, because both sides are Premium:
   `pack-advent-004` and `pack-christmas-004` gave DREAM the identical clue,
   though they are different dreams (Matthew 1:20, take Mary; Matthew 2:13, flee
   to Egypt). Both now say which.
2. **One self-revealing clue.** SEVENTY was clued "____ times seven, said
   Jesus" — the answer's own stem sitting in the clue. Now "Ten times the number
   Peter proposed, in the Lord's answer".
3. **Psalm 23's filler.** See below.

**The real finding: Psalm 23 is structurally stretched.**

It is a six-verse psalm carrying 5 puzzles × ~15 answers ≈ **77 answers**. There
is not that much Psalm 23, so roughly a third of the fill is thematic padding —
MEADOW, GRASS, BROOK, CALM, QUIET, REVIVE, RENEW, COURAGE, PROTECT, NEAR,
STRENGTH, FEAST — words that never appear in the psalm, several of which had
pure dictionary clues ("To make fresh again", "A grassy field for grazing")
with no scripture in them at all. Every other pack draws on a whole narrative
and has real vocabulary to spare.

I rewrote the eight worst to anchor them in the psalm rather than defining them,
which is the honest fix available without touching grids. **It does not solve
the underlying problem**, and the ticket's suggestion to add "+1–2 if thin" is
backwards — Psalm 23 is thin *because* it is already stretched over five
puzzles. Options if it needs revisiting, none of which are this ticket:
broaden the pack's remit to the shepherd psalms (23, 100, 95, John 10), or
accept it as the shortest pack and never grow it.

**Deliberately not done**

- **No new puzzles.** T3 asked for depth where counts were already met; adding
  more to Psalm 23 would deepen the exact problem the audit found.
- **Out of Egypt has no hard puzzle**, unlike every other pack. Not forced: it
  is the best-known narrative in the Old Testament and nothing in it is honestly
  hard. `difficulty` feeds the `hardCompleted` achievement, so mislabelling a
  medium puzzle to even up a table would inflate a real player stat.
  Women of the Bible *did* get one — Esther, on vocabulary (MORDECAI, SHUSHAN,
  VASHTI, PURIM), which is defensible on its own terms.

**Acceptance**
- [x] Every seasonal Premium pack has ≥5 exclusive puzzles
- [x] Seasonal gates correct, and none of the expiring `dates` kind
- [x] Zero duplicated clue texts involving a pack exclusive (was 6)
- [x] Zero clues containing their own answer (was 1)
- [x] Grids and answer sets **byte-identical** — clue text and one difficulty
      label are the only changes; both rotation pools untouched
- [x] `validate_content.py` OK; 170 tests pass

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

**Status:** `[x]`  
**Estimate:** S eng + process

- [x] **Quarterly cadence** written into `docs/seasonal-pack-calendar.md` rather
      than a new file, since that is where anyone shipping a pack already looks
- [x] **In-app “New” affordance** — it was cheap, so it exists rather than
      falling back to release-notes-only
- [x] **App Store “What’s New”** rule recorded, with the reason it can't be
      dropped in favour of the badge

**The eng, smaller than the ticket feared**

`PuzzlePack.addedOn` (optional ISO date) + `isNew(on:)` over a 14-day window
matched to `SeasonBadge.noticeDays`. The badge shows on the Packs tab and the
Home carousel, and a new pack sorts to the **front** of that carousel while it
lasts — a badge on the fifth tile of a horizontal strip is three swipes away,
which is the discovery problem the badge exists to solve.

- **Optional, and not backfilled.** Packs that shipped before the field have no
  honest answer, and dating them would announce the whole back catalogue at
  once. No `addedOn`, never new.
- **Not derived from `publishDate`.** `tools/README.md` calls that field
  cosmetic and free to shift, so a regeneration could re-announce a two-year-old
  pack.
- **Ranked against the season badge, not stacked** (`PackBadge`): a seasonal
  pack shipped mid-window is both new and closing, and the row holds one
  capsule. "Last day" wins — "New" will still be true tomorrow.
- 7 tests cover the window edges, a future date, an unparseable date, and the
  ranking. 170 → **177 tests**.

**Two defects found while doing it**

1. **T0 was incomplete.** `PackTile` in the Home carousel had the same
   locked-pack progress bug fixed in `PackCard` and `PackDetailView` — so a
   crowned pack could still read "Complete" on the home screen, the most visible
   surface of the three. Fixed here.
2. **The tile overflowed.** Adding a badge to a fixed 150pt tile pushed the
   puzzle count outside the card whenever the title also wrapped to two lines
   ("Women of the Bible"). Height is now a `@ScaledMetric` 176.

**The cadence, and a miss it turned up**

Two newly authored packs per quarter, with the rule that **a recurring seasonal
pack counts only in the year it is authored** — Advent returning in 2027 is not
new to anyone who played it in 2026. Named slots now exist for 2026 Q4
(`creation`, `acts`) and 2027 Q1 (`joseph`, `names-of-god`), each with a brief.

Writing that ledger surfaced that **`creation` missed its 2026 window**: the
calendar has it as `annual(07-01, 08-15)` with a 1 June ship-by, and it does not
exist in `packs.json`. As of 9 August the window closes in six days, less than
App Review turnaround — the summer quarter shipped no seasonal pack. Recorded in
the calendar rather than quietly re-dated, moved to a Q4 slot so it is authored
out of window and idle before 1 July 2027, and a **pre-quarter review** added so
the next slip is caught by a check rather than by an audit.

**Acceptance**
- [x] Next two quarters have named pack slots with briefs
- [x] Players can discover what's new without the App Store — verified on device:
      both new packs badged on the Packs tab, and leading the Home carousel with
      badges visible without scrolling
- [x] 177 tests pass

---

### T6 — Align marketing claims with shelf

**Status:** `[x]`  
**Estimate:** S

**The premise was wrong in an interesting way.** This task was written to guard
against *over*-claiming — "dozens of collections", "100+". Nothing anywhere
over-claims on packs; the website does not mention collections at all. What the
audit found was the opposite failure: **every quantity claim was stale and far
too low**, frozen at the 82-puzzle era.

| Surface | Claimed | Actual |
|---|---|---|
| App Store description, ×6 locales | 80+ puzzles | 228 |
| Website, 81 files | 80+ puzzles | 92 full-size |
| `archive.ts` tier headings | 28 / 35 / 19 | 31 / 39 / 22 |
| `archive.ts` `MINI_COUNT` | 30 | **90** |
| `/puzzles/` page | "plus 30 mini puzzles" | 90 |

- [x] No inflated pack numbers anywhere — there were none to remove
- [x] Paywall count stays live (`PremiumBenefit` interpolates, verified in T4:
      228 puzzles / 9 packs)
- [x] ASC and website now state packs + archive truthfully
- [x] Benefit string **not** watered down — the shelf grew instead, which is
      what this task asked for

**One real over-claim, and it was not about packs.** Promotional text in all six
locales ended *"New puzzle added daily!"*. The daily rotates a fixed pool; it is
not added to daily, and **the pool wraps on 2026-10-01** — the entire subject of
ticket 13. From that date a daily player starts seeing repeats while the App
Store promises new content every day. Replaced with "Free every day." (154 chars,
under the 170 limit).

**Fixed so it cannot drift again, rather than retyped**

The website's `ARCHIVE` is a hand-maintained mirror of the app's dailies, and it
was a *perfect subset* — 82 of 92 titles, zero difficulty or verse mismatches.
It had simply never been updated when ticket 13 shipped ten dailies. So the
drift was structural, not sloppy:

- The ten missing dailies added; the site now lists all 92.
- Tier headings are **computed from the lists they label** (`Easy · ${n} puzzles`)
  instead of being literals typed beside them.
- Every `80+` in templates now interpolates `PUZZLE_COUNT`; the `/puzzles/` page
  uses `MINI_COUNT`.
- The 81 content JSON files can't import a constant, so the number came **out**
  of them — "Every puzzle, Genesis to Revelation". A figure typed into 81 files
  is a figure that will be wrong in 81 places.
- App Store copy uses **"200+"**, deliberately round and low: it is true at 228,
  consistent with the in-app count, and survives the next few content drops.
  A fastlane description cannot import anything, so the only defence is a number
  that ages well.

**Still hand-maintained:** `MINI_COUNT` and the `ARCHIVE` title list. Both are
retyped from `puzzles.json` and will drift again — the honest fix is generating
`archive.ts` from the bundle, which is a bigger change than this task. Recorded
here so the next drift is expected rather than discovered.

**Acceptance**
- [x] No external claim exceeds the real figures — and none understates them now
- [x] `npm run build` passes, 86 pages; rendered output verified as 92 full-size,
      90 minis, tiers 31/39/22
- [x] Promotional text within the 170-char limit in all six locales

---

### T7 — Optional: free teaser puzzle in each Premium pack

**Status:** `[—]` **Not doing.** Gate condition checked against live data and not
met. Nothing was built.

The task is explicitly conditional: *"Only if conversion data shows pack_locked
underperforms."* So the work was to answer that question, not to assume it.

**PostHog, 30 days to 2026-08-09, paywall by entry point:**

| source | opens | share | CTA taps | purchases | open→buy |
|---|---:|---:|---:|---:|---:|
| onboarding | 122 | 41% | 9 | 2 | 1.6% |
| hint_limit | 97 | 33% | 1 | 2 | 2.1% |
| completion | 48 | 16% | 0 | 0 | 0% |
| **pack_locked** | **13** | **4%** | **0** | **1** | **7.7%** |
| home_card | 11 | 4% | 1 | 2 | 18% |
| archive | 3 | 1% | 1 | 0 | 0% |
| profile | 1 | <1% | 0 | 0 | 0% |

**`pack_locked` does not underperform.** At 1 purchase in 13 opens it sits above
both of the high-volume sources. The gate is not met, so the default stands:
full pack lock, `first-steps` free.

**But do not read that table as evidence either.** Eight purchases across every
source in thirty days is not enough to rank anything — `pack_locked`'s rate is
one purchase, and losing it would take the row to 0%. The honest summary is that
**no paywall source can be compared on this data yet**, in either direction.

Three further reasons not to build it, independent of the numbers:

1. **The calendar already decided against it.** `docs/seasonal-pack-calendar.md`:
   "No free teaser inside a Premium pack… a seasonal pack whose first puzzle is
   free would be a second free surface with none of the same purpose." T7 would
   contradict a documented product decision, which at minimum needs settling
   first rather than shipping past it.
2. **A taste already exists.** `PuzzleAccess` gives a rolling 7-day window per
   pool plus anything already started, on top of the free `first-steps` pack. A
   pack teaser would be a third free surface, not the first.
3. **The leverage is elsewhere.** `pack_locked` is 4% of paywall traffic.
   Doubling its conversion would be worth roughly one extra purchase a month.
   Onboarding is 41% of opens at 1.6% — that is where a point of conversion is
   worth having, and it is ticket 07's ground, not this one's.

**Reopen when** `pack_locked` has ~200+ opens with a rate that is clearly below
`hint_limit` on the same window. On current volume (~13/month) that is a year
away — realistically this stays closed unless pack traffic grows a lot, which
T4's shelf may itself cause.

> **Data-quality caveat, and it is not small.** Internal and test filtering is
> still unset on this project, and *this session's own simulator testing is in
> the numbers* — today's 15 opens across 9 "people" include several fresh
> installs I made while verifying T0–T6. Add the note that pre-2026-07-28 data
> carries simulator traffic too. Before any paywall decision is made on these
> events, internal traffic needs excluding; otherwise the next person to read
> this table will be measuring us.

---

## Phasing

| Phase | Deliverable | Done when |
|-------|-------------|-----------|
| **P0** | ~~T1 audit~~ **done** + T0 display fix **done** | Next packs prioritized |
| **P1** | ~~T2 David + Parables exclusive expansion~~ **done** | Overlay packs earn the lock |
| **P2** | ~~T3 seasonal density check/fix~~ **done** (became a clue-quality audit) | Seasonal Premium not thin |
| **P3** | ~~T4 two new evergreen packs~~ **done** | Catalog floor met |
| **P4** | ~~T5 cadence + T6 claims~~ **done** | Sustainable, honest growth |

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
