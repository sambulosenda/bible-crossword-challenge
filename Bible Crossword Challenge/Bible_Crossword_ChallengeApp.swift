//
//  Bible_Crossword_ChallengeApp.swift
//  Bible Crossword Challenge
//
//  Created by Sambulo Senda on 21/06/2026.
//

import SwiftUI
import SwiftData
import FirebaseCore

@main
struct Bible_Crossword_ChallengeApp: App {
    @State private var store = StoreService()
    @State private var showSplash = true
    @AppStorage("appTheme") private var appTheme: AppTheme = .system
    private let container: ModelContainer

    init() {
        FirebaseApp.configure()
        do {
            container = try ModelContainer(for: PlayerProfile.self, PuzzleRecord.self)
        } catch {
            fatalError("Failed to create the model container: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                RootView()
                    .environment(store)
                    .preferredColorScheme(appTheme.colorScheme)
                if showSplash {
                    SplashView { showSplash = false }
                        .zIndex(1)
                }
            }
        }
        .modelContainer(container)
    }
}
