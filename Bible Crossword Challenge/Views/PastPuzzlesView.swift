//
//  PastPuzzlesView.swift
//  Bible Crossword Challenge
//
//  A calendar of the days behind today: tap a day, play its puzzle.
//
//  The Library is a list to search; this is the same puzzles as the days
//  they were served, which is the shape a daily player remembers them in —
//  and the one that shows a gap. It reaches back one trip round the pool and
//  stops (see `PastPuzzles`), so no day here is ever a repeat of another.
//
//  Free players see every day and can open the ones `PuzzleAccess` allows:
//  the rolling window and anything they've started. The rest open the
//  paywall. Drawn quieter, not hidden — a calendar with its past cut off
//  would have nothing to want in it.
//
//  One colour, as everywhere: ink fills a solved day, the accent rings
//  today (the day to play), orange marks one under way, as in the Library.
//

import SwiftUI
import SwiftData

/// Pushes the calendar onto the Puzzles tab's stack.
struct PastPuzzlesRoute: Hashable {}

/// A puzzle opened from the calendar. Its own type so the tab's stack logs
/// `entrySource: "past_puzzles"` for it — see `LibraryPuzzleRoute`.
struct PastPuzzleRoute: Hashable {
    let puzzle: Puzzle
}

struct PastPuzzlesView: View {
    let profile: PlayerProfile
    /// The Puzzles tab's stack, which this screen is pushed onto.
    @Binding var path: NavigationPath

    @Environment(\.puzzleProvider) private var puzzleProvider
    @Environment(\.analytics) private var analytics
    @Environment(\.challengeService) private var challengeService
    @Environment(\.today) private var today
    @Environment(\.calendar) private var calendar
    @Environment(StoreService.self) private var store
    @Query private var records: [PuzzleRecord]

    @State private var kind: PastPuzzleKind = .daily
    @State private var showPaywall = false
    /// `.task` re-runs on every pop back from a puzzle.
    @State private var didLogOpen = false

    private enum DayState {
        case solved, inProgress, open, locked
    }

    /// Everything a body pass needs, worked out once.
    private struct Page {
        let months: [PastPuzzleMonth]
        let states: [Date: DayState]
        let total: Int
        let solved: Int
        let locked: Int
    }

    private func makePage(for kind: PastPuzzleKind) -> Page {
        let days = PastPuzzles.days(kind, provider: puzzleProvider, today: today, calendar: calendar)
        let recordsByID = records.byPuzzleID
        let gate = PuzzleAccess(
            provider: puzzleProvider, date: today, calendar: calendar,
            challengedIDs: challengeService.pendingPuzzleIDs
        )
        var states: [Date: DayState] = [:]
        for day in days {
            let record = recordsByID[day.puzzle.id]
            switch PuzzleStatus(record: record) {
            case .completed:
                states[day.date] = .solved
            case .inProgress:
                states[day.date] = .inProgress
            case .start:
                let playable = gate.canPlay(day.puzzle, isPremium: store.isPremium, hasProgress: record != nil)
                states[day.date] = playable ? .open : .locked
            }
        }
        return Page(
            months: PastPuzzles.months(days, calendar: calendar),
            states: states,
            total: days.count,
            solved: states.values.count { $0 == .solved },
            locked: states.values.count { $0 == .locked }
        )
    }

    var body: some View {
        let page = makePage(for: kind)

        ScrollView {
            LazyVStack(alignment: .leading, spacing: Theme.Spacing.l) {
                summary(page)
                ForEach(page.months) { month in
                    monthCard(month, states: page.states)
                }
                if page.locked > 0 {
                    premiumOffer(locked: page.locked)
                }
            }
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.top, Theme.Spacing.s)
            .padding(.bottom, Theme.Spacing.l)
            // A calendar stretched across an iPad puts a week's ends a
            // forearm apart; the Library's readable column, a little tighter.
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        // The other pool is another calendar: start it at this month, not
        // wherever the last one was scrolled to. Inside the sheet and the
        // task, whose identity must not move with it.
        .id(kind)
        .background(Theme.background)
        .safeAreaInset(edge: .top, spacing: 0) { kindPicker }
        .navigationTitle("Past Puzzles")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPaywall) {
            PaywallView(source: .pastPuzzles)
        }
        .task {
            guard !didLogOpen else { return }
            didLogOpen = true
            analytics.log(.pastPuzzlesOpened(kind: kind.rawValue, solved: page.solved, locked: page.locked))
        }
    }

    // MARK: - Header

    /// Daily or Mini, pinned: they are different sittings, and the choice is
    /// the first one made here — as on the Library.
    private var kindPicker: some View {
        Picker("Puzzle type", selection: $kind) {
            ForEach(PastPuzzleKind.allCases) { kind in
                Text(kind.label).tag(kind)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, Theme.Spacing.s)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
        .background(Theme.background)
    }

    /// How much of the calendar is filled in, as the Library states it.
    private func summary(_ page: Page) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("\(page.solved) of ^[\(page.total) day](inflect: true) solved")
                .font(.subheadline.weight(.semibold))
            ProgressView(value: Double(page.solved), total: Double(max(page.total, 1)))
                .tint(Theme.progressBar)
            if page.locked > 0 {
                // The rule, once, in the player's terms.
                Text("The last week is free, and anything you start stays yours.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
        }
        .padding(.horizontal, Theme.Spacing.xs)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Month

    private static let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    private func monthCard(_ month: PastPuzzleMonth, states: [Date: DayState]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text(month.start.formatted(.dateTime.month(.wide).year()))
                .font(.headline)
                .padding(.horizontal, Theme.Spacing.xs)
                .accessibilityAddTraits(.isHeader)

            LazyVGrid(columns: Self.columns, spacing: Theme.Spacing.xs) {
                ForEach(Array(PastPuzzles.weekdaySymbols(calendar: calendar).enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .accessibilityHidden(true)
                }
                ForEach(month.cells) { cell in
                    switch cell {
                    case .blank:
                        Color.clear.frame(height: Self.cellSide)
                    case .outside(let date):
                        // A day the calendar doesn't reach. Shown, so the
                        // month keeps its shape; said to nobody.
                        dayNumber(date)
                            .foregroundStyle(.quaternary)
                            .frame(maxWidth: .infinity, minHeight: Self.cellSide)
                            .accessibilityHidden(true)
                    case .day(let day):
                        dayCell(day, state: states[day.date] ?? .locked)
                    }
                }
            }
        }
        .padding(Theme.Spacing.m)
        .elevatedCard()
    }

    /// The tap target's side: the 44pt floor.
    private static let cellSide: CGFloat = 44
    /// The disc inside it.
    private static let discSide: CGFloat = 36

    /// The numerals stop growing at a size seven columns can still hold; the
    /// rest of the screen keeps scaling.
    private func dayNumber(_ date: Date) -> some View {
        Text("\(calendar.component(.day, from: date))")
            .font(.callout)
            .monospacedDigit()
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }

    private func dayCell(_ day: PastPuzzleDay, state: DayState) -> some View {
        let isToday = calendar.isDate(day.date, inSameDayAs: today)
        return Button {
            if state == .locked {
                showPaywall = true
            } else {
                path.append(PastPuzzleRoute(puzzle: day.puzzle))
            }
        } label: {
            ZStack {
                switch state {
                case .solved:
                    Circle().fill(Theme.ink)
                case .inProgress, .open:
                    // A system fill, not the canvas colour: in dark mode the
                    // canvas is black on a grey card, and a day not yet
                    // played drew heavier than a solved one.
                    Circle().fill(Color(uiColor: .tertiarySystemFill))
                case .locked:
                    Color.clear
                }
                if isToday {
                    // Blue is for the thing to do: today's is the day to play.
                    Circle().strokeBorder(Theme.accent, lineWidth: 2)
                }
                dayNumber(day.date)
                    .fontWeight(state == .solved || isToday ? .semibold : .regular)
                    .foregroundStyle(numberStyle(state))
            }
            .frame(width: Self.discSide, height: Self.discSide)
            .overlay(alignment: .bottom) {
                if state == .inProgress {
                    Circle()
                        .fill(.orange)
                        .frame(width: 5, height: 5)
                        .offset(y: 4)
                }
            }
            .frame(maxWidth: .infinity, minHeight: Self.cellSide)
            .contentShape(.rect)
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityLabel(accessibilityLabel(day, state: state, isToday: isToday))
        .accessibilityHint(state == .locked ? "Opens Premium plans" : "Opens the puzzle")
    }

    private func numberStyle(_ state: DayState) -> Color {
        switch state {
        case .solved: Theme.onInk
        case .inProgress, .open: .primary
        case .locked: Color(uiColor: .secondaryLabel)
        }
    }

    private func accessibilityLabel(_ day: PastPuzzleDay, state: DayState, isToday: Bool) -> String {
        let date = isToday
            ? "Today"
            : day.date.formatted(.dateTime.weekday(.wide).day().month(.wide))
        let status = switch state {
        case .solved: "solved"
        case .inProgress: "in progress"
        case .open: "not started"
        case .locked: "locked"
        }
        return "\(date), \(day.puzzle.title), \(status)"
    }

    // MARK: - Offer

    /// The one offer on the screen, under the calendar it speaks for — the
    /// Library's card, in the calendar's words.
    private func premiumOffer(locked: Int) -> some View {
        Button {
            showPaywall = true
        } label: {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Play any day")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Color.primary)
                    Text("^[\(locked) more day](inflect: true) to open here, plus hints whenever you need them.")
                        .font(.subheadline)
                        .foregroundStyle(Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                PremiumOfferCTA()
            }
            .padding(Theme.Spacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
            .elevatedCard()
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityHint("Opens Premium plans")
    }
}
