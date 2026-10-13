# Bible Crossword Challenge — engineering rules

Each rule below exists because breaking it shipped a bug.

## View identity
- Sheets, covers, "opened/started/abandoned" analytics and session lifecycle (`.task`, `.onDisappear`, window probes) go on a view whose identity is stable. Never put them inside a `switch`/`if` branch, a layout that changes on rotation or a Duo fold, or a card that can disappear (e.g. the upgrade card removed by a purchase).
- `.task` re-runs on every pop back. A once-per-visit event needs an explicit `didLog…` guard.
- Don't build models in `State(initialValue:)`. The argument is evaluated on every parent redraw. Build once in `onAppear` (see `CrosswordGameView`).

## Analytics
- Log an impression only once the thing is actually shown. A delayed ask must be cancellable and log after its delay, not before.
- Lifecycle-sensitive events get a UI test in `Bible Crossword ChallengeUITests`. The app records events to `UI_ANALYTICS_LOG` in DEBUG (`AnalyticsRecorder`). Launch with `-uiCleanSlate -hasOnboarded YES`. Run on an iPhone simulator.

## Data
- Index records with `records.byPuzzleID`, never `Dictionary(uniqueKeysWithValues:)`. CloudKit can land duplicate `PuzzleRecord`s between merges.
- "Today" comes from `@Environment(\.today)`, not `Date()` in a body. A body reading `Date()` doesn't redraw at midnight.

## Concurrency
- The app and test targets are Swift 6 with `MainActor` default isolation. Delegate callbacks from system frameworks (UserNotifications, MetricKit, UIPasteboard completions) arrive off the main actor. Mark them `nonisolated` and hop to the main actor, passing only Sendable values across.
