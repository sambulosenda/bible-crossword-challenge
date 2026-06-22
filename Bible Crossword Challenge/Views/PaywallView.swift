//
//  PaywallView.swift
//  Bible Crossword Challenge
//
//  Premium upgrade screen. Purchase/restore go through StoreService (StoreKit 2).
//

import SwiftUI

struct PaywallView: View {
    @Environment(StoreService.self) private var store
    @Environment(\.analytics) private var analytics
    @Environment(\.dismiss) private var dismiss

    private let benefits: [(symbol: String, title: String, detail: String)] = [
        ("nosign", "Remove Ads", "Enjoy a distraction-free experience"),
        ("lightbulb.fill", "Unlimited Hints", "Never get stuck on a tricky clue"),
        ("archivebox.fill", "Puzzle Archive", "Replay every past daily puzzle"),
        ("gift.fill", "Future Packs", "Get upcoming puzzle packs included"),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.l) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(.yellow)
                        .padding(.top, Theme.Spacing.xl)

                    Text("Bible Crossword Premium")
                        .font(.largeTitle.bold())
                        .multilineTextAlignment(.center)

                    Text("One-time purchase · \(store.displayPrice)")
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    VStack(spacing: Theme.Spacing.m) {
                        ForEach(benefits, id: \.title) { benefit in
                            HStack(spacing: Theme.Spacing.m) {
                                Image(systemName: benefit.symbol)
                                    .font(.title3)
                                    .foregroundStyle(Theme.accent)
                                    .frame(width: 32)
                                VStack(alignment: .leading) {
                                    Text(benefit.title).font(.headline)
                                    Text(benefit.detail).font(.subheadline).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(Theme.Spacing.l)
                    .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: Theme.cornerRadius))

                    if store.isPremium {
                        Label("You're Premium — thank you!", systemImage: "checkmark.seal.fill")
                            .font(.headline)
                            .foregroundStyle(.green)
                            .padding(.top, Theme.Spacing.m)
                    } else {
                        purchaseButtons
                    }
                }
                .padding(Theme.Spacing.l)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Premium")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private var purchaseButtons: some View {
        VStack(spacing: Theme.Spacing.m) {
            Button {
                Task {
                    if await store.purchase() { analytics.log(.premiumPurchased) }
                }
            } label: {
                Group {
                    if store.purchaseInFlight {
                        ProgressView()
                    } else {
                        Text("Unlock for \(store.displayPrice)")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.extraLarge)
            .disabled(store.purchaseInFlight || store.product == nil)

            Button("Restore Purchase") {
                Task { await store.restore() }
            }
            .font(.subheadline)
            .disabled(store.purchaseInFlight)

            Text("One-time purchase. Restores on your other devices.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
    }
}
