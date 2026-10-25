//
//  ReadingPlansView.swift
//  Bible Crossword Challenge
//
//  The chapter-a-day plan: the card that shows today's chapter (on the Read
//  tab and, once a plan is running, on Today), and the list to pick one.
//

import SwiftUI

// MARK: - Card

/// Today's chapter, or the invitation to pick a plan. `compact` is Today's
/// version: one row, no blurb, no progress bar — the tab has room to explain,
/// the feed has room to remind.
struct ReadingPlanCard: View {
    var compact = false
    /// The Read tab draws the running plan at the top and the invite at the
    /// foot, so each placement asks for one half.
    var showsActive = true
    var showsInvite = true
    /// Opens today's chapter. The card can't push the reader itself: on Today
    /// and on Read it lands on different stacks.
    let onRead: () -> Void

    @Environment(\.readingPlans) private var plans

    var body: some View {
        if let plan = plans.activePlan, let progress = plans.progress {
            if showsActive {
                if plans.isComplete {
                    completeCard(plan)
                } else if let day = plans.nextDay {
                    activeCard(plan, day: day, of: progress.chapterCount)
                }
            }
        } else if !compact && showsInvite {
            inviteCard
        }
    }

    private func activeCard(_ plan: ReadingPlan, day: Int, of total: Int) -> some View {
        let doneToday = plans.readToday
        // Once today's is read the card shows what was read, with the next
        // chapter named underneath; tapping still opens the next one, since
        // reading ahead is allowed.
        let shownDay = doneToday ? max(1, day - 1) : day
        let reference = "\(plan.book) \(shownDay)"
        return Button(action: onRead) {
            if compact {
                // Today's version is a cover row like the rest of "Keep
                // going", its bar the share of the book read.
                CoverRow(
                    symbol: doneToday ? "checkmark" : "book.pages",
                    tint: doneToday ? FeatureTint.solved : FeatureTint.readingPlan,
                    title: reference,
                    subtitle: doneToday
                        ? "Read today · Next: \(plan.book) \(day)"
                        : "Today's chapter · Day \(day) of \(total)",
                    progress: Double(day - 1) / Double(max(total, 1))
                )
            } else {
                fullActiveLabel(plan, day: day, total: total, doneToday: doneToday, reference: reference)
            }
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Today's chapter, \(reference), day \(shownDay) of \(total)\(doneToday ? ", read today" : "")")
        .accessibilityHint("Opens the chapter")
    }

    /// The Read tab's version: a card with a kicker, a serif title and the
    /// plan's progress bar.
    private func fullActiveLabel(_ plan: ReadingPlan, day: Int, total: Int, doneToday: Bool, reference: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack(spacing: Theme.Spacing.m) {
                RowIcon(symbol: doneToday ? "checkmark" : "book.pages",
                        tint: doneToday ? FeatureTint.solved : FeatureTint.readingPlan)
                VStack(alignment: .leading, spacing: 2) {
                    // The count sits in the subtitle: as a kicker
                    // "TODAY'S CHAPTER · DAY 12 OF 21" wrapped on a phone.
                    Label("Today's chapter", systemImage: "calendar")
                        .kicker()
                    Text(reference)
                        .font(.scripture(.title3, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(doneToday
                         ? "Read today · Next: \(plan.book) \(day)"
                         : "\(plan.title) · Day \(day) of \(total)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            ProgressView(value: Double(day - 1), total: Double(total))
                .tint(Theme.progressBar)
        }
        .cardRowPadding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .elevatedCard()
    }

    private func completeCard(_ plan: ReadingPlan) -> some View {
        NavigationLink {
            ReadingPlansView()
        } label: {
            if compact {
                CoverRow(
                    symbol: "checkmark.seal.fill",
                    tint: FeatureTint.solved,
                    title: "You read all of \(plan.book)",
                    subtitle: "Choose another book to read through"
                )
            } else {
            HStack(spacing: Theme.Spacing.m) {
                RowIcon(symbol: "checkmark.seal.fill", tint: FeatureTint.solved)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Plan complete").kicker()
                    Text("You read all of \(plan.book)")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("Choose another book to read through")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .cardRowPadding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .elevatedCard()
            }
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Plan complete. You read all of \(plan.book). Choose another book.")
    }

    private var inviteCard: some View {
        NavigationLink {
            ReadingPlansView()
        } label: {
            HStack(spacing: Theme.Spacing.m) {
                Image(systemName: "book.pages")
                    .font(.title2)
                    .foregroundStyle(Theme.accent)
                    .frame(width: 44, height: 44)
                    .background(Theme.accent.opacity(0.14), in: .circle)
                VStack(alignment: .leading, spacing: 2) {
                    Text("A chapter a day").kicker()
                    Text("Read through a book")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("One chapter each day, with today's waiting here.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(Theme.Spacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .elevatedCard()
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("A chapter a day. Read through a book, one chapter each day.")
        .accessibilityHint("Opens the list of reading plans")
    }
}

// MARK: - Picker

struct ReadingPlansView: View {
    @Environment(\.readingPlans) private var plans
    @Environment(\.scripture) private var scripture
    @Environment(\.analytics) private var analytics
    @Environment(\.dismiss) private var dismiss

    /// A plan tapped while another is running — confirmed before it replaces it.
    @State private var pendingSwitch: ReadingPlan?

    /// Plan days opened from the running plan's card.
    @State private var readingDay: Int?

    private var runningPlan: ReadingPlan? {
        guard let plan = plans.activePlan, !plans.isComplete else { return nil }
        return plan
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                Text("One chapter a day, with today's waiting on the Verses tab.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, Theme.Spacing.xs)

                if let plan = runningPlan {
                    runningCard(plan)
                }

                let others = ReadingPlan.all.filter { $0.id != runningPlan?.id }
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    if runningPlan != nil {
                        Text("Other plans").sectionHeader()
                            .padding(.horizontal, Theme.Spacing.xs)
                    }
                    // Cards, two or three abreast on a wide screen: five plans
                    // are a shelf to choose from, and as 640pt list rows on an
                    // opened iPhone Duo each was a line of text with 400pt of
                    // white before its chevron. One per line on a phone.
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 260), spacing: Theme.Spacing.m)],
                        alignment: .leading,
                        spacing: Theme.Spacing.m
                    ) {
                        ForEach(others) { planCard($0) }
                    }
                }
            }
            .padding(Theme.Spacing.m)
            .frame(maxWidth: 960)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background)
        .navigationDestination(item: $readingDay) { day in
            if let plan = plans.activePlan {
                ChapterReaderView(
                    startBook: plan.book,
                    startChapter: day,
                    source: "read_plan",
                    planChapter: PlanChapter(book: plan.book, chapter: day),
                    onPlanChapterRead: { markRead(plan, day: day) }
                )
            }
        }
        .navigationTitle("Reading plans")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Switch plans?",
            isPresented: Binding(get: { pendingSwitch != nil }, set: { if !$0 { pendingSwitch = nil } }),
            titleVisibility: .visible
        ) {
            if let pendingSwitch {
                Button("Start \(pendingSwitch.title)", role: .destructive) { start(pendingSwitch) }
            }
            Button("Keep current plan", role: .cancel) {}
        } message: {
            if let current = plans.activePlan {
                Text("Your progress in \(current.title) will be lost.")
            }
        }
    }

    /// The plan being read leads, with where the player is and the next
    /// chapter one tap away. It sat third in the list, marked only by its
    /// meta line turning black.
    private func runningCard(_ plan: ReadingPlan) -> some View {
        let total = max(chapterCount(plan), 1)
        let done = plans.progress?.readDays.count ?? 0
        let next = plans.nextDay ?? min(done + 1, total)
        return VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("Reading now").kicker()
                Text(plan.title)
                    .font(.scripture(.title2, weight: .semibold))
                Text(plan.blurb)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                ProgressView(value: Double(done), total: Double(total))
                    .tint(Theme.progressBar)
                Text("Day \(min(done + 1, total)) of \(total)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Button {
                analytics.log(.scriptureOpened(reference: "\(plan.book) \(next)", source: "read_plan"))
                readingDay = next
            } label: {
                Label(plans.readToday ? "Read ahead · \(plan.book) \(next)" : "Read \(plan.book) \(next)",
                      systemImage: "book")
            }
            .buttonStyle(.pillProminent)
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .elevatedCard()
    }

    private func planCard(_ plan: ReadingPlan) -> some View {
        Button {
            choose(plan)
        } label: {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(plan.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                Text(plan.blurb)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Theme.Spacing.s)
                Text(meta(plan))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(Theme.Spacing.l)
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
            .elevatedCard()
            .contentShape(.rect)
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(plans.activePlan?.id == plan.id ? "Your current plan" : "Starts this plan")
    }

    private func markRead(_ plan: ReadingPlan, day: Int) {
        guard plans.markRead(day: day) else { return }
        analytics.log(.planChapterRead(plan: plan.id, day: day))
        if plans.isComplete {
            analytics.log(.planCompleted(plan: plan.id, days: day))
        }
    }

    /// "21 days", or where the player is in the plan they're running.
    private func meta(_ plan: ReadingPlan) -> String {
        let total = chapterCount(plan)
        guard plans.activePlan?.id == plan.id, let progress = plans.progress else {
            return "\(total) days"
        }
        if plans.isComplete { return "Finished · \(total) days" }
        return "Reading · day \(min(progress.readDays.count + 1, total)) of \(total)"
    }

    private func chapterCount(_ plan: ReadingPlan) -> Int {
        scripture.book(named: plan.book)?.chapterCount ?? 0
    }

    private func choose(_ plan: ReadingPlan) {
        if let current = plans.activePlan, current.id != plan.id, !plans.isComplete {
            pendingSwitch = plan
        } else {
            start(plan)
        }
    }

    private func start(_ plan: ReadingPlan) {
        if let current = plans.activePlan, current.id != plan.id, let progress = plans.progress {
            analytics.log(.planStopped(plan: current.id, day: progress.readDays.count))
        }
        plans.start(plan, chapterCount: chapterCount(plan))
        analytics.log(.planStarted(plan: plan.id))
        pendingSwitch = nil
        dismiss()
    }
}
