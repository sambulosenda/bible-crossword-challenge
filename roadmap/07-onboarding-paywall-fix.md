# Ticket 07 — Fix onboarding paywall (trial + trust)

**Priority:** high (first-run conversion + trust)  
**Status:** `[x]`  
**Type:** eng / copy  
**Estimate:** S–M  
**File:** `Bible Crossword Challenge/Views/OnboardingView.swift`  
**Related:** `PaywallView.swift` (`PremiumCopy`, `PremiumBenefit`, trial CTA patterns), `StoreService`

## Problem

Onboarding Premium (page 4) is on-brand and review-safe, but under-sells the trial and under-explains free vs paid vs the main `PaywallView`:

- CTA is generic **"Start Free Trial"** — main paywall uses **"Start 7-day free trial"** (length is the persuasive bit)
- No trial accent under the hero (main paywall: “Start with a **7-day free trial** — pay nothing today”)
- Headline is only generic `PremiumCopy.promise` — ignores that they just finished first solve
- Free path only lives in the secondary button; nothing above the fold says daily stays free
- Benefit icons use fixed `34pt` frames; main paywall scales with `@ScaledMetric`
- Progress bar treats the sales page as setup step 5/5 (mild bait-and-switch feel)

## Goal

Match main-paywall **trial clarity** and improve **moment-specific trust**, without turning onboarding into a hard wall or adding plan pickers.

**Out of scope:** monthly/lifetime picker on onboarding; auto-presenting full `PaywallView` sheet; changing free-tier rules; Family Sharing.

---

## Tasks

### T1 — Trial-forward CTA + price line (parity with main paywall)

**Status:** `[x]`

- [x] When yearly has an intro offer, CTA = `"Start \(trial)"` using the same string `StoreService.introOfferText` already returns (e.g. “Start 7-day free trial”), **not** bare “Start Free Trial”
- [x] When no trial (already used / none configured), keep “Unlock Premium” (or equivalent non-trial copy)
- [x] Keep existing `priceLine` under CTA (trial → then price/period, cancel anytime); ensure it doesn’t contradict CTA length

**Acceptance**
- With intro offer loaded: primary button text includes trial **duration**
- Without intro offer: no “free trial” wording on the button
- `paywall_cta_tapped` still fires with `offersTrial: true/false` correctly

---

### T2 — Trial / free subhead under hero

**Status:** `[x]`

- [x] Under `PremiumCopy.promise`, when trial available, show a subhead matching main paywall intent, e.g.  
  `Start with a` + **accent/bold trial** + `— pay nothing today`
- [x] When no trial, show a quiet trust line instead, e.g.  
  `The daily puzzle stays free either way.`
- [x] Prefer reusing main-paywall wording patterns so the two surfaces don’t drift again

**Acceptance**
- Trial path: trial length visible above the benefits card without scrolling on a standard iPhone SE-class height (or as close as layout allows with Dynamic Type)
- Non-trial path: free-daily reassurance still visible

---

### T3 — Moment-aware headline (light)

**Status:** `[x]`

- [x] If first-solve step was completed (`solved == true`), use a completion-aware headline instead of only the generic promise, e.g.  
  `You got the idea. Keep the streak going.`  
  or  
  `One clue down. A library waiting.`
- [x] If they skipped first solve, keep `PremiumCopy.promise`
- [x] Do **not** invent fake stats (no “12 solved” — they have at most the onboarding mini)

**Acceptance**
- Skip vs solve produce different hero lines
- Tone stays calm / paper-brand (no shouty IAP language)

---

### T4 — Free-tier reassurance near CTA

**Status:** `[x]`

- [x] Keep **"Continue with the free daily puzzle"** as the secondary action (never hide or gray-out into oblivion)
- [x] Optional one-line caption above or below that button if T2 non-trial line isn’t enough: free daily + free mini still available without Premium
- [x] Confirm cancel / fail paths still work: cancel → finish onboarding; fail/pending → stay for alert; free button always exits

**Acceptance**
- Free exit tappable without scrolling on common phone sizes (controls already pinned — verify after T1–T2 content growth)
- App Review path: purchase surface still has Restore + Terms + Privacy

---

### T5 — Accessibility polish on benefits

**Status:** `[x]`

- [x] Benefit icon circle size uses `@ScaledMetric` (or equivalent) like `PaywallView.checkSize`, not hard-coded 34
- [x] Benefit rows still combine for VoiceOver; Dynamic Type XL doesn’t clip title/detail

**Acceptance**
- Extra Large content size: premium page scrolls if needed; primary + free CTAs remain usable

---

### T6 — Progress bar: don’t pretend Premium is “setup” (optional, small)

**Status:** `[x]`

Pick one:

- **A (preferred):** 4 setup segments only (welcome → solve → name → reminders); Premium page shows no filled “step 5” or a distinct treatment (e.g. no progress bar / different gold indicator)
- **B:** Keep 5 segments but kicker or eyebrow makes clear this step is optional Premium, not required setup

**Acceptance**
- Player can tell Premium is optional, not “finish setup by paying”

---

## Analytics (no new events required)

Existing is enough:

- `paywall_opened(source: "onboarding")`
- `paywall_cta_tapped(plan: "yearly", source: "onboarding", offersTrial:)`
- `premium_purchased` / `purchase_failed` via `StoreService`

After ship, compare **onboarding** CTA rate and trial starts vs pre-change baseline (same source string — history stays comparable).

---

## Implementation notes

- Touch primarily `premiumPage` + `premiumControls` (+ maybe progress bar) in `OnboardingView.swift`
- Reuse `store.introOfferText(for:)`, `store.periodText(for:)`, `store.yearly` — don’t re-parse StoreKit offers
- Consider extracting a tiny shared helper for “Start \(trial)” CTA title if both screens should stay identical (optional; avoid big refactor)
- `PremiumBenefit.all` stays shared — don’t fork benefit copy again

## Test plan

- [x] Fresh install, intro offer present: see duration in CTA + subhead; buy sandbox trial; lands in app Premium
- [x] Fresh install, skip first solve: generic headline; free path works
- [x] Fresh install, solve first clue: moment-aware headline
- [x] Cancel StoreKit sheet: onboarding finishes (current behavior)
- [x] Fail purchase: stay on page, notice alert, free button still works
- [x] Products fail to load: CTA disabled / safe; free path works
- [x] Dynamic Type accessibility sizes: no clipped legal row; scroll works
- [x] Restore on this page still restores entitlement

## Done when

Onboarding Premium matches main paywall on **trial length visibility**, states free daily clearly, keeps soft exit + legal, and (if T6) doesn’t frame the ask as mandatory setup.

---

## Ship notes

**Trial is 3-day, not 7.** The ticket's examples say "7-day" throughout; the shipped
offer has been 3-day since `e843a09`. Nothing was hardcoded either way — CTA and
subhead both take the string from `StoreService.introOfferText`, so the copy follows
whatever is configured in App Store Connect.

**Shared copy moved into `PremiumCopy`** (`trialCTA`, `trialSubhead`,
`freeDailyReassurance`) and the main paywall now reads from it too, rather than
onboarding copying the wording across. That's the optional helper in the
implementation notes — taken because this ticket exists to fix a drift that had
already happened twice (`promise`, `PremiumBenefit.all`).

**T6 chose option A**: four setup segments, and the bar turns gold on the offer page,
reusing the gold the canvas wash already switches to there.

**One fix beyond the listed tasks.** T4 flagged "verify after T1–T2 content growth" —
worth doing, because it found a real bug. The controls stack was the only thing that
gave when space ran short, so at accessibility text sizes on an SE the buttons
truncated instead of wrapping: `Start 3-day fr…`, and the renewal terms as
`Cancel an…`. Truncated purchase terms are an App Review problem, not just an ugly
one. `controls` is now `.fixedSize(vertical:)`, so the pages absorb the squeeze
instead — they can, each being its own ScrollView. This fixed every onboarding page,
not just Premium (`Remind me at 19:00` was truncating too).

**Verified** on iPhone SE at default and accessibility-extra-large, both paths:
solved (moment-aware headline) and skipped (generic promise). Not verified: an actual
sandbox purchase — per `storekit-purchase-testing`, simctl launches can't complete a
buy, so the trial-start leg of the test plan still needs an Xcode run against
`Products.storekit`.
