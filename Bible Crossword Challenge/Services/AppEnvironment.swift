//
//  AppEnvironment.swift
//  Bible Crossword Challenge
//
//  Custom environment values for injecting stateless services. Defaults point
//  at shared singletons so they stay stable across reads (per the @Entry rule).
//

import SwiftUI

extension EnvironmentValues {
    @Entry var analytics: any AnalyticsService = FirebaseAnalyticsService.shared
    @Entry var ads: any AdProvider = NoOpAdProvider.shared
    @Entry var puzzleProvider: PuzzleProvider = PuzzleProvider.shared
    @Entry var notifications: NotificationService = .shared
    @Entry var gameCenter: GameCenterService = .shared
    @Entry var scripture: ScriptureProvider = .shared
    @Entry var readerRouter: ReaderRouter = .shared
}
