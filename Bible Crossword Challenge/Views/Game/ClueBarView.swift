//
//  ClueBarView.swift
//  Bible Crossword Challenge
//
//  Shows the active clue above the keyboard with previous/next navigation.
//

import SwiftUI

struct ClueBarView: View {
    @Bindable var vm: GameViewModel
    /// At accessibility text sizes the pill can no longer share the number
    /// line without running into it, so it falls back to its own row there.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Runs the stall nudge's action when the line is tapped — a whole-puzzle
    /// check, the verse, or a free letter per `vm.stallNudgeKind`. Owned by the
    /// game view so the analytics and check/hint plumbing stay in one place.
    var onStallTap: (() -> Void)? = nil
    /// Opens the passage the active clue is drawn from — the free verse hint,
    /// one tap from the clue instead of a row inside the Hints menu. In the 30
    /// days to 2026-09-02 the verse was the least-found hint (56 players vs 140
    /// for letter reveals) and the most-used per player who found it (~24
    /// uses each): a demand the menu was hiding. Same path as the menu row,
    /// so the analytics compare directly.
    var onVerseTap: (() -> Void)? = nil
    /// Whether the bar sets the clue text itself. Off while the clue list is
    /// standing beside it: the list's highlighted row already is the active
    /// clue, and repeating it here put the same words on screen twice. The
    /// number line, nudge, Verse and chevrons stay — they are controls the
    /// list doesn't have.
    var showsClue: Bool = true

    var body: some View {
        VStack(spacing: Theme.Spacing.s) {
            if dynamicTypeSize.isAccessibilitySize {
                HStack(spacing: Theme.Spacing.s) {
                    inlineNudge
                    Spacer(minLength: 0)
                    verseButton
                }
            }
            clueRow
        }
        .animation(.snappy, value: endgameNudge)
        .animation(.snappy, value: vm.isStallNudgeActive)
        .animation(.snappy, value: showsVerseButton)
        // The whole bar stops where the clue does (see `clueText`). Capped
        // there alone, "2 Down" and Verse kept growing and at AX5 outranked
        // the clue they label. `dynamicTypeSize` above still reads the
        // player's real size, so the accessibility layouts keep firing.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .padding(.horizontal, Theme.Spacing.s)
        // Room to breathe on both edges. The bar sits between a grid and a
        // keyboard with no margin of its own, so 4pt read as content jammed
        // against both. Affordable because moving the nudge onto the number
        // line gave back a whole row — this spends part of it and the bar is
        // still shorter than it was. Without the clue the bar is one row of
        // 44pt controls, which is room enough; the list above gets the rest.
        .padding(.top, showsClue ? Theme.Spacing.s : 0)
        .padding(.bottom, showsClue ? Theme.Spacing.s + Theme.Spacing.xs : 0)
        // On the page, not in a grey band: the clue is part of the puzzle,
        // and the filled strip read as a toolbar bolted under the grid. No
        // hairline under it either, now the keypad sits on the same paper —
        // a rule between two halves of one surface read as a seam.
    }

    /// The clue itself.
    ///
    /// Two of the three modifiers here are one decision: how much room the
    /// clue gets. `reservesSpace` needs a concrete count, so the unreserved
    /// case is a separate branch rather than a `nil` passed through.
    @ViewBuilder
    private func clueText(_ clue: String) -> some View {
        // Title3, the size the clue list's rows are measured against: the clue
        // is what the player reads most, and it was the smallest text on the
        // screen. System, not the scripture serif — the serif marks scripture,
        // and the same clue set in the list's font beside the panel read as two
        // different things. Every clue
        // written fits two lines at the row's 282pt (iPhone 18 Pro) from 16pt
        // up, and 56 of 3,549 need the shrink below to get there — so it
        // floors at 0.8 (16pt, the callout size this replaced) rather than
        // truncating or growing the bar a line.
        let text = Text(clue)
            .font(.title3)
            .minimumScaleFactor(0.8)
            .foregroundStyle(.primary)
        Group {
            if let clueLines {
                // Reserved, not just capped: without it a one-line clue and a
                // two-line clue give the bar different heights, so the grid
                // reflowed on plain clue navigation too — the same bug as the
                // nudge row, just triggered more often.
                text.lineLimit(clueLines, reservesSpace: true)
            } else {
                text.lineLimit(nil)
            }
        }
        // The clue is the puzzle. Two lines holds the longest one written (72
        // characters) at the default size and nothing larger, so every step up
        // cut the clue off mid-word — at AX5 it read "The Bible's fir…" and the
        // puzzle could not be solved at all. The ceiling is the keyboard's, for
        // the keyboard's reason: ten fixed columns and three rows below cannot
        // give any more.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    /// Lines reserved for the clue, or `nil` to let it run as long as it must.
    ///
    /// Two lines is a fixed height, which is the point: it stops the bar —
    /// and so the grid above it — resizing every time you step to a clue of a
    /// different length. That holds up to the accessibility sizes, where the
    /// glyphs stop growing at the cap but the wrap keeps tightening: measured
    /// on device, a capped line takes about fourteen characters, so the
    /// longest clue written wants five lines and the next one written could
    /// want six. Any fixed number is a guess that truncates the clue the day
    /// it is wrong, so above the cap there is no number — the clue is the
    /// puzzle, and a bar that changes height is a smaller price than a clue
    /// that can't be read.
    ///
    /// The price is not nothing. On a phone at these sizes the grid is in its
    /// pan/zoom viewport (`CrosswordGridView.body` falls back to it once the
    /// fitted cell would drop under 24pt), where cell size comes from
    /// `zoomSide` and not from the height left over, so the cells hold still
    /// and only the viewport changes. On a screen roomy enough to stay in the
    /// fitted layout — an iPad at the lower accessibility sizes — stepping to
    /// a longer clue does still resize the cells, which is the reflow the
    /// reservation was added to stop. Traded knowingly: that reflow is a
    /// wobble, and the truncation it was preventing was a clue you could not
    /// read at all.
    private var clueLines: Int? {
        dynamicTypeSize.isAccessibilitySize ? nil : 2
    }

    /// The rescue offer and the endgame countdown, sharing the clue-number
    /// line rather than claiming a row of their own above the bar.
    ///
    /// As its own row it grew the bar, and the grid takes whatever height is
    /// left (`maxHeight: .infinity` in CrosswordGameView) — so every cell
    /// resized and reflowed the moment the nudge appeared, which is precisely
    /// the moment the player was already stuck. It also sat furthest from the
    /// clue it refers to, and pushed that clue away from the keyboard. On the
    /// number line it costs no height at all: the number is short and the rest
    /// of that line was dead space.
    ///
    /// The stall line still outranks the endgame countdown while active: a
    /// stuck player needs an action, not encouragement.
    /// The nudge's appearance only, with no behaviour. Rendered twice: once
    /// hidden inside the clue button to reserve its footprint on the number
    /// line, and once for real in the overlay on top. The overlay alone can't
    /// do the job — it takes no part in layout, so at longer clue numbers or
    /// larger text the pill simply sat on top of "10 Down".
    @ViewBuilder
    private var nudgeBody: some View {
        if vm.isStallNudgeActive {
            Label(stallNudgeText, systemImage: stallNudgeIcon)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.accent)
                .lineLimit(1)
                // The verse variant is the longest string here and only just
                // clears an iPhone-mini-width column; shrink it a little
                // rather than truncate an offer mid-word.
                .minimumScaleFactor(0.85)
                .padding(.horizontal, Theme.Spacing.s)
                .padding(.vertical, Theme.Spacing.xs)
                .background(Theme.accent.opacity(0.12), in: .capsule)
        } else if let nudge = endgameNudge {
            Text(nudge)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.accent)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .padding(.vertical, Theme.Spacing.xs)
        }
    }

    /// The interactive nudge. Only the stall tier is tappable — the endgame
    /// line is encouragement, with nothing to act on.
    @ViewBuilder
    private var inlineNudge: some View {
        if vm.isStallNudgeActive {
            Button {
                onStallTap?()
            } label: {
                nudgeBody.contentShape(.capsule)
            }
            .buttonStyle(.plain)
            .accessibilityHint(stallNudgeAccessibilityHint)
            // Fades in place. The old row slid up from the bar's edge, which
            // only read as motion because the bar was growing underneath it.
            .transition(.opacity)
        } else if endgameNudge != nil {
            nudgeBody
                .accessibilityHidden(true)
                .transition(.opacity)
        }
    }

    /// The stall line's copy, matched to the action the tap performs. The
    /// early tier promises a letter, not a check — under 40% fill there is
    /// nothing worth checking, and a vague "stuck?" with no offer is exactly
    /// the line a quitting player ignores.
    /// Short by necessity: sharing the number line leaves roughly 150pt on a
    /// 402pt screen, and the old full sentences ran to ~178pt — they fit only
    /// by pressing right up against "10 Down", which is what made the bar feel
    /// airless. The "Stuck?" prefix is what got cut, and the existing note
    /// below argues that is the right half to lose: the offer is the part that
    /// stops a quitting player, not the question.
    private var stallNudgeText: String {
        switch vm.stallNudgeKind {
        case .checkAnswers: "Check answers"
        case .readVerse: "Read the verse"
        case .freeLetter: "Free letter"
        }
    }

    private var stallNudgeIcon: String {
        switch vm.stallNudgeKind {
        case .checkAnswers: "checkmark.circle"
        case .readVerse: "book"
        case .freeLetter: "a.square"
        }
    }

    private var stallNudgeAccessibilityHint: String {
        switch vm.stallNudgeKind {
        case .checkAnswers: "Checks the whole puzzle for mistakes"
        case .readVerse: "Opens the passage this clue comes from, without using a hint"
        case .freeLetter: "Reveals one letter without using a hint"
        }
    }

    /// Endgame encouragement for the full-size grids. Fires when the last one
    /// or two words are all that's left — the point where quitting means
    /// forfeiting an almost-finished puzzle, which is worth saying out loud.
    /// Minis don't get it: with five clues it would appear mid-solve.
    private var endgameNudge: String? {
        guard !vm.puzzle.isMini, !vm.isComplete else { return nil }
        switch vm.remainingClueCount {
        case 1: return "Last clue!"
        case 2: return "2 clues to go!"
        default: return nil
        }
    }

    /// Only on clues that have a passage: an always-present button would
    /// advertise a hint most clues can't offer yet, and a dimmed one is a
    /// question the player can't answer. See ClueListView. Stands down while
    /// the stall line is offering the same verse, so one action isn't on the
    /// line twice.
    private var showsVerseButton: Bool {
        guard vm.activeSlot?.reference != nil, onVerseTap != nil else { return false }
        return !(vm.isStallNudgeActive && vm.stallNudgeKind == .readVerse)
    }

    /// The verse button's appearance, with no behaviour — rendered hidden on
    /// the number line to reserve its width, like `nudgeBody`.
    private var verseLabel: some View {
        Label("Verse", systemImage: "book")
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.accent)
            .lineLimit(1)
            .padding(.vertical, Theme.Spacing.xs)
    }

    /// The free verse hint, on the clue-number line. It used to be a 44pt
    /// icon column in the clue row, which took the width the clue needs to
    /// hold two lines at title3; the number line had that width spare.
    @ViewBuilder
    private var verseButton: some View {
        if showsVerseButton, let onVerseTap {
            Button {
                onVerseTap()
            } label: {
                verseLabel
                    // The label is caption-sized (~24pt tall with its
                    // padding); the touch target isn't. 10pt each way makes 44.
                    .contentShape(.rect.inset(by: -10))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Read the verse")
            .accessibilityHint("Opens the passage this clue comes from. Free, but counts as a hint.")
            .transition(.opacity)
        }
    }

    private var clueRow: some View {
        HStack(spacing: Theme.Spacing.s) {
            Button {
                vm.advanceClue(by: -1)
            } label: {
                Image(systemName: "chevron.backward")
                    .font(.headline)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .accessibilityLabel("Previous clue")

            Button {
                vm.toggleDirection()
            } label: {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    if let slot = vm.activeSlot {
                        HStack(spacing: Theme.Spacing.s) {
                            // Secondary, not accent: it is a label, and blue
                            // is kept for what can be tapped — the chevrons
                            // and Verse on this same row.
                            // The answer's length rides here, not as "(6)"
                            // after the clue: the clue's two reserved lines
                            // are measured against the clue alone, and the
                            // suffix would push more of them into the shrink.
                            // The clue's name in ink, its length in grey: one
                            // line in two weights of emphasis, so the bar has
                            // a head without a box around it.
                            Text("\(Text("\(slot.number) \(slot.direction.label)").foregroundStyle(.primary)) · \(slot.length) letters")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .layoutPriority(1)
                            // Without this the row hugs its content and the
                            // spacer collapses, parking the pill against the
                            // number instead of out at the column's edge.
                            Spacer(minLength: Theme.Spacing.m)
                            // Invisible twin of the overlaid pill: it claims
                            // the width so the number can never collide with
                            // it, and collapses to nothing when no nudge is
                            // showing. Only on the line they actually share:
                            // at accessibility sizes the nudge has its own row
                            // (see `body`), so reserving for it here was pure
                            // theft — it squeezed "19 Across" down to "19 A…".
                            if !dynamicTypeSize.isAccessibilitySize {
                                HStack(spacing: Theme.Spacing.s) {
                                    nudgeBody
                                    if showsVerseButton { verseLabel }
                                }
                                .hidden()
                            }
                        }
                        .frame(maxWidth: .infinity)
                        if showsClue {
                            clueText(slot.clue)
                        }
                    } else {
                        Text("Select a cell to begin")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(clueAccessibilityLabel)
            .accessibilityHint("Switches between across and down")
            // Overlaid rather than stacked into the label: it must stay its
            // own focusable control, and `children: .combine` above would
            // swallow it into the clue element if it were a child.
            .overlay(alignment: .topTrailing) {
                if !dynamicTypeSize.isAccessibilitySize {
                    HStack(spacing: Theme.Spacing.s) {
                        inlineNudge
                        verseButton
                    }
                }
            }

            Button {
                vm.advanceClue(by: 1)
            } label: {
                Image(systemName: "chevron.forward")
                    .font(.headline)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .accessibilityLabel("Next clue")
        }
    }

    private var clueAccessibilityLabel: String {
        guard let slot = vm.activeSlot else { return "Select a cell to begin" }
        return "Clue \(slot.number) \(slot.direction.label), \(slot.length) letters: \(slot.clue)"
    }
}
