# Epic 02 — Challenge history / family challenge

**Priority:** 2  
**Goal:** Growth  
**Status:** `[ ]`  
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

**Status:** `[ ]`  
**Type:** eng  
**Estimate:** M

- [ ] Persist sent + received challenge results (device-local UserDefaults or SwiftData non-synced)
- [ ] Record: puzzleID, opponent name, their time, my time, won/lost, date
- [ ] Profile or Home section: “Recent challenges” list
- [ ] Tap → open puzzle / rematch share sheet
- [ ] Cap list (e.g. last 50); no CloudKit schema change

**Acceptance**
- After finishing a challenge, result appears in history with win/loss + delta
- Survives app relaunch; no new synced models

---

### P2-T2 — History from outgoing challenges

**Status:** `[ ]`  
**Type:** eng  
**Estimate:** S

- [ ] When user shares “beat my time”, store outgoing pending entry (puzzle, my time, name)
- [ ] When rematch sent, link to prior history entry if possible
- [ ] Analytics already cover rematch — keep events consistent

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

**Status:** `[ ]`  
**Type:** eng / design  
**Estimate:** S

- [ ] Primary CTA hierarchy: Share result / Challenge a friend / Rematch (if pending consumed)
- [ ] Show last opponent + “Play them again” when history exists for this puzzle
- [ ] Empty state copy for first-time sharers

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

- Display name: always Profile username, or per-challenge prompt?
- Family board privacy (names only on device — OK for v1?)
