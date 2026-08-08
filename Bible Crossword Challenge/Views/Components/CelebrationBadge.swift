//
//  CelebrationBadge.swift
//  Bible Crossword Challenge
//
//  The badge that crowns a celebration moment — solve, achievement, freeze.
//  One component so the three can't drift apart in hue, rim or glyph weight.
//

import SwiftUI
import Lottie

/// A tinted disc with a gold rim and a `Mark` at its centre.
///
/// The mark is drawn natively rather than baked into the Lottie: it then tracks
/// `Theme.accent`, adapts to light and dark, and — the reason this exists — the
/// Reduce Motion path is the *same* view minus the burst, so the two can never
/// be different designs. The Lottie supplies confetti only.
///
/// Symbol marks are SF Symbols because a glyph drawn as a bezier has to be
/// optically centred by hand; the symbol already is, at every weight and size.
struct CelebrationBadge: View {
    /// What sits at the centre of the disc.
    enum Mark {
        /// An SF Symbol — achievement star, freeze snowflake, a checkmark.
        case symbol(String)
        /// The solved puzzle's own grid, as rows where "." marks a block. A
        /// checkmark is the mark iOS uses for "operation succeeded" and says
        /// nothing about what was solved; the grid is the shape the player just
        /// filled, and it's a different shape every day.
        case grid([String])
    }

    let mark: Mark
    /// Bundled Lottie supplying the confetti burst. Nil draws a static badge.
    var confetti: String?
    /// Disc tint. Defaults to the app accent; freeze overrides it for cyan.
    var tint: Color = Theme.accent
    /// Diameter of the disc. Confetti overflows it and is not clipped.
    var size: CGFloat = 120

    init(mark: Mark, confetti: String? = nil, tint: Color = Theme.accent, size: CGFloat = 120) {
        self.mark = mark
        self.confetti = confetti
        self.tint = tint
        self.size = size
    }

    init(systemImage: String, confetti: String? = nil, tint: Color = Theme.accent, size: CGFloat = 120) {
        self.init(mark: .symbol(systemImage), confetti: confetti, tint: tint, size: size)
    }

    init(grid: [String], confetti: String? = nil, tint: Color = Theme.accent, size: CGFloat = 120) {
        self.init(mark: .grid(grid), confetti: confetti, tint: tint, size: size)
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var landed = false

    /// Rim scales with the disc so a 72pt freeze badge and a 120pt solve badge
    /// read as the same object at different sizes.
    private var rimWidth: CGFloat { max(2, size * 0.045) }

    /// 44% keeps the glyph clear of the rim. The old baked checkmark ran to 56%
    /// of the inner circle, which is what made it crowd the edge.
    ///
    /// A grid gets more room: a symbol is one solid shape read at a glance, while
    /// a 15×15 grid is 225 dots read as texture, and at 44% the dots collapse
    /// into a smudge. 64% still clears the rim because the grid is square and
    /// its corners, not its edges, are what approach the circle.
    private var glyphSize: CGFloat {
        switch mark {
        case .symbol: size * 0.44
        case .grid: size * 0.64
        }
    }

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

    @ViewBuilder
    private var centreMark: some View {
        switch mark {
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: glyphSize, weight: .bold))
                .foregroundStyle(.white)
        case .grid(let rows):
            // Solid white dots on the accent disc, the inverse of the muted
            // thumbnails on Today and Library — this is the one that celebrates.
            //
            GridThumbnail(grid: rows, tint: .white, gap: 0.5, cropsToContent: true)
                .frame(width: glyphSize, height: glyphSize)
        }
    }

    private var disc: some View {
        Circle()
            .fill(tint)
            .overlay {
                Circle().strokeBorder(Theme.badgeRim, lineWidth: rimWidth)
            }
            .overlay { centreMark }
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
        // A dense daily and a mini — the grid mark has to hold at both.
        CelebrationBadge(grid: [
            "...ABC...", ".DEFGHIJ.", "KLM.NOP..", ".QR.STUV.",
            "WXY.Z.AB.", ".CDEFGH..", "..IJK.LM.", ".NOPQRST.", "...UVW..."
        ])
        CelebrationBadge(grid: ["ABCDE", "F.G.H", "IJKLM", "N.O.P", "QRSTU"])
        CelebrationBadge(systemImage: "star.fill", size: 112)
        CelebrationBadge(systemImage: "snowflake", tint: .cyan, size: 72)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Theme.background)
}
