//
//  ChallengeLinkTests.swift
//  Bible Crossword ChallengeTests
//
//  The link the app shares must be the link the app accepts. The https
//  universal link was dropped on arrival for its first six weeks because the
//  router checked the scheme before the parser saw it; this pins the round
//  trip at the service level so the two can't drift apart again.
//

import Testing
import Foundation
@testable import Bible_Crossword_Challenge

@MainActor
struct ChallengeLinkTests {

    private func service() -> ChallengeService {
        ChallengeService(
            defaults: UserDefaults(suiteName: "challenge-link-tests-\(UUID().uuidString)")!,
            now: Date.init,
            puzzleExists: { _ in true }
        )
    }

    private func components(_ url: URL) throws -> URLComponents {
        try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
    }

    @Test func theSharedWebLinkIsRecognisedAndParses() throws {
        let s = service()
        let url = try #require(s.challengeWebURL(puzzleID: "daily-042", seconds: 154, name: "Sam"))
        #expect(url.scheme == "https")
        #expect(ChallengeService.isChallengeLink(url, components: try components(url)))
        guard case .valid(let challenge) = s.parse(url) else {
            Issue.record("shared web link did not parse: \(url)")
            return
        }
        #expect(challenge.puzzleID == "daily-042")
        #expect(challenge.challengerName == "Sam")
    }

    @Test func theCustomSchemeLinkStillParses() throws {
        let s = service()
        let url = try #require(s.challengeURL(puzzleID: "daily-042", seconds: 154, name: "Sam"))
        #expect(url.scheme == "biblecrossword")
        #expect(ChallengeService.isChallengeLink(url, components: try components(url)))
        guard case .valid = s.parse(url) else {
            Issue.record("custom-scheme link did not parse: \(url)")
            return
        }
    }

    @Test func aWwwLinkAlreadyInTheWildStillParses() throws {
        let s = service()
        let url = try #require(URL(string: "https://www.biblecrosswordchallenge.com/challenge/?v=1&p=daily-042&t=154&n=Sam"))
        #expect(ChallengeService.isChallengeLink(url, components: try components(url)))
        guard case .valid = s.parse(url) else {
            Issue.record("www link did not parse")
            return
        }
    }

    @Test func anUnrelatedSiteLinkIsNotAChallenge() throws {
        let url = try #require(URL(string: "https://biblecrosswordchallenge.com/puzzles/"))
        #expect(!ChallengeService.isChallengeLink(url, components: try components(url)))
        guard case .notAChallenge = service().parse(url) else {
            Issue.record("a plain site link parsed as a challenge")
            return
        }
    }
}
