# Epic 02 — Challenge history / family challenge

**Priority:** 2  
**Goal:** Growth  
**Status:** `[~]` — T1, T2, T4 shipped; T3 and T5 open  
**Depends on:** `ChallengeService`, Completion share, universal links  
**Related:** `docs/friend-challenge-spec.md`

## Why

Beat-my-time is shipped. History + multi-person challenges turn one-off shares into a repeatable viral loop (family, small group) without a backend.

## Success metrics

- `challenge_sent` / `challenge_opened` / `challenge_completed` volume
- Rematch rate (`challenge_rematch_sent`)
- Installs attributed to challenge web page (if measurable)

---

## Tickets

### P2-T1 — Challenge history (local)

**Status:** `[x]`  
**Type:** eng  
**Estimate:** M

- [x] Persist sent + received challenge results (`ChallengeHistory`, UserDefaults `challengeHistory.v1`)
- [x] Record: puzzleID, title, opponent name, their time, my time, outcome, date
- [x] Profile section: “Recent challenges” (last 3) → `ChallengeHistoryView` for the rest
- [x] Tap → confirmation dialog: Play Again / Challenge Again
- [x] Cap list (50); no CloudKit schema change

**Acceptance**
- After finishing a challenge, result appears in history with win/loss + delta
- Survives app relaunch; no new synced models

---

### P2-T2 — History from outgoing challenges

**Status:** `[x]`  
**Type:** eng  
**Estimate:** S

- [x] Sharing “beat my time” stores a `.sent` row — written on the share sheet's
      completion handler, so a cancelled share doesn't claim a challenge
- [x] A rematch marks `rematchSentAt` on the row it answers instead of opening a
      second row for the same matchup
- [x] Analytics untouched — `challenge_sent` / `challenge_rematch_sent` still fire
      at presentation, so the existing series stays comparable

**Acceptance**
- User sees challenges they *sent*, not only ones received

---

### P2-T3 — Family / group challenge (v1, no backend)

**Status:** `[ ]`  
**Type:** eng  
**Estimate:** L

Design constraint: still URL- or sheet-based, offline-friendly.

**Option A (recommended MVP)** — Shared scorecard link  
- [ ] URL encodes puzzle id + host name + host time; recipients append their result by sharing *back* or via multi-share text
- [ ] Or: host creates “family race” → shareable message with puzzle deep link; each person plays solo; compare times in a simple group sheet the host fills manually — too weak, prefer Option B

**Option B (preferred)** — Multi-result local board  
- [ ] After solve, “Add to family board” / “Challenge the family”
- [ ] Board = puzzleID + list of `{name, seconds}` stored locally
- [ ] Share board as text or image (ranked list) + link so others can play same puzzle
- [ ] Incoming solve can open sheet “Log your time under name X” on the *recipient’s* device only (honest local brag board)
- [ ] Optional: encode top N times in URL for small groups (size limits!)

**Acceptance**
- ≥2 people can play same puzzle and see ranked times without accounts
- Works for installed users; web page still funnels non-installed to App Store

---

### P2-T4 — Challenge UX on Completion

**Status:** `[x]`  
**Type:** eng / design  
**Estimate:** S

- [x] CTA hierarchy unchanged in shape: Share (prominent) → challenge (tonal) →
      Home; an incoming challenge still replaces the tonal slot with the result
      card's "Send Result Back"
- [x] Last opponent named in the CTA ("Challenge Sam Again") with the standing
      result underneath, when this puzzle has history
- [x] Empty state copy for first-time sharers ("They'll get a link to this exact
      puzzle. Fastest time wins.")

**Acceptance**
- Challenge is one tap from completion; no buried menu only

---

### P2-T5 — Group / church weekly mini race (stretch)

**Status:** `[ ]`  
**Type:** eng  
**Estimate:** M  
**Depends on:** P2-T3

- [ ] Weekly: point at daily mini + Game Center leaderboard already exists
- [ ] In-app explainer: “Compete this week’s Mini in Game Center”
- [ ] Optional share graphic with week number + time

**Acceptance**
- Clear path from Mini completion → Game Center weekly board + share

---

## Out of scope

- Live multiplayer co-op
- Real-time rooms / push between friends
- Deferred deep link after install (accepted limitation unless App Clip later)
- Server leaderboards beyond Game Center

## Open questions

- ~~Display name: always Profile username, or per-challenge prompt?~~ Settled by
  T1/T2: Profile username, with a one-time inline prompt the first time someone
  sends a challenge (the highest-motivation moment to ask). Same prompt now on
  both send paths — Completion and the history list.
- Family board privacy (names only on device — OK for v1?)
