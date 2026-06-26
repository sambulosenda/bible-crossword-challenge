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

    private static let size = CGSize(width: 340, height: 440)

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

            Text("Solve the daily Bible crossword")
                .font(.caption.weight(.medium))
                .foregroundStyle(ink.opacity(0.7))
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

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(gold)
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

/// Share configuration. `storeURL` is appended to the share caption once the app
/// is published — leave nil until an App Store / marketing link exists.
enum ShareConfig {
    static let storeURL: URL? = nil
}

#Preview {
    ShareCardView(
        title: "The Major Prophets",
        seconds: 154,
        streak: 12,
        verse: "Thou shalt love thy neighbour as thyself.",
        reference: "Luke 10:27"
    )
    .padding()
}
