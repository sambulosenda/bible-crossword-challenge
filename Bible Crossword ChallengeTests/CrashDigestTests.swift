//
//  CrashDigestTests.swift
//  Bible Crossword ChallengeTests
//
//  The MetricKit call-stack digest, over a synthetic tree in the JSON shape
//  `MXCallStackTree.jsonRepresentation()` produces.
//

import Testing
import Foundation
@testable import Bible_Crossword_Challenge

struct CrashDigestTests {
    private func frame(_ binary: String, _ offset: Int, sub: [[String: Any]] = []) -> [String: Any] {
        var f: [String: Any] = [
            "binaryUUID": "0000",
            "binaryName": binary,
            "offsetIntoBinaryTextSegment": offset,
            "address": 4_000_000 + offset,
            "sampleCount": 1,
        ]
        if !sub.isEmpty { f["subFrames"] = sub }
        return f
    }

    private func tree(attributedSecond: Bool = true) throws -> Data {
        // Thread 0: an idle worker. Thread 1: main → UIKit → app → app (crash).
        let idle = frame("libsystem_pthread.dylib", 0x10, sub: [frame("libdispatch.dylib", 0x20)])
        let crashing = frame("dyld", 0x100, sub: [
            frame("App", 0x2000, sub: [
                frame("UIKitCore", 0x3000, sub: [
                    frame("App", 0x4000, sub: [
                        frame("App", 0x5000),
                    ]),
                ]),
            ]),
        ])
        let root: [String: Any] = [
            "callStackPerThread": true,
            "callStacks": [
                ["threadAttributed": !attributedSecond, "callStackRootFrames": [idle]],
                ["threadAttributed": attributedSecond, "callStackRootFrames": [crashing]],
            ],
        ]
        return try JSONSerialization.data(withJSONObject: root)
    }

    @Test func readsTheAttributedThreadDeepestFirst() throws {
        let digest = CrashDigest(callStackJSON: try tree(), appBinaryName: "App")
        #expect(digest.frames == ["App+0x5000", "App+0x4000", "UIKitCore+0x3000", "App+0x2000", "dyld+0x100"])
        #expect(digest.appFrames == ["App+0x5000", "App+0x4000", "App+0x2000"])
        #expect(digest.framesLine == "App+0x5000 < App+0x4000 < UIKitCore+0x3000 < App+0x2000 < dyld+0x100")
    }

    @Test func fallsBackToTheFirstThreadWhenNoneIsAttributed() throws {
        let digest = CrashDigest(callStackJSON: try tree(attributedSecond: false), appBinaryName: "App")
        // First thread carries `threadAttributed: true` in this fixture, so
        // it wins — the idle stack, with no app frames at all.
        #expect(digest.frames == ["libdispatch.dylib+0x20", "libsystem_pthread.dylib+0x10"])
        #expect(digest.appFrames.isEmpty)
    }

    @Test func capsTheFrameCount() throws {
        var deepest = frame("App", 1)
        for i in 2...40 { deepest = frame("App", i, sub: [deepest]) }
        let root: [String: Any] = ["callStacks": [["threadAttributed": true, "callStackRootFrames": [deepest]]]]
        let digest = CrashDigest(callStackJSON: try JSONSerialization.data(withJSONObject: root), appBinaryName: "App")
        #expect(digest.frames.count == CrashDigest.maxFrames)
        #expect(digest.appFrames.count == CrashDigest.maxAppFrames)
        #expect(digest.frames.first == "App+0x1")
    }

    @Test func malformedTreeYieldsAnEmptyDigest() {
        let digest = CrashDigest(callStackJSON: Data("not json".utf8), appBinaryName: "App")
        #expect(digest == CrashDigest(frames: [], appFrames: []))
        #expect(digest.framesLine.isEmpty)
    }
}
