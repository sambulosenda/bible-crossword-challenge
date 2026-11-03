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
        UpNextCard(
            puzzle: puzzle,
            kicker: kicker,
            note: progress.steppedToday
                ? "Today's done. The next one is ready whenever you are."
                : "About 2 minutes. Verse hints help you along.",
            // The bar once there is something to show on it.
            progress: progress.solved > 0 ? progress.fraction : nil
        ) {
            NavigationLink(value: BeginnerPuzzleRoute(puzzle: puzzle)) {
                // "Start Puzzle" is what the UI tests find the hero by.
                Label(hasEntries || progress.solved > 0 ? "Continue" : "Start Puzzle", systemImage: "play.fill")
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
