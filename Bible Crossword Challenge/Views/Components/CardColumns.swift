//
//  CardColumns.swift
//  Bible Crossword Challenge
//
//  A tab's cards in one readable column — or two side by side when the
//  window is a wide regular one: iPhone Duo open in landscape, an iPad on
//  its side. One 560pt column in the middle of a 950pt window left a third
//  of the width blank each side, with the fold running through it. Two
//  columns use the width, and the seam between them is where a partial
//  fold wants it.
//

import SwiftUI

struct CardColumns<Lead: View, More: View>: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var containerSize: CGSize = .zero

    /// The readable width of a column.
    var maxWidth: CGFloat = 560
    /// What the tab is for: first in one column, the left of two.
    @ViewBuilder let lead: () -> Lead
    /// The rest, in the order it already had.
    @ViewBuilder let more: () -> More

    var body: some View {
        Group {
            if twoColumns {
                if #available(iOS 27.1, *) {
                    // The system's split arrangement moves the seam off a
                    // partial fold; horizontal only, because two stacked
                    // scroll views would be the phone layout done worse.
                    ArrangementView {
                        column { lead() }
                    } secondary: {
                        column { more() }
                    }
                    .arrangementViewStyle(.split.axes(.horizontal))
                } else {
                    HStack(spacing: 0) {
                        column { lead() }
                        column { more() }
                    }
                }
            } else {
                column {
                    lead()
                    more()
                }
            }
        }
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { size in
            containerSize = size
        }
    }

    /// Regular width and wider than tall. Size class alone would split an
    /// iPad in portrait, which has the height for one column and not the
    /// width for two.
    private var twoColumns: Bool {
        horizontalSizeClass == .regular && containerSize.width > containerSize.height
    }

    /// One scrolling column of cards at the readable width.
    private func column<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.l, content: content)
                .padding(Theme.Spacing.m)
                .frame(maxWidth: maxWidth)
                .modifier(ColumnWidth(pinToContainer: !twoColumns))
        }
    }
}

/// How a column's content takes its width.
///
/// Alone, the scroll content's width is pinned to the scroll container
/// rather than left to the column's own measurement: left to itself the
/// column came out two-thirds of a point wider than the screen (fractional
/// layout out of the readable-width chain), which made the vertical
/// scroller horizontally scrollable — the whole page could be dragged and
/// bounced left and right.
///
/// In a split, `containerRelativeFrame` resolves to the window, not the
/// pane, and every column came out 560pt wide over the pane's edge — the
/// left ran under the right, the right under the rail. There the column
/// simply fills the pane it was given.
private struct ColumnWidth: ViewModifier {
    let pinToContainer: Bool

    func body(content: Content) -> some View {
        if pinToContainer {
            content.containerRelativeFrame(.horizontal)
        } else {
            content.frame(maxWidth: .infinity)
        }
    }
}
