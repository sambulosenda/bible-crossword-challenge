//
//  WhyIMadeThisView.swift
//  Bible Crossword Challenge
//
//  The maker's note, from Settings → About (2026-11-04). Plain text on the
//  page, signed: a note from the person who built the app, not marketing.
//  Kept out of onboarding and Today on purpose — day 0 is where players are
//  lost, and Today already opens on a verse.
//

import SwiftUI

struct WhyIMadeThisView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                Text("I built Bible Crossword so that a few minutes with a puzzle become a few minutes in God's Word.")
                Text("Every clue leads back to a verse. Each answer you fill in is a line of Scripture you've read, thought about and carried with you. Day by day, that adds up.")
                Text("Wherever you are in your walk with Christ, I'm glad you're here.")

                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    Text("Your word is a lamp to my feet and a light to my path.")
                        .font(.scripture(.body))
                        .lineSpacing(6)
                    Text("Psalm 119:105")
                        .font(.subheadline.weight(.semibold))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Theme.Spacing.l)
                .elevatedCard()
                .accessibilityElement(children: .combine)

                Text("Sambulo")
                    .font(.headline)
            }
            .font(.body)
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 600, alignment: .leading)
            .padding(.horizontal, Theme.Spacing.m + 4)
            .padding(.vertical, Theme.Spacing.m)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background)
        .navigationTitle("Why I made this")
        .navigationBarTitleDisplayMode(.large)
    }
}

#Preview {
    NavigationStack { WhyIMadeThisView() }
}
