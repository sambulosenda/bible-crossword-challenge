//
//  HomeView.swift
//  Bible Crossword Challenge
//
//  The "Today" tab. The screen opens like a page rather than a dashboard: a
//  greeting and the date, the day's verse set in serif on the bare paper, and
//  only then the daily puzzle — the one card that carries a tint, so the hero
//  is unmistakable among the white cards below it (mini, streak, collections,
//  next achievement, upgrade, and a bottom banner placeholder).
//
//  Each card is its own `View` type with narrow VALUE inputs so SwiftUI can
//  skip re-evaluating cards whose inputs didn't change (e.g. the verse card
//  stays put when only the streak updates).
//

import SwiftUI
import SwiftData

struct HomeView: View {
    let profile: PlayerProfile
    /// Owned by RootView so a widget deep-link can push the daily puzzle here.
    @Binding var path: NavigationPath

    @Environment(\.puzzleProvider) private var puzzleProvider
    @Environment(\.ads) private var ads
    @Environment(StoreService.self) private var store
    @Query private var records: [PuzzleRecord]

    private var dailyPuzzle: Puzzle? { puzzleProvider.dailyPuzzle() }
    private var dailyMini: Puzzle? { puzzleProvider.dailyMini() }

    /// Packs available today (seasonal ones only surface in-window), seasonal
    /// first so a timely pack leads the carousel.
    private var collectionPacks: [PuzzlePack] {
        let available = puzzleProvider.availablePacks()
        return available.filter(\.isSeasonal) + available.filter { !$0.isSeasonal }
    }

    /// Shared record lookup for pack-progress calculation in the carousel.
    private var recordsByID: [String: PuzzleRecord] {
        Dictionary(records.map { ($0.puzzleID, $0) }, uniquingKeysWith: { a, _ in a })
    }

    /// True when a streak freeze was spent today, so the streak card can show a
    /// one-time reassurance instead of the idle freeze count.
    private var freezeSavedToday: Bool {
        guard let used = profile.lastFreezeUsedDate else { return false }
        return Calendar.current.isDateInToday(used)
    }

    /// Weekdays with a completed puzzle in the current week, for the streak
    /// card's week row.
    private var completedWeekdaysThisWeek: Set<Int> {
        let calendar = Calendar.current
        guard let week = calendar.dateInterval(of: .weekOfYear, for: Date()) else { return [] }
        return Set(records.compactMap { record in
            guard record.isCompleted, let date = record.completedDate, week.contains(date) else { return nil }
            return calendar.component(.weekday, from: date)
        })
    }

    var body: some View {
        // Resolve the daily puzzle + its record once per body pass; the verse
        // card derives from the puzzle so it never spoils today's answer.
        let daily = dailyPuzzle
        let record = daily.flatMap { d in records.first { $0.puzzleID == d.id } }
        let mini = dailyMini
        let miniRecord = mini.flatMap { m in records.first { $0.puzzleID == m.id } }

        return NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: Theme.Spacing.l) {
                    TodayHeader(
                        name: displayName,
                        verse: verseOfTheDay(excluding: daily)
                    )

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
                        savedRecently: freezeSavedToday,
                        completedWeekdays: completedWeekdaysThisWeek
                    )

                    if !collectionPacks.isEmpty {
                        CollectionsCarousel(
                            packs: collectionPacks,
                            recordsByID: recordsByID,
                            isPremium: store.isPremium
                        )
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
            // Inline, because the greeting below is the screen's real title —
            // a large "Today" on top of it would be two headings for one page.
            .navigationTitle("Today")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Puzzle.self) { puzzle in
                CrosswordGameView(puzzle: puzzle, profile: profile)
            }
            .navigationDestination(for: PuzzlePack.self) { pack in
                PackDetailView(pack: pack, profile: profile)
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
                .font(.scripture(.title3, weight: .bold))
            Text("In the meantime, you can replay any puzzle from the Archive.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.l)
        .elevatedCard()
        .accessibilityElement(children: .combine)
    }

    /// The player's name for the greeting, or nil while it's still the
    /// placeholder a fresh profile is created with — "Good evening, Friend"
    /// reads like a form letter.
    private var displayName: String? {
        let trimmed = profile.username.trimmingCharacters(in: .whitespaces)
        return (trimmed.isEmpty || trimmed == "Friend") ? nil : trimmed
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

// MARK: - Today header
//
// The page's opening: date, greeting, and the day's verse set on the bare paper
// rather than in a card. Scripture is the one thing here that isn't a module,
// and taking the white box away is what says so — a card would file it
// alongside "Next Achievement".

private struct TodayHeader: View {
    /// Nil when the player hasn't named themselves; the greeting stands alone.
    let name: String?
    /// Nil only if the bundled puzzle set is missing.
    let verse: Puzzle?

    @Environment(\.readerRouter) private var readerRouter

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .kicker()
                // Sans, not serif. A salutation is chrome, not content, and
                // keeping the serif for scripture alone is what lets the verse
                // below stand apart without a rule or a box drawn around it.
                // Smaller than the daily card's title too: the puzzle is what
                // you came for, so it keeps the largest type on the page.
                Text(greeting)
                    .font(.title2.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)

            if let verse {
                scripture(verse)
            }
        }
        .padding(.horizontal, Theme.Spacing.xs)
        .padding(.top, Theme.Spacing.s)
    }

    private var greeting: String {
        let stem: String
        switch Calendar.current.component(.hour, from: Date()) {
        case 0..<12: stem = "Good morning"
        case 12..<17: stem = "Good afternoon"
        default: stem = "Good evening"
        }
        return name.map { "\(stem), \($0)" } ?? stem
    }

    /// Scripture, set plainly. No rule, no box, no quote glyph: the serif is
    /// the only serif in the header, and that is the whole signal. An ornament
    /// here would be decoration standing in for a typographic distinction that
    /// the type is already making.
    ///
    /// It is labelled, though. Removing the card removed the kicker with it,
    /// which left an unexplained quotation under the greeting — the VoiceOver
    /// label named it all along, so only sighted readers lost the answer to
    /// "what is this?".
    private func scripture(_ verse: Puzzle) -> some View {
        Button {
            readerRouter.open(reference: verse.reference)
        } label: {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    Text("Verse of the Day")
                        .kicker()
                    // Three lines, then truncate. Verses run from one line to
                    // six, and an unbounded header pushed the daily card's CTA
                    // below the fold on a 667pt screen while landing it in a
                    // different place every day. The reference below is the
                    // affordance for reading the whole passage.
                    Text(verse.verse)
                        .font(.scripture(.title3))
                        .lineSpacing(6)
                        .lineLimit(3)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 4) {
                    Text(verse.reference)
                        .font(.headline)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                }
                .foregroundStyle(Theme.accent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Verse of the day. \(verse.verse). \(verse.reference)")
        .accessibilityHint("Opens this passage in the reader")
    }
}

// MARK: - Daily puzzle card
//
// The hero of the screen. It is the only tinted card on Today — every other
// module is white — so the eye lands here first without any of them shouting.
// A larger serif title and roomier padding carry the rest; the accent wash is
// the same device the completion screen uses to mark its one important card.
// When solved it becomes a quiet win moment (the time you earned) rather than
// a dead "done" tile.

private struct DailyPuzzleCard: View {
    let puzzle: Puzzle
    let status: PuzzleStatus
    var solveSeconds: Int? = nil
    var progress: Double? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var celebrate = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            info
            actionButton
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .elevatedCard(fill: Theme.accent.opacity(0.10))
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

            HStack(alignment: .top, spacing: Theme.Spacing.m) {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    Text(puzzle.title)
                        .font(.scripture(.title, weight: .bold))
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

                Spacer(minLength: 0)

                // Today's actual grid shape, in miniature. Ornament that happens
                // to be true — and the first thing that makes one day's card
                // look different from the next. Dropped at accessibility sizes,
                // where the title needs the whole width.
                if !typeSize.isAccessibilitySize {
                    GridThumbnail(grid: puzzle.grid)
                        .frame(width: 72, height: 72)
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
            // out-shouting the ink pill used for unsolved puzzles.
            NavigationLink(value: puzzle) {
                Label("Play again", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.pillTonal)
        } else {
            NavigationLink(value: puzzle) {
                Label(status.actionTitle, systemImage: status.actionSymbol)
            }
            .buttonStyle(.pillProminent)
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

// MARK: - Collections carousel
//
// A horizontal strip of themed packs, so collections are discoverable from the
// daily feed rather than only via the Packs tab. Each tile pushes the pack's
// detail onto the Today stack.

private struct CollectionsCarousel: View {
    let packs: [PuzzlePack]
    let recordsByID: [String: PuzzleRecord]
    let isPremium: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Label("COLLECTIONS", systemImage: "square.stack.3d.up").kicker()
                .padding(.horizontal, Theme.Spacing.xs)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.m) {
                    ForEach(packs) { pack in
                        NavigationLink(value: pack) {
                            PackTile(
                                pack: pack,
                                progress: PackProgress(pack: pack, recordsByID: recordsByID),
                                isLocked: pack.isPremium && !isPremium
                            )
                        }
                        .buttonStyle(PressableCardStyle())
                    }
                }
                .padding(.horizontal, Theme.Spacing.xs)
                // Give the row breathing room so the last tile's shadow/press
                // scale isn't clipped by the ScrollView edge.
                .padding(.vertical, 2)
            }
        }
    }
}

/// A compact, fixed-width pack card sized for the horizontal carousel.
private struct PackTile: View {
    let pack: PuzzlePack
    let progress: PackProgress
    let isLocked: Bool

    @ScaledMetric(relativeTo: .title) private var coverSize = 44

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack {
                Image(systemName: pack.coverSymbol)
                    .font(.title3)
                    .foregroundStyle(pack.accent)
                    .frame(width: coverSize, height: coverSize)
                    .background(pack.accent.opacity(0.14), in: .rect(cornerRadius: 12, style: .continuous))
                Spacer(minLength: 0)
                if isLocked {
                    Image(systemName: "crown.fill")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                }
            }

            Text(pack.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            if progress.isComplete {
                Label("Complete", systemImage: "checkmark.seal.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.green)
            } else {
                ProgressView(value: progress.fraction).tint(pack.accent)
                Text("\(progress.solved)/\(progress.total)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(Theme.Spacing.m)
        .frame(width: 160, height: 150, alignment: .topLeading)
        .elevatedCard()
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        var parts = [pack.title]
        if isLocked { parts.append("Premium") }
        parts.append(progress.isComplete ? "Complete" : "\(progress.solved) of \(progress.total) solved")
        return parts.joined(separator: ". ")
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
    @State private var showPaywall = false

    var body: some View {
        // A sheet, as every other entry point presents it. Pushed onto the
        // Today stack instead, the paywall arrived with a navigation back
        // button colliding with its own close button and the tab bar sitting
        // over its legal text.
        Button {
            showPaywall = true
        } label: {
            HStack(spacing: Theme.Spacing.m) {
                Image(systemName: "crown.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: iconSize, height: iconSize)
                    .background(Color.primary.opacity(0.06), in: .circle)
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
            // Plain white like every other module: the upsell was the only
            // tinted card on the screen, which made it louder than the puzzle.
            // That tint now belongs to the daily card.
            .elevatedCard()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Go Premium")
            .accessibilityHint("Remove ads, unlimited hints, and full puzzle archive")
        }
        .buttonStyle(PressableCardStyle())
        .sheet(isPresented: $showPaywall) {
            PaywallView(source: "home_card")
        }
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
        .buttonStyle(PressableCardStyle())
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
