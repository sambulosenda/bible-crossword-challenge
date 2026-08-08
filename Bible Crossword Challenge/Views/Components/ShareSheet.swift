//
//  ShareSheet.swift
//  Bible Crossword Challenge
//
//  A thin `UIActivityViewController` wrapper for imperative sharing. `ShareLink`
//  covers the declarative cases; challenge links can't use it because the URL is
//  built after an optional name prompt, and because history should only record a
//  send that actually happened.
//

import SwiftUI
import UIKit

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    /// Called with `true` only when the player picked a destination and the
    /// share went through — cancelling reports `false`. Callers use this to
    /// avoid writing history for a challenge nobody ever received.
    var onComplete: (Bool) -> Void = { _ in }

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        let onComplete = onComplete
        controller.completionWithItemsHandler = { _, completed, _, _ in
            onComplete(completed)
        }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
