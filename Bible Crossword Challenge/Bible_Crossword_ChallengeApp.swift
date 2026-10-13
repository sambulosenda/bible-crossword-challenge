//
//  Bible_Crossword_ChallengeApp.swift
//  Bible Crossword Challenge
//
//  Created by Sambulo Senda on 21/06/2026.
//

import SwiftUI
import SwiftData
import FirebaseCore
import os

@main
struct Bible_Crossword_ChallengeApp: App {
    @State private var store = StoreService()
    @State private var showSplash = true
    @AppStorage("appTheme") private var appTheme: AppTheme = .system
    private let container: ModelContainer

    init() {
        #if DEBUG
        // UI tests: every launch starts from nothing — no saved settings and
        // an in-memory store — so one test's solve can't change the next
        // one's Today. Launch arguments (`-hasOnboarded YES`) still apply.
        let cleanSlate = ProcessInfo.processInfo.arguments.contains("-uiCleanSlate")
        if cleanSlate, let domain = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: domain)
        }
        #else
        let cleanSlate = false
        #endif
        FirebaseApp.configure()
        FirebaseAnalyticsService.configure()
        PostHogAnalyticsService.configure()
        // After the analytics backends exist: MetricKit hands over last
        // session's crash and hang diagnostics early in launch.
        CrashReporter.shared.start()
        // Touched here purely to install its notification-centre delegate. A
        // cold launch from a notification tap delivers the response during the
        // launch cycle, so a delegate first assigned from a view's `.task` is
        // assigned too late and the tap opens the app at its front door.
        _ = NotificationService.shared
        do {
            container = try ModelContainer(
                for: PlayerProfile.self, PuzzleRecord.self,
                configurations: cleanSlate
                    ? ModelConfiguration(isStoredInMemoryOnly: true)
                    : ModelConfiguration(cloudKitDatabase: .automatic)
            )
        } catch {
            // iCloud can be unavailable (signed out, entitlement missing in a
            // dev build). Both configurations use the same default store URL,
            // so falling back keeps the player's local data intact.
            do {
                container = try ModelContainer(
                    for: PlayerProfile.self, PuzzleRecord.self,
                    configurations: ModelConfiguration(cloudKitDatabase: .none)
                )
            } catch {
                // Last resort: run in-memory rather than crash at launch. The
                // player can still solve today's puzzle; progress just won't
                // persist this session. In-memory can only fail on a schema
                // programming error, which the two attempts above would have
                // hit identically first.
                Log.persistence.critical("Model container failed twice, running in-memory: \(error, privacy: .public)")
                container = try! ModelContainer(
                    for: PlayerProfile.self, PuzzleRecord.self,
                    configurations: ModelConfiguration(isStoredInMemoryOnly: true)
                )
            }
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
