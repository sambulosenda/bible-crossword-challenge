//
//  AppStoreRating.swift
//  Bible Crossword Challenge
//
//  The app's App Store rating, for the line on the Premium offer
//  ("★★★★★ 4.9 on the App Store").
//
//  Read from Apple's public lookup for the player's own storefront rather than
//  written into the app, so the line can never claim a rating the store no
//  longer shows. Cached for a day, and shown only when there are enough
//  ratings to mean something and the average is worth saying — otherwise the
//  offer simply has no rating line. No player data is sent: the request names
//  the app and a country code, nothing else.
//

import Foundation
import Observation

@Observable
final class AppStoreRating {
    static let shared = AppStoreRating()

    struct Summary: Codable, Equatable {
        let average: Double
        let count: Int
        let fetchedAt: Date
        /// The storefront it was read for, lowercased ("us"). A rating is per
        /// country: the UK's 2 ratings are not the US's 41.
        let country: String
    }

    static let appID = "6783034270"

    /// Fewer ratings than this and a storefront's average is a handful of
    /// people, not a reputation.
    static let minimumCount = 20
    /// Below this the line doesn't help the offer, so it isn't shown.
    static let minimumAverage = 4.5
    static let maxAge: TimeInterval = 24 * 60 * 60

    private static let cacheKey = "appStoreRating.summary"

    private(set) var summary: Summary?
    private var refreshing = false

    init(defaults: UserDefaults = .standard) {
        if let data = defaults.data(forKey: Self.cacheKey) {
            summary = try? JSONDecoder().decode(Summary.self, from: data)
        }
    }

    /// The player's storefront, as the lookup names it.
    static var currentCountry: String {
        (Locale.current.region?.identifier ?? "US").lowercased()
    }

    /// The rating to show, or nil when the offer should have no rating line.
    var displayable: Summary? {
        guard let summary, summary.country == Self.currentCountry,
              Self.isDisplayable(average: summary.average, count: summary.count) else { return nil }
        return summary
    }

    static func isDisplayable(average: Double, count: Int) -> Bool {
        count >= minimumCount && average >= minimumAverage
    }

    /// "4.9" — one decimal, rounded as the App Store rounds it.
    static func formatted(_ average: Double) -> String {
        ((average * 10).rounded() / 10).formatted(.number.precision(.fractionLength(1)))
    }

    /// Fetches a fresh rating when the cached one is missing or a day old.
    /// Failures keep whatever was cached.
    func refreshIfStale(now: Date = Date()) async {
        let country = Self.currentCountry
        if let summary, summary.country == country,
           now.timeIntervalSince(summary.fetchedAt) < Self.maxAge { return }
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }

        guard let url = URL(string: "https://itunes.apple.com/lookup?id=\(Self.appID)&country=\(country)") else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(LookupResponse.self, from: data)
            guard let app = response.results.first else { return }
            let fresh = Summary(average: app.averageUserRating ?? 0,
                                count: app.userRatingCount ?? 0,
                                fetchedAt: now,
                                country: country)
            summary = fresh
            if let encoded = try? JSONEncoder().encode(fresh) {
                UserDefaults.standard.set(encoded, forKey: Self.cacheKey)
            }
        } catch {
            // Offline or the lookup changed shape: keep the cached value.
        }
    }

    private struct LookupResponse: Decodable {
        struct App: Decodable {
            let averageUserRating: Double?
            let userRatingCount: Int?
        }
        let results: [App]
    }
}
