# Ticket 08 — Main paywall polish

**Priority:** high (pairs with 07)  
**Status:** `[ ]`  
**Type:** eng / copy  
**Estimate:** M  
**Files:** `Views/PremiumOfferView.swift`, `Views/PaywallView.swift`, `Products.storekit`, App Store Connect product copy  
**Related:** 07 onboarding paywall, Library locked preview, Premium packs

## Problem

Main `PaywallView` is strong on craft, but still leaves conversion on the table and has honesty drift:

1. Comment promises **locked packs below** benefits — UI never shows them (Library does a locked preview; paywall doesn’t).
2. Auto sources **`first_completion`** / **`streak_3`** fall through to generic headline (`PremiumCopy.promise`) — high-volume opens, weak moment match.
3. ~~StoreKit / ASC product descriptions still say **“Remove ads”** while benefits intentionally dropped ads (ads aren’t live — see 12).~~ **Done in `151671a`** (T3). ASC was already correct — the claim only ever existed in the local `.storekit` fixture.
4. Benefit lines slightly overclaim “all N puzzles unlocked” when free already has daily — archive + packs + hints is the real delta.

## Goal

Make the main paywall show **withheld content**, match **source-specific** moments, and **align product copy** with what Premium actually is — without redesigning the whole sheet or changing prices.

**Out of scope:** Family plan (06), onboarding page (07), changing free-tier rules (09), wiring AdMob (12).

---

## Tasks

### T1 — Locked packs strip on paywall

**Status:** `[ ]`

- [ ] Below benefits (or between benefits and plans), show 2–3 Premium packs that are locked for free users
- [ ] Reuse pack title, symbol/accent, progress if any; lock affordance
- [ ] Tap either opens pack detail (then lock CTA) or is non-navigating preview — pick one and stay consistent with Library
- [ ] Hide strip when `premiumPackCount == 0` or user already Premium
- [ ] Don’t push CTA below fold: keep pinned purchase bar; strip must not break SE layout (scroll OK)

**Acceptance**
- Free user opening `source: pack_locked` or `home_card` sees named packs they don’t have
- VoiceOver: strip has a coherent label (“Premium collections locked”)

---

### T2 — Source headlines for auto + missing entries

**Status:** `[x]`

Extend `PaywallView.Entry` / `headlineText`:

| source | Suggested direction |
|--------|---------------------|
| `first_completion` | Celebrate first solve → more waiting (not generic brand line) |
| `streak_3` | Habit formed → unlock the rest / protect the habit |
| `profile` | Optional: same as default or “Your Premium” framing |
| `onboarding` | N/A if only soft page; if full sheet ever used, trial-forward |

- [x] Keep existing entries (`hint_limit`, `completion`, `pack_*`, `home_card`, `archive`) — untouched
- [x] Unknown sources still fall back to `PremiumCopy.promise` (no blank hero) — the failable `init(rawValue:)` still does this

Shipped headlines:

| source | headline |
|--------|----------|
| `first_completion` | “That’s your first. The rest are waiting.” |
| `streak_3` | “A habit needs more than one a day.” |
| `mini_completion` | “Two minutes was just the start.” |

`streak_3` names the actual reason Premium matters at that moment: the habit
just formed runs on one puzzle a day, which is exactly what free gives.

**`profile` deliberately left on the default.** The table marked it optional,
and `headlineText` already carried a reasoned comment for it — a player who
hasn’t hit a wall needs telling what the app is for, not what it withholds.
Overriding that on an “optional” line would have been the wrong trade.
**`onboarding` needs no case**: it never reaches `PaywallView`, its premium
page is part of `OnboardingView`. Comment corrected to say so.

> **Audit note (2026-08-08).** The table above is right — `first_completion`
> and `streak_3` are real, auto-presented from `maybeAutoShowPaywall`
> (`CompletionView.swift:538`), each firing once ever at the highest-intent
> moment there is, and both fall through to the generic line. One source the
> table misses: **`mini_completion`** (`CompletionView.swift:335`) has no
> `Entry` case either. Full set of live sources with no case: `first_completion`,
> `streak_3`, `mini_completion`, `profile`, `onboarding`.

**Acceptance**
- `first_completion` and `streak_3` sheets show distinct heroes in UI
- Analytics `source` strings **unchanged** (history stays comparable)

---

### T3 — Align StoreKit / ASC copy with benefits

**Status:** `[x]` **Done** (`151671a` + ASC verified 2026-08-08)

- [x] Update `Products.storekit` localizations for monthly / yearly / lifetime
- [x] Mirror same wording in App Store Connect when shipping — checked 2026-08-08, ASC was already correct; nothing to change
- [x] Drop “Remove ads” — took the second option: accurate benefits, since 12 chose Path A and the ad scaffold is deleted
- [x] Lifetime description must not promise features free tier already fully has without naming the real unlocks — now names hints, archive and future packs

**Acceptance**
- [x] In-app product `description` / display names don’t contradict `PremiumBenefit.all`
- [x] ~~No “remove ads” claim while `AdProvider.isLive == false`~~ — unsatisfiable as written: `AdProvider` no longer exists. Met in substance, there is no ad-removal claim and nothing to remove

---

### T4 — Tighten benefit wording (light)

**Status:** `[x]`

- [x] Reframe first benefit toward **archive + replay**, not “all puzzles” in a way that fights free daily
- [x] Keep live counts from `puzzleProvider` / pack count — `puzzleCount` still interpolated
- [x] Shared `PremiumBenefit.all` still used by onboarding — both stay in sync, one edit changed both

Was: **“All \(puzzleCount) puzzles, unlocked”** / “Every daily, mini and themed
pack — replay any of them, any time.”
Now: **“\(puzzleCount) puzzles, not just today’s”** / “The whole archive, back
to the very first — replay any of them, any time.”

“Unlocked” described a state the reader was not in: free already gives a daily
and a mini, so the line invited them to go and check, find today’s puzzle
playable, and discount the other two rows with it. Naming the free tier inside
the offer is the only version a daily player can’t catch out.

The detail line also stopped reaching for packs, which row three already owns —
the ticket’s **archive + replay + packs** is now one row for archive and replay,
one for hints, one for packs, rather than row one restating row three.

**Acceptance**
- Onboarding + main paywall still share one benefit list
- Copy review: free daily player doesn’t feel lied to

---

### T5 — Optional: pack-locked entry polish

**Status:** `[ ]`

- [ ] When `source == pack_locked`, prefer highlighting **that** pack first in the strip (if pack id can be passed — may need optional `contextPackID` param; only if cheap)
- [ ] If passing pack id is invasive, skip — strip of premium packs is enough

---

### T6 — Offer layout + trial timeline

**Status:** `[x]`

Not in the original problem list — this ticket was written about honesty and
moment-matching, and the layout was the thing actually costing conversions. All
of it landed in `PremiumOfferView`, so it applies to **both** surfaces; the
onboarding page is ~91% of paywall views, so this is mostly an onboarding change.

Reference sweep on Mobbin (Babbel, Wolt, Centr, Deezer, Linktree, Open,
Everyday Rewards; trial timelines from Vocabulary, Mimo, Strava, Nibble,
Deepstash, Yazio) — the patterns below are where ours disagreed with all of them.

- [x] **Savings pill straddles the yearly card's top border** instead of taking a
      row inside it. As a row it had to be laid out invisibly on monthly too,
      purely to keep the two cards' baselines level — a whole line on each card
      to say nothing on one of them. Both cards got shorter.
- [x] **One selection language.** Plan cards signalled selection with tint +
      border, the lifetime row with a radio — the same screen taught "selected"
      twice. All three now carry the radio/check.
- [x] **Unselected plans are outlined on paper, not filled white.** They used
      `Theme.surface`, the same material as the benefits card directly above, so
      monthly read as more information rather than the other half of a choice.
      Exactly one white card remains on the page.
- [x] **Lifetime row shares the plan chrome.** Unselected it had no edge at all,
      so until you tapped it the third option read as a caption about the other two.
- [x] **Trial timeline** after the plans: `Today — full access to all N puzzles,
      you pay nothing` / `In <duration> — <price>/year begins, unless you cancel
      first`. Price, period and duration all come from the same product the CTA
      buys, so it cannot drift from the button.
- [x] Timeline is keyed to the **selected** plan, not to yearly — monthly and
      lifetime carry no introductory offer, and leaving it up would describe an
      offer the CTA isn't making.

**Two deliberate omissions**

1. **No "we'll remind you" step.** Every reference has it as the middle step;
   we don't have the reminder. `NotificationService` schedules the daily
   reminder, season openings and the streak nudge, and nothing for a trial —
   and notification permission is optional here, so even once one is scheduled
   the claim stays false for everyone who declined. Add the step only alongside
   a real trial reminder, and only for players who granted notifications.
2. **The dead band returns on monthly/lifetime**, which have no trial and so no
   timeline. Yearly is preselected so it's the uncommon path, and inventing a
   timeline for a plan that charges immediately would be a worse trade.

**Bug found in verification**

At accessibility text sizes the plans stack, and the straddling pill grew until
its lower half came down over the word "Yearly" — it can only hang over the edge
while it stays shorter than the card's top padding. Stacked, the cards are full
width and no longer share a baseline, so the badge goes back **in the flow** as
the card's first row and nothing needs to overhang. Fixed and re-verified.

**Acceptance**

- [x] Yearly and monthly cards are the same height with no phantom rows
- [x] Every option on the page uses the same selection mark
- [x] Timeline appears for yearly, disappears for monthly and lifetime
- [x] Timeline prices match the CTA and the commitment line exactly
- [x] Verified on the sheet and the onboarding page, default and
      accessibility-extra-large; onboarding still fits without scrolling
- [x] VoiceOver: cards combine to e.g. "Yearly, $9.99/year, $0.83/month, SAVE 58%";
      timeline steps combine to one label each
- [x] 170 tests pass

> **Note for T1.** The locked-packs strip wanted roughly the space the timeline
> now occupies. Its natural home is between the benefits card and the plans,
> which pushes the CTA further down — check SE and large Dynamic Type before
> committing to that placement.

---

## Analytics

No new events required. After ship, compare conversion by existing sources — especially `first_completion`, `streak_3`, `pack_locked`, `archive`.

## Test plan

- [ ] Open paywall from hint limit, archive, pack lock, home card, completion, first_completion, streak_3 — heroes differ where expected
- [ ] Pack strip visible free; gone when Premium
- [ ] SE + large Dynamic Type: CTA still pinned, content scrolls
- [ ] StoreKit config descriptions updated in local scheme test
- [ ] Purchase / restore unchanged

## Done when

Paywall shows **what’s locked**, speaks to **auto-open moments**, and **doesn’t claim ads** it doesn’t remove.
