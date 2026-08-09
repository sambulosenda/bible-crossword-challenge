//
//  SeasonBadge.swift
//  Bible Crossword Challenge
//
//  "4 days left" on a seasonal pack that is running out. A seasonal pack's whole
//  argument is that it won't be here later, and until now the app never said so
//  — the window lived in packs.json and expressed itself only by the pack
//  vanishing one morning.
//

import SwiftUI

struct SeasonBadge: View {
    /// Whole days left including today; `0` is the last day.
    let daysRemaining: Int

    /// How close to the end the badge starts appearing. A countdown on day one
    /// of a six-week season isn't urgency, it's furniture — and it would sit on
    /// the Lent pack for a month and a half being ignored.
    static let noticeDays = 14

    /// Days left when the pack is close enough to its last day to say so, else
    /// `nil` (evergreen, out of season, or still early in the window).
    static func daysRemaining(for pack: PuzzlePack, on date: Date = SeasonClock.now) -> Int? {
        guard let days = pack.daysRemaining(on: date), (0...noticeDays).contains(days) else {
            return nil
        }
        return days
    }

    /// "Last day" / "1 day left" / "9 days left". Shared with the card
    /// accessibility labels, which announce the same fact in the same words.
    static func text(daysRemaining days: Int) -> String {
        switch days {
        case 0: "Last day"
        case 1: "1 day left"
        default: "\(days) days left"
        }
    }

    /// The final stretch, where the badge earns a warmer colour. Amber, not red:
    /// nothing is wrong, something is ending.
    private var isClosing: Bool { daysRemaining <= 3 }

    private var tint: Color { isClosing ? .orange : .secondary }

    var body: some View {
        Label(Self.text(daysRemaining: daysRemaining), systemImage: "clock")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            // Three words in a capsule wrap to two lines the moment the row is
            // tight (a long pack title, a crown, and "11 days left"). The badge
            // keeps its natural width and the title, which has room to wrap,
            // gives way instead.
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, Theme.Spacing.s)
            .padding(.vertical, 3)
            .background(tint.opacity(0.12), in: .capsule)
    }
}

/// "New" on a collection that shipped in the last fortnight.
///
/// The cadence this marks is only worth keeping if a returning player can see
/// it without reading the App Store release notes — which is the whole point of
/// promising "and every new one" on the paywall.
struct NewPackBadge: View {
    var body: some View {
        Text("New")
            .font(.caption2.weight(.bold))
            .textCase(.uppercase)
            .foregroundStyle(Theme.accent)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, Theme.Spacing.s)
            .padding(.vertical, 3)
            .background(Theme.accent.opacity(0.12), in: .capsule)
    }
}

/// Which badge a pack row shows, when more than one could apply.
///
/// A pack can be both new and closing — a seasonal collection first shipped
/// part-way through its own window is exactly that. Two capsules beside a title
/// and a crown is more than the row can hold, so they are ranked rather than
/// stacked: **closing wins**. "New" is an invitation and will still be true
/// tomorrow; "Last day" stops being actionable the moment it lapses.
enum PackBadge {
    case closing(days: Int)
    case new

    static func forPack(_ pack: PuzzlePack, on date: Date = SeasonClock.now) -> PackBadge? {
        if let days = SeasonBadge.daysRemaining(for: pack, on: date) { return .closing(days: days) }
        if pack.isNew(on: date) { return .new }
        return nil
    }

    /// The spoken form, so card accessibility labels say what the badge says.
    var label: String {
        switch self {
        case let .closing(days): SeasonBadge.text(daysRemaining: days)
        case .new: "New"
        }
    }
}

extension PackBadge: View {
    var body: some View {
        switch self {
        case let .closing(days): SeasonBadge(daysRemaining: days)
        case .new: NewPackBadge()
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: Theme.Spacing.m) {
        SeasonBadge(daysRemaining: 12)
        SeasonBadge(daysRemaining: 3)
        SeasonBadge(daysRemaining: 1)
        SeasonBadge(daysRemaining: 0)
        NewPackBadge()
    }
    .padding()
    .background(Theme.background)
}
