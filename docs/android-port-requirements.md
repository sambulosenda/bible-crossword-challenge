# Android (Kotlin) Port — Requirements

Derived from inspecting the shipping iOS app at `93e0a0f` (2.10 / build 21).
Source: ~23k lines Swift, 85 files, SwiftUI + SwiftData + CloudKit.

---

## 1. Goal & scope

Ship the same game on Google Play: same puzzles, same rules, same economy, same
monetization. Not a redesign. Anything below marked **[decision]** cannot be
answered from the iOS source and needs a call before that piece is built.

Non-goals for v1: iPad/tablet-specific layouts, Wear OS, offline-sync between
platforms (see §6), localization beyond English (see §14).

---

## 2. What already exists (portable vs. rewrite)

| Layer | iOS | Portability |
|---|---|---|
| Content (`puzzles.json`, `packs.json`, `quests.json`, `bsb.json`) | 5.4 MB bundled JSON | **Copy verbatim.** No schema change. |
| Lottie animations (4 files) | lottie-ios | **Copy verbatim.** lottie-android reads same JSON. |
| Game engine (`GameViewModel`, 1147 lines) | Pure Swift, no UIKit, no persistence | **Port 1:1.** Already persistence-agnostic + unit tested. |
| Rules (streaks, hints, achievements, access, cloze, journey) | Pure value types | **Port 1:1.** ~30 test files already pin the behaviour. |
| Views (40 SwiftUI files, ~12k lines) | SwiftUI | **Rewrite** in Compose. |
| Persistence | SwiftData + CloudKit | **Rewrite** (Room). Sync is a **[decision]**. |
| Billing | StoreKit 2 via RevenueCat | Rewrite against RevenueCat Android; same `pro` entitlement. |
| Analytics | Firebase + PostHog | Same SDKs exist on Android; event names must match exactly. |
| Widget | WidgetKit | Rewrite as Glance app widget. |

**Rule of thumb:** everything in `Models/`, `ViewModels/`, and the pure parts of
`Services/` is a mechanical translation with an existing test suite. Everything
in `Views/` is new work.

---

## 3. Target platform

| Item | Requirement |
|---|---|
| Language | Kotlin 2.x, coroutines + Flow |
| UI | Jetpack Compose (Material 3), single-Activity |
| minSdk | 26 (Android 8.0) — needed for `java.time`, notification channels |
| targetSdk | latest stable at build time |
| Architecture | MVVM: `GameViewModel` port + Compose screens; Hilt or manual DI mirroring `AppEnvironment` |
| Build | Gradle KTS, version catalog |
| Package | `com.sambulosendas1.biblecrossword` **[decision]** — must match RevenueCat + Play Console + assetlinks |

### 3.1 Repository layout

The Android app lives in **`android/` in this repo**, not a separate one.

```
Bible Crossword Challenge/
├── Bible Crossword Challenge/     iOS app
├── BibleCrosswordWidget/
├── android/                       <- new
│   ├── app/
│   ├── build.gradle.kts
│   └── settings.gradle.kts
├── web/                           Astro site + .well-known
├── docs/
├── fastlane/
└── marketing/
```

This is already a monorepo (`web/`, `marketing/`, `fastlane/`, `tools/`), so
Android fits the existing pattern. Four reasons it has to be this way:

1. **Content cannot be allowed to drift.** Puzzle ids key saved progress *and*
   challenge links across both platforms. One repo means one commit changes both
   apps; two repos means a sync process nobody runs.
2. **The content files need not be copied at all.** Point Gradle at the iOS
   resources and there is one physical copy of every puzzle:

   ```kotlin
   sourceSets["main"].assets.srcDirs("../../Bible Crossword Challenge/Resources")
   ```

   All eight files there (`puzzles`, `packs`, `quests`, `bsb`, and the four
   Lottie animations) are wanted on Android unchanged.
3. **`assetlinks.json` belongs in `web/public/.well-known/`**, beside the AASA
   file that is already there (§12.2). Same repo, one commit.
4. Docs, roadmap, and the analytics event vocabulary (§9) are shared context that
   both apps have to agree on.

Cost: Android developers clone ~63 MB of Xcode history and an Astro site. That is
cheaper than a content-drift bug that corrupts saved progress.

---

## 4. Content requirements

Content is decoded with kotlinx.serialization from the shared iOS `Resources/`
directory, mapped in as Android assets (§3.1) — no duplicate copies. No network
required to play; the app must be fully offline.

### 4.1 `puzzles.json` — 241 puzzles

```
{ id, title, difficulty, verse, reference, publishDate, size, grid[], clues[], kind? }
clue: { number, direction, row, col, text, answer, reference? }
```

- 138 daily (15×15), 90 mini (7×7), 13 sunday (21×21)
- difficulty: easy 141 / medium 68 / hard 32
- `kind` absent ⇒ `daily` (must decode as optional)
- `grid` is `size` strings; `.` = block
- 1519 of 3549 clues carry a `reference` (drives verse hints + Read chips)
- **ids are content-stable and never renumbered** — they key saved progress and
  challenge links. Same rule applies on Android.
- ids prefixed `pack-` are pack exclusives, excluded from the daily/archive pools

### 4.2 `packs.json` — 10 packs

`{ id, title, blurb, coverSymbol, accentHex?, isPremium, puzzleIDs[], season? }`

### 4.3 `quests.json` — 3 journeys

`{ id, title, blurb, coverSymbol, accentHex?, isPremium, puzzleIDs[] }`

### 4.4 `bsb.json` — 4.6 MB Berean Standard Bible

`{ translation, abbreviation, books[{ name, testament, chapters[{ number, verses[{ number, text }] }] }] }`

Must be **lazily decoded off the main thread** (iOS does the same) — decoding
4.6 MB on the UI thread will ANR.

### 4.5 Icons — **[decision, real work]**

90 distinct SF Symbol names are referenced across views, `packs.json`
(`coverSymbol`), `quests.json`, and the 14 achievements (`symbol`). Android has
no SF Symbols. Options:

- (a) map each to a Material Symbol and add a `coverSymbolAndroid` field / lookup table
- (b) ship a name→drawable map in Kotlin and leave the JSON untouched (preferred —
  keeps content files shared with iOS)

---

## 5. Game engine requirements (port 1:1)

Port `GameViewModel` faithfully. Every behaviour below is deliberate and
measured — do not "simplify" any of it.

### 5.1 Grid & entry
- Build cells from `grid` rows; `.` = block; clue numbers from clue starts
- Opening selection = **shortest answer in the grid**, ties across-then-lower-number
- Tap a selected cell ⇒ toggle across/down
- Typing advances to next empty cell in word, wraps to earlier gaps, then to
  the next incomplete word — crossing words first, else nearest by Manhattan distance
- Backspace clears current, else steps back and clears
- Hardware keyboard arrows walk over blocks (nice-to-have on Android)

### 5.2 Pencil mode
- Provisional letters; never complete a word or puzzle; stored separately
  (`pencilData`) so "progress" counts stay honest

### 5.3 Check (free, never reveals)
- Scopes: letter / word / puzzle
- Marks wrong filled cells (pencil included) until edited
- Correct positions flash green transiently and are **never persisted** — persistent
  green would be a free answer oracle
- `autoCheck` setting: marks wrong letters as you type; seeded ON for players
  under 3 completions, OFF for everyone else, at first read only

### 5.4 Hints (quota economy)

| Hint | Cost | Effect |
|---|---|---|
| Show the Verse | 0 | Opens the passage; touches no cells |
| Reveal Letter | 1 | Fills + **locks** one cell |
| Reveal Word | 2 | Fills + locks the word (leaves player's correct pen letters unlocked) |
| Reveal Puzzle | 3 | Fills the grid; confirmed before use |

- Free daily pool = 3 (`freeHintLimit`); premium = unlimited
- **Learning window**: players with < 3 completions get unlimited free hints
- A hint must always buy progress — refuse (and refund) if nothing to reveal
- Locked cells: typing into one skips it and fires a visible flash + haptic
  (`lockedEntryTick`), never silently
- `hint-quota-one` experiment reduces the pool to 1 — the limit is passed in as a
  parameter, the model never reads the flag SDK

### 5.5 Starter-word gift
- New player, no entries: the opening (shortest) word is filled free
- **Paced**: letters land one at a time, 170 ms apart, so the player watches the
  mechanic happen. Cancellation-safe. Player input flushes the remainder instantly.
- Free: does not bump `hintsUsed`, does not set `usedHint`
- Refuses on any existing progress (a resume must never be overwritten)

### 5.6 Stall rescue (`stall-nudge` flag gates both tiers)

| Tier | Condition | Offer |
|---|---|---|
| Early | < 40% fill, idle ≥ 12s (learning) / 30s | free letter, once per sitting |
| Mid-solve | ≥ 40% fill, idle ≥ 20s (learning) / 45s | check / read verse / free letter, chosen from grid state; max 3 per sitting, re-arms on input |

Mid-solve kind: unmarked wrong letters ⇒ check; else active clue has a
reference ⇒ read verse; else free letter.

### 5.7 Timing
- Clock advances **only from rendered ticks of the visible timer**, capped at
  1.5s per tick, so background/other-tab/covered time never accrues
- Suppressed while the verse reader sheet is open
- Accumulates across sittings; frozen at the solve moment
- Android equivalent: drive from a Compose `withFrameNanos`/1 s ticker that only
  runs while the composable is `RESUMED` **and** the sheet is closed. iOS needed a
  UIKit window probe because SwiftUI lifecycle lied — verify Compose's
  `Lifecycle.State` is trustworthy here, and log if not.

### 5.8 Instrumented counters (feed `puzzle_abandoned`)
`cellTaps`, `keyPresses`, `fill_percent`, `hints_used`, `idle_seconds` — per sitting.

---

## 6. Persistence & sync — **[the biggest decision]**

iOS: SwiftData `PlayerProfile` + `PuzzleRecord`, synced by CloudKit private DB,
with `SyncMerge` collapsing duplicates from sync races.

### 6.1 Local (required, straightforward)

Room, two tables mirroring the Swift models exactly:

**PlayerProfile** (single row): `username`, `currentStreak`, `bestStreak`,
`totalPuzzlesCompleted`, `lastCompletedDate`, `hintsUsedToday`, `hintsDate`,
`unlockedAchievementIDs`, `bestSolveSeconds`, `noHintSolves`, `hardCompleted`,
`completedPackIDs`, `completedQuestIDs`, `streakFreezes`, `lastFreezeUsedDate`,
`createdAt`.

**PuzzleRecord** (per puzzle): `puzzleID`, `isCompleted`, `completedDate`,
`elapsedSeconds`, `entriesData`, `pencilData`, `usedHint`, `updatedAt`.

Entries encoding must match iOS exactly: `{"row,col": "A"}`, **lowercase letter =
hint-locked cell**. Keep it — it is what lets a future cross-platform sync work.

UserDefaults-backed stores port to DataStore: memory verses, bookmarks, reading
plans, recent chapters, challenge history, `appTheme`, `autoCheckErrors`,
reminder time/enabled.

### 6.2 Cross-device sync — pick one

| Option | Cost | Consequence |
|---|---|---|
| **A. Local only** | none | Android users lose progress on device change. Simplest v1. |
| **B. Play Games Saved Games** | small | Android↔Android sync, free, no backend, no account UI. No iOS parity. |
| **C. Firebase Auth + Firestore** | large | True cross-platform sync, but iOS must migrate off CloudKit too. |

Recommendation: **B for v1** (Play Games is already needed for leaderboards, §10),
revisit C only if cross-platform demand shows up. Whatever is chosen, keep
`SyncMerge`'s merge semantics — always keep the most generous value of each field,
so a sync race never costs the player something they earned.

### 6.3 Migrations
Same rule as iOS: **any new non-null column needs an inline default**, or the app
crashes on update. Room requires an explicit migration for every schema change —
no additive free pass.

---

## 7. Screens

Five bottom-nav tabs: **Today · Packs · Library · Read · Profile**.

| Screen | Contents |
|---|---|
| **Splash** | Brief branded hold |
| **Onboarding** | Multi-page: hero, playable mini first-solve, reminder ask, paywall page. `onboarding_step` + `onboarding_first_solve` events. No reminders page (killed on iOS 2026-08-24 — do not re-add). |
| **Today (Home)** | Today's verse **stays at the top** (positioning decision, never trade it for layout). Daily card, Mini card, Sunday Special card, streak week dots, active quest, collection packs, reading-plan resume, comeback card, premium ask, trial re-offer |
| **Game** | Grid + clue bar + custom letter keyboard + clue list sheet, hint menu, check menu, pencil toggle, stall nudge line, verse-hint reader sheet, full-but-wrong alert, reveal-puzzle confirm |
| **Completion** | Time in header, streak + week dots scorecard, verse on paper, pinned bar = Challenge pill + Share icon + "…". Memory-verse door pill. ✕ to close. **No new cards above the verse.** |
| **Packs** | Pack grid, season badges, pack detail with puzzle list + progress |
| **Library** | Archive of dailies/minis/sundays, free-window framing, locked rows |
| **Read** | Bible reader (BSB), search (reference or phrase), chapter reader with puzzle chips at chapter foot, verse hint sheet, bookmarks, reading plans, memory verses |
| **Journey** | Book-by-book Bible progress map (empty / untouched / touched / deep) |
| **Profile** | Stats tiles, achievements, streak freezes, challenge history, theme picker, reminder settings, restore purchases, legal links |
| **Paywall** | Yearly (trial) + monthly plan picker; `PaywallSource` tracked on every entry |
| **Premium offer** | Proactive ask at 5 solves, once ever (`premium-ask` flag) |

Interaction requirements that carry over: haptics on key press / word solve /
wrong check, word-solve cascade flash, celebration badge, Lottie on
achievement unlock + puzzle complete + streak freeze + premium crown.

---

## 8. Monetization

- **RevenueCat Android SDK** over Google Play Billing 7+
- Shared entitlement id: **`pro`**
- New RevenueCat *app* under the existing project; products created in Play Console
- Offering: **monthly + yearly**. Yearly is currently **$12.99 with a 7-day trial**
  (iOS live price since 2026-09-01). Lifetime is legacy on iOS and **should not be
  offered on Android**. **[decision]** confirm Android launch price — the iOS $24.99
  experiment failed (1 of 11 trial→paid vs 7 of 9 at $9.99).
- Purchase outcome must distinguish **purchased(isTrial) / cancelled / pending
  (deferred) / failed(reason)** — a bare Bool loses every non-purchase, which was a
  real bug on iOS
- Restore purchases in Profile and on the paywall
- No auto paywall sheets on completion (removed on iOS 2026-09-02). Hint wall is inline.
- `syncPurchases()` on first run after a migration — the iOS gap cost real actives

### 8.1 Free tier (`PuzzleAccess` — port exactly)
- Rolling window: today's puzzle + the 6 before it, **per pool** (daily / mini),
  plus this week's Sunday Special
- Anything already started stays playable forever (a soft gate must not take
  something back)
- A pending friend challenge unlocks that puzzle, even a pack exclusive
- `pack-` exclusives are never free

---

## 9. Analytics & experiments

**Firebase Analytics + PostHog**, both fanned out from one `AnalyticsService`
interface, exactly as on iOS.

**Event names and property names must match iOS byte-for-byte** — the dashboards,
saved insights and endpoints are shared. ~110 events including: `app_open`,
`daily_puzzle_started`, `daily_puzzle_completed`, `puzzle_abandoned`, `hint_used`,
`hint_limit_reached`, `check_used`, `stall_nudge_shown`, `stall_nudge_tapped`,
`starter_word_gifted`, `streak_updated`, `streak_broken`, `paywall_opened`,
`paywall_cta_tapped`, `paywall_dismissed`, `premium_purchased`,
`purchase_cancelled`, `purchase_failed`, `challenge_sent`, `challenge_completed`,
`memory_verse_*`, `plan_*`, `read_puzzle_chip_tapped`, `app_crash`, `app_hang`.

Add one property to every event: platform = `android`, so the two apps can be
told apart in the shared project.

**PostHog feature flags** (same keys, same semantics):
`stall-nudge`, `premium-ask`, `hint-quota-one`. Read via `getFeatureFlag`, not
`isFeatureEnabled`; a flag read at the moment it takes effect is what carves the
audience.

**Crash reporting**: iOS uses MetricKit → `app_crash`/`app_hang`. Android
equivalent: Firebase Crashlytics + ANR reporting, and mirror the same two events
into analytics so the day-0 "vanished" cohort stays measurable.

---

## 10. Platform services

| iOS | Android |
|---|---|
| Game Center weekly leaderboard `mini.weekly.time` | Play Games Services leaderboard, same weekly recurrence, Mini solve times |
| CloudKit | see §6.2 |
| WidgetKit streak widget (small, medium, 3 accessory families) | Glance app widget — small + medium; no lock-screen equivalent needed |
| App Group shared defaults for widget | Same-process DataStore, or a small SharedPreferences file the Glance worker reads |
| MetricKit | Crashlytics + Play Vitals |
| `requestReview` (direct, no gate — the pre-prompt card was removed) | Play In-App Review API, same direct call |

---

## 11. Notifications

Local notifications only, no push server.

- Daily reminder at a user-chosen time; default **19:00**; suggested time seeded from
  first-session hour
- Schedules **N days ahead** with per-day copy (iOS uses `daily-<offset>` ids) because
  a local notification cannot recompute state at fire time
- Win-back copy at lapse day 3, 7, 14
- Streak-risk nudge (`streak-risk`)
- Seasonal pack openings (`pack-open-<packID>`)
- Android specifics: notification channel(s), `POST_NOTIFICATIONS` runtime permission
  (API 33+), `AlarmManager`/`WorkManager` scheduling, reschedule on `BOOT_COMPLETED`
- Opt-in placement: **on return-day completion**, inside the scorecard row — not
  onboarding, not a card. (iOS learned this the hard way: the old card was ignored
  by 76 of 79 players.)
- Tapping a notification must deep-link to the right puzzle even from a cold start

---

## 12. Deep links & the challenge loop

### 12.1 Link shapes (identical to iOS)
- Custom scheme: `biblecrossword://challenge?...`
- Web: `https://biblecrosswordchallenge.com/challenge/?...`
- Memory door: `biblecrossword://memory` (the completion door **must** use this link —
  writing the path directly renders blank on iOS)
- Marketing: `/go?s=<channel>`

Query carries puzzle id, seconds, name, version. Same parser, same
`valid / needsUpdate / notAChallenge` outcomes. Family boards ride the same
`/challenge/` path and are told apart by query, not path.

### 12.2 App Links setup — **work required**
`web/public/.well-known/` currently serves only `apple-app-site-association`.
Android needs **`assetlinks.json`** added there with the Play signing cert SHA-256,
served from the **apex** domain (apex serves the whole site; `www` is not the
canonical host).

### 12.3 Install handoff
iOS carries a challenge across an App Store install via the clipboard (two-step,
because reading the clipboard shows a paste prompt). Android can read the clipboard
without a prompt, and Play Install Referrer is the cleaner path — **[decision]**
prefer Install Referrer.

---

## 13. Design system

Port `Theme.swift` to a Compose theme.

- Accent: **system blue**. Never red. (YouVersion-derived design language.)
- Canvas: warm paper background; elevated surfaces; ink/onInk text pair
- Spacing scale 4 / 8 / 16 / 24 / 32; corner radius 20
- Buttons: `pillProminent` / `pillTonal`
- Scripture + hero titles set in a **serif** (iOS uses New York). Android has no
  New York — bundle a serif with matching warmth (Literata or Source Serif 4) and
  define `Typography.scripture`. **[decision]** pick the face.
- Cell palette: empty / border / in-word / selected / error / correct
- Light + dark + system, user-selectable (`appTheme`), applied at the root
- Dynamic Type ⇒ respect Android font scale everywhere, including the grid

---

## 14. Accessibility & localization

- Every grid cell, clue row, and card on iOS carries an explicit accessibility
  label — TalkBack needs the same (`contentDescription`, merged semantics)
- Word solves are announced to the screen reader — use `LiveRegion`
- Respect Reduce Motion: Lottie playback is gated on it on iOS; gate on
  `Settings.Global.ANIMATOR_DURATION_SCALE` / `TRANSITION_ANIMATION_SCALE`
- Minimum touch targets 48dp
- **All UI strings on iOS are hardcoded English** — there is no `Localizable.strings`.
  On Android, put every string in `strings.xml` from day one so a later translation
  is a content task, not a refactor.

---

## 15. Testing

The iOS suite (31 test files, ~355 tests) is the specification for the ported
logic. Translate these first, before writing the corresponding Kotlin:

`EngineTests`, `ProgressTests`, `HintQuotaTests`, `RotationWrapTests`,
`PuzzleAccessTests`, `PacksTests`, `QuestsTests`, `BibleJourneyTests`,
`MemoryClozeTests`, `MemoryMasteryTests`, `MemoryLevelUpWaitTests`,
`ChallengeLinkTests`, `ChallengeHistoryTests`, `FamilyBoardTests`,
`ChapterPuzzleIndexTests`, `ScriptureSearchTests`, `ReadingPlanStoreTests`,
`BookmarkStoreTests`, `ClueReferenceTests`, `VerseHintWindowTests`,
`EngagementCountersTests`, `PremiumAskTests`, `PaywallSourceTests`,
`ReminderAskTests`, `ReviewAskTests`, `TrialReofferTests`,
`NotificationCopyTests`, `PurchaseAmountTests`, `CrashDigestTests`.

Plus: Room migration tests, Compose UI tests for the grid/keyboard/completion,
and a billing smoke test against a Play internal-test track (a purchase cannot be
completed from a plain emulator install — same constraint as the iOS sandbox).

---

## 16. Release

- Play Console app, internal → closed → production tracks
- Store listing: reuse `fastlane/metadata` copy (en-US/GB/AU/CA already written)
- Screenshots: phone + 7"/10" tablet sets — the iOS `simulator-screenshots` sizes
  do not satisfy Play
- Play promo video **[decision]** optional
- Data safety form: declare analytics + purchases + (if chosen) Play Games saves
- `fastlane supply` can drive uploads; keep the UTF-8 locale export the iOS lanes need

---

## 17. Suggested phasing

1. **Skeleton** — project, theme, nav shell, content decoding, Room schema
2. **Engine** — port `GameViewModel` + rules with their tests, no UI
3. **Play a puzzle** — grid, keyboard, clue bar, clue list, save/resume
4. **Loop closes** — completion screen, streaks, achievements, Today tab
5. **Money** — RevenueCat, paywall, free-tier gating
6. **Measurement** — Firebase + PostHog + flags + Crashlytics
7. **Depth** — Read tab, memory verses, packs, quests, journey
8. **Retention surface** — notifications, widget, challenge links, Play Games
9. **Ship** — a11y pass, Play listing, internal test → production

Steps 1–5 are a playable, monetized app. 6 must land before 5 goes live to
anyone, or the launch is unmeasurable.

---

## 18. Open questions

1. **Sync**: local-only, Play Games Saved Games, or a real cross-platform backend? (§6.2)
2. **Package id** — must be fixed before RevenueCat, Play Console, and assetlinks.
3. **Android launch price** — match iOS $12.99/yr + 7-day trial, or test lower?
4. **Lifetime tier** — confirm it is not offered on Android at all.
5. **Serif typeface** for scripture — Literata, Source Serif 4, or licence New York's nearest match?
6. **SF Symbol mapping** — Kotlin lookup table (keeps JSON shared) or a new field in the content files?
7. **Install handoff for challenges** — Install Referrer, clipboard, or skip for v1?
8. **Tablet** — phone-only v1, or does the 15×15 grid need a tablet layout at launch?
9. **Play Games leaderboard** — same weekly `mini.weekly.time` semantics, or a separate Android board?
10. **Content updates** — stays bundled-per-release on Android too, or is this the moment to add a remote puzzle feed for both platforms?
