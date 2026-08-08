# Epic 06 — Family Premium / gift

**Priority:** 6  
**Goal:** Revenue  
**Status:** `[ ]`  
**Depends on:** `StoreService`, `PaywallView`, StoreKit products  
**Related:** Premium benefits (hints, ads, packs)

## Why

Faith apps often purchased *for* parents/grandparents. Family plan + gift raise AOV and fit brand better than only individual sub.

## Success metrics

- New product conversion rate
- Gift redemptions
- Revenue per paying user
- Support volume (gifting can create tickets — keep UX simple)

---

## Tickets

### P6-T1 — Product design + StoreKit config

**Status:** `[ ]`  
**Type:** product + eng  
**Estimate:** S

- [ ] Define SKUs: e.g. Family monthly/yearly (up to N Apple ID… **note Apple limitation**)
- [ ] Reality check: StoreKit subscriptions are per Apple ID — true multi-seat family usually means:
  - **Family Sharing** enabled on subscription, OR
  - Gift: one-time code / App Store gift of subscription (Apple-managed), OR
  - “Buy for someone else” education (send them a gift card / share purchase instructions)
- [ ] Pick approach; document constraints in this ticket
- [ ] Update `Products.storekit` + App Store Connect

**Acceptance**
- Written decision: Family Sharing vs educational gift vs third-party codes
- Products appear in paywall debug/storekit config

---

### P6-T2 — Enable Apple Family Sharing (if chosen)

**Status:** `[ ]`  
**Type:** eng / ASC  
**Estimate:** S

- [ ] Turn on Family Sharing for Premium subscription in App Store Connect
- [ ] Paywall copy: “Share with your household via Apple Family Sharing”
- [ ] Profile: “Manage subscription” already — confirm shared access shows Premium

**Acceptance**
- Second Family Sharing member gets Premium entitlements without second purchase

---

### P6-T3 — Gift Premium UX (in-app)

**Status:** `[ ]`  
**Type:** eng / design  
**Estimate:** M

If using App Store gift / share sheet:

- [ ] Paywall or Profile: “Gift Premium”
- [ ] Opens share flow with App Store gift link **or** clear steps to gift the sub
- [ ] Avoid building custom redeem codes unless willing to support them

If one-time “Premium lifetime gift” IAP:

- [ ] Non-consumable or consumable? Prefer **non-renewing** carefully — usually subscription gift via Apple is cleaner
- [ ] Receipt validation still via StoreKit 2 current path

**Acceptance**
- User can start a gift flow in &lt;3 taps
- No orphan custom codes without support plan

---

### P6-T4 — Paywall packaging

**Status:** `[ ]`  
**Type:** design + eng  
**Estimate:** S

- [ ] Plan picker: Individual vs Family (if priced differently)
- [ ] Feature list: packs, hints, ads, seasonal early access
- [ ] Analytics: plan name on `paywall_cta_tapped` / `premium_purchased` already has `plan` — extend values

**Acceptance**
- Distinct plan strings in analytics
- Pricing legal text still correct (trial, auto-renew)

---

### P6-T5 — Optional one-time pack IAPs (stretch)

**Status:** `[ ]`  
**Type:** eng  
**Estimate:** M

- [ ] Seasonal pack as one-time unlock for anti-sub buyers
- [ ] Must not fight subscription story — position as “gift a pack” or “own this collection”
- [ ] Entitlement storage: StoreKit + local unlock list

**Acceptance**
- Can unlock one pack without full Premium; Premium still unlocks all

---

## Out of scope

- Custom account system for seat management
- Cross-platform family seats
- Refund automation

## Open questions

- Price points: Family = 1.5× or 2× individual yearly?
- Lifetime Premium? (usually avoid — support burden)
- Gift focus: grandparents (one sub + Family Sharing) vs church bulk (not App Store friendly)?
