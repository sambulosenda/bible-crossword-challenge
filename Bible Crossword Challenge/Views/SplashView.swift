//
//  SplashView.swift
//  Bible Crossword Challenge
//
//  Animated launch splash shown once per cold start. Its first frame matches the
//  static LaunchScreen.storyboard (same brand blue), so the OS → app handoff is
//  seamless; the mark animates in, then the splash fades to reveal the app.
//

import SwiftUI

struct SplashView: View {
    /// Called after the exit fade completes so the host can remove the splash.
    var onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false
    @State private var leaving = false

    // Brand blues — the gradient's centre matches LaunchScreen.storyboard's fill.
    private static let top = Color(red: 0.29, green: 0.47, blue: 0.96)
    private static let bottom = Color(red: 0.13, green: 0.25, blue: 0.78)

    var body: some View {
        ZStack {
            LinearGradient(colors: [Self.top, Self.bottom],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()

            VStack(spacing: Theme.Spacing.l) {
                mark
                Text("Bible Crossword")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
            }
            .scaleEffect(reduceMotion ? 1 : (revealed ? 1 : 0.82))
            .opacity(revealed ? 1 : 0)
        }
        .opacity(leaving ? 0 : 1)
        .task { await run() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Bible Crossword")
    }

    /// White book with a glowing gold cross, echoing the app icon.
    private var mark: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(.white.opacity(0.16))
                .frame(width: 120, height: 120)
            Image(systemName: "book.closed.fill")
                .font(.system(size: 54, weight: .semibold))
                .foregroundStyle(.white)
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "cross.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.yellow)
                        .shadow(color: .yellow.opacity(0.7), radius: 8)
                        .offset(x: 11, y: -9)
                }
        }
    }

    private func run() async {
        withAnimation(reduceMotion
                      ? .easeIn(duration: 0.25)
                      : .spring(response: 0.55, dampingFraction: 0.7)) {
            revealed = true
        }
        try? await Task.sleep(for: .seconds(reduceMotion ? 0.7 : 1.05))
        withAnimation(.easeOut(duration: 0.35)) { leaving = true }
        try? await Task.sleep(for: .seconds(0.35))
        onFinished()
    }
}

#Preview {
    SplashView(onFinished: {})
}
