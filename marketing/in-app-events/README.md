# December In-App Events

Two App Store In-App Events for December 2026. They show as cards in App Store
search results and on the product page: extra impressions for free, which is
the install lever (store conversion is already 11.2%, top quartile for word
apps; see memory `acquisition-readout-2026-11`).

Set up in **App Store Connect → Apps → Bible Crossword Challenge → In-App Events → +**.
Events need App Review approval, so **submit the Advent event by ~Nov 13** so it can
start promoting on Nov 17. Submit the Christmas event by ~Dec 7 for its Dec 12
promote date.

Every text field below is within Apple's limits (name ≤30, short ≤50, long ≤120).
Use the same text for en-US, en-GB, en-CA and en-AU.

---

## 1. Advent Puzzle Journey

**Status 2026-11-16:** SUBMITTED, Waiting for Review (submitted Nov 16, 2:43 PM,
submission id 77b3abeb-a032-4cd9-afd6-3b289869a5a0, review note pasted). Fields
re-checked against the table below before submitting; all matched.

**Status 2026-11-12:** drafted and saved in App Store Connect (event id
6834042545), not yet added for review. As entered: primary language English
(U.K.), times in GMT, start Dec 1 00:00, end Dec 26 00:00 (the picker has no
23:59), publish from Nov 17 00:00. Paste the review note below on the
submission page after pressing Add for Review.

| Field | Value |
|---|---|
| Reference name | Advent 2026 |
| Event name | **Advent Puzzle Journey** (21) |
| Short description | **Count down to Christmas, one puzzle at a time** (45) |
| Long description | **Free Advent crosswords through December, from Zechariah to the manger, with a Christmas Day puzzle. More with Premium.** (118) |
| Badge | Special Event |
| Purpose | Appropriate for all users |
| Event start | Dec 1, 2026, 00:00 (local time) |
| Event end | Dec 25, 2026, 23:59 (local time) |
| Publish (promote) from | Nov 17, 2026 (the 14-day maximum) |
| Priority | Normal |
| Deep link | `biblecrossword://today` (opens Today, where the free daily is) |
| Requires in-app purchase | **No**: the core is free (see below) |
| Event card media (16:9) | `advent-card-1920x1080.png` |
| Event details media (9:16) | `advent-detail-1080x1920.png` |

**Why "no purchase required" is honest:** the free daily rotation carries Advent
content all month (checked 2026-11-12 against `schedule.json` in the live 2.21
build). Dailies: Your Prayer Has Been Heard, the Zechariah story (Dec 6), A
Shoot from Jesse (Dec 13), The Son of David (Dec 20), O Little Town (Dec 22),
His Name Is John (Dec 23), His Name Shall Be (Dec 24), Born This Day (Dec 25).
Minis: Like a Refiner's Fire (Dec 6), Prepare the Way (Dec 13), Comfort My
People (Dec 20), Gifts for a King (Dec 24), When the Time Had Come (Dec 25).
Sunday Specials, free in their week: Promises Kept (Dec 13) and The First
Christmas (Dec 20). The Advent pack (6 puzzles) is the Premium extra, and the
long description says so ("More with Premium").

The link lands on Today, not on the Advent pack: the event is marked "no
purchase required", so it must not open on a Premium screen.

Known gap: the first Advent-themed free puzzle is Dec 6. Dec 1–5 the free
daily is an ordinary one and the only Advent content is the Premium pack.

**Review note (paste into the event's notes for App Review):**
> Free Advent-themed daily crosswords run through December (first on Dec 6,
> then Dec 13, 20, 22, 23, 24 and 25). The link opens the Today screen, where
> each day's free puzzle appears. No purchase is needed to take part.

## 2. Twelve Days of Christmas

| Field | Value |
|---|---|
| Reference name | Christmas 2026 |
| Event name | **Twelve Days of Christmas** (24) |
| Short description | **From the manger to the temple, one a day** (40) |
| Long description | **Five Christmas crosswords for the twelve days: the Word made flesh, the star, the magi, Simeon and Anna, and more.** (114) |
| Badge | Special Event |
| Purpose | Appropriate for all users |
| Event start | Dec 26, 2026, 00:00 (local time) |
| Event end | Jan 6, 2027, 23:59 (local time) |
| Publish (promote) from | Dec 12, 2026 |
| Priority | Normal |
| Deep link | `biblecrossword://pack?id=christmas` |
| Requires in-app purchase | **Yes**: the Christmas pack is Premium |
| Event card media (16:9) | `christmas-card-1920x1080.png` |
| Event details media (9:16) | `christmas-detail-1080x1920.png` |

The deep link only opens the pack while it's in season (Dec 26 – Jan 6,
`PackSeason` in packs.json), which is exactly the event window. Outside it the
app opens Today.

**Review note (paste into the event's notes for App Review):**
> The Christmas collection unlocks on Dec 26, the day the event starts. Before
> that date the link opens the Today screen. The collection is part of Premium.

---

## Seasonal keywords (need an editable app version)

Keyword fields only change with an app version. 2.22 was already "Waiting for
Review" on 2026-11-12, so its keywords are locked. **Decided 2026-11-12: ship
them with 2.23**, and leave 2.22 in review. 2.23 must be approved by Dec 1, so
submit it by ~Nov 25.
Edited in `fastlane/metadata` on 2026-11-12, not yet pushed to App Store Connect.

| Locale | Out | In | Why |
|---|---|---|---|
| en-US (also read by UK) | gospel, learn | christmas, advent | Both out-words unranked since June. In: "christmas crossword" (popularity 20, difficulty 13), "advent" (34, 17) |
| en-CA | easter, learn | christmas, advent | Easter is out of season; "learn" unranked in CA |
| en-AU | easter | advent | Already had christmas |

Push with `bundle exec fastlane push_text_fields version:2.23 fields:keywords`
(export `LANG`/`LC_ALL=en_US.UTF-8` first).

**Revert in the first release after Jan 6**: christmas/advent out, easter back in
ahead of Lent (Feb 10, 2027).

## Promotional text (no review, change on the day)

- **Dec 1** (135): Advent: free Advent crosswords through December, a Christmas Day puzzle on the 25th, and a new Bible crossword every day. No ads, ever.
- **Dec 26** (128): The Twelve Days of Christmas: five crosswords from the manger to the temple, plus a new Bible crossword every day. No ads, ever.
- **Jan 7**: back to the standing text in `fastlane/metadata/en-US/promotional_text.txt`.

---

## Checks before submitting
- The live app version must handle the deep links. Both are handled by the live
  2.21 build: `biblecrossword://pack?id=` has shipped for months, and
  `biblecrossword://today` falls through to the Today tab (`RootView`).
- Media is PNG, RGB, no transparency, and carries no text beyond the crossword
  tiles. The App Store prints the event name on the card.
- Both crosswords are valid: every crossing letter matches, and no accidental
  words form (checked when rendered).

## Measuring
App Store Connect → App Analytics → **In-App Events**: impressions, opens, and
downloads from the event. Compare December's App Store search impressions with
October's (292 product page views and ~270 first-time downloads, Oct 8 – Nov 6).

Images are rendered by a script (crossword tiles in each pack's colour, a
star, soft glow). Ask Claude to regenerate them if the art needs to change.
