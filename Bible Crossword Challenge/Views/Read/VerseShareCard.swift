//
//  VerseShareCard.swift
//  Bible Crossword Challenge
//
//  A verse as a shareable image, from the reader's long-press. The
//  completion screen's `ShareCardView` is a scorecard — time, streak, grid —
//  and none of that belongs on a verse someone wants to send to a friend.
//  Same canvas and palette, so the two read as one app.
//

import SwiftUI

struct VerseShareCard: View {
    let verse: String
    let reference: String

    private static let size = CGSize(width: 340, height: 490)
    private let ink = Color.white
    private let gold = Color(red: 0.99, green: 0.82, blue: 0.36)
    private let cream = Color(red: 0.94, green: 0.93, blue: 0.88)

    var body: some View {
        VStack(spacing: 24) {
            Text("BIBLE CROSSWORD")
                .font(.caption.weight(.bold))
                .tracking(2)
                .foregroundStyle(ink.opacity(0.85))

            Spacer(minLength: 0)

            VStack(spacing: 14) {
                Text("“\(verse)”")
                    .font(.system(size: 22, design: .serif))
                    .foregroundStyle(cream)
                    .multilineTextAlignment(.center)
                    .lineSpacing(5)
                    .lineLimit(10)
                    .minimumScaleFactor(0.6)
                Text(reference)
                    .font(.headline)
                    .foregroundStyle(gold)
            }

            Spacer(minLength: 0)

            Text("Read the Bible, one clue at a time")
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
}

#Preview {
    VerseShareCard(
        verse: "For God so loved the world that He gave His one and only Son, that everyone who believes in Him shall not perish but have eternal life.",
        reference: "John 3:16"
    )
}
