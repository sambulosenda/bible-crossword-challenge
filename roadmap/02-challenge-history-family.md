# Epic 02 — Challenge history / family challenge

**Priority:** 2  
**Goal:** Growth  
**Status:** `[~]` — T1–T4 shipped (T3 needs a web landing page); T5 open  
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

**Status:** `[x]` — Option B, app + web. Not yet deployed.  
**Type:** eng  
**Estimate:** L

Design constraint: still URL- or sheet-based, offline-friendly.

**Option A** — rejected, as the ticket already leaned. A board nobody can see
isn't a board.

**Option B (built)** — Multi-result board that travels in the link
- [x] After solve: "Start a family board" when the puzzle has none; the ranked
      board itself when it does
- [x] Board = puzzleID + `[{name, seconds}]`, UserDefaults `familyBoards.v1`,
      12 names, 20 boards
- [x] Share as ranked text (medals) + the link
- [x] An incoming solve is added under the player's own name on their *own*
      device; the name is only asked for when the board is about to leave it
- [x] The standings ride in the URL — this is what makes the acceptance
      criterion reachable at all. `e=<seconds>:<name>`, repeated

**Not built:** a ranked-list share *image*. `ShareCardView` is built around one
person's result; a board image is its own design job. Text + link ships the loop.

**Wire format** — `?v=2&p=<id>&e=154:Sam&e=201:Ann`, on the existing
`/challenge/` path. The AASA file claims `/challenge*` and nothing else, so a
`/board/` path would have opened Safari until a web deploy caught up. `v=2` does
the discriminating: builds that predate boards read it as "newer than I
understand" and show their existing update alert. One-to-one links stay `v=1`.

**Merge rule** — lowest time wins per name, so merging is commutative: the link
can criss-cross a group in any order and every copy converges on the same board.
Your own row is never overwritten by a replay.

**Acceptance**
- [x] ≥2 people play the same puzzle and see ranked times, no accounts —
      verified on device: 3-name link → join → solve → 4-name ranked board
- [x] Web page for non-installed recipients — `/challenge/` now renders either
      payload, ranked list included. Its parser mirrors `FamilyBoardService`
      rule for rule; keep the two in step if the wire format ever moves.
      **Still needs a deploy** — until then, board links only work app-to-app.

**Known v1 limits (deliberate)**
- Two people with the same first name merge into one row
- Honour system throughout — anyone can hand-edit a link (as with `ChallengeService`)

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
