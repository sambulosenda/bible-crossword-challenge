# Product roadmap

Prioritized feature epics for Bible Crossword Challenge. Each file is a grab-able epic with sub-tickets.

**Principles (match existing app)**
- Offline-first, bundled content
- No backend / accounts unless unavoidable
- Reuse packs, challenges, CloudKit progress, premium
- Calm daily habit first; social + Premium second

## Priority order

Dated work first — 13 has a hard deadline that the rest do not.

| # | Epic | Goal | File |
|---|------|------|------|
| 13 | **Daily rotation wrap** — due **2026-09-29** (minis) / **2026-10-01** (dailies) | Streak-break event | [13-daily-rotation-wrap.md](./13-daily-rotation-wrap.md) |
| 1 | Seasonal packs + content cadence | Retention + Premium | [01-seasonal-packs-content-cadence.md](./01-seasonal-packs-content-cadence.md) |
| 2 | Challenge history / family challenge | Growth | [02-challenge-history-family.md](./02-challenge-history-family.md) |
| 3 | Deeper post-solve scripture loop | Positioning | [03-post-solve-scripture-loop.md](./03-post-solve-scripture-loop.md) |
| 4 | Pencil/check + larger grid / a11y | Audience expansion | [04-pencil-check-a11y.md](./04-pencil-check-a11y.md) |
| 5 | Bible journey map | Long-term engagement | [05-bible-journey-map.md](./05-bible-journey-map.md) |
| 6 | Family Premium / gift | Revenue | [06-family-premium-gift.md](./06-family-premium-gift.md) |
| 7 | Onboarding paywall fix | First-run trial + trust | [07-onboarding-paywall-fix.md](./07-onboarding-paywall-fix.md) |
| 8 | Main paywall polish | Conversion + honesty | [08-main-paywall-polish.md](./08-main-paywall-polish.md) |
| 9 | Free archive soft gate | Fairness + reviews | [09-free-archive-soft-gate.md](./09-free-archive-soft-gate.md) |
| 10 | Widget deep links | Habit loop | [10-widget-deep-links.md](./10-widget-deep-links.md) |
| 11 | Streak break / comeback | D1–D7 retention | [11-streak-comeback.md](./11-streak-comeback.md) |
| 12 | Ads: ship or strip claims | Free-tier $ / honesty | [12-ads-honesty-or-ship.md](./12-ads-honesty-or-ship.md) |
| 14 | **Premium content value** — earn “all packs + every new one” | Trial→paid / catalog | [14-premium-content-value.md](./14-premium-content-value.md) |
| 15 | Verse hint (“Show the Verse”) | Scripture in the solve loop | [15-verse-hint.md](./15-verse-hint.md) |

## Dated

The daily and mini pools rotate with `daysSinceEpoch % pool.count` from a
2026-07-01 epoch, so they wrap and start repeating on fixed dates. Re-record these
whenever puzzles are added — every daily added moves the first date by one.

| Pool | Size | Wraps |
|------|------|-------|
| Dailies | 92 | 2026-10-01 |
| Minis | 90 | 2026-09-29 |

`RotationWrapTests` asserts both pool sizes and both dates, so adding content
fails the suite until these are re-recorded — the table can't quietly go stale.

**The mini pool now wraps first**, on 29 September, two days before the dailies.

## Status legend

- `[ ]` todo
- `[~]` in progress
- `[x]` done
- `—` blocked / deferred

## Related specs

- `docs/themed-packs-spec.md`
- `docs/friend-challenge-spec.md`
- `docs/clue-references-spec.md`

## Current baseline (shipped)

- Daily full + daily mini
- Packs: First Steps, Life of David, Parables, Psalm 23, plus four seasonal —
  Lent, Easter, Advent, Christmas — on recurring windows (`PackSeason`)
- Streaks + freezes, achievements, hints, paywall
- Friend “beat my time” challenges (URL, no backend)
- Scripture reader + post-solve clue refs (partial)
- Widget, Game Center mini leaderboard, share cards, CloudKit sync
