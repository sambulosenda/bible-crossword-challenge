//
//  HomeView.swift
//  Bible Crossword Challenge
//
//  The "Today" tab: a time-based greeting and date, the daily puzzle card,
//  streak summary, verse of the day, next achievement, an upgrade prompt for
//  free users, and a bottom banner placeholder.
//
//  Each card is its own `View` type with narrow VALUE inputs so SwiftUI can
//  skip re-evaluating cards whose inputs didn't change (e.g. the verse card
//  stays put when only the streak updates).
//

import SwiftUI
import SwiftData

struct HomeView: View {
    let profile: PlayerProfile

    @Environment(\.puzzleProvider) private var puzzleProvider
    @Environment(\.ads) private var ads
    @Environment(StoreService.self) private var store
    @Query private var records: [PuzzleRecord]

    private var dailyPuzzle: Puzzle? { puzzleProvider.dailyPuzzle() }
    private var dailyMini: Puzzle? { puzzleProvider.dailyMini() }

    /// True when a streak freeze was spent today, so the streak card can show a
    /// one-time reassurance instead of the idle freeze count.
    private var freezeSavedToday: Bool {
        guard let used = profile.lastFreezeUsedDate else { return false }
        return Calendar.current.isDateInToday(used)
    }

    var body: some View {
        // Resolve the daily puzzle + its record once per body pass; the verse
        // card derives from the puzzle so it never spoils today's answer.
        let daily = dailyPuzzle
        let record = daily.flatMap { d in records.first { $0.puzzleID == d.id } }
        let mini = dailyMini
        let miniRecord = mini.flatMap { m in records.first { $0.puzzleID == m.id } }

        return NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.l) {
                    if let daily {
                        DailyPuzzleCard(
                            puzzle: daily,
                            status: PuzzleStatus(record: record),
                            solveSeconds: record?.isCompleted == true ? record?.elapsedSeconds : nil,
                            progress: inProgressFraction(daily, record: record)
                        )
                    } else {
                        emptyDailyCard
                    }

                    if let mini {
                        MiniPuzzleCard(
                            puzzle: mini,
                            status: PuzzleStatus(record: miniRecord),
                            solveSeconds: miniRecord?.isCompleted == true ? miniRecord?.elapsedSeconds : nil
                        )
                    }

                    StreakCard(
                        current: profile.currentStreak,
                        best: profile.bestStreak,
                        freezes: profile.streakFreezes,
                        savedRecently: freezeSavedToday
                    )

                    if let verse = verseOfTheDay(excluding: daily) {
                        VerseCard(puzzle: verse)
                    }

                    NextAchievementCard(profile: profile)

                    if !store.isPremium {
                        UpgradeCard()
                    }
                }
                .padding(Theme.Spacing.m)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .background(Theme.background)
            .navigationTitle("Today")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: Puzzle.self) { puzzle in
                CrosswordGameView(puzzle: puzzle, profile: profile)
            }
            .safeAreaInset(edge: .bottom) {
                if !store.isPremium && ads.isLive {
                    BannerAdView()
                }
            }
        }
    }

    // MARK: - Empty state (only reachable if the bundled puzzle set is missing)

    private var emptyDailyCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Label("DAILY PUZZLE", systemImage: "calendar").kicker()
            Text("Today's puzzle is on its way")
                .font(.title3.weight(.bold))
            Text("In the meantime, you can replay any puzzle from the Archive.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.l)
        .elevatedCard()
        .accessibilityElement(children: .combine)
    }

    // MARK: - Derived state

    /// Fraction of playable cells filled, or nil when the puzzle isn't mid-solve.
    private func inProgressFraction(_ puzzle: Puzzle, record: PuzzleRecord?) -> Double? {
        guard let record, !record.isCompleted, !record.entries.isEmpty else { return nil }
        let total = puzzle.grid.reduce(0) { $0 + $1.filter { $0 != "." }.count }
        guard total > 0 else { return nil }
        return min(1.0, Double(record.entries.count) / Double(total))
    }

    /// A daily inspirational verse, rotated deterministically and chosen from a
    /// puzzle other than today's so it never spoils the daily answer.
    private func verseOfTheDay(excluding daily: Puzzle?) -> Puzzle? {
        let pool = puzzleProvider.puzzles.filter { $0.id != daily?.id }
        guard !pool.isEmpty else { return nil }
        let day = Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0
        return pool[((day % pool.count) + pool.count) % pool.count]
    }
}

// MARK: - Daily puzzle card
//
// The hero of the screen — it earns focus through hierarchy (a large serif
// title, the accent kicker, a prominent CTA), not a saturated colour block, and
// shares the same elevated surface as every other card. When solved it becomes
// a quiet win moment (the time you earned) rather than a dead "done" tile.

private struct DailyPuzzleCard: View {
    let puzzle: Puzzle
    let status: PuzzleStatus
    var solveSeconds: Int? = nil
    var progress: Double? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var celebrate = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            info
            actionButton
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .elevatedCard()
        .onAppear {
            if status == .completed && !reduceMotion { celebrate.toggle() }
        }
    }

    // Non-interactive content, grouped as one VoiceOver element; the action
    // button stays a separate focusable control below.
    private var info: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack {
                Label("DAILY PUZZLE", systemImage: "calendar").kicker()
                Spacer()
                DifficultyBadge(difficulty: puzzle.difficulty)
            }

            Text(puzzle.title)
                .font(.title2.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)

            if status == .completed {
                solvedReward
            } else {
                metaRow
                if let progress {
                    ProgressView(value: progress)
                        .tint(Theme.accent)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private var metaLabels: some View {
        Label("\(puzzle.clueCount) clues", systemImage: "list.bullet")
        Label("\(puzzle.size)×\(puzzle.size)", systemImage: "square.grid.3x3")
    }

    private var metaRow: some View {
        // Stacks vertically when the labels can't fit side by side (large Dynamic Type).
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Theme.Spacing.m) { metaLabels }
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) { metaLabels }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }

    // The win moment: leads with the time the user just earned, echoing the
    // CompletionView language (green seal + monospaced clock).
    // A compact success pill that hugs its content (not a full-width bar).
    private var solvedReward: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(.green)
                .symbolEffect(.bounce, value: celebrate)
            Text("Solved").foregroundStyle(.green)
            if let secs = solveSeconds, secs > 0 {
                Text("in \(TimeFormat.clock(secs))")
                    .foregroundStyle(.primary)
                    .monospacedDigit()
            }
        }
        .font(.subheadline.weight(.semibold))
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, Theme.Spacing.s)
        .background(Color.green.opacity(0.12), in: .capsule)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var actionButton: some View {
        if status == .completed {
            // Full-width but secondary (tonal) — replay stays available without
            // out-shouting the prominent CTA used for unsolved puzzles.
            NavigationLink(value: puzzle) {
                Label("Play again", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        } else {
            NavigationLink(value: puzzle) {
                Label(status.actionTitle, systemImage: status.actionSymbol)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    private var accessibilityLabel: String {
        switch status {
        case .completed:
            if let secs = solveSeconds, secs > 0 {
                return "Daily puzzle. \(puzzle.title). Solved in \(TimeFormat.clock(secs))."
            }
            return "Daily puzzle. \(puzzle.title). Completed."
        case .inProgress:
            return "Daily puzzle. \(puzzle.title). \(puzzle.difficulty.label) difficulty. In progress. \(puzzle.clueCount) clues, \(puzzle.size) by \(puzzle.size) grid."
        case .start:
            return "Daily puzzle. \(puzzle.title). \(puzzle.difficulty.label) difficulty. \(puzzle.clueCount) clues, \(puzzle.size) by \(puzzle.size) grid."
        }
    }
}

// MARK: - Verse of the day card

private struct VerseCard: View {
    let puzzle: Puzzle

    @Environment(\.readerRouter) private var readerRouter

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Label("VERSE OF THE DAY", systemImage: "book.closed").kicker()
            Text(puzzle.verse)
                .font(.callout)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                readerRouter.open(reference: puzzle.reference)
            } label: {
                HStack(spacing: 4) {
                    Text(puzzle.reference)
                        .font(.subheadline.weight(.semibold))
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                }
                .foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .elevatedCard()
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Verse of the day. \(puzzle.verse). \(puzzle.reference)")
        .accessibilityHint("Opens this passage in the reader")
        .accessibilityAction { readerRouter.open(reference: puzzle.reference) }
    }
}

// MARK: - Next achievement card

private struct NextAchievementCard: View {
    let profile: PlayerProfile

    @ScaledMetric(relativeTo: .title) private var iconSize = 52

    var body: some View {
        if let next = Achievements.all.first(where: { !$0.isUnlocked(by: profile) }) {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                Label("NEXT ACHIEVEMENT", systemImage: "target").kicker()
                HStack(spacing: Theme.Spacing.m) {
                    iconTile(next.symbol)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(next.title).font(.headline)
                        Text(next.detail).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Text(next.progressText(for: profile))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: next.progress(for: profile))
                    .tint(Theme.accent)
            }
            .padding(Theme.Spacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .elevatedCard()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Next achievement: \(next.title), \(next.detail), \(next.progressText(for: profile)) complete")
        } else {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                Label("ACHIEVEMENTS", systemImage: "star.circle.fill").kicker()
                HStack(spacing: Theme.Spacing.m) {
                    iconTile("star.circle.fill")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("All achievements unlocked").font(.headline)
                        Text("You've completed every milestone.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(Theme.Spacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .elevatedCard()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("All achievements unlocked. You've completed every milestone.")
        }
    }

    private func iconTile(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.title2)
            .foregroundStyle(Theme.accent)
            .frame(width: iconSize, height: iconSize)
            .background(Theme.accent.opacity(0.14), in: .circle)
    }
}

// MARK: - Upgrade card

private struct UpgradeCard: View {
    @ScaledMetric(relativeTo: .title) private var iconSize = 44

    var body: some View {
        NavigationLink {
            PaywallView()
        } label: {
            HStack(spacing: Theme.Spacing.m) {
                Image(systemName: "crown.fill")
                    .font(.title3)
                    .foregroundStyle(Theme.accent)
                    .frame(width: iconSize, height: iconSize)
                    .background(Theme.accent.opacity(0.16), in: .circle)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Go Premium")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.primary)
                    Text("Remove ads · Unlimited hints · Archive")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(Theme.Spacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .elevatedCard(fill: Theme.accent.opacity(0.10))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Go Premium")
            .accessibilityHint("Remove ads, unlimited hints, and full puzzle archive")
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Daily Mini card
//
// A compact companion to the hero card: the quick 7×7 for days (or moments)
// the full puzzle is too big. Kept visually lighter than the daily so it
// reads as the second course, not a competing headline.

private struct MiniPuzzleCard: View {
    let puzzle: Puzzle
    let status: PuzzleStatus
    var solveSeconds: Int? = nil

    var body: some View {
        NavigationLink(value: puzzle) {
            HStack(spacing: Theme.Spacing.m) {
                Image(systemName: status == .completed ? "checkmark.circle.fill" : "bolt.circle.fill")
                    .font(.title)
                    .foregroundStyle(status == .completed ? .green : Theme.accent)

                VStack(alignment: .leading, spacing: 2) {
                    Label("DAILY MINI", systemImage: "square.grid.3x3").kicker()
                    Text(puzzle.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(Theme.Spacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .elevatedCard()
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var subtitle: String {
        switch status {
        case .completed:
            if let secs = solveSeconds, secs > 0 {
                return "Solved in \(TimeFormat.clock(secs))"
            }
            return "Solved"
        case .inProgress:
            return "In progress · \(puzzle.size)×\(puzzle.size)"
        case .start:
            return "\(puzzle.size)×\(puzzle.size) · A quick two-minute puzzle"
        }
    }

    private var accessibilityLabel: String {
        switch status {
        case .completed: return "Daily mini. \(puzzle.title). \(subtitle)."
        case .inProgress: return "Daily mini. \(puzzle.title). In progress."
        case .start: return "Daily mini. \(puzzle.title). A quick two-minute puzzle."
        }
    }
}
