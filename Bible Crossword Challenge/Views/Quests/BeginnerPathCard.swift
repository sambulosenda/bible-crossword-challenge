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
                .monospacedDigit()
            ProgressView(value: progress.fraction)
                .tint(.white)
                .accessibilityLabel("Beginner path progress")
                .accessibilityValue("\(progress.solved) of \(progress.total) completed")
            Text(puzzle.title)
                .font(.title2.bold())
                .fixedSize(horizontal: false, vertical: true)
            Text(progress.steppedToday
                 ? "A little each day. Your next mini is ready whenever you are."
                 : "One short mini a day, with Bible verses to help you along.")
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            NavigationLink(value: BeginnerPuzzleRoute(puzzle: puzzle)) {
                Label(hasEntries || progress.solved > 0 ? "Continue" : "Start Puzzle", systemImage: "play.fill")
            }
            .buttonStyle(.pillOnColor)
            .accessibilityIdentifier("beginnerPathPlay")
            .accessibilityHint("Opens \(puzzle.title), an easy mini crossword")
        }
        .foregroundStyle(.white)
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.accent, in: .rect(cornerRadius: Theme.cornerRadius))
    }
}
