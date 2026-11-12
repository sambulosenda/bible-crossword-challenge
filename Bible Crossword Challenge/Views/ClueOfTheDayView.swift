//
//  ClueOfTheDayView.swift
//  Bible Crossword Challenge
//
//  The Clue of the Day screen and its row on Today. One answer, up to four
//  clues, hardest first; the row of squares is checked the moment it is full,
//  as a grid checks a finished word. Rules live in `ClueOfTheDay.swift`.
//
//  Progress is saved in settings, not SwiftData: it is one small value that
//  only matters today, and it must not ride CloudKit into a merge.
//

import SwiftData
import SwiftUI

/// Pushes `ClueOfTheDayView` on Today's stack.
struct ClueOfTheDayRoute: Hashable {}

/// A puzzle opened from a finished round, so its start reads as source
/// `clue_of_day`: the measure of whether the clue leads into the grid.
struct CluePuzzleRoute: Hashable {
    let puzzle: Puzzle
}

/// Where the day's progress and the running tally are kept.
enum ClueOfTheDayStorage {
    static let progressKey = "clueOfTheDay.progress"
    static let solvedCountKey = "clueOfTheDay.solvedCount"

    static func decode(_ data: Data) -> ClueProgress? {
        data.isEmpty ? nil : try? JSONDecoder().decode(ClueProgress.self, from: data)
    }

    static func encode(_ progress: ClueProgress) -> Data {
        (try? JSONEncoder().encode(progress)) ?? Data()
    }
}

// MARK: - Today row

/// Today's row. Renders nothing when there is no round to play.
struct ClueOfTheDayRow: View {
    @Environment(\.today) private var today
    @AppStorage(ClueOfTheDayStorage.progressKey) private var saved = Data()

    var body: some View {
        if let round = ClueOfTheDay.round(on: today) {
            let progress = ClueOfTheDayStorage.decode(saved).flatMap { $0.belongs(to: round, on: today) ? $0 : nil }
            let subtitle = progress?.summary(clueCount: round.clues.count) ?? "One answer, \(round.clues.count) clues"
            NavigationLink(value: ClueOfTheDayRoute()) {
                CoverRow(
                    symbol: progress?.outcome == .solved ? "checkmark" : "questionmark",
                    tint: FeatureTint.daily,
                    title: "Clue of the Day",
                    subtitle: subtitle
                )
                .cardRowPadding()
            }
            .buttonStyle(PressableCardStyle())
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("Clue of the Day. \(subtitle)")
            .accessibilityIdentifier("clueOfTheDayRow")
        }
    }
}

// MARK: - Screen

struct ClueOfTheDayView: View {
    @Environment(\.today) private var today
    @Environment(\.analytics) private var analytics
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(ClueOfTheDayStorage.progressKey) private var saved = Data()
    @AppStorage(ClueOfTheDayStorage.solvedCountKey) private var solvedCount = 0
    @Query private var records: [PuzzleRecord]

    /// Built in `onAppear`, not `State(initialValue:)`: that argument is
    /// evaluated on every parent redraw.
    @State private var game: ClueGame?
    /// `onAppear` runs again on every return to the screen; the impression
    /// is once per visit.
    @State private var didLogOpen = false
    @State private var shake = 0
    @FocusState private var keysFocused: Bool

    var body: some View {
        Group {
            if let game {
                content(game)
            } else {
                Theme.background
            }
        }
        .background(Theme.background)
        .navigationTitle("Clue of the Day")
        .navigationBarTitleDisplayMode(.inline)
        // A place to play, like the grid: the tabs come back on the way out.
        .toolbar(.hidden, for: .tabBar)
        .onAppear(perform: setUpIfNeeded)
        // Left open over midnight: the day's round changes under it.
        .onChange(of: today) {
            game = nil
            setUpIfNeeded()
        }
    }

    private func setUpIfNeeded() {
        guard game == nil, let round = ClueOfTheDay.round(on: today) else { return }
        let built = ClueGame(round: round, day: today, saved: ClueOfTheDayStorage.decode(saved))
        game = built
        if !didLogOpen {
            didLogOpen = true
            analytics.log(.clueOfDayOpened(roundID: round.id, state: Self.state(of: built)))
        }
    }

    private static func state(of game: ClueGame) -> String {
        switch game.progress.outcome {
        case .solved: "solved"
        case .missed: "missed"
        case nil: game.progress.cluesShown > 1 || game.progress.wrongGuesses > 0 ? "in_progress" : "new"
        }
    }

    // MARK: Layout

    private func content(_ game: ClueGame) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    clues(game)
                    tiles(game)
                    if game.isFinished {
                        result(game)
                    }
                }
                .padding(Theme.Spacing.m)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            if !game.isFinished {
                controls(game)
            }
        }
        .focusable(!game.isFinished)
        .focusEffectDisabled()
        .focused($keysFocused)
        .onKeyPress(characters: .letters, phases: .down) { press in
            guard let letter = press.characters.first else { return .ignored }
            enter(letter)
            return .handled
        }
        .onKeyPress(.delete, phases: .down) { _ in
            delete()
            return .handled
        }
        .onAppear { keysFocused = true }
        .sensoryFeedback(.success, trigger: game.progress.outcome == .solved) { _, solved in solved }
        .sensoryFeedback(.error, trigger: game.progress.wrongGuesses)
    }

    /// Every clue asked for so far in one card, the newest last and in ink;
    /// the ones before it step back to grey.
    private func clues(_ game: ClueGame) -> some View {
        let shown = Array(game.visibleClues)
        return VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text(game.isFinished ? "The clues" : "Clue \(shown.count) of \(game.round.clues.count)")
                .sectionHeader()
                .padding(.horizontal, Theme.Spacing.m)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(shown.enumerated()), id: \.offset) { index, clue in
                    if index > 0 { Divider().padding(.leading, Theme.Spacing.m) }
                    let isNewest = index == shown.count - 1 && !game.isFinished
                    Text(clue)
                        .font(isNewest ? .title3.weight(.semibold) : .body)
                        .foregroundStyle(isNewest || game.isFinished ? .primary : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Theme.Spacing.m)
                        .accessibilityLabel("Clue \(index + 1). \(clue)")
                }
            }
            .elevatedCard()
        }
    }

    private func tiles(_ game: ClueGame) -> some View {
        let letters = Array(game.entry)
        let solved = game.progress.outcome == .solved
        return HStack(spacing: 6) {
            ForEach(0..<game.round.answer.count, id: \.self) { index in
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(tileFill(game, solved: solved))
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: 56)
                    .overlay {
                        if index < letters.count {
                            Text(String(letters[index]))
                                .font(.title2.weight(.bold))
                                .foregroundStyle(game.isWrong ? CellPalette.error : CellPalette.textColor())
                                .minimumScaleFactor(0.6)
                        }
                    }
            }
        }
        .frame(maxWidth: .infinity)
        .modifier(Shake(travel: reduceMotion ? 0 : 8, shakes: CGFloat(shake)))
        .animation(reduceMotion ? nil : .default, value: shake)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tilesLabel(game))
    }

    private func tileFill(_ game: ClueGame, solved: Bool) -> Color {
        if solved { return CellPalette.fill(isSelected: false, isInWord: false, isCorrect: true) }
        if game.isWrong { return CellPalette.errorWash }
        return CellPalette.empty
    }

    private func tilesLabel(_ game: ClueGame) -> String {
        let count = game.round.answer.count
        if game.isFinished { return "The answer: \(game.round.answer)" }
        if game.isWrong { return "\(game.entry), not the answer" }
        return game.entry.isEmpty ? "\(count) letters" : "\(game.entry), \(game.entry.count) of \(count) letters"
    }

    /// The one choice besides typing, over the keys.
    private func controls(_ game: ClueGame) -> some View {
        VStack(spacing: 0) {
            Button(game.hasEasierClue ? "Show an easier clue" : "Show the answer") {
                game.hasEasierClue ? revealClue() : showAnswer()
            }
            .font(.headline)
            .padding(.vertical, Theme.Spacing.s)
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
            .accessibilityIdentifier("clueOfTheDayEasier")

            LetterKeyboardView(onLetter: enter, onDelete: delete)
        }
    }

    private func result(_ game: ClueGame) -> some View {
        let solved = game.progress.outcome == .solved
        let used = game.progress.cluesShown
        return VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(solved ? (used == 1 ? "Solved in 1 clue" : "Solved in \(used) clues") : "The answer was \(game.round.answer.capitalized)")
                    .font(.title2.weight(.bold))
                Text(solved && solvedCount > 1 ? "\(solvedCount) solved so far. A new clue tomorrow." : "A new clue tomorrow.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, Theme.Spacing.m)

            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Text(game.round.verse)
                    .font(.scripture(.title3))
                    .fixedSize(horizontal: false, vertical: true)
                Text(game.round.reference)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.m)
            .elevatedCard()
            .accessibilityElement(children: .combine)

            // The screen's one blue button: on to the grid. Sharing steps
            // back to the quiet weight beside it.
            if let next = nextPuzzle() {
                NavigationLink(value: CluePuzzleRoute(puzzle: next.puzzle)) {
                    Label(next.title, systemImage: "play.fill")
                }
                .buttonStyle(.pillAccent)
                .accessibilityIdentifier("clueOfTheDayPlay")
            }
            if solved {
                ShareLink(item: shareText(used: used, of: game.round.clues.count)) {
                    Label("Share result", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.pillTonal)
            }
        }
    }

    /// Today's crossword, or the Mini once that is done, with the words for
    /// where the player stands in it. Nil when both are finished today.
    private func nextPuzzle() -> (puzzle: Puzzle, title: String)? {
        let byID = records.byPuzzleID
        let calendar = Calendar.current
        let next = ClueOfTheDay.nextPuzzle(on: today) { puzzle in
            guard let record = byID[puzzle.id], record.isCompleted, let done = record.completedDate else { return false }
            return calendar.isDate(done, inSameDayAs: today)
        }
        guard let next else { return nil }
        let kind = next.id.hasPrefix("mini-") ? "Mini" : "crossword"
        let started = byID[next.id]?.hasPlayerEntries == true && byID[next.id]?.isCompleted != true
        return (next, "\(started ? "Continue" : "Play") today's \(kind)")
    }

    /// The result without the answer: a friend can still play today's. The
    /// link is the site's install hop, so these installs read as campaign
    /// `clue` in App Store Connect.
    private func shareText(used: Int, of total: Int) -> String {
        "Clue of the Day: solved in \(used) of \(total) clues.\nBible Crossword Challenge https://biblecrosswordchallenge.com/go/?s=clue"
    }

    // MARK: Play

    private func enter(_ letter: Character) {
        guard var current = game else { return }
        let result = current.type(letter)
        game = current
        switch result {
        case .solved:
            solvedCount += 1
            finish(current)
        case .wrong:
            shake += 1
            save(current)
        case nil:
            break
        }
    }

    private func delete() {
        game?.delete()
    }

    private func revealClue() {
        guard var current = game, current.revealClue() else { return }
        game = current
        save(current)
        analytics.log(.clueOfDayClueRevealed(roundID: current.round.id, clueNumber: current.progress.cluesShown))
    }

    private func showAnswer() {
        guard var current = game, current.showAnswer() else { return }
        game = current
        finish(current)
    }

    private func finish(_ game: ClueGame) {
        save(game)
        analytics.log(.clueOfDayFinished(
            roundID: game.round.id,
            outcome: game.progress.outcome?.rawValue ?? "",
            cluesUsed: game.progress.cluesShown,
            wrongGuesses: game.progress.wrongGuesses
        ))
    }

    private func save(_ game: ClueGame) {
        saved = ClueOfTheDayStorage.encode(game.progress)
    }
}

/// A sideways shake for a wrong spelling. `shakes` counts wrong guesses, so
/// each one animates a whole number of swings and lands back at rest.
private nonisolated struct Shake: GeometryEffect {
    var travel: CGFloat
    var shakes: CGFloat

    var animatableData: CGFloat {
        get { shakes }
        set { shakes = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: travel * sin(shakes * .pi * 4), y: 0))
    }
}
