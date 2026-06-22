//
//  OnboardingView.swift
//  Bible Crossword Challenge
//
//  First-run experience: value props, name capture, and a soft premium pitch.
//  Shown once (gated by @AppStorage in RootView). The free daily puzzle is
//  always available — the premium page is a dismissible upsell.
//
//  Each page's content animates in (staggered fade + rise) when it becomes
//  active, hero symbols react with a bounce, and all motion respects the
//  Reduce Motion accessibility setting.
//

import SwiftUI

struct OnboardingView: View {
    @Bindable var profile: PlayerProfile
    var onFinish: () -> Void

    @Environment(StoreService.self) private var store
    @Environment(\.analytics) private var analytics
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var page = 0
    @FocusState private var nameFocused: Bool

    private let lastPage = 3

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                welcomePage.tag(0)
                featuresPage.tag(1)
                namePage.tag(2)
                premiumPage.tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut, value: page)

            controls
        }
        .background(
            LinearGradient(
                colors: [Color(.systemBackground), Theme.accent.opacity(0.10)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .sensoryFeedback(.selection, trigger: page)
    }

    // MARK: - Pages

    private var welcomePage: some View {
        let active = page == 0
        return VStack(spacing: Theme.Spacing.l) {
            Spacer()
            heroIcon("book.pages", tint: Theme.accent, active: active)
            VStack(spacing: Theme.Spacing.m) {
                Text("Bible Crossword\nChallenge")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                    .entrance(active: active, delay: 0.10, reduceMotion: reduceMotion)
                Text("Learn and remember Scripture — one puzzle a day.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .entrance(active: active, delay: 0.18, reduceMotion: reduceMotion)
            }
            Spacer()
            Spacer()
        }
        .padding(Theme.Spacing.xl)
    }

    private var featuresPage: some View {
        let active = page == 1
        let rows: [(String, String, String, Color)] = [
            ("calendar", "Daily Puzzles", "A fresh Bible crossword every day.", .blue),
            ("flame.fill", "Build a Streak", "Play each day and watch your streak grow.", .orange),
            ("book.closed.fill", "Discover Verses", "Unlock a Scripture verse with every puzzle.", .purple),
            ("trophy.fill", "Earn Achievements", "From Bible Beginner to Apostle.", .yellow),
        ]
        return VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            Spacer()
            Text("A daily habit\nfor your faith")
                .font(.largeTitle.bold())
                .entrance(active: active, delay: 0.05, reduceMotion: reduceMotion)
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                ForEach(Array(rows.enumerated()), id: \.offset) { i, r in
                    feature(r.0, r.1, r.2, r.3)
                        .entrance(active: active, delay: 0.12 + Double(i) * 0.08, reduceMotion: reduceMotion)
                }
            }
            Spacer()
            Spacer()
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var namePage: some View {
        let active = page == 2
        return VStack(spacing: Theme.Spacing.l) {
            Spacer()
            heroIcon("person.crop.circle", tint: Theme.accent, active: active)
            Text("What should we\ncall you?")
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
                .entrance(active: active, delay: 0.10, reduceMotion: reduceMotion)
            TextField("Your name", text: $profile.username)
                .font(.title2)
                .multilineTextAlignment(.center)
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
                .focused($nameFocused)
                .padding(Theme.Spacing.m)
                .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: Theme.cornerRadius))
                .padding(.horizontal, Theme.Spacing.l)
                .onSubmit { nameFocused = false }
                .entrance(active: active, delay: 0.18, reduceMotion: reduceMotion)
            Text("You can change this any time in your profile.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .entrance(active: active, delay: 0.24, reduceMotion: reduceMotion)
            Spacer()
            Spacer()
        }
        .padding(Theme.Spacing.xl)
    }

    private var premiumPage: some View {
        let active = page == 3
        return VStack(spacing: Theme.Spacing.l) {
            Spacer()
            heroIcon("crown.fill", tint: .yellow, active: active)
            Text("Go Premium")
                .font(.largeTitle.bold())
                .entrance(active: active, delay: 0.10, reduceMotion: reduceMotion)
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                benefit("Remove all ads")
                benefit("Unlimited hints")
                benefit("Full puzzle archive")
                benefit("Future puzzle packs included")
            }
            .padding(Theme.Spacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: Theme.cornerRadius))
            .padding(.horizontal, Theme.Spacing.s)
            .entrance(active: active, delay: 0.18, reduceMotion: reduceMotion)
            Spacer()
        }
        .padding(Theme.Spacing.xl)
    }

    // MARK: - Building blocks

    private func heroIcon(_ name: String, tint: Color, active: Bool) -> some View {
        Image(systemName: name)
            .font(.system(size: 88))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(tint)
            .padding(Theme.Spacing.l)
            .background(tint.opacity(0.12), in: .circle)
            .scaleEffect(active || reduceMotion ? 1 : 0.7)
            .opacity(active ? 1 : 0)
            .animation(reduceMotion ? .easeOut(duration: 0.3) : .spring(duration: 0.55, bounce: 0.45), value: active)
            .symbolEffect(.bounce, value: active)
    }

    private func feature(_ icon: String, _ title: String, _ detail: String, _ tint: Color) -> some View {
        HStack(spacing: Theme.Spacing.m) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .background(tint.opacity(0.15), in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private func benefit(_ text: String) -> some View {
        Label(text, systemImage: "checkmark.circle.fill")
            .font(.body)
            .foregroundStyle(.primary)
            .labelStyle(.titleAndIcon)
            .tint(.green)
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(spacing: Theme.Spacing.m) {
            HStack(spacing: Theme.Spacing.s) {
                ForEach(0...lastPage, id: \.self) { i in
                    Capsule()
                        .fill(i == page ? Theme.accent : Color(.tertiaryLabel))
                        .frame(width: i == page ? 22 : 8, height: 8)
                        .animation(.spring(duration: 0.3), value: page)
                }
            }
            .accessibilityHidden(true)

            if page < lastPage {
                Button {
                    withAnimation { page += 1 }
                } label: {
                    Text("Continue").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else {
                Button {
                    Task {
                        if await store.purchase() { analytics.log(.premiumPurchased) }
                        finish()
                    }
                } label: {
                    Group {
                        if store.purchaseInFlight {
                            ProgressView()
                        } else {
                            Text("Unlock Premium · \(store.displayPrice)")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(store.purchaseInFlight)

                Button("Continue with the free daily puzzle") {
                    finish()
                }
                .font(.subheadline)
            }
        }
        .padding(Theme.Spacing.l)
        .animation(.easeInOut, value: page)
    }

    private func finish() {
        nameFocused = false
        if profile.username.trimmingCharacters(in: .whitespaces).isEmpty {
            profile.username = "Friend"
        }
        onFinish()
    }
}

// MARK: - Staggered entrance

private struct Entrance: ViewModifier {
    let active: Bool
    let delay: Double
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .opacity(active ? 1 : 0)
            .offset(y: reduceMotion ? 0 : (active ? 0 : 18))
            .animation(
                reduceMotion
                    ? .easeOut(duration: 0.25)
                    : .spring(duration: 0.55).delay(active ? delay : 0),
                value: active
            )
    }
}

private extension View {
    func entrance(active: Bool, delay: Double = 0, reduceMotion: Bool) -> some View {
        modifier(Entrance(active: active, delay: delay, reduceMotion: reduceMotion))
    }
}
