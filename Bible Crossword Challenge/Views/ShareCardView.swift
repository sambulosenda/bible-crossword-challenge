//
//  ShareCardView.swift
//  Bible Crossword Challenge
//
//  A fixed-size, spoiler-free result card rendered to an image for sharing from
//  the completion screen. It uses an explicit palette (no scheme-dependent
//  system colors) so the exported PNG looks identical regardless of the user's
//  light/dark setting, and fixed point sizes (not Dynamic-Type scaled) so the
//  layout is stable when rasterised.
//

import SwiftUI

struct ShareCardView: View {
    let title: String
    let seconds: Int
    let streak: Int
    let verse: String
    let reference: String
    /// The puzzle's grid rows. Cell positions only — no letters — so this stays
    /// spoiler-free while making every shared card look like its own puzzle.
    var grid: [String] = []

    /// Taller than it was: the grid mark needs ~50pt that the old 440 didn't
    /// have, and taking it from the content squeezed the verse down to two lines
    /// and an ellipsis. The verse is the reason anyone shares this card, so the
    /// card grew instead.
    private static let size = CGSize(width: 340, height: 490)

    // Fixed palette — independent of the user's color scheme.
    private let ink = Color.white
    private let gold = Color(red: 0.99, green: 0.82, blue: 0.36)
    private let cream = Color(red: 0.94, green: 0.93, blue: 0.88)

    var body: some View {
        VStack(spacing: 20) {
            header

            Text(title)
                .font(.system(size: 26, weight: .bold, design: .serif))
                .foregroundStyle(ink)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.7)

            HStack(spacing: 14) {
                stat(value: TimeFormat.clock(seconds), label: "TIME", symbol: "timer")
                stat(value: "\(streak)", label: "DAY STREAK", symbol: "flame.fill")
            }

            verseBlock

            Spacer(minLength: 0)

            VStack(spacing: 4) {
                Text("Solve the daily Bible crossword")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(ink.opacity(0.7))
                Text(ShareConfig.siteName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(gold.opacity(0.9))
            }
        }
        .padding(28)
        .frame(width: Self.size.width, height: Self.size.height)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.11, green: 0.13, blue: 0.34),
                    Color(red: 0.23, green: 0.27, blue: 0.60),
                ],
                startPoint: .top, endPoint: .bottom
            )
        )
    }

    /// The puzzle's own grid over the wordmark, in place of the seal-and-tick
    /// lockup this used to carry.
    ///
    /// A tick beside a brand name is the mark for "operation succeeded" and says
    /// nothing about what was solved; every card looked the same whichever
    /// puzzle produced it. The grid makes each shared image its own puzzle, and
    /// it stays spoiler-free because `GridThumbnail` draws cell positions only,
    /// never letters.
    ///
    /// 56pt because this mark has to survive the one journey that matters — a
    /// screenshot in someone else's chat thread. At the ~22pt the old lockup
    /// icon occupied, a 15×15 grid collapses into a smudge.
    private var header: some View {
        VStack(spacing: 10) {
            GridThumbnail(grid: grid, tint: gold, gap: 0.5, cropsToContent: true)
                .frame(width: 56, height: 56)
            Text("BIBLE CROSSWORD")
                .font(.caption.weight(.bold))
                .tracking(2)
                .foregroundStyle(ink.opacity(0.85))
        }
    }

    private var verseBlock: some View {
        VStack(spacing: 8) {
            Text("“\(verse)”")
                .font(.system(size: 16, design: .serif)).italic()
                .foregroundStyle(cream)
                .multilineTextAlignment(.center)
                .lineLimit(4)
                .minimumScaleFactor(0.7)
            Text(reference)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(gold)
        }
        .padding(.horizontal, 8)
    }

    private func stat(value: String, label: String, symbol: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(gold)
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(ink)
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .tracking(1)
                .foregroundStyle(ink.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color.white.opacity(0.10), in: .rect(cornerRadius: 16))
    }
}

/// Share configuration. Every share carries a link so a recipient has a
/// tappable path to the app.
///
/// The link is the site's `/go/` page, not the App Store directly: `/go/`
/// turns `s=` into the App Store campaign token, so installs from shares
/// show in App Store Connect → Acquisition → Campaigns by kind, and it tells
/// an Android or desktop recipient the app is iOS-only instead of dropping
/// them on a store page they can't use. Shares were the raw store URL until
/// 2.9 and were therefore invisible as an acquisition channel.
enum ShareConfig {
    /// Shown on the card images themselves — a picture can't carry a token,
    /// but it can carry somewhere to type.
    static let siteName = "biblecrosswordchallenge.com"

    /// `kind` becomes the campaign token: `share_card` for the completion
    /// scorecard, `share_verse` for a verse from the reader.
    static func storeURL(kind: String) -> URL? {
        URL(string: "https://biblecrosswordchallenge.com/go/?s=\(kind)")
    }
}

#Preview {
    ShareCardView(
        title: "The Major Prophets",
        seconds: 154,
        streak: 12,
        verse: "Thou shalt love thy neighbour as thyself.",
        reference: "Luke 10:27",
        grid: [
            "...ABC...", ".DEFGHIJ.", "KLM.NOP..", ".QR.STUV.",
            "WXY.Z.AB.", ".CDEFGH..", "..IJK.LM.", ".NOPQRST.", "...UVW..."
        ]
    )
    .padding()
}
