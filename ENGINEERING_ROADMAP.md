# Engineering roadmap

Solo dev (Sambulo + Claude). Started 2026-11-07. Living doc: tick items, add dates.

## Rules
- ~70% product / 30% engineering. Each release = 1 product change + 1 Track 1/2 item.
- Every fix ships with a test that reproduces it.
- Readout 2 weeks after a release before building more on that surface.
- Split big files only when a product change touches them. No big-bang rewrite.

## Baseline (2026-11-07)
- 136 commits / 30d: 76 feat, 31 fix (~1 in 4 is a fix; game + design churn).
- No CI. Releases = local fastlane, archive with Xcode 27.1 (beta builds rejected).
- App 102 files / 29.5k lines; tests 34 files / 6.8k lines; 2 UI test files.
- Big files: CompletionView 1804, CrosswordGameView 1699, HomeView 1521, GameViewModel 1219.

## Track 1 — Release safety (do first)
- [ ] Xcode Cloud: unit tests on every push to main (iPhone sim, Xcode 27.1).
- [ ] Xcode Cloud: archive + TestFlight upload workflow on tag; retire local archive (no more 10 GB disk issue).
- [ ] Migration test: open a store saved by the previous release with the current build (SwiftData inline defaults).
- [ ] CloudKit schema guard: fail if @Model fields changed since last recorded schema deploy.
- [x] Content runway guard: already exists — `RotationWrapTests` + `schedule.json` (see roadmap/README.md "Dated").

## Track 2 — Code health
- [ ] Freeze spec vectors while Android is on hold: stop iOS test failing on vector changes; keep files for later.
- [ ] UI tests: onboarding → first solve; completion events; paywall open/cancel.
- [ ] Split CompletionView / CrosswordGameView / HomeView / GameViewModel when touched.
- [ ] Remove leftovers: empty FeatureFlags hook, stale `.claude/worktrees`.

## Track 3 — Product
Features + game expansion live in `roadmap/` (epics 01–17, `BACKLOG.md`). This file covers only the engineering work around them.

## Open
- 70/30 split and "split when touched" are defaults; revisit after 2 releases.
