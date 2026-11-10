//
//  DailyRitualCard.swift
//  Bible Crossword Challenge
//
//  "Daily Bread" on Today: three rows — solve a puzzle, read its verse, review
//  one memory verse — under one ring that closes when all three are done. See
//  `DailyRitual` for what each beat is and where its state comes from.
//
//  Narrow value inputs, like the other Today cards, and no navigation or
//  sheets of its own: HomeView owns those (CLAUDE.md — a sheet on a card that
//  can disappear is torn away with it), and the card only says which row was
//  tapped.
//

import SwiftUI

struct DailyRitualCard: View {
    let ritual: DailyRitual
    /// The puzzle beat one opens — the hero's puzzle. Nil leaves the row
    /// pointing at the hero rather than a button.
    let puzzleTitle: String?
    let onBeat: (DailyRitual.Beat) -> Void
    /// The card is on screen — the impression.
    let onSeen: () -> Void

    /// What the ring shows. Lags `ritual.doneCount` so a beat finished on
    /// another screen closes its segment on the way back, where the player
    /// sees it, rather than while Today is covered.
    @State private var shownDone: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Captured as a plain Int: the haptic's condition closure isn't
        // main-actor isolated.
        let total = DailyRitual.Beat.allCases.count
        return VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            header
            VStack(spacing: 0) {
                ForEach(DailyRitual.Beat.allCases, id: \.self) { beat in
                    if beat != .puzzle { Divider().padding(.leading, 36) }
                    row(beat)
                }
            }
        }
        .padding(Theme.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .elevatedCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("dailyRitualCard")
        .onScrollVisibilityChange(threshold: 0.6) { visible in
            if visible { onSeen() }
        }
        .onAppear { catchUpRing() }
        .onChange(of: ritual.doneCount) { catchUpRing() }
        // The ring closing, felt as well as seen — once, as it fills.
        .sensoryFeedback(.success, trigger: shownDone) { old, new in
            old != nil && old != total && new == total
        }
    }

    private func catchUpRing() {
        guard let shown = shownDone else {
            shownDone = ritual.doneCount
            return
        }
        guard shown != ritual.doneCount else { return }
        if reduceMotion {
            shownDone = ritual.doneCount
        } else {
            withAnimation(.spring(duration: 0.7, bounce: 0.3).delay(0.35)) {
                shownDone = ritual.doneCount
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: Theme.Spacing.m) {
            RitualRing(done: shownDone ?? ritual.doneCount, total: DailyRitual.Beat.allCases.count)
            VStack(alignment: .leading, spacing: 2) {
                Text("Daily Bread")
                    .font(.headline)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Daily Bread. \(subtitle)")
        .accessibilityAddTraits(.isHeader)
    }

    private var subtitle: String {
        switch ritual.doneCount {
        case 0: return "Three minutes: a puzzle, its verse, one review"
        case DailyRitual.Beat.allCases.count: return "Done for today. See you tomorrow"
        default: return "\(ritual.doneCount) of \(DailyRitual.Beat.allCases.count) done"
        }
    }

    // MARK: - Rows

    private func row(_ beat: DailyRitual.Beat) -> some View {
        let done = ritual.done.contains(beat)
        let enabled = isEnabled(beat)
        return Button {
            onBeat(beat)
        } label: {
            HStack(spacing: Theme.Spacing.m) {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(done ? AnyShapeStyle(FeatureTint.solved) : AnyShapeStyle(.tertiary))
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title(beat))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(done ? .secondary : .primary)
                    Text(detail(beat))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                if enabled {
                    Image(systemName: "chevron.forward")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, Theme.Spacing.s)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title(beat)). \(detail(beat))")
        .accessibilityValue(done ? "Done" : "Not done")
        .accessibilityAddTraits(enabled ? .isButton : [])
        .accessibilityIdentifier(identifier(beat))
    }

    private func isEnabled(_ beat: DailyRitual.Beat) -> Bool {
        switch beat {
        case .puzzle:
            return !ritual.done.contains(.puzzle) && puzzleTitle != nil
        case .verse:
            // Re-readable once done: it's a verse, not a chore.
            return ritual.verse != nil
        case .review:
            switch ritual.review {
            case nil, .waitingForVerse: return false
            default: return true
            }
        }
    }

    private func title(_ beat: DailyRitual.Beat) -> String {
        switch beat {
        case .puzzle: return "Solve a puzzle"
        case .verse: return "Read its verse"
        case .review:
            if case .learn = ritual.review { return "Learn it by heart" }
            return "Review a memory verse"
        }
    }

    private func detail(_ beat: DailyRitual.Beat) -> String {
        switch beat {
        case .puzzle:
            if ritual.done.contains(.puzzle) { return "Done" }
            return puzzleTitle ?? "Today's puzzle, above"
        case .verse:
            guard let verse = ritual.verse else { return "Opens when you finish a puzzle" }
            return verse.reference
        case .review:
            switch ritual.review {
            case nil: return "Done"
            case .practice(_, let reference, let isDue):
                return isDue ? "\(reference) · due today" : reference
            case .learn(let verse): return "\(verse.reference) · one minute"
            case .waitingForVerse: return "Opens with today's verse"
            case .choose: return "Pick a verse to learn"
            }
        }
    }

    private func identifier(_ beat: DailyRitual.Beat) -> String {
        switch beat {
        case .puzzle: return "ritualPuzzle"
        case .verse: return "ritualVerse"
        case .review: return "ritualReview"
        }
    }
}

// MARK: - Ring

/// One ring in three arcs, filling as beats are done; green with a check once
/// it closes. Decoration — the header's text says the same for VoiceOver.
private struct RitualRing: View {
    let done: Int
    let total: Int

    var body: some View {
        let complete = done >= total
        ZStack {
            Circle()
                .stroke(Color(.tertiarySystemFill), lineWidth: 5)
            Circle()
                .trim(from: 0, to: CGFloat(min(done, total)) / CGFloat(max(total, 1)))
                .stroke(
                    complete ? FeatureTint.solved : Theme.accent,
                    style: StrokeStyle(lineWidth: 5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            Image(systemName: complete ? "checkmark" : "leaf.fill")
                .font(.system(size: complete ? 17 : 15, weight: .bold))
                .foregroundStyle(complete ? FeatureTint.solved : FeatureTint.memory)
                .contentTransition(.symbolEffect(.replace))
        }
        .frame(width: 44, height: 44)
        .accessibilityHidden(true)
    }
}

// MARK: - Verse sheet

/// Beat two: the verse of the puzzle just solved, set to be read, with the
/// one step that turns it into tomorrow's habit — putting it on the shelf.
/// Reading it is the beat; the shelf is an offer.
struct RitualVerseSheet: View {
    let verse: DailyRitual.Verse
    /// The verse fits the memory grid, isn't held, and the shelf has room.
    let canLearn: Bool
    let onLearn: () -> Void
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            Label("TODAY'S VERSE", systemImage: "book").kicker()
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    Text(verse.text)
                        .font(.scripture(.title2))
                        .lineSpacing(6)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(verse.reference)
                        .font(.headline)
                        .foregroundStyle(Theme.accent)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)

            if canLearn {
                VStack(spacing: Theme.Spacing.s) {
                    Button(action: onLearn) {
                        Label("Learn it by heart", systemImage: "brain")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.pillProminent)
                    .accessibilityIdentifier("ritualVerseLearn")
                    .accessibilityHint("Adds the verse to your memory verses for today's review")
                    Button("Not now", action: onDone)
                        .font(.subheadline.weight(.medium))
                        .buttonStyle(.borderless)
                        .tint(Theme.accent)
                        .accessibilityIdentifier("ritualVerseDone")
                }
            } else {
                Button(action: onDone) {
                    Text("Done").frame(maxWidth: .infinity)
                }
                .buttonStyle(.pillProminent)
                .accessibilityIdentifier("ritualVerseDone")
            }
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .background(Theme.background)
    }
}
