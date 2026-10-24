//
//  ProfileView.swift
//  Bible Crossword Challenge
//
//  The player: who they are, the verse they're carrying, how far into
//  Scripture they've come, and what they're walking through. No
//  authentication in v1 — everything is on device (and in their iCloud).
//
//  Rebuilt to the design canvas on 2026-10-24: cards on the paper, like
//  Today, in place of an inset-grouped List. Scripture leads — the verse
//  being learned, books explored, verses learned — and the game's records
//  follow. On day one the stats give way to one card that starts them: a
//  row of four zeros was a scoreboard for a game not yet begun.
//
//  Settings live behind the gear in the toolbar (`SettingsView`), not at the
//  foot of this screen. This tab is visited for the progress and settings
//  rarely, and making the one longer for the other served neither.
//

import SwiftUI
import SwiftData

struct ProfileView: View {
    @Bindable var profile: PlayerProfile
    /// Presents Settings. RootView owns the sheet so ⌘, can open it from any
    /// tab, not only this one.
    let openSettings: () -> Void

    @Environment(StoreService.self) private var store
    @Environment(\.gameCenter) private var gameCenter
    @Environment(\.challengeHistory) private var challengeHistory
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.memoryVerses) private var memoryVerses
    @Environment(\.puzzleProvider) private var puzzleProvider
    @Environment(\.modelContext) private var modelContext
    /// Books reached through a solved puzzle, and the Journey to show, worked
    /// out when the tab appears. A one-off fetch rather than a standing
    /// `@Query`: the numbers only move when a puzzle is solved elsewhere, and
    /// a live query over every record on a tab that's built at launch was one
    /// more observer on the synced store for nothing.
    @State private var booksExplored = 0
    @State private var journey: QuestLine?
    @State private var journeyProgress: QuestProgress?
    @State private var showRename = false
    @State private var draftName = ""
    @State private var showChallengeHistory = false

    private var unlockedCount: Int {
        Achievements.all.filter { $0.isUnlocked(by: profile) }.count
    }

    /// Before the first solve, when every number on this tab is a zero.
    private var isDayOne: Bool { profile.totalPuzzlesCompleted == 0 }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    identityRow
                    memoryVerseCard
                    if isDayOne {
                        firstSolveCard
                    } else {
                        ProfileStatsRow(
                            booksExplored: booksExplored,
                            totalBooks: BibleCanon.books.count,
                            versesLearned: memoryVerses.entries.count(where: \.isMastered),
                            currentStreak: profile.currentStreak
                        )
                    }
                    CardGroup(dividerInset: Theme.Spacing.m + CoverRow.coverSide + Theme.Spacing.m) {
                        journeyRow
                        badgesRow
                        leaderboardRow
                    }
                    challengesSection
                }
                .padding(.horizontal, Theme.Spacing.m + Theme.Spacing.xs)
                .padding(.top, Theme.Spacing.s)
                .padding(.bottom, Theme.Spacing.l)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .background(Theme.background)
            .navigationTitle("Profile")
            .onAppear(perform: refreshProgress)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings", systemImage: "gearshape", action: openSettings)
                }
            }
            .navigationDestination(isPresented: $showChallengeHistory) {
                ChallengeHistoryView(profile: profile)
            }
            .navigationDestination(for: MemoryRoute.self) { route in
                MemoryVerseListView(source: route.source)
            }
            .navigationDestination(for: MemoryPracticeRoute.self) { route in
                MemoryPracticeView(referenceKey: route.referenceKey, source: route.source)
            }
            .navigationDestination(for: QuestRoute.self) { route in
                QuestDetailView(quest: route.quest, profile: profile, source: route.source)
            }
            .navigationDestination(for: Puzzle.self) { puzzle in
                CrosswordGameView(puzzle: puzzle, profile: profile, entrySource: "profile")
            }
            .alert(chosenName == nil ? "Add your name" : "Your name", isPresented: $showRename) {
                TextField("Your name", text: $draftName)
                    .textInputAutocapitalization(.words)
                Button("Cancel", role: .cancel) {}
                Button("Save") { commitRename() }
            } message: {
                // Not "only stored on your device": the profile syncs through
                // iCloud, and the name rides in every challenge link.
                Text("Friends see it on the challenges you send.")
            }
        }
    }

    // MARK: - Identity

    /// The initial on an ink disc, the name, and how long they've been here —
    /// on the paper, as the page's heading rather than a row in a card.
    /// Without a name it says only that: the name is asked for at the first
    /// challenge, where it's used, and a blue "Add your name" here read as a
    /// chore on day one. A tap still edits it.
    private var identityRow: some View {
        Button {
            // Starts empty for a player who never chose one, so they type a
            // name rather than delete the placeholder first.
            draftName = chosenName ?? ""
            showRename = true
        } label: {
            HStack(spacing: Theme.Spacing.m) {
                if !dynamicTypeSize.isAccessibilitySize {
                    Avatar(name: chosenName ?? "")
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(chosenName ?? membershipLine)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Color.primary)
                    if chosenName != nil {
                        Text(membershipLine)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(chosenName.map { "\($0). \(membershipLine)" } ?? membershipLine)
        .accessibilityHint(chosenName == nil ? "Adds your name" : "Edits your name")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Memory verse

    /// The verse to practise: one that's due first, else the one practised
    /// most recently, among those not yet mastered.
    private var learningNow: MemoryVerseStore.Entry? {
        memoryVerses.entries
            .filter { !$0.isMastered }
            .max { lhs, rhs in
                let lhsDue = memoryVerses.isDue(lhs), rhsDue = memoryVerses.isDue(rhs)
                if lhsDue != rhsDue { return !lhsDue }
                return (lhs.lastPracticedAt ?? lhs.startedAt) < (rhs.lastPracticedAt ?? rhs.startedAt)
            }
    }

    /// The verse being learned, in serif on its own card, with the way to
    /// practise it — or, with none chosen yet, the invitation in grey.
    @ViewBuilder
    private var memoryVerseCard: some View {
        if let entry = learningNow {
            NavigationLink(value: MemoryPracticeRoute(referenceKey: entry.referenceKey, source: "profile")) {
                verseCardBody(
                    kicker: "Learning now",
                    quote: entry.verseText,
                    isInvitation: false,
                    reference: entry.reference,
                    action: memoryVerses.isDue(entry) ? "Practice now" : "Practice"
                )
            }
            .buttonStyle(PressableCardStyle())
            .accessibilityHint("Practises this verse")
        } else {
            NavigationLink(value: MemoryRoute(source: "profile")) {
                verseCardBody(
                    kicker: "Memory verse",
                    quote: "Choose a verse to carry with you this week.",
                    isInvitation: true,
                    reference: "From any puzzle you solve",
                    action: "Choose"
                )
            }
            .buttonStyle(PressableCardStyle())
        }
    }

    private func verseCardBody(
        kicker: String, quote: String, isInvitation: Bool, reference: String, action: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(kicker)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(quote)
                .font(.scripture(.title2))
                .tracking(-0.2)
                .foregroundStyle(isInvitation ? Color.secondary : Color.primary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 4)
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
                Text(reference)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: Theme.Spacing.s)
                Text(action)
                    .font(.body)
                    .foregroundStyle(Theme.accent)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .elevatedCard(cornerRadius: Theme.featureCornerRadius)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Day one

    /// In place of the stats until the first solve: what the numbers will
    /// be, and the way to start them.
    private var firstSolveCard: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "flame.fill")
                .font(.title2)
                .foregroundStyle(FeatureTint.streak)
                .frame(width: CoverRow.coverSide, height: CoverRow.coverSide)
                .background(FeatureTint.streak.opacity(0.14), in: .rect(cornerRadius: 12, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Your first solve starts your streak")
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Books explored and verses learned add up from there.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let daily = puzzleProvider.dailyPuzzle() {
                    NavigationLink(value: daily) {
                        Text("Play today's puzzle")
                            .font(.body)
                            .foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, Theme.Spacing.xs)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .elevatedCard()
    }

    // MARK: - Journey, badges, leaderboard

    /// The Journey the player is on, or the first to begin — the same one
    /// Today's Keep going shows.
    @ViewBuilder
    private var journeyRow: some View {
        if let journey, let progress = journeyProgress {
            NavigationLink(value: QuestRoute(quest: journey, source: .profile)) {
                CoverRow(
                    symbol: journey.coverSymbol,
                    tint: FeatureTint.journey,
                    title: progress.solved == 0 ? "Start a Journey" : journey.title,
                    subtitle: journeySubtitle(journey, progress: progress),
                    progress: progress.solved > 0 ? progress.fraction : nil
                )
                .cardRowPadding()
            }
            .buttonStyle(PressableCardStyle())
        }
    }

    private func journeySubtitle(_ journey: QuestLine, progress: QuestProgress) -> String {
        if progress.solved == 0 { return "\(journey.title) · one step a day" }
        if progress.steppedToday { return "Step \(progress.solved) of \(progress.total) done · next one tomorrow" }
        return QuestProgress.stepLine(solved: progress.solved, total: progress.total)
    }

    /// The badges, gold once there's one earned; before then, grey, naming
    /// the first one and what it takes.
    private var badgesRow: some View {
        NavigationLink {
            AchievementsView(profile: profile, source: "profile")
        } label: {
            CoverRow(
                symbol: "star.fill",
                tint: unlockedCount > 0 ? Theme.badgeRim : Color.secondary,
                title: "Badges",
                subtitle: badgesSubtitle
            )
            .cardRowPadding()
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityHint("Opens every badge and its progress")
    }

    private var badgesSubtitle: String {
        let next = Achievements.all.first { !$0.isUnlocked(by: profile) }
        guard unlockedCount > 0 else {
            return next.map { "\($0.title) · \($0.detail)" } ?? "Solve puzzles to earn your first badge"
        }
        let earned = "\(unlockedCount) of \(Achievements.all.count) earned"
        return next.map { "\(earned) · next, \($0.title)" } ?? earned
    }

    /// The standing way back to this week's Mini leaderboard — the only other
    /// entry point is the post-solve completion screen. Hidden when the player
    /// isn't signed in to Game Center.
    @ViewBuilder
    private var leaderboardRow: some View {
        if gameCenter.isAuthenticated {
            Button {
                gameCenter.showWeeklyMiniLeaderboard()
            } label: {
                CoverRow(
                    symbol: "list.number",
                    tint: FeatureTint.mini,
                    title: "Weekly leaderboard",
                    subtitle: "This week's fastest Mini times"
                )
                .cardRowPadding()
            }
            .buttonStyle(PressableCardStyle())
            .accessibilityHint("Opens Game Center")
        }
    }

    // MARK: - Challenges

    /// The friend-challenge ledger, previewed. Hidden until there is something
    /// to show: a "Challenges" heading over an empty card advertises a feature
    /// by its absence, and the completion screen is where the invitation to
    /// send one actually belongs.
    @ViewBuilder
    private var challengesSection: some View {
        let recent = Array(challengeHistory.entries.prefix(3))
        if !recent.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.s + Theme.Spacing.xs) {
                Text("Challenges").sectionHeader()
                CardGroup {
                    // Every row leads to the same place — the full list is
                    // where replay and rematch live.
                    ForEach(recent) { entry in
                        Button {
                            showChallengeHistory = true
                        } label: {
                            ChallengeHistoryRow(entry: entry)
                        }
                        .buttonStyle(.plain)
                    }
                    Button {
                        showChallengeHistory = true
                    } label: {
                        Text(challengeHistory.entries.count > recent.count
                             ? "See all \(challengeHistory.entries.count)"
                             : "See all")
                            .font(.body)
                            .foregroundStyle(Theme.accent)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .cardRowPadding()
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Data

    /// Books explored, and the Journey to show: the first one not yet walked.
    private func refreshProgress() {
        let records = (try? modelContext.fetch(FetchDescriptor<PuzzleRecord>())) ?? []
        let solved = Set(records.filter(\.isCompleted).map(\.puzzleID))
        booksExplored = BibleJourney.booksTouched(
            completedPuzzleIDs: solved, puzzles: puzzleProvider.allPuzzles
        ).count
        let recordsByID = records.byPuzzleID
        journey = puzzleProvider.quests.first {
            !QuestProgress(quest: $0, recordsByID: recordsByID).isComplete
        }
        journeyProgress = journey.map { QuestProgress(quest: $0, recordsByID: recordsByID) }
    }

    /// The name the player chose, or nil while it is still the placeholder
    /// onboarding and the challenge prompt fall back to.
    private var chosenName: String? {
        let trimmed = profile.username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != ChallengeService.placeholderName else { return nil }
        return trimmed
    }

    /// Premium status when there is some, otherwise how long they've been
    /// here — "Joined today" on the first day, where a month and year read
    /// like a long time.
    private var membershipLine: String {
        if store.isPremium { return "Premium member" }
        if Calendar.current.isDateInToday(profile.createdAt) { return "Joined today" }
        return "Solving since \(profile.createdAt.formatted(.dateTime.month(.wide).year()))"
    }

    private func commitRename() {
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // The challenge prompt's cap: the name rides in challenge links and on
        // family boards, and only this door let a longer one through.
        profile.username = String(trimmed.prefix(20))
    }
}

// MARK: - Stats

/// Three numbers about Scripture, on one card: books explored out of the 66,
/// verses learned, and the day streak (2026-10-24, design canvas). "Solved"
/// and "Best streak" left: Profile says how far into Scripture a player has
/// come, and the completion screen keeps the game's records. Plain values
/// only, so SwiftUI can skip it when unrelated state changes.
private struct ProfileStatsRow: View {
    let booksExplored: Int
    let totalBooks: Int
    let versesLearned: Int
    let currentStreak: Int

    var body: some View {
        HStack(spacing: 0) {
            stat("\(booksExplored)", of: "/\(totalBooks)", "Books explored")
            Divider()
            stat("\(versesLearned)", "Verses learned")
            Divider()
            stat("\(currentStreak)", "Day streak")
        }
        .padding(.vertical, Theme.Spacing.m)
        .frame(maxWidth: .infinity)
        .elevatedCard()
    }

    private func stat(_ value: String, of total: String = "", _ label: String) -> some View {
        VStack(spacing: 2) {
            (Text(value)
                + Text(total)
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                    .foregroundStyle(.secondary))
                .font(.system(.title, design: .rounded, weight: .bold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Theme.Spacing.xs)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(total.isEmpty ? value : "\(value) of \(total.dropFirst())")
    }
}

// MARK: - Avatar

/// The player's initial in serif on an ink disc, as the canvas draws it;
/// without a name, a neutral disc with the person glyph.
private struct Avatar: View {
    let name: String

    @ScaledMetric(relativeTo: .title) private var size: CGFloat = 64

    private var initial: String? {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .first
            .map { String($0).uppercased() }
    }

    var body: some View {
        ZStack {
            if let initial {
                Circle().fill(Theme.ink)
                Text(initial)
                    .font(.scripture(.title, weight: .semibold))
                    .foregroundStyle(Theme.onInk)
            } else {
                Circle().fill(Color.primary.opacity(0.06))
                Image(systemName: "person.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
