//
//  LibraryView.swift
//  Bible Crossword Challenge
//
//  The library of every puzzle — searchable, filterable by difficulty and
//  completion status, with a one-tap jump to the next unsolved puzzle.
//
//  Free players see the same list behind a soft gate rather than a locked
//  screen: what they can play, then what Premium opens. The rule is in
//  `PuzzleAccess`; this file only draws it.
//
//  Called a library, not an archive, because that is what it is: the daily
//  puzzle rotates with `days % pool.count` (see PuzzleProvider.rotated), so
//  every puzzle recurs every 82 days and none of them belongs to a date. Copy
//  here promises a collection to browse, never a day to go back to.
//

import SwiftUI
import SwiftData

struct LibraryView: View {
    let profile: PlayerProfile

    @Environment(\.puzzleProvider) private var puzzleProvider
    @Environment(StoreService.self) private var store
    @Environment(\.challengeService) private var challengeService
    @Query private var records: [PuzzleRecord]

    @State private var query = ""
    @State private var difficulty: PuzzleDifficulty?
    @State private var statusFilter: ArchiveStatusFilter = .all
    /// Which length of puzzle — a 15×15, a 7×7 or a 21×21 is a different
    /// sitting, and the free list used to run all three together.
    @State private var kind: LibraryKind = .all
    /// The premium section shows a taste of what's locked, not all of it.
    @State private var showAllLocked = false
    @State private var showPaywall = false
    /// Driven by hand in the two-column layout, where each half is a button:
    /// a List row holding two NavigationLinks treats the whole row as one
    /// target, so a tap on the right-hand puzzle opened the left.
    @State private var path = NavigationPath()
    /// Width the list has to work with, measured. Wide — iPhone Duo open,
    /// iPad landscape — the rows go two to a line across the whole width;
    /// one 640pt column there left a third of the screen empty and sat
    /// under a search field drawn far wider than it.
    @State private var listWidth: CGFloat = 0
    private var isWide: Bool { listWidth >= 820 }

    private var puzzles: [Puzzle] { puzzleProvider.puzzles }
    private var minis: [Puzzle] { puzzleProvider.minis }
    private var sundays: [Puzzle] { puzzleProvider.sundays }

    /// One lookup built per body pass, reused by filtering and rows instead of
    /// scanning `records` for every puzzle. Built by `byPuzzleID`, which
    /// tolerates the duplicate records CloudKit can land between merges.
    private var recordsByID: [String: PuzzleRecord] {
        records.byPuzzleID
    }

    private func status(for puzzle: Puzzle) -> PuzzleStatus {
        PuzzleStatus(record: recordsByID[puzzle.id])
    }

    private var filtered: [Puzzle] {
        guard kind == .all || kind == .daily else { return [] }
        return puzzles.filter(matches)
    }

    /// Minis honour every filter, difficulty included — by their own
    /// difficulty. The difficulty filter used to empty the Mini section
    /// outright, so picking "Medium" quietly hid every 7×7 without saying so.
    private var filteredMinis: [Puzzle] {
        guard kind == .all || kind == .mini else { return [] }
        return minis.filter(matches)
    }

    private var filteredSundays: [Puzzle] {
        guard kind == .all || kind == .sunday else { return [] }
        return sundays.filter(matches)
    }

    /// Title or verse reference: in a Bible app "Psalm" or "John" should find
    /// the puzzles built on them, not only the ones that say so in the title.
    private func matches(_ puzzle: Puzzle) -> Bool {
        (query.isEmpty
            || puzzle.title.localizedCaseInsensitiveContains(query)
            || puzzle.reference.localizedCaseInsensitiveContains(query))
            && (difficulty == nil || puzzle.difficulty == difficulty)
            && statusMatches(puzzle)
    }

    /// Playable rows in the order a player wants them: started, then not yet
    /// solved, then solved. Alphabetical put eight solved puzzles above the
    /// first one left to play.
    private func playOrder(_ list: [Puzzle]) -> [Puzzle] {
        func rank(_ puzzle: Puzzle) -> Int {
            switch status(for: puzzle) {
            case .inProgress: 0
            case .start: 1
            case .completed: 2
            }
        }
        return list.enumerated()
            .sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }
            .map(\.element)
    }

    private func statusMatches(_ puzzle: Puzzle) -> Bool {
        switch statusFilter {
        case .all: return true
        case .unsolved: return status(for: puzzle) != .completed
        case .completed: return status(for: puzzle) == .completed
        }
    }

    /// First puzzle the player hasn't completed, honouring the type and
    /// difficulty filters — a Mini when the list is showing Minis.
    private var nextUnsolved: Puzzle? {
        (filtered + filteredSundays + filteredMinis).first { status(for: $0) != .completed }
    }

    private var isFiltering: Bool { difficulty != nil || statusFilter != .all }

    private var completedCount: Int {
        let ids = Set(puzzles.map(\.id))
        return records.filter { $0.isCompleted && ids.contains($0.puzzleID) }.count
    }

    // MARK: - Free tier

    /// The soft gate. Two small windows of ids — see `PuzzleAccess` for the rule
    /// and why it holds no persisted state.
    private var access: PuzzleAccess {
        PuzzleAccess(provider: puzzleProvider, challengedIDs: challengeService.pendingPuzzleIDs)
    }

    private func canPlay(_ puzzle: Puzzle, gate: PuzzleAccess) -> Bool {
        gate.canPlay(
            puzzle,
            isPremium: store.isPremium,
            hasProgress: recordsByID[puzzle.id] != nil
        )
    }

    /// Everything the filters admit, split by whether this player can open it.
    /// Minis follow the dailies rather than interleaving: they're a different
    /// length of sitting, and the premium list already groups them apart.
    private func partitioned(gate: PuzzleAccess) -> (free: [Puzzle], locked: [Puzzle]) {
        let all = filtered + filteredSundays + filteredMinis
        var free: [Puzzle] = []
        var locked: [Puzzle] = []
        for puzzle in all {
            if canPlay(puzzle, gate: gate) { free.append(puzzle) } else { locked.append(puzzle) }
        }
        return (free, locked)
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if store.isPremium {
                    premiumList
                } else {
                    freeList
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { listWidth = $0 }
            .navigationTitle("Library")
            // Inline, like Today: a large title can't collapse over a list with
            // a pinned inset above it — it vanished and left a blank band.
            // The bar then carries the title, the search field and the type
            // picker as one fixed header, which is what this screen is for.
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Puzzle.self) { puzzle in
                CrosswordGameView(puzzle: puzzle, profile: profile, entrySource: "library")
            }
            .sheet(isPresented: $showPaywall) {
                // Source stays "archive" even though the screen is now called
                // Library — renaming it would split this entry point's
                // conversion history in Firebase at an arbitrary point.
                PaywallView(source: .archive)
            }
        }
    }

    // MARK: - Premium list

    private var premiumList: some View {
        List {
            if query.isEmpty, statusFilter != .completed, let next = nextUnsolved {
                Section {
                    nextUnsolvedRow(next)
                }
            }

            if !filtered.isEmpty {
                Section {
                    rows(filtered, row)
                } header: {
                    progressHeader
                }
            }

            if !filteredSundays.isEmpty {
                Section {
                    rows(filteredSundays, row)
                } header: {
                    Text("Sunday Specials")
                }
            }

            if !filteredMinis.isEmpty {
                Section {
                    rows(filteredMinis, row)
                } header: {
                    Text("Minis")
                }
            }
        }
        // Warm paper canvas behind the native list rows (see SettingsView).
        .scrollContentBackground(.hidden)
        // Same readable column as the card screens — a row stretched across a
        // 13" iPad puts its chevron half a metre from its title.
        .frame(maxWidth: isWide ? .infinity : 640)
        .frame(maxWidth: .infinity)
        .background(Theme.background)
        .searchable(
            text: $query,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search titles or verses"
        )
        .toolbar { filterMenu }
        .safeAreaInset(edge: .top, spacing: 0) { kindPicker }
        .overlay {
            if filtered.isEmpty && filteredSundays.isEmpty && filteredMinis.isEmpty {
                if query.isEmpty {
                    ContentUnavailableView(
                        "No Puzzles",
                        systemImage: "line.3.horizontal.decrease.circle",
                        description: Text("No puzzles match these filters.")
                    )
                } else {
                    ContentUnavailableView.search(text: query)
                }
            }
        }
    }

    /// Completion as a bar, not a sentence. This is the one screen whose whole
    /// subject is how much of the collection you've finished, and it was
    /// stating that in a grey section header.
    private var progressHeader: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack {
                Text("\(completedCount) of \(puzzles.count) solved")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
                if completedCount > 0 {
                    Text("\(Int((Double(completedCount) / Double(max(puzzles.count, 1)) * 100).rounded()))%")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            ProgressView(value: Double(completedCount), total: Double(max(puzzles.count, 1)))
                .tint(Theme.progressBar)
        }
        .textCase(nil)          // section headers upper-case by default
        .padding(.bottom, Theme.Spacing.xs)
        .accessibilityElement(children: .combine)
    }

    @ToolbarContentBuilder
    private var filterMenu: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Picker("Difficulty", selection: $difficulty) {
                    Text("All Difficulties").tag(PuzzleDifficulty?.none)
                    ForEach(PuzzleDifficulty.allCases, id: \.self) { difficulty in
                        Text(difficulty.label).tag(Optional(difficulty))
                    }
                }
                .pickerStyle(.inline)

                Picker("Show", selection: $statusFilter) {
                    ForEach(ArchiveStatusFilter.allCases) { filter in
                        Text(filter.label).tag(filter)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Image(systemName: isFiltering
                    ? "line.3.horizontal.decrease.circle.fill"
                    : "line.3.horizontal.decrease.circle")
            }
            .accessibilityLabel("Filter")
        }
    }

    private func nextUnsolvedRow(_ puzzle: Puzzle) -> some View {
        NavigationLink(value: puzzle) {
            HStack(spacing: Theme.Spacing.m) {
                Image(systemName: "play.circle.fill")
                    .font(.title)
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Next unsolved")
                        .font(.subheadline.weight(.semibold))
                    Text(puzzle.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 2)
        }
        .accessibilityLabel("Next unsolved puzzle, \(puzzle.title)")
    }

    /// One puzzle per row on a phone; two per row when wide, each half its
    /// own button.
    @ViewBuilder
    private func rows<Row: View>(_ puzzles: [Puzzle], _ make: @escaping (Puzzle) -> Row) -> some View {
        if isWide {
            ForEach(Array(stride(from: 0, to: puzzles.count, by: 2)), id: \.self) { i in
                HStack(alignment: .center, spacing: Theme.Spacing.l) {
                    make(puzzles[i])
                        .frame(maxWidth: .infinity)
                    Divider()
                    Group {
                        if i + 1 < puzzles.count {
                            make(puzzles[i + 1])
                        } else {
                            Color.clear
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                // Borderless: in a List row, only borderless buttons take
                // their own taps; any other style hands the tap to the row.
                .buttonStyle(.borderless)
            }
        } else {
            ForEach(puzzles) { make($0) }
        }
    }

    /// Covers grow a little on a wide screen, where the row has the room.
    private var coverSide: CGFloat { isWide ? 52 : 44 }

    private func row(_ puzzle: Puzzle) -> some View {
        let record = recordsByID[puzzle.id]
        let status = PuzzleStatus(record: record)

        return rowLink(puzzle) {
            HStack(spacing: Theme.Spacing.m) {
                // The book the puzzle's verse comes from, on its kind's colour
                // (2026-10-24). Eighty-two rows of title-plus-badge are
                // indistinguishable at a glance; the cover is what makes one
                // scannable from the next. It replaced the grid's shape in
                // pale dots, which was too faint at this size to tell apart.
                PuzzleCover(puzzle: puzzle, side: coverSide)

                VStack(alignment: .leading, spacing: 2) {
                    Text(puzzle.title)
                        .font(.body)
                        .multilineTextAlignment(.leading)
                    // One plain line, as a system list row's subtitle: the
                    // coloured difficulty capsule on every row made the list a
                    // confetti of green, orange and purple. Status sits here,
                    // beside the facts it goes with.
                    metaLine(puzzle, status: status, record: record)
                }
                Spacer(minLength: 0)
                if status == .completed {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
            .padding(.vertical, Theme.Spacing.xs)
            .contentShape(.rect)
        }
    }

    /// A button that pushes onto `path`, at every width. A NavigationLink in a
    /// List draws a chevron on every row, and the rest of the app's rows
    /// dropped theirs (2026-10-24): the whole row is the tap target.
    private func rowLink<Label: View>(_ puzzle: Puzzle, @ViewBuilder label: () -> Label) -> some View {
        Button { path.append(puzzle) } label: { label() }
            .foregroundStyle(.primary)
    }

    /// "Luke 15:11 · Easy · In progress" — one secondary line. The passage
    /// leads (2026-10-24): "Easy · 20 clues" on nearly every row said the
    /// same thing two hundred times. "In progress" is orange, as on the pack
    /// list — blue means "tap here" across the app; a solve time is just
    /// another fact.
    private func metaLine(_ puzzle: Puzzle, status: PuzzleStatus, record: PuzzleRecord?) -> some View {
        var text = Text("\(puzzle.reference) · \(puzzle.difficulty.label)")
        switch status {
        case .completed:
            if let secs = record?.elapsedSeconds, secs > 0 {
                text = text + Text(" · \(TimeFormat.clock(secs))").monospacedDigit()
            }
        case .inProgress:
            text = text + Text(" · ") + Text("In progress").foregroundStyle(.orange)
        case .start:
            break
        }
        return text
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }

    // MARK: - Free list

    /// The half most people see.
    ///
    /// This screen used to be all-or-nothing: a locked preview of four dimmed
    /// rows and an Unlock button, with no way to play anything. That maximised
    /// paywall pressure, at the cost of a player meeting "everything is locked"
    /// before they had seen enough of the collection to want it — and of
    /// contradicting the store listing, which invites them to revisit a library.
    ///
    /// Now the same list premium sees, with the gate drawn through it: what they
    /// can play first, what Premium opens underneath. The rule lives in
    /// `PuzzleAccess`; this only renders it.
    private var freeList: some View {
        let gate = access
        let split = partitioned(gate: gate)
        let playable = playOrder(split.free)
        let locked = (showAllLocked || !query.isEmpty) ? split.locked : Array(split.locked.prefix(Self.lockedPreview))
        let hiddenLocked = split.locked.count - locked.count

        return List {
            // No "Next unsolved" jump here, unlike premium: these rows are in
            // play order, so it always named the first row below it — the
            // same puzzle twice at the top of the list. Premium's list is in
            // catalogue order, where the jump still saves a scroll.
            if !playable.isEmpty {
                Section {
                    rows(playable, row)
                } header: {
                    freeHeader(freeCount: playable.count)
                } footer: {
                    // The rule, under the list it explains — as a header it
                    // made a two-line block over the first row.
                    Text("Seven new each week, and anything you start stays yours.")
                }
            }

            if !split.locked.isEmpty {
                Section {
                    premiumOffer(count: split.locked.count)
                    rows(locked, lockedRow)
                    if hiddenLocked > 0 {
                        Button {
                            withAnimation { showAllLocked = true }
                        } label: {
                            Text("Show all \(split.locked.count)")
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                } header: {
                    Text("Premium")
                }
            }
        }
        .scrollContentBackground(.hidden)
        // See premiumList: keep rows at a readable width on iPad.
        .frame(maxWidth: isWide ? .infinity : 640)
        .frame(maxWidth: .infinity)
        .background(Theme.background)
        .searchable(
            text: $query,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search titles or verses"
        )
        .toolbar { filterMenu }
        .safeAreaInset(edge: .top, spacing: 0) { kindPicker }
        .overlay {
            if split.free.isEmpty && split.locked.isEmpty {
                if query.isEmpty {
                    ContentUnavailableView(
                        "No Puzzles",
                        systemImage: "line.3.horizontal.decrease.circle",
                        description: Text("No puzzles match these filters.")
                    )
                } else {
                    ContentUnavailableView.search(text: query)
                }
            }
        }
    }

    /// How many locked rows the Premium section shows before "Show all". It
    /// used to list every one — about 170 — with the only way to Premium in a
    /// footer underneath them.
    private static let lockedPreview = 5

    /// Daily, Mini or Sunday, up front rather than inside the filter menu:
    /// they're different lengths of sitting, and the choice is the first one
    /// a player makes here. Pinned above the list rather than its first row,
    /// so changing type deep in a long list doesn't mean scrolling back up.
    private var kindPicker: some View {
        Picker("Puzzle type", selection: $kind) {
            ForEach(LibraryKind.allCases) { kind in
                Text(kind.label).tag(kind)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, Theme.Spacing.s)
        .frame(maxWidth: isWide ? .infinity : 640)
        .frame(maxWidth: .infinity)
        .background(Theme.background)
    }

    /// States the allowance in the player's own terms, without claiming dates.
    ///
    /// "This week's seven" describes which puzzles are open, not when they were
    /// published — the pool rotates, so no puzzle belongs to a day (see the file
    /// note above). The count is what they can actually open right now, which
    /// grows past seven as they start puzzles and keep them; the line under it
    /// says so, where "27 to play" over "this week's seven are free" read as a
    /// sum that didn't add up.
    private func freeHeader(freeCount: Int) -> some View {
        Text("^[\(freeCount) puzzle](inflect: true) to play")
            .font(.title3.weight(.semibold))
            .foregroundStyle(Color.primary)
            .textCase(nil)
    }

    /// The upgrade path, at the top of the locked rows rather than in a footer
    /// under all of them. Same words as every card that opens the paywall —
    /// never "Unlock" (see `PremiumCopy.cardCTA`).
    private func premiumOffer(count: Int) -> some View {
        Button {
            showPaywall = true
        } label: {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Every puzzle, back to the first")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Color.primary)
                    Text("\(count) more here, play and replay as often as you like.")
                        .font(.subheadline)
                        .foregroundStyle(Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // The shared offer button — see `PremiumOfferCTA`.
                PremiumOfferCTA()
            }
            .padding(.vertical, Theme.Spacing.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens Premium plans")
    }

    /// A locked row: the same shape as a playable one so the list reads as one
    /// collection, but it opens the paywall instead of the puzzle.
    private func lockedRow(_ puzzle: Puzzle) -> some View {
        Button {
            showPaywall = true
        } label: {
            HStack(spacing: Theme.Spacing.m) {
                PuzzleCover(puzzle: puzzle, isLocked: true, side: coverSide)

                VStack(alignment: .leading, spacing: 2) {
                    Text(puzzle.title)
                        .font(.body)
                        .foregroundStyle(.secondary)
                    Text("\(puzzle.reference) · \(puzzle.difficulty.label)")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
                Image(systemName: "lock.fill")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 2)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(puzzle.title), locked")
        .accessibilityHint("Opens Premium")
    }
}

// MARK: - Puzzle kind

private enum LibraryKind: String, CaseIterable, Identifiable {
    case all, daily, mini, sunday

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "All"
        case .daily: return "Daily"
        case .mini: return "Mini"
        case .sunday: return "Sunday"
        }
    }
}

// MARK: - Status filter

private enum ArchiveStatusFilter: String, CaseIterable, Identifiable {
    case all, unsolved, completed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "All"
        case .unsolved: return "Unsolved"
        case .completed: return "Completed"
        }
    }
}
