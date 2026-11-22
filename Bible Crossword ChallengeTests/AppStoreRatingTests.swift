//
//  AppStoreRatingTests.swift
//  Bible Crossword ChallengeTests
//
//  When the Premium offer may show its App Store rating line, and how the
//  number reads.
//

import Testing
import Foundation
@testable import Bible_Crossword_Challenge

struct AppStoreRatingTests {

    @Test func showsAGoodRatingWithEnoughVotes() {
        #expect(AppStoreRating.isDisplayable(average: 4.9, count: 49))
    }

    @Test func hidesARatingFromAHandfulOfPeople() {
        #expect(!AppStoreRating.isDisplayable(average: 5.0, count: 3))
    }

    @Test func hidesAnAverageNotWorthSaying() {
        #expect(!AppStoreRating.isDisplayable(average: 4.2, count: 300))
    }

    @Test func hidesAStorefrontWithNoRatings() {
        #expect(!AppStoreRating.isDisplayable(average: 0, count: 0))
    }

    @Test func roundsToOneDecimalAsTheStoreDoes() {
        #expect(AppStoreRating.formatted(4.8775) == "4.9")
        #expect(AppStoreRating.formatted(4.5) == "4.5")
        #expect(AppStoreRating.formatted(5) == "5.0")
    }

    @Test func cachedRatingIsShownWithoutAFetch() throws {
        let defaults = try #require(UserDefaults(suiteName: "AppStoreRatingTests"))
        defaults.removePersistentDomain(forName: "AppStoreRatingTests")
        let cached = AppStoreRating.Summary(average: 4.9, count: 49, fetchedAt: Date(),
                                            country: AppStoreRating.currentCountry)
        defaults.set(try JSONEncoder().encode(cached), forKey: "appStoreRating.summary")
        #expect(AppStoreRating(defaults: defaults).displayable == cached)
    }

    @Test func anotherCountrysRatingIsNotShown() throws {
        let defaults = try #require(UserDefaults(suiteName: "AppStoreRatingTests.other"))
        defaults.removePersistentDomain(forName: "AppStoreRatingTests.other")
        let elsewhere = AppStoreRating.currentCountry == "zz" ? "yy" : "zz"
        let cached = AppStoreRating.Summary(average: 4.9, count: 49, fetchedAt: Date(), country: elsewhere)
        defaults.set(try JSONEncoder().encode(cached), forKey: "appStoreRating.summary")
        #expect(AppStoreRating(defaults: defaults).displayable == nil)
    }
}
