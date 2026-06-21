//
//  Bible_Crossword_ChallengeApp.swift
//  Bible Crossword Challenge
//
//  Created by Sambulo Senda on 21/06/2026.
//

import SwiftUI
import SwiftData

@main
struct Bible_Crossword_ChallengeApp: App {
    @State private var store = StoreService()
    private let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(for: PlayerProfile.self, PuzzleRecord.self)
        } catch {
            fatalError("Failed to create the model container: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
        }
        .modelContainer(container)
    }
}
