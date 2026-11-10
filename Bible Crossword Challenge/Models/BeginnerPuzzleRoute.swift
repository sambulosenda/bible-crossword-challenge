/// A Your First Seven step, pushed onto Today's stack so the game gets the
/// path's pacing and its `entrySource`.
struct BeginnerPuzzleRoute: Hashable {
    let puzzle: Puzzle
    /// The step onboarding hands a new player to, rather than one tapped on
    /// Today's path card. Logged under its own source so the readout can tell
    /// the hand-off from a later tap — both were `beginner_path`, and a
    /// player who lost the hand-off and found the card read as one start.
    var fromOnboarding = false

    /// `daily_puzzle_started.source` for the hand-off.
    static let onboardingSource = "onboarding_handoff"

    var entrySource: String {
        fromOnboarding ? Self.onboardingSource : "beginner_path"
    }
}
