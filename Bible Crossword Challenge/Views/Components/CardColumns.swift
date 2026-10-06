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

    /// The readable width of a column.
    var maxWidth: CGFloat = 560
    /// How the cards line up inside a column.
    var alignment: HorizontalAlignment = .center
    /// What the tab is for: first in one column, the left of two.
    @ViewBuilder let lead: () -> Lead
    /// The rest, in the order it already had.
    @ViewBuilder let more: () -> More

    var body: some View {
        // Measured on the way in rather than through state: a tab root that
        // was first laid out closed kept its stale size after the device
        // opened, and stayed one column. A GeometryReader has no state to
        // go stale, and fills its container, which is what the columns do.
        GeometryReader { proxy in
            let twoColumns = Self.twoColumns(horizontalSizeClass, proxy.size)
            if twoColumns {
                if #available(iOS 27.1, *) {
                    // The system's split arrangement moves the seam off a
                    // partial fold; horizontal only, because two stacked
                    // scroll views would be the phone layout done worse.
                    ArrangementView {
                        column(width: nil) { lead() }
                    } secondary: {
                        column(width: nil) { more() }
                    }
                    .arrangementViewStyle(.split.axes(.horizontal))
                    .environment(\.inCardColumnSplit, true)
                } else {
                    HStack(spacing: 0) {
                        column(width: nil) { lead() }
                        column(width: nil) { more() }
                    }
                    .environment(\.inCardColumnSplit, true)
                }
            } else {
                column(width: proxy.size.width) {
                    lead()
                    more()
                }
            }
        }
    }

    /// Regular width and wider than tall. Size class alone would split an
    /// iPad in portrait, which has the height for one column and not the
    /// width for two.
    private static func twoColumns(_ sizeClass: UserInterfaceSizeClass?, _ size: CGSize) -> Bool {
        sizeClass == .regular && size.width > size.height
    }

    /// One scrolling column of cards at the readable width. `width` is the
    /// measured window width when the column stands alone, `nil` in a split.
    private func column<Content: View>(width: CGFloat?, @ViewBuilder _ content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: alignment, spacing: Theme.Spacing.l, content: content)
                .padding(Theme.Spacing.m)
                .frame(maxWidth: maxWidth)
                .modifier(ColumnWidth(width: width))
        }
    }
}

/// How a column's content takes its width.
///
/// Alone, the scroll content's width is pinned to the width the
/// GeometryReader measured rather than left to the column's own
/// measurement: left to itself the column came out two-thirds of a point
/// wider than the screen (fractional layout out of the readable-width
/// chain), which made the vertical scroller horizontally scrollable — the
/// whole page could be dragged and bounced left and right. Not
/// `containerRelativeFrame`: its container is the scroll view, which sizes
/// to this content, so after iPhone Duo folds the column held the open
/// width (867pt on a 382pt screen) — the cards sat off-centre and ran
/// under the rail.
///
/// In a split, `containerRelativeFrame` resolves to the window, not the
/// pane, and every column came out 560pt wide over the pane's edge — the
/// left ran under the right, the right under the rail. There the column
/// simply fills the pane it was given.
private struct ColumnWidth: ViewModifier {
    let width: CGFloat?

    func body(content: Content) -> some View {
        if let width {
            content.frame(width: width)
        } else {
            content.frame(maxWidth: .infinity)
        }
    }
}

extension EnvironmentValues {
    /// True inside one of `CardColumns`' two side-by-side columns, so a card
    /// can size itself to half a window rather than a phone.
    @Entry var inCardColumnSplit: Bool = false
}
