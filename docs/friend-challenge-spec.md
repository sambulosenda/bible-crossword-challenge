# Friend Challenge — Implementation Spec

Solve a puzzle → share a link that says "beat my time" → friend taps it, plays the
*same* grid, and gets a head-to-head result screen. First social/viral loop in the
app. No backend: the entire challenge is encoded in the URL.

## Design principles (match the existing app)

- **No backend, no accounts** — challenge payload lives entirely in the share URL.
  Works offline once opened. Mirrors the bundled-JSON philosophy.
- **Reuse existing primitives** — `puzzleProvider.puzzle(id:)`, `PuzzleRecord.elapsedSeconds`,
  the `onOpenURL` → `todayPath` push in `RootView`, `CompletionView`, `ShareCardView`.
- **No CloudKit schema change** — pending challenges are device-local state
  (UserDefaults JSON), NOT a new `@Model`. A new synced model would require a
  Production schema re-deploy (per project memory) for a feature that has no
  cross-device meaning anyway.
- **Puzzle ids are content-stable** (per project memory) — which is exactly what
  makes a URL-encoded `puzzleID` safe to send between devices/app versions.

---

## Phasing

### Phase 1 — MVP (custom scheme, installed users only)
`biblecrossword://challenge?...` links. Sender shares from the completion screen;
recipient with the app installed taps and plays. Ship this first — it's pure Swift,
no infra.

### Phase 2 — Universal links (the actual growth loop)
`https://<domain>/c?...` so links are tappable in iMessage/WhatsApp for everyone.
Non-installed recipients land on a tiny static page → App Store. Needs: a domain,
an AASA file (static hosting, e.g. Cloudflare Pages), `applinks:` entitlement.
Phase 1 code parses the same query params, so Phase 2 is routing only.

> Known limitation (accepted): no deferred deep-linking without a backend — a
> recipient who *installs* from the link won't auto-open the challenge. The page
> should say "ask them to re-send the link once you've installed". Do not do
> clipboard-sniffing hacks.

---

## URL format

```
biblecrossword://challenge?v=1&p=daily-042&t=154&n=Sam
https://<domain>/c?v=1&p=daily-042&t=154&n=Sam        (Phase 2, same params)
```

| param | meaning | rules |
|---|---|---|
| `v` | payload version | reject `v` > current with an "update the app" alert |
| `p` | puzzle id | must resolve via `puzzleProvider.puzzle(id:)` |
| `t` | challenger's seconds | Int, clamp to `1...86_400`; reject otherwise |
| `n` | challenger's display name | percent-encoded, trim + cap at 20 chars on both ends |

Times are honest-system plaintext. Casual tampering is possible; accepted for v1
(stakes are bragging rights). Don't add crypto.

## Data model (local only)

```swift
/// A "beat my time" a friend sent us, parsed from a challenge URL.
struct Challenge: Codable, Equatable {
    let puzzleID: String
    let challengerName: String
    let seconds: Int
    let receivedAt: Date
}
```

Stored as `[Challenge]` JSON in UserDefaults (standard, not app group — the widget
doesn't need it). One pending challenge per `puzzleID`; a newer link for the same
puzzle replaces the older. Consumed (removed) when its result screen has been shown.

## New service

`Services/ChallengeService.swift` (`@Observable`, injected like `ReaderRouter`):
- `parse(_ url: URL) -> Challenge?` — validates params per table above.
- `pending(for puzzleID: String) -> Challenge?`
- `accept(_ challenge: Challenge)` / `consume(puzzleID:)`
- `challengeURL(puzzle: Puzzle, seconds: Int, name: String) -> URL`

Ignore self-shaped no-ops: if a parsed challenge's puzzle is already the target of
an identical pending entry, replacing it is fine (idempotent).

---

## Sender flow

`CompletionView` gains a **Challenge a Friend** action next to Share:
- `ShareLink` with caption:
  `Can you beat me? I solved "<title>" in 2:34 — Bible Crossword` + challenge URL.
- Name comes from `profile.username` (defaults to "Friend" — fine).
- Also offer it retroactively from Archive rows' context menu (premium users
  replaying old puzzles) — *v2, not MVP*.

`ShareConfig.storeURL` is still `nil` — set it now that the app is live (needed for
the caption fallback and the Phase 2 landing page).

## Recipient flow

1. `RootView.handleDeepLink` learns `host == "challenge"`:
   - parse → `challengeService.accept(...)` → select Today tab → push the puzzle:
     `todayPath = NavigationPath([puzzle])`.
   - **Onboarding guard**: today the guard drops deep links pre-onboarding. Instead,
     stash the challenge (accept it) and only skip *navigation*; after onboarding
     finishes, if a pending challenge exists, push its puzzle.
   - Unknown `p` (older app bundle) → alert "Update the app to play this challenge."
2. **Gating exception (deliberate)**: the challenged puzzle is playable even if it
   isn't today's daily and the user isn't premium. One puzzle via a friend's link is
   an acquisition hook, not an archive leak — the Archive itself stays locked.
3. `CrosswordGameView` shows a compact **target chip** when
   `challengeService.pending(for: puzzle.id)` exists: `⏱ Sam · 2:34` (static; no
   live ghost timer in MVP).
4. On completion, `CompletionView` renders a **result card** above the verse card:
   - Won: "You beat Sam! 2:11 vs 2:34" ・ Lost: "Sam holds the crown — 2:51 vs 2:34"
   - Primary follow-up: **Send your result back** — a fresh challenge link with
     *your* time. This is the rematch loop; it's the whole point.
   - Then `consume(puzzleID:)`.
5. **Already-solved edge**: if the recipient has a completed `PuzzleRecord` for that
   puzzle, skip play entirely — show the comparison immediately from
   `record.elapsedSeconds` (alert or small sheet), with the same "send result back"
   action. No replay mode in MVP.
6. **In-progress edge**: a partially-solved grid gives the recipient an advantage.
   Accepted for v1; the result card doesn't claim fairness.

## Analytics (add to `Analytics.swift`)

```
challenge_sent(puzzle_id)
challenge_opened(puzzle_id)          // valid deep link parsed
challenge_completed(puzzle_id, won: Bool, delta_seconds: Int)
challenge_rematch_sent(puzzle_id)
```
`challenge_opened / challenge_sent` is the K-factor proxy; `rematch_sent` measures
the loop actually looping.

## Files touched

| file | change |
|---|---|
| `Services/ChallengeService.swift` | new — parse/store/build URLs |
| `Views/RootView.swift` | `challenge` host in `handleDeepLink`; onboarding stash |
| `Views/CompletionView.swift` | Challenge button; result card; rematch share |
| `Views/Game/CrosswordGameView.swift` | target chip |
| `Services/Analytics.swift` | 4 new events |
| `Views/ShareCardView.swift` | (v2) challenge variant of the card image |
| `Info.plist` / entitlements | Phase 2 only — `applinks:` domain |

## Testing

- Unit-test `ChallengeService.parse`: valid, missing params, junk `t`, oversized
  `n`, future `v`, unknown puzzle id.
- Simulator deep-link smoke test:
  `xcrun simctl openurl booted "biblecrossword://challenge?v=1&p=daily-042&t=154&n=Sam"`
  (build+run via simctl per project memory — test runner is broken).
- Flows: fresh puzzle, already-completed puzzle, pre-onboarding link, self-link.

---

## Unresolved questions

1. **Phase 2 domain** — do you own a domain for universal links (or want a
   Cloudflare Pages one)? Phase 1 doesn't need it, but the caption copy does
   benefit from including a store URL now — what's the App Store link?
2. **Free-user exception** — agree that a challenged non-today puzzle is playable
   for free (single-puzzle acquisition hook), or must it respect the archive gate?
3. **Challenge from Archive/packs pages** (not just post-completion) — v2 or never?
4. `profile.username` is "Friend" by default — worth a one-time "pick a name"
   prompt the first time someone sends a challenge?
