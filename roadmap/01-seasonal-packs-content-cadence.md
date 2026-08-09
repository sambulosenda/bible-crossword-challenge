# Epic 01 — Seasonal packs + content cadence

**Priority:** 1  
**Goal:** Retention + Premium  
**Status:** `[x]` — all six tickets closed 2026-08-08  
**Depends on:** Existing pack system (`packs.json`, `PuzzlePack`, dedicated `pack-*` puzzles)  
**Related:** `docs/themed-packs-spec.md`, `docs/seasonal-pack-calendar.md`, **`14-premium-content-value.md`** (catalog floor / exclusive depth beyond seasonal ship)

## Decisions (2026-08-08)

- **Seasons recur.** `availableFrom`/`availableTo` are gone; a pack declares a
  `PackSeason` rule — `dates` (one-off), `annual` (`"12-01"`, may wrap the new
  year), or `easter` (days from Easter Sunday, computed). Advent used to expire
  permanently on 2026-12-26 and Easter couldn't be expressed at all.
- **Expired seasonal packs are hidden**, everywhere. No "returns in December"
  teaser.
- **No free teaser inside a Premium seasonal pack.** `first-steps` stays the
  only free pack.

## Why

Pack infra + Advent window already ship. Seasonal packs = re-engagement spikes and a *content* reason for Premium, not just ad-removal / unlimited hints.

## Success metrics

- Pack open / complete rates (`pack_opened`, `pack_completed`)
- Seasonal window DAU lift vs non-seasonal weeks
- Paywall open + purchase from pack-gated surfaces

---

## Tickets

### P1-T1 — Content calendar (editorial)

**Status:** `[x]` — `docs/seasonal-pack-calendar.md`  
**Type:** content / process  
**Estimate:** S

- [x] Define 12-month pack calendar (ship windows + marketing dates)
- [x] Minimum: Easter, Christmas, Lent, one summer VBS-style pack
- [x] Document “overlay vs dedicated” per pack — all five are dedicated
- [x] Assign free vs Premium (`isPremium`) + season rule per pack

**Acceptance**
- ✅ Q1–Q4 windows, pack slugs, puzzle counts, free/premium flags, ship-by dates
  and a per-pack brief in `docs/seasonal-pack-calendar.md`

---

### P1-T2 — Easter pack (dedicated puzzles)

**Status:** `[x]`  
**Type:** content + light app  
**Estimate:** M

- [x] 5 specs in `tools/puzzle_specs.json` with `"pack": "easter"`, 20 candidate
      answers each, KJV verses:
      1. Hosanna in the Highest (Matthew 21:9, easy)
      2. It Is Finished (John 19:30, easy)
      3. The First Day of the Week (John 20:16, medium)
      4. The Road to Emmaus (Luke 24:32, medium)
      5. Breakfast by the Sea (John 21:12, hard)
- [x] Generated as `pack-easter-001…005`, 15×15, 19–20 clues each. `puzzles.json`
      diff is 924 insertions / **0 deletions** — the 82-daily rotation is untouched.
- [x] Ids written back into the specs (they are now permanent)
- [x] `packs.json` entry: `sunrise` cover, `#C8912B`, Premium,
      `"season": {"kind":"easter","from":-7,"to":7}`
- [x] `validate_content.py` OK; 108 tests green; opened it on the simulator at a
      simulated 30 Mar 2027 — resolves, shows "5 days left", ends 4 April

**Acceptance**
- ✅ In window Palm Sunday → Easter+7, computed from the feast, every year
- ✅ Hidden outside it
- ⚠️ Pack-complete + "Next in pack" run on the existing `PackCompletion` path
  (covered by `PacksTests`), but not played end-to-end here — the pack is
  Premium and a sandbox purchase can't be completed from a `simctl` launch.
  Worth one manual pass from Xcode with `Products.storekit` before release.

---

### P1-T3 — Christmas pack (expand beyond Advent)

**Status:** `[x]`  
**Type:** content  
**Estimate:** M

Audited: Advent was 2 *overlay* puzzles (`daily-019`, `daily-028`) — a pack in
name only, and both already solved by any regular player.

- [x] 6 dedicated `pack-advent-001…006`, replacing both overlays. Prophecy to
      the manger, in narrative order: Isaiah 9 · Luke 1 (annunciation) ·
      Luke 1 (Magnificat) · Matthew 1 · Luke 2 (the census) · Luke 2 (the
      shepherds). 17–20 clues each.
- [x] New `christmas` pack, 5 dedicated puzzles, `annual 12-26 → 01-06`:
      John 1 · Luke 2 (Simeon and Anna) · Matthew 2 (the star) ·
      Matthew 2 (the flight) · Luke 2 (the boy in the temple). 18–19 clues each.
- [x] Advent closes 12-26, Christmas opens on it. Both are in season that one
      day — verified on the simulator, Advent reads "Last day" while Christmas
      reads "11 days left". That overlap *is* the handoff.
- [x] `daily-019` and `daily-028` stay in the daily rotation, so the two new
      packs deliberately avoid their vocabulary — a pack whose answers a player
      typed last week is not new content.

**Acceptance**
- ✅ Seasonal carousel carries Advent through December and Christmas into
  January without displacing the evergreen collections (they stay under
  "All Collections").

**Note for release:** a player who solved both old overlay dailies may already
hold `advent` in `completedPackIDs` (launch reconciliation runs regardless of
season). The pack now reads 0 of 6 for them while the achievement stays
unlocked. `PackCompletion.record` only ever appends, so nothing is taken away.

---

### P1-T4 — Lent pack

**Status:** `[x]`  
**Type:** content  
**Estimate:** M

- [x] 5 dedicated `pack-lent-001…005`, 19–20 clues each:
      1. Rend Your Heart (Joel 2:13, easy)
      2. Forty Days in the Wilderness (Matthew 4:4, easy)
      3. A Great Way Off (Luke 15:20, medium)
      4. He Washed Their Feet (John 13:14, medium)
      5. Not as I Will (Matthew 26:39, hard)
- [x] `"season": {"kind":"easter","from":-46,"to":-1}` — Ash Wednesday → Easter Eve
- [x] Tone: repentance, wilderness, mercy, the basin, the garden. The Prodigal
      Son sits at the centre so the arc isn't forty days of dread.
- [x] Leads *up to* the Easter pack rather than repeating it — none of these five
      chapters appear in `pack-easter-*`, which starts at the triumphal entry.
      Lent's window overlaps Easter's through Holy Week by design: verified on
      the simulator at 25 Mar 2027, Lent reads "2 days left" and Easter
      "10 days left", both computed off Easter Sunday 28 March.

**Acceptance**
- ✅ Pack live Ash Wednesday → Easter Eve, tracking the feast every year
- ⚠️ Completion share card uses the pack title via the existing `PackCompletion`
  path; not played end-to-end (Premium — same sandbox-purchase limit as T2)

---

### P1-T5 — Cadence pipeline (tooling)

**Status:** `[x]`  
**Type:** eng  
**Estimate:** S

- [x] "Ship a pack" checklist (author → generate → write ids back → packs.json →
      validate → test → look → tick the calendar) in `tools/README.md`, plus a
      season-shape table
- [x] `tools/validate_content.py` — pack ids resolve, no daily-pool leakage for
      `pack-*`, season windows parse, every shipped id written back to its spec,
      exactly one free pack
- [x] Answer-overlap sanity check (warns; currently flags `life-of-david`
      sharing 8 answers between `daily-013` and `daily-035`)

**Acceptance**
- ✅ One checklist, no tribal knowledge. `python3 tools/validate_content.py`
  exits non-zero on anything the app would swallow silently.

---

### P1-T6 — Seasonal surface polish

**Status:** `[x]`  
**Type:** eng / design  
**Estimate:** S

- [x] Days-left badge (`SeasonBadge`) on the Home carousel tile, the Collections
      card and the pack header. Appears in the last 14 days, amber in the last 3.
      Earlier in a window the header states the end date instead.
- [x] Paywall names the pack when opened from a locked *seasonal* one
      ("Easter is only here this season"); an evergreen pack keeps the generic
      promise rather than inventing urgency. Locked state states the end date.
- [x] Local notification at 10:00 on the day a seasonal pack opens — inside the
      existing `reschedule` flow, so it inherits the reminders toggle and the
      authorization guard. Needs no "already sent" flag: every reschedule
      recomputes from the calendar and a window already under way is not an
      upcoming opening.
- [x] Tap routes to the pack via `biblecrossword://pack?id=…` (new
      `UNUserNotificationCenterDelegate` on `NotificationService`, drained by
      `RootView` through the same handler as any other deep link).

**Acceptance**
- ✅ Seasonal packs already lead the Home carousel; the badge now says how long
  they have.
- ✅ `pack_opened` carries `source` — `home` / `packs` / `notification`, as a
  `PackOpenSource` on the pushed `PackRoute` rather than a bare string.

---

## Out of scope

- Server-driven pack downloads
- Unlimited AI-generated seasonal content
- Changing daily rotation index rules

## Open questions

- ~~Keep expired seasonal packs in Collections forever, or hide after window?~~
  Hidden — decided 2026-08-08.
- ~~Free teaser puzzle inside Premium seasonal packs?~~ No — decided 2026-08-08.
- Should a seasonal pack stay openable after its window for a player who started
  it mid-season? Today their progress survives but is unreachable until next
  year. Deferred until there's a complaint to act on.
