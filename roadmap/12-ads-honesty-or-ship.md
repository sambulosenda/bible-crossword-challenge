# Ticket 12 — Ads: ship real ads **or** strip all “no ads” claims

**Priority:** high if monetizing free tier / ASC honesty  
**Status:** `[x]` **Done** — Path A shipped in code, ASC verified clean 2026-08-08  
**Type:** eng / product / store copy  
**Estimate:** S (honesty-only) or L (ship AdMob)  
**Files:** `Services/AdProvider.swift`, `Views/Components/Components.swift` (`BannerAdView`), Home interstitial call sites, `Products.storekit`, ASC metadata, paywall benefits if ads return  
**Related:** 08 paywall polish (T3 ads copy), Premium positioning

## Problem

Free tier is wired for ads, but ads are **not live**:

- `NoOpAdProvider.isLive == false`
- `BannerAdView` is a yellow “Advertisement” **placeholder** only when `ads.isLive`
- Interstitial load/show exist on protocol; real SDK not integrated
- StoreKit product copy still says **“Remove ads”** in places
- Paywall benefits **correctly** omit ads (comment: add back only if AdMob wired)

Result: either free users never see ads (fine) while **store listing still promises ad removal**, or someone flips a flag later and ships placeholders. Both are bad.

> **Audit correction (2026-08-08).** Two of the claims above did not hold when
> checked. The **App Store listing was already clean**: `fastlane/metadata`
> across all six locales mentions ads nowhere, so the shipped product page never
> promised ad removal. And the “Remove ads” copy in `Products.storekit` is a
> local StoreKit **test fixture** — the app never renders `product.description`
> (no call site), so that string reached no user either. The only surface with
> real exposure is the **ASC** IAP description, which is not in this repo.
> The placeholder banner was real but unreachable: gated on `ads.isLive`, a
> hardcoded `false`. Interstitials had zero call sites. Scope was therefore much
> smaller than estimated — see the Decision record.

## Goal

Pick **one** path and make the whole product consistent.

| Path | When to choose |
|------|----------------|
| **A — Honesty (no ads)** | Prefer calm brand; Premium = hints + archive + packs only |
| **B — Ship AdMob** | Want free-tier $ without only sub conversion |

**Do not** leave placeholder banners or “remove ads” claims in limbo.

**Out of scope:** Mediation networks beyond AdMob v1; rewarded video for hints (can be a follow-up); kids-category compliance deep dive unless age rating requires it.

---

## Path A — No ads (honesty cleanup) · Estimate S

### A1 — Product / store

- [x] Remove “Remove ads” / “No ads” from `Products.storekit` all tiers — all three tiers now lead with hints + archive
- [x] **Update ASC subscription + lifetime descriptions** — checked 2026-08-08, already correct; no ad-removal claim was ever live there
- [x] App Store screenshots / description if they mention ad-free — already clean in all six locales, no change needed
- [x] Ensure `PremiumBenefit` stays without ads (already true)

### A2 — Code hygiene

- [x] Keep `AdProvider` no-op **or** delete dead interstitial hooks if unused — **deleted the whole scaffold**, see Decision record
- [x] Confirm Home never shows `BannerAdView` while `isLive == false` — moot, the gate and the view are both gone
- [x] Remove any user-visible “Advertisement” placeholder from production paths
- [x] ~~Comment in `AdProvider`~~ — file deleted; the rationale now lives on `PremiumBenefit.all`, which is where the next person will look

### A3 — Acceptance (Path A)

- [x] Grep for “ad” / “ads” in user-facing free+Premium marketing strings — no false “ad-free” Premium claim. Remaining hits are code comments plus `web/` saying “No ads”, which is **accurate** and stays
- [x] Free app: no ad UI
- [x] Premium pitch never leads with ads

---

## Path B — Ship real ads · Estimate L

### B1 — Decision + compliance

- [ ] AdMob app ID, banner + interstitial unit IDs (debug vs prod)
- [ ] Privacy Nutrition / ATT if needed; update privacy policy + `PrivacyInfo.xcprivacy`
- [ ] Confirm age rating / “made for kids” — if kids, ads rules change drastically
- [ ] Premium still removes ads (`!store.isPremium && ads.isLive`)

### B2 — Implementation

- [ ] Add Google Mobile Ads SDK via SPM/CocoaPods per current Google guidance
- [ ] `GoogleAdProvider: AdProvider` with `isLive == true` in Release (or remote flag)
- [ ] Real `BannerAdView` wrapping banner; safe area on Home already reserved
- [ ] Interstitial: load early; show only at **natural breaks** (e.g. after completion for free users) — never mid-clue entry
- [ ] Frequency cap (e.g. max 1 interstitial per completion or per N minutes)
- [ ] No ads for Premium; respect Remove Ads forever via entitlement

### B3 — Paywall + store

- [ ] Re-add **“No ads”** benefit in `PremiumBenefit.all` (shared with onboarding)
- [ ] StoreKit/ASC: “Remove ads” accurate again
- [ ] Analytics: `ad_impression`, `ad_shown` optional low-cardinality

### B4 — Acceptance (Path B)

- [ ] Free: real banner on Home when configured; interstitial at most at agreed moments
- [ ] Premium: zero ad requests
- [ ] Debug: test unit IDs; no crash offline
- [ ] Placeholder `BannerAdView` yellow stub gone from Release

---

## Recommended default

**Path A now** (align with calm Bible brand + current paywall), revisit Path B only if free→paid conversion + seasonal packs (01) aren’t enough revenue.

If Path A: do it in the **same release** as 08 T3 so store + paywall stop lying together.

---

## Decision record

- [x] Chosen path: **A** — no ads
- [x] Date / owner: 2026-08-08, Sambulo
- [x] **ASC copy: verified correct 2026-08-08.** The yearly, monthly and
      lifetime descriptions in App Store Connect never carried the “Remove ads”
      claim — it existed only in the local `.storekit` fixture, which no user
      ever sees. **No false ad-removal claim was ever live on the store.** The
      whole honesty risk in this ticket was theoretical; the work reduced to
      deleting dead code and correcting a test fixture.

**Why the scaffold was deleted rather than kept as a no-op.** A2 allowed
either. Once the placeholder banner went, `isLive` had no readers, and an
injected environment dependency nobody consumes is the same half-state the
“Done when” warns about. Path B is an L that would integrate a real SDK and
write its own provider — it would not reuse a six-line stub protocol. Removed:
`Services/AdProvider.swift`, `BannerAdView` in `Components.swift`, the
`safeAreaInset` gate and `@Environment(\.ads)` in `HomeView.swift`, and the
`ads` entry in `AppEnvironment.swift`. Git history has it if Path B ever runs.

**Unrelated discrepancy noticed, not fixed.** `Products.storekit` declares the
yearly introductory offer as `P1W` and its description says “7-day free trial”,
but the onboarding paywall renders “3-days free trial, then $9.99/year”. One of
the two is wrong. Which depends on the real ASC offer, so check it in the same
pass as the descriptions above. (Also: that string reads “3-days”, not
“3-day”.)

## Done when

Either **no ads anywhere and no ad-removal claims**, or **real ads free + clear Premium remove-ads** — with privacy/store in sync. No half states.
