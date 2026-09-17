# Pricing and packaging research — 2026-09-13

Primary-source research into where the annual price should sit, whether the
trial lengths are right, what packaging Apple permits, and what the offer
machinery costs to run. Sources are Apple (App Store Connect Help, StoreKit 2
docs, App Review Guidelines) and RevenueCat's *State of Subscription Apps 2026*
report pages. Every factual claim carries its source URL. Claims I could not
land on a primary source are marked **unverified** rather than asserted.

The app's measured numbers are treated as given and are not re-derived here.

## Framing

Conversion is not the problem and nothing in this document tries to fix it.
Initial conversion (5.5% / 7d), conversion to paying (3.8% / 7d) and trial→paid
(64%) are all 80th percentile or better. The weak metric is realized LTV per
paying customer: $9.99 at 30 days, ~$1.08/month/subscriber. Everything below is
aimed at that one number.

Two structural cautions apply throughout:

1. **The benchmark distributions are cross-sectional, not causal.** RevenueCat
   reports what apps at a given price *did earn*, not what this app *would*
   earn at that price. Apps that sustain high prices differ from apps that
   don't in ways the report does not control for. Treat "high-priced apps earn
   6x" as an upper bound on the opportunity, never as a forecast.
2. **At 11 active paid subs and ~396 new customers / 28 days, price cannot be
   A/B tested to significance.** See "What you cannot learn at this volume" at
   the end. Several otherwise-reasonable recommendations are unfalsifiable here
   and are marked as such.

---

## 0. Unresolved: which annual price is actually live

Internal project notes say yearly moved to **$12.99** in App Store Connect on
2026-09-01; the RevenueCat API still reports an indicative price of **$9.99**.
This cannot be resolved from outside App Store Connect and is not resolved here.

Corroborating internal evidence for $12.99: `docs/ux-audit-2026-09-02.md`
records that on device, both paywalls read App Store Connect and agreed on
"$12.99/year with a 7-day trial", confirmed with the owner on 2026-09-02. That
is repo evidence, not App Store Connect, so it is suggestive rather than
decisive. RevenueCat's indicative price is dashboard metadata and may simply be
stale — **unverified**, I did not find a primary RevenueCat document stating
how the indicative price is refreshed.

**Action:** confirm in App Store Connect → your app → Monetization →
Subscriptions → the yearly product → Subscription Prices / price schedule. That
view also shows any *scheduled* future price change, which matters for §4.

Where the answer changes a recommendation below, both cases are given.

---

## 1. Where should the annual price sit?

### What the Games-category benchmarks show

RevenueCat's Gaming breakout defines the category as "Games, Puzzle, Casual,
Word, Simulation, Board, and more" — a Bible crossword sits squarely inside it
(https://www.revenuecat.com/state-of-subscription-apps-2026-gaming).

Gaming price medians, same source:

| Plan | Median price | Most common price |
|---|---|---|
| Weekly | $5.81 | $5 |
| Monthly | $4.99 | $10 |
| Yearly | **$24.99** | **$30** |

Gaming realized LTV per payer, same source: **$8.41 median at month 1**,
**$11.22 median at year 1**.

Gaming conversion medians, same source: download-to-trial (D30) 4.4%,
trial→paid 25.0%, download-to-paid (D35) 1.0%.

Report-wide figures (https://www.revenuecat.com/state-of-subscription-apps):
methodology is "over 115,000 apps, representing more than $16 billion in
revenue" across more than a billion transactions during 2025. Global year-1
realized LTV median is $23/payer; North America $32; Western Europe $25.
High-priced apps show **$62.19 median yearly RLTV per payer versus $10.69 for
low-priced apps — a 6x spread** — and download-to-paid *also* rises with price
(2.8% vs 1.4% median).

**Unverified:** the report pages I could read do not define the price bands
that separate "high-priced" from "low-priced". Without that cutoff the 6x
figure cannot be mapped onto a specific target price.

### Reading this against the app

- The monthly price ($4.99) is exactly the gaming median. It is correctly
  priced and is not the problem.
- The annual price is the problem. At $9.99 it is **60% below** the $24.99
  gaming yearly median; at $12.99 it is still **48% below** it, and well under
  the $30 most-common yearly price
  (https://www.revenuecat.com/state-of-subscription-apps-2026-gaming).
- Realized LTV is *not* anomalously bad for the category. $9.99 at 30 days sits
  above the gaming month-1 median of $8.41 and near the gaming year-1 median of
  $11.22 (same source). The app converts top-decile and then earns a
  category-median amount per payer. That is the signature of a product priced
  below what its funnel can carry, not of a monetisation defect.

### The app's own price test is stronger evidence than the benchmarks

The $24.99 experiment (2026-08-11) is the only causal evidence available: the
paywall CTA tap rate roughly halved the day it changed, while trial→paid held.
Two things follow.

Halved CTA tap rate is an intent signal measured at the top of the paywall, not
a halving of purchases, and trial→paid holding up means the people who did
proceed were not worse leads. But a ~2.5x price with a ~0.5x entry rate is
roughly revenue-neutral at the point estimate, and the point estimate here rests
on a handful of conversions.

That argues against returning to $24.99 in one step, and for a level between
$12.99 and $24.99 that keeps the intent signal intact while closing most of the
gap to the category median.

### Recommendation

Move annual to **$19.99**, with the two-step caveat below. It is 20% under the
gaming median (so still a value price for a top-decile-converting product),
it is a ~54% increase on $12.99 rather than the ~92% jump to $24.99 that
visibly damaged CTA, and it lands on a conventional price point.

- **If live price is $12.99:** go to $19.99 directly.
- **If live price is $9.99:** go to $14.99 first, read 8 weeks, then $19.99.
  A $9.99 → $19.99 step is a 100% increase — the same magnitude that halved CTA
  in August, and the August result is the one measurement you actually own.

Do not re-run $24.99 until $19.99 has held for a full quarter.

---

## 2. Is the 7-day trial the right length?

### What the evidence says about trial length

Report-wide trial→paid medians by trial length
(https://www.revenuecat.com/state-of-subscription-apps):

| Trial length | Median trial→paid |
|---|---|
| 17–32 days | **42.5%** |
| 5–9 days | **37.4%** |
| ≤4 days | **25.5%** |

The report states the mismatch directly: "Trials of 17+ days convert 70% better
than short trials (42.5% vs. 25.5%), yet apps keep shifting to 3-day trials" —
and short trials (≤4 days) are now 46.5% of all trials, up 4.4pp year over year
(same source).

Gaming is the extreme case: "Gaming's 73.3% ≤4-day share is the highest of any
category" (https://www.revenuecat.com/state-of-subscription-apps-2026-gaming).
That explains gaming's low 25.0% median trial→paid — the category is mostly
running the trial length that converts worst.

Apple permits free trials of 3 days, 1 or 2 weeks, 1, 2, 3 or 6 months, or 1
year
(https://developer.apple.com/help/app-store-connect/manage-subscriptions/set-up-introductory-offers-for-auto-renewable-subscriptions/).

### The annual 7-day trial

7 days falls in the 5–9 day band (37.4% median). The app converts that trial at
**64%**, roughly 1.7x the band median and 2.6x the gaming median. The 7-day
trial is working and should not be shortened — shortening it moves toward the
≤4-day band that converts at 25.5%.

Lengthening to 14 days is the direction the distribution favours, but the
supporting jump (42.5%) belongs to the 17–32 day band, not to 14 days, and 14
days sits in no band the report breaks out. A 2-week trial is available in App
Store Connect (same Apple source). This is worth testing only if you accept it
cannot be measured — see the end.

**Verdict: keep 7 days on annual.** It is already outperforming its band by a
wide margin, and the metric that needs fixing is price, not trial length.
Changing both at once destroys the read on either.

### The 3-day trial on monthly is actively harmful — remove it

This is the strongest single finding in this document, and it is a mechanics
finding rather than a benchmark one.

StoreKit determines introductory offer eligibility at the **subscription group**
level, not per product. `isEligibleForIntroOffer` returns true if the customer
is eligible for an introductory offer "on the current auto-renewable
subscription, OR any auto-renewable subscription in the same subscription
group"
(https://developer.apple.com/documentation/storekit/product/subscriptioninfo/iseligibleforintrooffer).
App Store Connect states the rule from the other side: "Each person is only
eligible to redeem one introductory offer per subscription group"
(https://developer.apple.com/help/app-store-connect/manage-subscriptions/set-up-introductory-offers-for-auto-renewable-subscriptions/).

So a customer who starts the 3-day monthly trial **permanently burns their
eligibility for the 7-day annual trial**. The cheap, worst-converting trial
cannibalises the expensive, best-converting one, and the 3-day length sits in
the ≤4-day band at a 25.5% median against the 7-day trial's measured 64%.

**Remove the introductory offer from the monthly product.** Monthly at $4.99 —
exactly the gaming median — with no trial is entirely defensible: it becomes
the low-commitment escape hatch for people who decline the annual trial, and
annual keeps sole claim on the group's one intro offer. Effort is a
configuration change in App Store Connect, no code.

Caveat: this reduces monthly starts. Given monthly is the low-LTV product and
the goal is revenue per payer, that is the intended direction — but it is
**unverified** for this app specifically, and at this volume will not be
measurable.

---

## 3. Packaging: what Apple permits, and what the ladder should be

### What Guideline 3.1 actually allows

From https://developer.apple.com/app-store/review/guidelines/ :

- Auto-renewable subscriptions are allowed "regardless of category on the App
  Store" (3.1.2).
- "the subscription period must last at least seven days and be available
  across all of the user's devices" (3.1.2(a)). **Weekly is the shortest legal
  period.** No daily plans.
- "Subscriptions may be offered alongside à la carte offerings" (3.1.2(a)) —
  a lifetime non-consumable alongside subscriptions is explicitly permitted.
- "If you are changing your existing app to a subscription-based business
  model, you should not take away the primary functionality existing users have
  already paid for" (3.1.2(a)). The current handling of the removed lifetime —
  "Developer Removed From Sale", existing owners keep access — is exactly what
  this requires.
- Upgrades/downgrades: "Users should have a seamless upgrade/downgrade
  experience and should not be able to inadvertently subscribe to multiple
  variations of the same thing" (3.1.2(b)). Multiple tiers are permitted but
  must be ranked within the group so upgrade/downgrade resolves cleanly.
- 3.1.2(c) requires clearly describing what the customer gets for the price
  before they subscribe.

Nothing in the current or proposed packaging is anywhere near a 3.1 problem.

### Weekly

Gaming "is dominated by weekly plans (82%)", with only 13% annual adoption, and
the gaming weekly median is $5.81
(https://www.revenuecat.com/state-of-subscription-apps-2026-gaming). Weekly is
legal (≥7 days, 3.1.2(a)) and is the single largest structural difference
between this app's packaging and its category's.

But the 82% figure is dominated by hypercasual and puzzle games running
aggressive weekly-with-short-trial funnels — precisely the pattern producing
gaming's 25.0% median trial→paid, i.e. the funnel this app already beats by
2.6x. **Unverified:** I found no primary-source data on weekly pricing in
faith-based or devotional apps, and no evidence on how a devotional audience
responds to weekly billing. The reputational downside for a Bible app running a
$5.81/week plan is real and unmeasured.

**Verdict: do not add weekly.** The category median is not a mandate, and this
app's funnel is not the funnel that median describes.

### Lifetime

**Unverified.** The report pages I could reach carry no lifetime / one-time
purchase benchmarks, so I cannot say from a primary source whether
reintroducing lifetime raises or lowers total revenue. Apple permits it
(3.1.2(a), à la carte alongside subscriptions).

Mechanically, a lifetime purchase converts a recurring payer into a
single-payment customer, which is the opposite of the stated goal (revenue per
paying customer over time), unless priced well above annual LTV. Leave it
removed. If it ever returns, it should be priced at a multiple of the annual
price, not near it.

### A cheaper tier

Permitted under 3.1.2(b) if ranked for upgrade/downgrade. No benchmark support
found either way — **unverified**. Against it: it splits an already tiny
purchase volume across more products, makes every metric slower to read, and
adds paywall complexity to a paywall that is already converting at the 80–90th
percentile. **Do not add one.**

### Verdict on packaging

**Keep the two-product ladder (monthly + annual), trial on annual only.** The
ladder is not what is limiting revenue; the annual price point is. Adding
products spreads ~15 purchases/28 days thinner and buys no information.

---

## 4. Raising the price on existing subscribers

### Apple's exact rule

From
https://developer.apple.com/help/app-store-connect/manage-subscriptions/manage-pricing-for-auto-renewable-subscriptions/,
when you schedule an increase you choose per storefront between preserving the
current price for existing subscribers and applying the change to them.

If applied, **consent** is required when any of these hold:

- "The subscriber is located in a region that requires consent for any price
  changes."
- "The price increase is more than 50% of the current price **and** the
  difference in price exceeds approximately US$5 per period for non-annual
  subscriptions, or US$50 per year for annual subscriptions."
- "The subscriber experienced a price increase for that subscription within the
  past 12 months."

"If none of the criteria apply, Apple will automatically notify subscribers of
the price increase with no additional request for consent."

Regions listed as consent-required regardless of amount: **Austria, Germany,
Poland, Republic of Korea**
(https://developer.apple.com/help/app-store-connect/reference/in-app-purchases-and-subscriptions/auto-renewable-subscription-price-increase-thresholds/).
The same page gives the per-market amount thresholds — US$5 / US$50, CAD$7 /
$70, AUD$8 / $80, £5 / £50, ¥800 / ¥8,000, ₹500 / ₹5,000 — and notes they "are
subject to change based on changes in tax or foreign exchange rates."

Separately, Republic of Korea requires consent even for the ordinary
trial→standard-price conversion, collected by Apple via email, in-app sheet or
push
(https://developer.apple.com/help/app-store-connect/reference/in-app-purchases-and-subscriptions/consent-for-subscription-offer-conversions).

### Applied to this app

A $12.99 → $19.99 annual increase is +54% (over the 50% test) but the
difference is $7.00, far under the US$50 annual threshold. **In the US it is a
notice, not a consent request** — the two conditions are conjunctive. The same
holds for $12.99 → $24.99 (+92%, $12.00 difference). An annual product would
need a >US$50 increase to trip the amount threshold; this app will never
approach that.

**The clause that can bite is the third one.** Anyone who received the
2026-08-11 increase, *if it was applied to existing subscribers*, needs consent
for any further increase until 2027-08-11. Whether it was applied is not
knowable from outside App Store Connect — check the price schedule.

### Mechanics and risks

- Preserved subscribers keep their price indefinitely; "Subscribers whose
  subscription expires can resubscribe at the preserved price within 60 days of
  expiration."
- Notice timing for annual: first email 60 days before the renewal date, in-app
  messaging at first launch after entering the notice period, push 7 days
  before renewal if the in-app message was not viewed.
- Non-consent is fatal to the subscription: "If a subscriber doesn't consent
  before the first renewal at the higher price, their subscription will expire
  at the end of the last renewal cycle at the former price."
- Only "one future price change at a time, per country or region, per billing
  plan type" — scheduling a second overwrites the first.
- "Once a price increase goes into effect, it can't be reversed." Same for
  decreases. Every price move is one-way.

All quotes above from the manage-pricing page.

### Recommendation

**Preserve existing subscribers; raise for new customers only.** With 11 active
paid subs the upside of re-pricing them is a few dollars a year, against
churning the small cohort that proves the product retains (~0% monthly churn)
and generating price-increase emails and push notifications to the app's most
loyal users. It also avoids starting a 12-month consent clock that would
constrain the *next* price move — which matters more, given price is going to
move again.

---

## 5. Regional pricing

### What is automatic and what is not

When you set a base price, "App Store Connect provides comparable prices for all
175 App Store countries and regions, taking into account taxes and foreign
exchange rates", and you can override any storefront before confirming. You can
choose from 800 price points per currency, with more available on request from
the Account Holder
(https://developer.apple.com/help/app-store-connect/manage-subscriptions/manage-pricing-for-auto-renewable-subscriptions/).

**The important exception, easily missed:** Apple's ongoing automatic
re-equalisation does *not* apply to subscriptions. Same page: "Apple will not
make price adjustments on your auto-renewable subscription products. Retail
price changes initiated by Apple due to tax changes and significant foreign
exchange rate movements will exclude auto-renewable subscriptions... You can
choose to pass any changes caused by taxation or foreign exchange onto your
subscribers by adjusting the price for your subscription."

So the automatic behaviour described on Apple's general app-pricing pages —
periodic FX/tax adjustment to keep storefronts equalised
(https://developer.apple.com/help/app-store-connect/manage-app-pricing/set-a-price/)
— is a one-time generation for subscriptions, not an ongoing service. Foreign
storefront prices drift against the base over time and only manual action
corrects them.

### Is it worth the effort here?

No. Take Apple's generated prices and move on. At $56 per 28 days, a 10%
improvement in non-US realized price is worth cents, and the app is an
English-language Bible crossword whose revenue is almost certainly
US-concentrated — **unverified**, I have no storefront-level revenue split.

Revisit only if non-US revenue becomes a material share. The one thing to do
now is check the storefront split once, so the assumption is grounded.

---

## 6. Win-back offers and offer codes

### Win-back offers

From
https://developer.apple.com/help/app-store-connect/manage-subscriptions/set-up-win-back-offers/:

- Target lapsed subscribers. Eligibility windows you configure: 1–24 months
  since the last active subscription (both bounds required), a minimum paid
  duration of 1–24 months or 3/4/5 years, and an optional 2–24 month wait
  between offers.
- "Customers are only eligible for win-back offers for their most recently
  lapsed subscription product within each group."
- Limits: 350 win-back offers per subscription; 5 running per storefront per
  subscription at a time.
- Discount types: pay as you go, pay up front, free.
- **No code required.** Offers display automatically on the Manage Subscription
  page on iOS 14.3+ and in the in-app win-back sheet on iOS 18+.
- "Your subscription needs to be approved by App Review before you can create a
  win-back offer." Requires Account Holder, Admin, App Manager or Marketing
  role. No fee.

StoreKit 2 side
(https://developer.apple.com/documentation/storekit/supporting-win-back-offers-in-your-app):
eligibility means the subscription's `expirationDate` is past and `willAutoRenew`
is false. StoreKit delivers eligible offers via `Message.Reason.winBackOffer`;
server-side, `Get All Subscription Statuses` returns `eligibleWinBackOfferIds`,
best offer first. On iOS 18+ StoreKit adds win-back offers to purchase options
via `PurchaseIntent` without explicit support.

**Verdict: configure one, expect nothing.** Setup is a form, costs nothing and
needs no code. But with 11 active subs and ~0% monthly churn there is
essentially no lapsed pool to win back, and the minimum lapse window is 1 month.
This will produce a handful of impressions at most for a long time. Do it
because it is nearly free, not because it will move revenue.

### Offer codes

From
https://developer.apple.com/help/app-store-connect/manage-subscriptions/set-up-subscription-offer-codes/:

- "a maximum of 1 million redemptions per app, per quarter" — not a constraint
  here.
- **One-time-use codes:** 500–25,000 per batch, one redemption per code, expire
  at most 6 months after creation.
- **Custom codes:** a named code (e.g. SPRINGPROMO), optional expiry and
  optional cap up to 25,000 at a time, reusable across batches.
- Eligibility is selectable: new (never subscribed in the group), existing
  (currently subscribed, incl. billing retry / grace period), or expired.
- **Redemption URL needs no app code changes.** In-app redemption needs the
  StoreKit method and iOS 14+.
- Up to 10 active offers per subscription SKU. Offers cannot be edited after
  creation — a change means a new offer. Processing can take up to an hour.

**Verdict: worth it, narrowly.** A single custom code distributed by redemption
URL is zero engineering and fits the existing social/bio-link and creator
channels. Do not build in-app redemption.

### Promotional offers

From
https://developer.apple.com/help/app-store-connect/manage-subscriptions/set-up-promotional-offers-for-auto-renewable-subscriptions/:
target existing and previously-subscribed customers, and can be accepted "even
if they've already accepted an introductory offer" — the one way around the
one-intro-offer-per-group rule. Up to 10 active offers per subscription. Apply
to all storefronts; cannot be limited by region.

But they require generating In-App Purchase keys, creating the offer, and
implementing StoreKit APIs with signed offers — real server and client work.
**Skip at this volume.** Revisit if a lapsed-subscriber pool ever exists.

---

## What you cannot learn at this volume

Stated plainly, because it should shape how much effort goes into any of this.

With ~396 new customers and roughly 15 new payers per 28 days, and 11 active
subs, the app cannot detect anything smaller than a very large effect. A price
A/B test at a ~4% conversion base needs thousands of users per arm to resolve a
20% relative difference; this app produces a few hundred per month total. The
same applies to trial length, to removing the monthly trial, and to any paywall
variant.

Consequences:

- **Do not run a price A/B test.** It will not reach significance before the
  market moves. Choose the price from the category distribution and the one
  causal datapoint you own (the $24.99 CTA halving), ship it, and read *total
  revenue* — not conversion rate — over 8–12 weeks.
- **Trial→paid 64% and ~0% monthly churn are not yet real numbers.** Both are
  flagged low-sample in the source data; the 8.3% refund rate is likely one
  refund. Do not build a strategy on any of them holding.
- **Change one thing at a time**, because with this sample you get one weak
  signal per quarter and confounded changes produce none.

The honest summary: the single highest-value action is a price increase chosen
from benchmarks rather than measured, and most of the rest of the offer
machinery is not worth engineering time until there are enough subscribers to
tell whether it did anything.

---

## Ranked recommendations

| # | Action | Effort | Expected impact | Basis |
|---|---|---|---|---|
| 1 | **Confirm the live annual price in App Store Connect** (price schedule view, incl. any scheduled change and whether the Aug 11 increase was applied to existing subs) | 10 min | Unblocks everything below | §0, §4 |
| 2 | **Raise annual to $19.99** ($12.99 → $19.99 direct; if actually $9.99, go $14.99 first, then $19.99 after 8 weeks). Preserve prices for existing subscribers. | 30 min, no code | **High.** Closes most of the gap to the $24.99 gaming yearly median; directly targets the weak metric | §1, §4 |
| 3 | **Remove the 3-day introductory offer from the monthly product** | 15 min, no code | **Medium-high.** Stops the 25.5%-band trial burning group-level eligibility for the 64%-converting 7-day annual trial | §2 |
| 4 | **Keep the 7-day annual trial; keep the two-product ladder** | None | Protects a top-decile funnel while price moves | §2, §3 |
| 5 | **Create one custom offer code**, distributed by redemption URL | 30 min, no code | Low-medium. Unlocks creator/press/social promos with zero engineering | §6 |
| 6 | **Configure a win-back offer** (e.g. 1–6 months lapsed, free or discounted first period) | 30 min, no code | Low now, free later. Near-zero lapsed pool today | §6 |
| 7 | **Check the storefront revenue split once**; otherwise accept Apple's generated regional prices | 20 min | Low. Grounds the "US-concentrated" assumption; note Apple does *not* auto-adjust subscription prices for FX/tax over time | §5 |
| 8 | **Do not** add weekly, lifetime, a cheaper tier, or promotional offers | — | Avoids splitting ~15 purchases/28d across more products | §3, §6 |
| 9 | **Do not** A/B test price; read total revenue over 8–12 weeks after #2 | — | Avoids spending a quarter on an unresolvable test | "What you cannot learn" |

Rank 2 and 3 are the two that touch the weak metric. Everything else is
housekeeping or optionality.
