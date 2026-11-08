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
- [x] Xcode Cloud: unit tests on every push to main. Live 2026-11-08 (workflow still named "Default"; Xcode 27.2, iPhone 17, `UnitTests` plan, 435 tests in ~6.5 min). Build 1 failed on dl.google.com timeouts fetching Firebase binaries; the rebuild passed. Watch for repeats.
- [~] Xcode Cloud: archive + TestFlight upload on a `v*` tag; retires the local archive (no more 10 GB disk issue).
- [ ] Migration test: open a store saved by the previous release with the current build (SwiftData inline defaults).
- [ ] CloudKit schema guard: fail if @Model fields changed since last recorded schema deploy.
- [x] Content runway guard: already exists — `RotationWrapTests` + `schedule.json` (see roadmap/README.md "Dated").

## Xcode Cloud setup (Sambulo, one time)
Repo side is in place:
- `ci_scripts/ci_post_clone.sh` trusts package plugins/macros.
- `ci_scripts/ci_pre_xcodebuild.sh` runs `tools/validate_content.py` before every build.
- Scheme test plans: `AllTests` (default, local) and `UnitTests` (CI, no UI tests, saves compute hours).
- `SpecVectorsTests` and `PurchaseFlowTests` skip on CI test machines, which have no repo checkout.

Steps:
1. Push main to GitHub. Xcode Cloud builds from there.
2. Xcode → Product → Xcode Cloud → Create Workflow → Bible Crossword Challenge. Grant GitHub access when asked.
3. Workflow **Tests**:
   - Start condition: branch changes, `main`.
   - Environment: latest release Xcode (27.1, not beta).
   - Action: Test, scheme Bible Crossword Challenge, test plan **UnitTests**, a recent iPhone simulator.
4. Workflow **Release**:
   - Start condition: tag changes, `v*`. Same environment.
   - Action: Archive, iOS, deployment preparation **App Store Connect**.
   - Post-action: TestFlight internal testing.
5. App Store Connect → the app → Xcode Cloud → Settings → set the next build number to **32** (2.19 used 31).

Release from then on:
- Bump `MARKETING_VERSION` and commit.
- Tag it `v2.20` and push the tag. Cloud signs, archives and uploads.
- Submit in ASC as before.

## Track 2 — Code health
- [ ] Freeze spec vectors while Android is on hold: stop iOS test failing on vector changes; keep files for later.
- [ ] UI tests: onboarding → first solve; completion events; paywall open/cancel.
- [ ] Split CompletionView / CrosswordGameView / HomeView / GameViewModel when touched.
- [ ] Remove leftovers: empty FeatureFlags hook, stale `.claude/worktrees`.

## Track 3 — Product
Features + game expansion live in `roadmap/` (epics 01–17, `BACKLOG.md`). This file covers only the engineering work around them.

## Open
- 70/30 split and "split when touched" are defaults; revisit after 2 releases.
