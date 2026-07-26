//
//  CelebrationBadge.swift
//  Bible Crossword Challenge
//
//  The badge that crowns a celebration moment — solve, achievement, freeze.
//  One component so the three can't drift apart in hue, rim or glyph weight.
//

import SwiftUI
import Lottie

/// A tinted disc with a gold rim and an SF Symbol at its centre.
///
/// The mark is drawn natively rather than baked into the Lottie: it then tracks
/// `Theme.accent`, adapts to light and dark, and — the reason this exists — the
/// Reduce Motion path is the *same* view minus the burst, so the two can never
/// be different designs. The Lottie supplies confetti only.
///
/// The glyph is an SF Symbol because a checkmark drawn as a bezier has to be
/// optically centred by hand; the symbol already is, at every weight and size.
struct CelebrationBadge: View {
    /// SF Symbol drawn at the centre of the disc.
    let systemImage: String
    /// Bundled Lottie supplying the confetti burst. Nil draws a static badge.
    var confetti: String?
    /// Disc tint. Defaults to the app accent; freeze overrides it for cyan.
    var tint: Color = Theme.accent
    /// Diameter of the disc. Confetti overflows it and is not clipped.
    var size: CGFloat = 120

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var landed = false

    /// Rim scales with the disc so a 72pt freeze badge and a 120pt solve badge
    /// read as the same object at different sizes.
    private var rimWidth: CGFloat { max(2, size * 0.045) }

    /// 44% keeps the glyph clear of the rim. The old baked checkmark ran to 56%
    /// of the inner circle, which is what made it crowd the edge.
    private var glyphSize: CGFloat { size * 0.44 }

    /// Confetti is authored to fill ~30% of its canvas, so the burst needs a
    /// box well over the disc to have anywhere to fly.
    private var burstSize: CGFloat { size * 2.5 }

    var body: some View {
        disc
            .background(alignment: .center) {
                if let confetti, !reduceMotion {
                    LottieView(animation: .named(confetti))
                        .configure { $0.contentMode = .scaleAspectFit }
                        .playing(loopMode: .playOnce)
                        .frame(width: burstSize, height: burstSize)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: size, height: size)
            // Decorative: the headline and body text next to it carry the news.
            .accessibilityHidden(true)
            .onAppear { landed = true }
    }

    private var disc: some View {
        Circle()
            .fill(tint)
            .overlay {
                Circle().strokeBorder(Theme.badgeRim, lineWidth: rimWidth)
            }
            .overlay {
                Image(systemName: systemImage)
                    .font(.system(size: glyphSize, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: size, height: size)
            .scaleEffect(landed ? 1 : 0.6)
            .opacity(landed ? 1 : 0)
            // Damping 0.62 overshoots ~12%, the same pop the baked badge had,
            // but interruptible and driven by the system's clock.
            .animation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.62),
                       value: landed)
    }
}

#Preview("Badges") {
    VStack(spacing: 40) {
        CelebrationBadge(systemImage: "checkmark")
        CelebrationBadge(systemImage: "star.fill", size: 112)
        CelebrationBadge(systemImage: "snowflake", tint: .cyan, size: 72)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Theme.background)
}
