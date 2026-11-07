# Theme B: a reason to buy Premium (proposal)

Status: B1 + B2 built 2026-11-07 (ship with the December release). B3, B4 not started.

## Where Premium stands
Premium already gates the things retained players use:
- Memory verses: 3 unmastered free, unlimited with Premium.
- Packs: 1 of 10 free (First Steps).
- Journeys: 2 of 4 free (First Seven, Beginnings).
- Plus every past daily, Sunday Specials, unlimited hints.

So the gap isn't *what* is Premium. It's *when and how* players meet it.

## What the last 30 days say (2.15+, test devices out)
| Source | Saw paywall | Bought | Rate |
|---|---|---|---|
| Onboarding | 275 | 13 | 5% |
| Today upgrade card (`home_card`) | 13 | 4 | **31%** |
| Locked Journey (`quest_locked`) | 14 | 2 | **14%** |
| Hint limit (`hint_limit_card`) | 46 | 1 | 2% |
| Archive / packs / other | ~30 | 4 | ~13% |

24 purchases, 11 of them outside onboarding. **Showing specific content sells, blocking a player doesn't.** The Today card and locked Journeys convert at 14–31%. The hint wall converts at 2%. The catch is reach: only 13 people saw the Today card.

## Proposal: put Premium content in front of engaged players
Ranked by value per effort.

**B1. Graduation offer, after Your First Seven** (small)
- The 7th path completion is a natural "what's next" moment. Today the path deliberately shows no Premium offer.
- On graduation: "You've finished your first seven. Keep going with a Journey." Show one Premium Journey and one pack, with the trial.
- One ask, once, in the completion flow. No sheet.

**B2. More reach for what already converts** (small)
- The Today upgrade card and locked Journeys convert, but few people see them.
- After the day's puzzle is done, Today shows a "Continue" row with the next step of a Journey or pack (locked ones labelled Premium).
- This turns the daily finish into a moment to meet content, not a dead end.

**B3. A new pack every month** (content, ongoing)
- Pairs with theme D's monthly batch: each month one new Premium pack with a "New" badge on Today.
- Gives Premium a reason to exist for daily players: "new content for members".

**B4. Memory verses as a daily habit** (bigger, later)
- Memory users are the stickiest group (D7 ~50%).
- Premium gets a review queue (verses due today) and a gentle daily reminder; free stays at 3.
- Build only if B1–B2 show people respond to Premium content.

## Not doing
- More hint walls or stricter free limits (hint wall sells 2%; the 1-hint experiment showed walls just block).
- Auto paywalls on completion (removed 2026-09; don't re-add).
- Price changes (price affected trial starts, not conversion).

## Built (2026-11-07)
- **B1:** a crown row under Your First Seven's finished card, "Next: Life of David, a 9-step Journey" → paywall `path_graduation`. Free players only. Impression `upsell_shown:path_graduation` once, when on screen. Holds the widget line that sitting.
- **B2:** once the day's puzzles are solved, Today's hero swaps Play again for "Next: <Journey>" → the Journey page (`quest_opened` source `today_hero`; locked pages sell via `quest_locked`). Skipped if a step was taken today. Keep going drops that Journey's row so it isn't listed twice. Locked impressions log `upsell_shown:today_hero`.
- UI tests for both. DEBUG `-uiFree` launches as a free player; `-uiCleanSlate` now skips Game Center sign-in so UI tests stop failing at random.

## How we'll know
- Purchases from non-onboarding sources: 11 per 30 days now. Target 20+.
- Paywall opens from `home_card`, `quest_locked`, and the new graduation source.
- Read 2 weeks after each change ships. ~14 installs/day means before/after on the cohort, no A/B.

## Questions for Sambulo
1. Start with B1 + B2 together (both small), or B1 alone first?
2. B3: are you up for one new pack a month (5 puzzles), on top of the monthly daily/mini batch?
3. B4: is a verse review reminder OK, given notifications aren't a retention lever for puzzles?
