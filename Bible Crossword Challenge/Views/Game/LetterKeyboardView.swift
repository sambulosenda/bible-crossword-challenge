//
//  LetterKeyboardView.swift
//  Bible Crossword Challenge
//
//  Custom A–Z keypad. A dedicated keyboard avoids autocorrect/return-key issues
//  and gives precise control over crossword entry. Uses sensory feedback rather
//  than UIKit feedback generators.
//

import SwiftUI

struct LetterKeyboardView: View {
    var isPencilMode: Bool = false
    let onLetter: (Character) -> Void
    let onDelete: () -> Void
    /// Present only where pencil entry exists (the game); the onboarding
    /// first-solve keeps the plain pad.
    var onTogglePencil: (() -> Void)? = nil
    /// Height added to every key, from room the screen has spare (see
    /// `CrosswordGameView.keyGrowth`). Still under the 60pt ceiling below.
    var extraKeyHeight: CGFloat = 0
    /// The game's keys: white (grey in dark) on the warm keyboard bed the
    /// call site lays under the clue strip and the pad, with grey function
    /// keys, as the system keyboard sets them. Off, the pad keeps grey keys
    /// on whatever surface it sits on (onboarding, memory practice).
    var onBed = false

    @State private var lastKeyTick = 0

    /// Key height grows with the user's text-size setting so large Dynamic Type
    /// glyphs aren't clipped.
    @ScaledMetric(relativeTo: .title3) private var keyHeight: CGFloat = Self.baseKeyHeight

    /// The same ceiling the `dynamicTypeSize` cap in `body` puts on the glyphs,
    /// applied by hand because that modifier can't reach this property:
    /// `@ScaledMetric` resolves against the environment this view *receives*,
    /// and the cap only governs the environment it *passes down*. Left uncapped
    /// the keys went on growing under capped letters, and three rows of them
    /// pushed the grid off the bottom of the screen.
    private var cappedKeyHeight: CGFloat { min(keyHeight + extraKeyHeight, Self.maxKeyHeight) }

    /// Key height at the default text size, before any spare room is added.
    static let baseKeyHeight: CGFloat = 46
    static let maxKeyHeight: CGFloat = 60
    static let rowCount = 3

    private let rows = ["QWERTYUIOP", "ASDFGHJKL", "ZXCVBNM"]

    var body: some View {
        VStack(spacing: Theme.Spacing.s) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 6) {
                    if row.count < 10 { Spacer(minLength: 0) }
                    if row == rows.last, onTogglePencil != nil {
                        pencilKey
                    }
                    ForEach(Array(row), id: \.self) { letter in
                        key(for: letter)
                    }
                    if row == rows.last {
                        deleteKey
                    }
                    if row.count < 10 { Spacer(minLength: 0) }
                }
            }
        }
        // On the bed the keys run nearly edge to edge, as the system
        // keyboard's do; the bed is the margin.
        .padding(.horizontal, onBed ? 3 : Theme.Spacing.s)
        .padding(.top, onBed ? Theme.Spacing.s + 2 : Theme.Spacing.m)
        .padding(.bottom, Theme.Spacing.m)
        // On iPad the keys stop growing at a hand's width — a Q stretched to
        // an eighth of a 13" screen stops reading as a key. The outer frame
        // keeps the view full-width so a call site's background still spans.
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
        // Glyphs scale; columns can't. The pad is ten fixed columns across the
        // screen's width, so past this size a letter is wider than the cap it
        // sits in — Q and W overlapped and M was clipped — and three rows of
        // grown keys pushed the grid off the screen entirely. Height still
        // scales with `keyHeight`, up to the same cap.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .sensoryFeedback(.selection, trigger: lastKeyTick)
    }

    private func key(for letter: Character) -> some View {
        Button {
            lastKeyTick &+= 1
            onLetter(letter)
        } label: {
            Text(String(letter))
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: cappedKeyHeight)
        }
        .buttonStyle(KeyButtonStyle(onBed: onBed))
        .accessibilityLabel(String(letter))
    }

    /// Pencil (provisional entry) mode toggle. Mirrors the delete key on the
    /// other end of the bottom row; the filled accent state is the mode light.
    private var pencilKey: some View {
        Button {
            lastKeyTick &+= 1
            onTogglePencil?()
        } label: {
            Image(systemName: isPencilMode ? "pencil.circle.fill" : "pencil")
                .font(.title3)
                .frame(maxWidth: .infinity, minHeight: cappedKeyHeight)
                .foregroundStyle(isPencilMode ? Theme.accent : .primary)
        }
        .buttonStyle(KeyButtonStyle(onBed: onBed, isFunction: !isPencilMode))
        .accessibilityLabel("Pencil mode")
        .accessibilityValue(isPencilMode ? "on" : "off")
        .accessibilityAddTraits(.isToggle)
        .accessibilityHint("Letters you type are provisional until entered in pen")
    }

    private var deleteKey: some View {
        Button(role: .destructive) {
            lastKeyTick &+= 1
            onDelete()
        } label: {
            Image(systemName: "delete.left")
                .font(.title3)
                .frame(maxWidth: .infinity, minHeight: cappedKeyHeight)
        }
        .buttonStyle(KeyButtonStyle(onBed: onBed, isFunction: true))
        .accessibilityLabel("Delete")
    }
}

/// Key styling with an instant pressed state. A real keyboard key highlights the
/// moment a finger touches it (Apple's first fluid-interface rule: respond on
/// pointer-down, not on release) — `.plain` gave no visual feedback at all, so
/// only the haptic fired. `isPressed` flips on touch-down, so the darken + slight
/// depress now land on the same event as the finger, in harmony with the haptic.
private struct KeyButtonStyle: ButtonStyle {
    var onBed = false
    /// Pencil (while off) and delete: grey on the bed. Pencil turns white
    /// when on, so the lit key reads as the mode.
    var isFunction = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.primary)
            .background(
                fill(isPressed: configuration.isPressed),
                in: .rect(cornerRadius: onBed ? 6 : 8)
            )
            // The system key's lower edge: a hairline of shade that lifts the
            // key off the bed. On a slab there is no bed to lift off.
            .shadow(color: .black.opacity(onBed ? 0.28 : 0), radius: 0, y: 1)
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            // Asymmetric: the depress lands instantly (nil animation on press-in —
            // the frame the user is watching most), the release settles over a
            // short, bounce-free spring. A key is pressed 100+ times a session,
            // so the down-state must never lag.
            .animation(configuration.isPressed ? nil : .spring(duration: 0.18, bounce: 0), value: configuration.isPressed)
    }

    private func fill(isPressed: Bool) -> Color {
        if onBed {
            // Pressed, a letter takes the function grey and a function key the
            // letter face — the system keyboard's own swap.
            return isPressed == isFunction ? Theme.keyFace : Theme.keyFaceAlt
        }
        return isPressed ? Color(.systemGray3) : Color(.secondarySystemBackground)
    }
}
