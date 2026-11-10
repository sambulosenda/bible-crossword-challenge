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
| A | **First touch v2:** show the mechanic on the first real grid instead of a banner. Adaptive difficulty (backlog) belongs here. | Activation | Day-0 completion of starters; zero-touch abandons | `[~]` onboarding opens beginner path step 1 (5449e9f); first-puzzle replays readable + abandon diagnostics (22646db) |
| B | **A reason to buy Premium:** built around memory verses, quests, packs, not puzzle volume. See `B-premium-reason.md` | Revenue | Purchases from non-onboarding sources (11/30d → 20+); trial→paid | `[~]` B1 graduation offer + B2 solved-hero Journey built (50f4c99); paywall redesigned (f556654, 9b9855b); B3/B4 await answers |
| C | **Acquisition:** ASO, In-App Events, store localization, web Mini → app handoff, App Clip (backlog) | Installs | Installs/day; ASC Sources + `ct=` campaigns; event impressions | `[~]` December events ready (`marketing/in-app-events/`) |
| D | **Content cadence:** December batch done (fresh to 2027-01-01); January batch must land before **2027-01-02** | Retention | Wrap dates below stay ≥ 30 days out | `[~]` |
| E | **Small wins** (one per release) | — | — | `[ ]` |
| F | **Retention after D1:** D1 23% → D7 14%. Nothing targets it yet beyond B4 (memory verses, D7 ~50% for users) | Retention | D7 of day-0 finishers | `[ ]` not scoped |

**C — acquisition notes** (readout 2026-11-07: 94% of installs come from search; store page converts 11.2%, top quartile; the cap is impressions)
- [ ] December In-App Events: Advent (submit by ~Nov 13, promotes Nov 17) and Twelve Days of Christmas (promotes Dec 12). Sambulo submits.
- [ ] Store localization: none yet. Extra locales add impressions (es-MX / fr-CA keyword fields already used for US/CA).
- [ ] Keyword ranks ~Nov 18, 2 weeks after the 2.19 subtitle change (needs the Astro app open).

**E — small wins**
- [ ] Turn on Family Sharing for the subscription in ASC (from 06; a switch, not a SKU)
- [ ] Journey milestones (05 T3)
- [ ] Dedicated Sunday Special events (17 T7)
- [ ] Game Center weekly explainer (02 T5)

## Current state
- **Price:** $9.99/yr with a 3-day trial (since ~2026-10-05; trial 3 days as of 2026-11-04), plus monthly. Lifetime only for grandfathered buyers. Don't re-raise: the $12.99 test cost trial starts.
- **Android:** on hold since 2026-10-07. iOS only; spec vectors kept for later.

## Next release (December, must be live before 2026-12-02)
- Carries: December content batch, beginner-path first puzzle (A), B1 + B2, paywall redesign, replay + abandon diagnostics.
- Blockers: archive via Xcode Cloud (see `../ENGINEERING_ROADMAP.md`), or locally after freeing ~10 GB and reinstalling Xcode 27.1.

## Readouts (2 weeks after the December release, ~mid-Dec)
| What | Event / source | Bar |
|---|---|---|
| Instant abandons: real exits or detach artefacts? | `puzzle_abandoned.exit_path`, `puzzle_reattached` | Decide the fix |
| Hand-off kept (first puzzle not lost within 2 s of onboarding) | `daily_puzzle_started` source `onboarding_handoff`, then `puzzle_abandoned` | Zero lost, from 13 in the 45 days to 2026-11-10 |
| First puzzle finished on day 0, and D1 | beginner path `daily_puzzle_completed`, retention | Up vs pre-release cohort |
| Graduation offer (B1) | `upsell_shown` / `paywall_opened` source `path_graduation` | Taps ≥ 10% of impressions |
| Solved-hero Journey (B2) | `quest_opened` source `today_hero`, `upsell_shown:today_hero` | Reach > the old Today card (13 / 30d) |
| Paywall redesign | paywall CTA taps, purchase confirms | Taps > 13%, confirms > 37% |
| In-App Events | ASC App Analytics → In-App Events | Impressions and downloads vs October |

## Open questions (Sambulo)
- B3: one new Premium pack a month on top of the monthly batch?
- B4: a memory-verse review reminder, given notifications aren't a puzzle retention lever?

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
