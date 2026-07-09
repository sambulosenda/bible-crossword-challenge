# Themed Puzzle Packs — Implementation Spec

Curated collections of related puzzles ("The Life of David", "Parables", "Advent")
players browse and play as a set, alongside the linear daily feed. Gives Premium a
*content* reason, not just ad-removal, and seasonal packs drive re-engagement.

## Design principles (match the existing app)

- **Fully offline** — packs ship as bundled JSON, same as `puzzles.json`. No network.
- **Additive / backward-compatible** — no `packs.json` ⇒ feature simply absent; daily
  rotation and Archive untouched. Mirrors how `kind` was added to `Puzzle`.
- **Reuse existing primitives** — `PuzzleStatus`, `PuzzleRecord`, `DifficultyBadge`,
  Archive row, `NavigationLink(value: Puzzle)` → `CrosswordGameView`. Records already
  sync via CloudKit, so pack progress needs **zero** new synced state.
- **Daily-rotation index must stay stable** (per project memory). Dedicated pack
  puzzles must never enter the daily pool.

---

## Phasing

### Phase 1 — Overlay packs (ship first, zero new content)
Curate the existing 112 puzzles into themed sets. Titles are already thematic
("Animals of the Bible"…). **No change to `puzzles.json` or the generator.**
- Hand-author `Resources/packs.json` referencing existing `daily-NNN` ids.
- Those puzzles stay in daily rotation + Archive AND appear in their pack.
- New Collections UI + provider methods only.

### Phase 2 — Dedicated packs (as content grows)
Author *new* puzzles that live only inside a pack (never daily-rotated).
- specs.json entries carry `"pack": "<slug>"` → generator emits `pack-<slug>-NN`
  ids and the provider excludes `pack-` prefixed puzzles from the daily/archive pool.
- Same `packs.json` + UI. Real added content ⇒ strongest Premium hook.

Prefix convention already exists (`daily-`, `mini-`), so `pack-` is consistent and
keeps pool separation explicit without a new `Puzzle` field.

---

## Data model

New file `Models/PuzzlePack.swift`:

```swift
struct PuzzlePack: Codable, Identifiable, Hashable {
    let id: String            // slug: "life-of-david"
    let title: String         // "The Life of David"
    let blurb: String         // one-line description
    let coverSymbol: String   // SF Symbol name
    let accentHex: String?    // optional per-pack tint; nil = Theme.accent
    let isPremium: Bool        // false for the free starter pack
    let puzzleIDs: [String]   // ordered membership — the single source of truth
    let availableFrom: String? // ISO "2026-12-01" — seasonal gate (nil = always)
    let availableTo: String?   // ISO "2026-12-26"
}
```

`packs.json` is the **single source of pack membership + ordering + editorial
metadata**. Puzzles need no new field for membership; the provider derives a reverse
index for "which pack does this puzzle belong to".

Example `Resources/packs.json`:
```json
[
  {
    "id": "starter",
    "title": "First Steps",
    "blurb": "A gentle five-puzzle warm-up.",
    "coverSymbol": "figure.walk",
    "accentHex": null,
    "isPremium": false,
    "puzzleIDs": ["daily-001","daily-004","mini-001","daily-012","mini-003"],
    "availableFrom": null,
    "availableTo": null
  },
  {
    "id": "life-of-david",
    "title": "The Life of David",
    "blurb": "From the sheepfold to the throne.",
    "coverSymbol": "crown",
    "accentHex": "#8A6D3B",
    "isPremium": true,
    "puzzleIDs": ["daily-007","daily-018","daily-022","daily-031"],
    "availableFrom": null, "availableTo": null
  },
  {
    "id": "advent",
    "title": "Advent",
    "blurb": "Count down to Christmas, one puzzle a day.",
    "coverSymbol": "sparkles",
    "isPremium": true,
    "puzzleIDs": ["daily-040","daily-041","daily-042"],
    "availableFrom": "2026-12-01",
    "availableTo": "2026-12-26"
  }
]
```

## PackProgress (view-side, derived from records)

Records are SwiftData and live in views (as in Home/Archive), not the stateless
provider. A small helper:

```swift
struct PackProgress {
    let solved: Int
    let total: Int
    var fraction: Double { total == 0 ? 0 : Double(solved) / Double(total) }
    var isComplete: Bool { total > 0 && solved == total }

    init(pack: PuzzlePack, recordsByID: [String: PuzzleRecord]) {
        total = pack.puzzleIDs.count
        solved = pack.puzzleIDs.filter { recordsByID[$0]?.isCompleted == true }.count
    }
}
```

---

## PuzzleProvider changes (`Services/PuzzleProvider.swift`)

```swift
let packs: [PuzzlePack]                       // display order = file order
private let packByPuzzleID: [String: String]  // puzzleID -> packID (first wins)

// load in init(): decode packs.json (missing file -> [])
// Phase 2 only: dailyPool = all.filter { !$0.isMini && !$0.id.hasPrefix("pack-") }

func pack(id: String) -> PuzzlePack? { packs.first { $0.id == id } }

func pack(forPuzzle id: String) -> PuzzlePack? {
    packByPuzzleID[id].flatMap(pack(id:))
}

/// Resolve a pack's ordered puzzles; silently drop unknown ids (assertionFailure
/// in DEBUG so a typo is caught during authoring).
func puzzles(in pack: PuzzlePack) -> [Puzzle] {
    pack.puzzleIDs.compactMap { puzzle(id: $0) }
}

/// Packs whose seasonal window includes `date` (non-seasonal always included).
func availablePacks(on date: Date = Date()) -> [PuzzlePack] {
    packs.filter { $0.isAvailable(on: date) }   // date parse via ISO8601/DateFormatter
}
```

Loader follows the existing `loadBundledPuzzles` pattern (guard url, decode,
`assertionFailure` on failure). Missing `packs.json` ⇒ `packs = []`.

---

## UI

### Navigation surface (decision — see open questions)
Recommended: **new `RootTab.packs`** tab so free users can browse packs (Archive is
fully premium-gated and can't host a free preview). Tab bar goes 4 → 5, acceptable on
iPhone. `RootView.mainTabs` gains:
```swift
Tab("Packs", systemImage: "square.stack.3d.up", value: RootTab.packs) {
    PacksView(profile: profile)
}
```

### PacksView (`Views/Packs/PacksView.swift`)
- `@Query var records`, `@Environment(\.puzzleProvider)`, `@Environment(StoreService.self)`.
- Sections: **In season** (if any seasonal pack is in-window today) then **All collections**.
- Grid/list of `PackCard`. NavigationLink → `PackDetailView`.
- `.navigationDestination(for: Puzzle.self) { CrosswordGameView(...) }` so pack rows push straight into play.

### PackCard (`Views/Packs/PackCard.swift`)
Cover symbol on `accentHex ?? Theme.accent` tile, title, blurb, `PackProgress` bar
`3/8`, crown overlay when `isPremium && !store.isPremium`. Reuse `.elevatedCard()` +
`PressableCardStyle` from `HomeView`.

### PackDetailView (`Views/Packs/PackDetailView.swift`)
- Header: cover, title, blurb, progress bar.
- Body: list of the pack's puzzles — reuse Archive's `row(_:)` + `PuzzleStatus` +
  completion accessory + `NavigationLink(value: puzzle)`.
- **Premium gate**: if `pack.isPremium && !store.isPremium`, show the Archive
  `lockedState` pattern (ContentUnavailableView + "Unlock Premium" → `PaywallView`).
  The free `starter` pack is always playable.
- On `PackProgress.isComplete`: celebratory banner/seal (reuse CompletionView language).

### Home carousel (optional, `HomeView.swift`)
A "Collections" section: horizontal scroll of `availablePacks(on:)` cards, seasonal
first. Single entry point card ("Browse Collections") is the lighter alternative.

### "Next in pack" (optional, Phase 2 polish — `CompletionView.swift` / game toolbar)
When `provider.pack(forPuzzle: puzzle.id)` is non-nil and the pack has an unsolved
next puzzle, add a "Next in {pack.title}" button so a pack feels like a sequence.

---

## Premium strategy (decision — see open questions)
Recommended: **all packs included with Premium; one free `starter` pack** so free
users taste the format. Gate at `PackDetailView` (browse free, play gated), reusing
the existing paywall flow. `isPremium` per-pack already supports this.

---

## Analytics (`Services/Analytics.swift`)
Add events: `packOpened(id)`, `packPuzzleStarted(packID)`, `packCompleted(id)`.
Log via existing `analytics.log(...)`.

## Achievements (optional, Phase 2)
Add a `Goal` case `.packsCompleted(target)` and/or per-pack completion achievements
(`Achievements.Goal` enum already models `.puzzles`, `.streak`, etc.).

---

## Files

**New**
- `Models/PuzzlePack.swift` (+ `PackProgress`, `isAvailable(on:)`)
- `Resources/packs.json`
- `Views/Packs/PacksView.swift`, `PackDetailView.swift`, `PackCard.swift`

**Edit**
- `Services/PuzzleProvider.swift` — load packs, reverse index, `puzzles(in:)`,
  `availablePacks(on:)`, Phase-2 pool exclusion
- `Views/RootView.swift` — add `RootTab.packs` + tab (or Home entry point)
- `Services/Analytics.swift` — pack events
- (opt) `Views/HomeView.swift` — Collections carousel
- (opt) `Views/CompletionView.swift` — next-in-pack
- (Phase 2) `tools/generate_puzzles.py` — `"pack"` spec field → `pack-<slug>-NN` ids

---

## Tests (`Bible Crossword ChallengeTests`, style of EngineTests/ProgressTests)
- `puzzles(in:)` preserves order, drops unknown ids.
- `availablePacks(on:)` includes/excludes seasonal packs by date boundary.
- `pack(forPuzzle:)` reverse index correctness.
- Daily pool: Phase 1 unaffected by adding packs; Phase 2 excludes `pack-` ids and
  daily rotation index for existing `daily-NNN` is unchanged.
- `PackProgress` counts only completed records.

## Edge cases
- Missing/typo puzzleID → skipped (DEBUG `assertionFailure`), never crashes.
- Empty pack after resolution → hidden.
- Seasonal pack out of window → hidden (or "returns in December" — decision).
- Puzzle in multiple packs → allowed; reverse index keeps first listed as "primary".
- No `packs.json` → `packs = []`, all existing flows intact.
- Pack progress rides on `PuzzleRecord` → already CloudKit-synced, nothing new.

## Rollout
Phase 1 launch with ~3 packs from the existing 112 (one free starter + two premium
themed). No pipeline change → shippable immediately. Phase 2 authors dedicated
seasonal/character packs as the content bank grows.

---

## Unresolved questions
1. **Nav placement** — new 5th tab (free browse, recommended) vs. fold into Archive as
   a `Collections | All` picker (but Archive is fully premium-gated, blocks free preview)?
2. **Premium model** — all-packs-with-Premium + one free starter (recommended) vs.
   per-pack unlock vs. first-N-puzzles-of-each-pack free?
3. **Phase 1 vs. straight to Phase 2** — ship overlay packs from existing puzzles now,
   or hold for dedicated new content?
4. **Overlap policy** — should a pack puzzle also count toward the daily streak /
   Archive completion count, or be tracked separately? (Overlay reuses the same
   `PuzzleRecord`, so it counts once globally — confirm that's desired.)
5. **Seasonal out-of-window** — hide entirely, or show a locked "returns Dec 1" teaser?
6. **Ordering within a pack** — enforce sequential unlock (must solve #1 before #2) or
   free pick-any order (recommended — matches Archive)?
