# Product roadmap

Rewritten 2026-11-07 after an audit: the August plan had mostly shipped, and the
levers the data points at had no epic. Engineering work around these lives in
`../ENGINEERING_ROADMAP.md`.

**Principles**
- Offline-first, bundled content. No backend / accounts unless unavoidable.
- Calm daily habit first; social + Premium second.
- Build on what retained players use: memory verses, packs, quests.
- ~14 installs/day: nothing can be A/B tested. Judge before/after on the cohort,
  2 weeks after a release, with the denominator pinned.

## What the data says (as of 2026-11)
- **Activation is the lever.** Finish a puzzle on day 0 → 74% return; don't → 27%.
  ~Half of day-0 abandoners never touch the grid and leave inside 10 s.
- **Premium has no reason for daily players.** In-app walls sell ~nothing; trials
  come from onboarding. "More puzzles" doesn't matter to someone who plays once a day.
- **Install volume caps revenue**, not paywall conversion.
- **Not levers:** notifications, the Read tab, puzzle chips, the widget (0 opens / 30d).

## Priority order

| # | Theme | Goal | Measure | Status |
|---|-------|------|---------|--------|
| A | **First touch v2:** show the mechanic on the first real grid instead of a banner. Read first-solve replays first. Adaptive difficulty (backlog) belongs here. | Activation | Day-0 completion of starters; zero-touch abandons | `[ ]` |
| B | **A reason to buy Premium:** built around memory verses, quests, packs, not puzzle volume | Revenue | Trials from non-onboarding sources; trial→paid | `[ ]` |
| C | **Acquisition:** ASO, web Mini → app handoff, App Clip for challenge links (backlog) | Installs | Installs/day; ASC Sources + `ct=` campaigns | `[ ]` |
| D | **Content cadence:** December batch done (fresh to 2027-01-01); next batch must land before **2027-01-02** | Retention | Wrap dates below stay ≥ 30 days out | `[~]` |
| E | **Small wins** (one per release) | — | — | `[ ]` |

**E — small wins**
- [ ] Turn on Family Sharing for the subscription in ASC (from 06; a switch, not a SKU)
- [ ] Journey milestones (05 T3)
- [ ] Dedicated Sunday Special events (17 T7)
- [ ] Game Center weekly explainer (02 T5)

## Dated

The daily and mini pools rotate with `daysSinceEpoch % pool.count` from a
2026-07-01 epoch, so they wrap and start repeating on fixed dates. Re-record these
whenever puzzles are added — every daily added moves the first date by one.

| Pool | Size | Wraps |
|------|------|-------|
| Dailies | 143 | wrapped 2026-10-01 at 92; new served 2026-11-12 → 2027-01-01 via `schedule.json` (31 December batch from 2026-12-02; Born This Day on 12-25) |
| Minis | 148 | wrapped 2026-10-06 at 97; new served 2026-11-12 → 2027-01-01 via `schedule.json` |
| Sundays | 21 | 2026-11-08 repeats (shipped builds); new served 2026-11-15 → 2027-01-03 via `schedule.json` |

`RotationWrapTests` asserts both pool sizes and both dates, so adding content
fails the suite until these are re-recorded — the table can't quietly go stale.

## Done / dropped (August plan)

| # | Epic | Outcome |
|---|------|---------|
| 01 | Seasonal packs + cadence | Done 2026-08-08; cadence continues as D |
| 02 | Challenge history / family | T1–T4 shipped; T5 → E |
| 03 | Post-solve scripture loop | Built as reader chips, **removed** 2026-10-03 (1.8% tap rate) |
| 04 | Pencil / check / a11y | Shipped (`GameViewModel.check`, pencil). Epic file not updated |
| 05 | Bible journey map | T1, T2, T4 shipped; T3 → E; T5 dropped with 03 |
| 06 | Family Premium / gift | Multi-seat SKU dropped; Family Sharing switch → E |
| 07 | Onboarding paywall fix | Done |
| 08 | Main paywall polish | Done |
| 09 | Free archive soft gate | Done |
| 10 | Widget deep links | T1–T4 shipped; T5 dropped (widget 0 opens / 30d) |
| 11 | Streak comeback | Done |
| 12 | Ads honesty | Done (no ads) |
| 13 | Daily rotation wrap | Solved by `schedule.json` + `RotationWrapTests`; ongoing as D |
| 14 | Premium content value | Catalog done; didn't create a reason to buy → B |
| 15 | Verse hint | Shipped; the most-used assist |
| 16 | Notification opt-in | Done; data says notifications aren't a retention lever |
| 17 | Sunday Special | T1–T6 shipped; T7 → E |

Epic files 01–17 are kept as history. New themes get new files (`A-…md` etc.)
when work starts.

## Status legend
`[ ]` todo · `[~]` in progress · `[x]` done · `—` blocked / deferred

## Related
`BACKLOG.md` (parking lot) · `docs/themed-packs-spec.md` · `docs/friend-challenge-spec.md` · `docs/clue-references-spec.md`
