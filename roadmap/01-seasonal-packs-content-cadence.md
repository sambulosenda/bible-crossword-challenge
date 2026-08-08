# Epic 01 — Seasonal packs + content cadence

**Priority:** 1  
**Goal:** Retention + Premium  
**Status:** `[ ]`  
**Depends on:** Existing pack system (`packs.json`, `PuzzlePack`, dedicated `pack-*` puzzles)  
**Related:** `docs/themed-packs-spec.md`

## Why

Pack infra + Advent window already ship. Seasonal packs = re-engagement spikes and a *content* reason for Premium, not just ad-removal / unlimited hints.

## Success metrics

- Pack open / complete rates (`pack_opened`, `pack_completed`)
- Seasonal window DAU lift vs non-seasonal weeks
- Paywall open + purchase from pack-gated surfaces

---

## Tickets

### P1-T1 — Content calendar (editorial)

**Status:** `[ ]`  
**Type:** content / process  
**Estimate:** S

- [ ] Define 12-month pack calendar (ship windows + marketing dates)
- [ ] Minimum: Easter, Christmas, Lent, one summer VBS-style pack
- [ ] Document “overlay vs dedicated” per pack (reuse dailies vs new `pack-*` puzzles)
- [ ] Assign free vs Premium (`isPremium`) + `availableFrom` / `availableTo`

**Acceptance**
- One markdown or sheet with Q1–Q4 windows, pack slugs, puzzle counts, free/premium flags

---

### P1-T2 — Easter pack (dedicated puzzles)

**Status:** `[ ]`  
**Type:** content + light app  
**Estimate:** M

- [ ] Spec 4–6 Easter / Resurrection puzzles in `tools/puzzle_specs.json` with `"pack": "easter"`
- [ ] Generate + ship in `puzzles.json` as `pack-easter-*` (never daily-rotated)
- [ ] Add entry to `packs.json` with spring window (e.g. Palm Sunday → Easter+7)
- [ ] Cover symbol, blurb, accent; Premium unless intentionally free lead-in
- [ ] Achievements reconcile still works for new pack id
- [ ] Tests: pack resolves, excluded from daily/archive pool, seasonal gate

**Acceptance**
- Easter pack visible only in window (or always-available archive after season — decide + document)
- Completing last puzzle marks pack complete + optional completion card “Next in pack”

---

### P1-T3 — Christmas pack (expand beyond Advent)

**Status:** `[ ]`  
**Type:** content  
**Estimate:** M

- [ ] Audit current Advent pack (2 puzzles) — expand Advent and/or add `christmas` pack
- [ ] Target 5+ dedicated puzzles for Dec window
- [ ] Align windows so Advent → Christmas handoff feels intentional on Home carousel

**Acceptance**
- Seasonal carousel surfaces Christmas content in Dec without crowding non-seasonal packs off entirely

---

### P1-T4 — Lent pack

**Status:** `[ ]`  
**Type:** content  
**Estimate:** M

- [ ] 4–5 dedicated Lent / journey-to-the-cross puzzles
- [ ] Seasonal window Ash Wednesday → Easter Eve
- [ ] Tone: reflective, not grim; fit calm brand

**Acceptance**
- Pack live in window; completion share card uses pack title

---

### P1-T5 — Cadence pipeline (tooling)

**Status:** `[ ]`  
**Type:** eng  
**Estimate:** S

- [ ] Document author → generate → test → ship checklist in `tools/README.md`
- [ ] Optional: CI or script validates `packs.json` ids resolve, no daily-pool leakage for `pack-*`
- [ ] Optional: difficulty / answer-overlap sanity checks for new specs

**Acceptance**
- New pack can be shipped by following one short checklist without tribal knowledge

---

### P1-T6 — Seasonal surface polish

**Status:** `[ ]`  
**Type:** eng / design  
**Estimate:** S

- [ ] Home carousel: seasonal packs first (already partial) + “Ends soon” / days-left badge
- [ ] Paywall: mention *this season’s pack* when opened from a locked seasonal pack
- [ ] Push or in-app banner once when a seasonal pack *opens* (respect notification prefs)

**Acceptance**
- User can discover seasonal pack from Home without hunting Collections
- Analytics: pack_opened source includes home / packs / notification

---

## Out of scope

- Server-driven pack downloads
- Unlimited AI-generated seasonal content
- Changing daily rotation index rules

## Open questions

- Keep expired seasonal packs in Collections forever, or hide after window?
- Free teaser puzzle inside Premium seasonal packs?
