import SwiftUI

/// Today's lead for a new player: the next of their first seven Minis.
///
/// The collection pages' card since 2026-11-03 — the puzzle's grid, where it
/// sits in the seven, what it is, one line that answers "how hard, how long",
/// and the button. It led with "Your first seven puzzles · 0 of 7 completed"
/// and an empty bar: seven things not yet done, before the puzzle itself, on
/// the card whose one job is a first solve.
struct BeginnerPathCard: View {
    let puzzle: Puzzle
    let progress: QuestProgress
    let hasEntries: Bool

    var body: some View {
        // 2026-11-04, three things said once each:
        // - No bar. It measured the seven but sat under the puzzle, so it
        //   read as progress through this grid; the kicker already says
        //   "2 of 7 done", and it was the heaviest mark after the button.
        // - Size, difficulty and time on one line. "7×7 · Easy" above and
        //   "About 2 minutes" below said how big twice.
        // - "Continue" only for a grid with letters in it. After a solve the
        //   next step is new, and "Continue" promised something begun.
        UpNextCard(
            puzzle: puzzle,
            kicker: kicker,
            detail: "\(puzzle.reference) · \(puzzle.difficulty.label) · About 2 min",
            note: progress.steppedToday
                ? "Today's done. The next one is ready whenever you are."
                : "Verse hints help you along."
        ) {
            NavigationLink(value: BeginnerPuzzleRoute(puzzle: puzzle)) {
                // "Start Puzzle" is what the UI tests find the hero by.
                Label(hasEntries ? "Continue" : "Start Puzzle", systemImage: "play.fill")
            }
            .buttonStyle(.pillAccent)
            .accessibilityIdentifier("beginnerPathPlay")
            .accessibilityHint("Opens \(puzzle.title), an easy mini crossword")
        }
    }

    /// "Your first seven · 1 of 7" before the first solve — the puzzle's
    /// place, not a count of what's left — then "3 of 7 done".
    private var kicker: String {
        progress.solved == 0
            ? "Your first seven · 1 of \(progress.total)"
            : "Your first seven · \(progress.solved) of \(progress.total) done"
    }
}
