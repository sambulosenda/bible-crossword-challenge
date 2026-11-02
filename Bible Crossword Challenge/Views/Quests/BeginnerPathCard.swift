import SwiftUI

struct BeginnerPathCard: View {
    let puzzle: Puzzle
    let progress: QuestProgress
    let hasEntries: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text("Your first seven puzzles")
                .font(.headline)
            Text("\(progress.solved) of \(progress.total) completed")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            ProgressView(value: progress.fraction)
                .tint(Theme.progressBar)
                .accessibilityLabel("Beginner path progress")
                .accessibilityValue("\(progress.solved) of \(progress.total) completed")
            Text(puzzle.title)
                .font(.title2.bold())
                .fixedSize(horizontal: false, vertical: true)
            Text(progress.steppedToday
                 ? "A little each day. Your next mini is ready whenever you are."
                 : "One short mini a day, with Bible verses to help you along.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            NavigationLink(value: BeginnerPuzzleRoute(puzzle: puzzle)) {
                Label(hasEntries || progress.solved > 0 ? "Continue" : "Start Puzzle", systemImage: "play.fill")
            }
            .buttonStyle(.pillAccent)
            .accessibilityIdentifier("beginnerPathPlay")
            .accessibilityHint("Opens \(puzzle.title), an easy mini crossword")
        }
        // White, like every card on Today (2026-11-02): the solid blue fill
        // was the loudest block on the screen. Blue is the button's alone.
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .elevatedCard()
    }
}
