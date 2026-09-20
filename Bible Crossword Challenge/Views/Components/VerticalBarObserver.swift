//
//  VerticalBarObserver.swift
//  Bible Crossword Challenge
//
//  Tells a screen when the system has put its bars on a side rail (iPhone Duo
//  closed, or open in landscape). A custom toolbar view is never presented
//  vertically — it holds a second, horizontal bar open above the rail — so
//  screens with custom toolbar views swap them for a Label the rail can draw
//  as an icon, and move anything that can't be a Label onto the content.
//

import SwiftUI

extension View {
    /// Keeps `isVertical` in step with the toolbar's axis. False before
    /// iOS 27.1, where bars are always horizontal.
    func observeVerticalBars(_ isVertical: Binding<Bool>) -> some View {
        background {
            if #available(iOS 27.1, *) {
                Color.clear.modifier(VerticalBarObserver(isVertical: isVertical))
            }
        }
    }
}

/// Mirrors `toolbarVerticalEdge` into state a toolbar builder can read.
/// A modifier rather than a property on the screen: the environment key is
/// iOS 27.1, and a stored `@Environment` cannot be availability-gated.
@available(iOS 27.1, *)
private struct VerticalBarObserver: ViewModifier {
    @Environment(\.toolbarVerticalEdge) private var edge
    @Binding var isVertical: Bool

    func body(content: Content) -> some View {
        content.onChange(of: edge != nil, initial: true) { _, vertical in
            isVertical = vertical
        }
    }
}
