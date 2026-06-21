//
//  AdProvider.swift
//  Bible Crossword Challenge
//
//  Ad abstraction. The default is a no-op so the free tier shows a placeholder
//  banner only. A GoogleMobileAds-backed provider can conform to `AdProvider`
//  once the AdMob SDK and app ID are configured.
//

import Foundation

protocol AdProvider {
    /// Whether real ads should be requested at all (false for the no-op stub).
    var isLive: Bool { get }
    func loadInterstitial()
    func showInterstitial()
}

struct NoOpAdProvider: AdProvider {
    static let shared = NoOpAdProvider()
    var isLive: Bool { false }
    func loadInterstitial() {}
    func showInterstitial() {}
}
