//
//  DeferredChallenge.swift
//  Bible Crossword Challenge
//
//  Carries a friend's challenge across an App Store install.
//
//  iOS has no deferred deep linking. A friend without the app taps the
//  challenge link, lands on the web page, installs, and the app opens knowing
//  nothing — the invite that brought them in is gone, and they get the same
//  onboarding as a stranger. The web landing page copies the link to the
//  clipboard when its App Store button is tapped; this reads it back exactly
//  once, at the end of the first onboarding.
//
//  Two steps, because reading the clipboard shows the system "pasted from
//  Safari" banner and a bare read on every fresh install would show it to
//  people who never held a link. `detectPatterns` classifies the contents
//  without exposing them and without a banner, so the read only happens when
//  iOS itself says there is probably a web URL there. A match clears the
//  clipboard so it cannot fire twice; anything else is left exactly as found.
//

import UIKit

enum DeferredChallenge {
    /// Prompt-free: does the clipboard probably hold a web URL?
    @MainActor
    static func pasteboardLooksLikeLink() async -> Bool {
        let board = UIPasteboard.general
        // `hasURLs`/`hasStrings` are metadata, no banner. Skip the classifier
        // entirely on an empty or image-only clipboard.
        guard board.hasURLs || board.hasStrings else { return false }
        // UIKit exposes this with a completion handler only (no async twin in
        // the iOS 26 SDK), so it's bridged here.
        let webURL: PartialKeyPath<UIPasteboard.DetectedValues> = \UIPasteboard.DetectedValues.probableWebURL
        // Reduced to a Bool inside the callback: UIKit calls it off the main
        // actor, and the key-path set isn't Sendable.
        return await withCheckedContinuation { continuation in
            board.detectPatterns(for: [webURL]) { result in
                let found = (try? result.get()) ?? []
                continuation.resume(returning: found.contains(webURL))
            }
        }
    }

    /// Reads the clipboard through `detectValues`, which is what puts up the
    /// system paste prompt, and returns the challenge link if that is what it
    /// holds. Asynchronous because the prompt is: a plain `UIPasteboard.string`
    /// read at that moment comes back empty while the sheet is up, which is
    /// how the first version of this quietly fell through to the Mini.
    @MainActor
    static func claimPastedLink() async -> URL? {
        let board = UIPasteboard.general
        let webURL: PartialKeyPath<UIPasteboard.DetectedValues> = \UIPasteboard.DetectedValues.probableWebURL
        // The string is pulled out inside the callback, for the same reason.
        let detected: String = await withCheckedContinuation { continuation in
            board.detectValues(for: [webURL]) { result in
                continuation.resume(returning: (try? result.get())?.probableWebURL ?? "")
            }
        }
        let raw = detected.trimmingCharacters(in: .whitespacesAndNewlines)
        #if DEBUG
        print("📋 DeferredChallenge: clipboard URL = \(raw.isEmpty ? "none" : raw)")
        #endif
        guard !raw.isEmpty,
              let url = URL(string: raw),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              ChallengeService.isChallengeLink(url, components: components)
        else { return nil }
        board.items = []
        return url
    }
}
