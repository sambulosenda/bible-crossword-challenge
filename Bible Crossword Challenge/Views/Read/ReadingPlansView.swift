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
    /// Opens today's chapter. The card can't push the reader itself: on Today
    /// and on Read it lands on different stacks.
    let onRead: () -> Void

    @Environment(\.readingPlans) private var plans

    var body: some View {
        if let plan = plans.activePlan, let progress = plans.progress {
            if plans.isComplete {
                completeCard(plan)
            } else if let day = plans.nextDay {
                activeCard(plan, day: day, of: progress.chapterCount)
            }
        } else if !compact {
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
            VStack(alignment: .leading, spacing: compact ? Theme.Spacing.xs : Theme.Spacing.m) {
                HStack(spacing: Theme.Spacing.m) {
                    Image(systemName: doneToday ? "checkmark.circle.fill" : "book.pages")
                        .font(.title2)
                        .foregroundStyle(doneToday ? .green : Theme.accent)
                        .frame(width: 44, height: 44)
                        .background((doneToday ? Color.green : Theme.accent).opacity(0.14), in: .circle)
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
                    Image(systemName: "chevron.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                if !compact {
                    ProgressView(value: Double(day - 1), total: Double(total))
                        .tint(Theme.accent)
                }
            }
            .padding(Theme.Spacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .elevatedCard()
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Today's chapter, \(reference), day \(shownDay) of \(total)\(doneToday ? ", read today" : "")")
        .accessibilityHint("Opens the chapter")
    }

    private func completeCard(_ plan: ReadingPlan) -> some View {
        NavigationLink {
            ReadingPlansView()
        } label: {
            HStack(spacing: Theme.Spacing.m) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.title2)
                    .foregroundStyle(.green)
                    .frame(width: 44, height: 44)
                    .background(Color.green.opacity(0.14), in: .circle)
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

    var body: some View {
        List(ReadingPlan.all) { plan in
            Button {
                choose(plan)
            } label: {
                HStack(spacing: Theme.Spacing.m) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(plan.title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text("\(chapterCount(plan)) chapters · one a day")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                        Text(plan.blurb)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    if plans.activePlan?.id == plan.id {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Theme.accent)
                            .accessibilityLabel("Current plan")
                    }
                }
                .padding(.vertical, 4)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Starts this plan")
        }
        .scrollContentBackground(.hidden)
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity)
        .background(Theme.background)
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
