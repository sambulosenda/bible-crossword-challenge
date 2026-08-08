# Seasonal pack calendar

The twelve-month plan for seasonal content: which packs exist, when each is in
season, how many puzzles it needs, and whether it's free or Premium.

Ships alongside `docs/themed-packs-spec.md` (how packs work) and
`tools/README.md` (how to author and ship one).

## Decisions this calendar rests on

- **Seasons recur.** A pack declares a *rule*, not a pair of dates — see
  `PackSeason` in `Models/PuzzlePack.swift`. Nothing in this calendar needs
  re-dating in 2027, 2028 or 2041. The only reason to edit `packs.json` again is
  to change the content or the window itself.
- **Expired means hidden.** A seasonal pack out of window does not appear
  anywhere: not in Collections, not on Home, not as a locked teaser. A pack that
  will be back in eleven months is not a purchase reason today, and a permanent
  row of dead-end teasers would crowd out the packs a player can actually open.
- **No free teaser inside a Premium pack.** Every seasonal pack is Premium in
  full. The free lead-in is `first-steps`, which stays the one free pack — a
  seasonal pack whose first puzzle is free would be a second free surface with
  none of the same purpose, and the paywall already has the season to argue with.
- **Dedicated, not overlay.** Every pack below is authored as `pack-<slug>-NNN`
  content that never enters the daily rotation. The whole retention argument is
  *new* content arriving on a date; recycling four dailies into a Lent pack gives
  a returning player nothing they haven't already solved.

## The year

Windows are the rule as written in `packs.json`. "Ship by" is a content
deadline — the build must be **live on the App Store**, so allow for review.

| Quarter | Pack | Slug | Season rule | Runs (2027) | Puzzles | Tier | Ship by | Status |
|---|---|---|---|---|---|---|---|---|
| Q1 | Lent | `lent` | `easter(-46, -1)` | 10 Feb – 27 Mar | 5 | Premium | 13 Jan | `[x]` |
| Q1/Q2 | Easter | `easter` | `easter(-7, +7)` | 21 Mar – 4 Apr | 5 | Premium | 21 Feb | `[x]` |
| Q3 | Summer (VBS-style) | `creation` | `annual(07-01, 08-15)` | 1 Jul – 15 Aug | 5 | Premium | 1 Jun | `[ ]` |
| Q4 | Advent | `advent` | `annual(12-01, 12-26)` | 1 – 26 Dec | 6 | Premium | 1 Nov | `[x]` |
| Q4/Q1 | Christmas | `christmas` | `annual(12-26, 01-06)` | 26 Dec – 6 Jan | 5 | Premium | 1 Nov | `[x]` |

Easter moves — 28 March 2027, 16 April 2028, 1 April 2029 — which is exactly why
`easter(from:to:)` counts days from it rather than naming dates. Lent and Easter
shift with it automatically; the "Runs" column above is 2027 for illustration.

### Why these five

- **Lent** and **Easter** are the largest re-engagement window in the Christian
  year, and the app had nothing in it.
- **Advent** shipped as two overlay puzzles, which is a pack in name only. Six
  is the minimum that reads as a countdown.
- **Christmas** picks up where Advent stops, so December ends with a handoff
  rather than a cliff. The windows share exactly one day: `advent` closes on the
  26th and `christmas` opens on it, so on Boxing Day both are in season — one
  reading "Last day", the other "11 days left". That overlap is the handoff, and
  it's the only day the app shows two seasonal packs at once.
- **Summer** is the one non-liturgical slot, and the quarter with no other
  anchor. VBS-style: creation, Noah, Jonah — the stories children's programmes
  run in July.

### Deliberately not on the calendar

Pentecost, Reformation Day, Thanksgiving, Harvest. Each is defensible; five
seasonal packs a year is already 26 new puzzles on top of the daily bank, and a
calendar that isn't met is worse than a shorter one that is. Revisit once two
consecutive packs have shipped on time.

## Per-pack briefs

### `lent` — Lent ✅ shipped
Journey to the cross, reflective rather than grim: repentance (Joel 2), the
wilderness (Matthew 4), the prodigal (Luke 15), the basin (John 13), the garden
(Matthew 26). The Prodigal Son sits at the centre on purpose — forty days of
dread would sit badly next to a daily puzzle habit. Cover `leaf` (Ash Wednesday
ashes are burnt palms), accent `#6B5B95`.

Lent's window runs to Easter Eve and Easter's opens on Palm Sunday, so the two
overlap through Holy Week. That is deliberate: the week belongs to both, and
neither pack repeats the other's chapters.

### `easter` — Easter ✅ shipped
Palm Sunday through the week after, in narrative order and rising difficulty:
the triumphal entry (Matthew 21), the cross (John 19), the empty tomb and
Thomas (John 20), the road to Emmaus (Luke 24), breakfast by the sea (John 21).
Cover `sunrise`, accent `#C8912B`. One passage per puzzle, so every clue can be
checked against a single chapter.

### `creation` — Wonders of Creation
Summer, family-facing. Creation week, Noah, Jonah, Daniel, David and Goliath —
the stories that carry a vacation Bible school. Easier difficulty skew than the
other packs. Cover `leaf.circle` or `globe.europe.africa`, accent green
(`#2F7D4F`).

### `advent` — Advent ✅ shipped
Six dedicated puzzles replacing the two overlay dailies: Isaiah 9, the
annunciation, the Magnificat, Joseph's dream, the census journey, the shepherds
and the heavenly host. Keeps `#1F6F54`. The two retired overlays (`daily-019`,
`daily-028`) stay in the daily rotation, so the pack's vocabulary steers clear
of theirs.

### `christmas` — Christmas ✅ shipped
The twelve days: the Word made flesh (John 1), Simeon and Anna, the star in the
east, the flight into Egypt, the boy of twelve in the temple. Cover `star`,
accent `#2E4A8E`. Titled "Christmas", not "Christmastide" — the longer word
hyphen-breaks in a card row that also carries a crown and a countdown.

## Windows at a glance

```
Jan   Feb   Mar   Apr   May   Jun   Jul   Aug   Sep   Oct   Nov   Dec
├─christmas─┤
      ├────lent────┤
              ├─easter─┤
                                ├────creation────┤
                                                        ├──advent──┤
                                                                 ├─christmas→
```

Two gaps by design — May–June and September–October carry no seasonal pack, so
the evergreen collections and the daily rotation have the floor.

## Open (deferred, not blocking)

- Whether a seasonal pack should stay openable *after* its window for players
  who already started it mid-season. Today it disappears with their progress
  intact but unreachable until next year. Revisit if support mail says so.
- Whether `creation` should be free rather than Premium, as a family-facing
  acquisition play. Held until there's per-source paywall data from a full
  seasonal cycle.
