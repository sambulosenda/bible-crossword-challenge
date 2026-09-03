//
//  CrashReporter.swift
//  Bible Crossword Challenge
//
//  MetricKit crash and hang diagnostics, forwarded to analytics as `app_crash`
//  and `app_hang`. No third-party crash SDK: MetricKit is on every device,
//  costs nothing at runtime, and the question it exists to answer is narrow —
//  when a new player opens a grid and the event stream simply stops, did the
//  app die? Diagnostics arrive on the launch after the event, so a player who
//  never comes back still reports nothing; the numbers are a floor. Xcode's
//  Organizer keeps the full reports; this puts a count and a fingerprint next
//  to the puzzle events where the funnel is read.
//
//  Nothing is delivered on the simulator.
//

import Foundation
import MetricKit
import os

final class CrashReporter: NSObject, MXMetricManagerSubscriber {
    static let shared = CrashReporter()

    private static let log = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "BibleCrossword",
        category: "crash"
    )

    private var analytics: any AnalyticsService = MultiAnalyticsService.production
    private var isStarted = false

    /// Subscribes once. `analytics` is injectable for tests; production uses
    /// the same fan-out every other event goes through.
    func start(analytics: (any AnalyticsService)? = nil) {
        if let analytics { self.analytics = analytics }
        guard !isStarted else { return }
        isStarted = true
        MXMetricManager.shared.add(self)
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            for crash in payload.crashDiagnostics ?? [] {
                report(crash)
            }
            for hang in payload.hangDiagnostics ?? [] {
                report(hang)
            }
        }
    }

    /// Splits one crash diagnostic into the event's fields. Internal so a test
    /// can feed a synthetic payload without MetricKit in the loop.
    func report(_ crash: MXCrashDiagnostic) {
        let digest = CrashDigest(callStackJSON: crash.callStackTree.jsonRepresentation())
        // The Objective-C exception message (iOS 17+) names the actual
        // failure — "index out of range" beats a bare SIGABRT — so it wins
        // over the termination reason when present.
        let reason = crash.exceptionReason?.composedMessage ?? crash.terminationReason
        Self.log.error("Crash on build \(crash.metaData.applicationBuildVersion, privacy: .public): \(digest.appFramesLine, privacy: .public)")
        analytics.log(.appCrash(
            signal: crash.signal?.intValue,
            exceptionType: crash.exceptionType?.intValue,
            exceptionCode: crash.exceptionCode?.intValue,
            reason: reason,
            build: crash.metaData.applicationBuildVersion,
            os: crash.metaData.osVersion,
            frames: digest.framesLine,
            appFrames: digest.appFramesLine
        ))
    }

    func report(_ hang: MXHangDiagnostic) {
        let digest = CrashDigest(callStackJSON: hang.callStackTree.jsonRepresentation())
        let seconds = hang.hangDuration.converted(to: .seconds).value
        Self.log.error("Hang of \(seconds, privacy: .public)s on build \(hang.metaData.applicationBuildVersion, privacy: .public): \(digest.appFramesLine, privacy: .public)")
        analytics.log(.appHang(
            seconds: (seconds * 10).rounded() / 10,
            build: hang.metaData.applicationBuildVersion,
            os: hang.metaData.osVersion,
            frames: digest.framesLine,
            appFrames: digest.appFramesLine
        ))
    }
}

// MARK: - Call-stack digest

/// The part of an `MXCallStackTree` worth sending: the attributed thread's
/// deepest frames as `Binary+0xoffset`. The full JSON runs to tens of
/// kilobytes per diagnostic and is unsymbolicated anyway; the offset into
/// the binary is stable for a build, so this string groups identical crashes
/// and symbolicates by hand with `atos -o App.dSYM/… -l 0x0 +0xoffset`.
///
/// Pure parsing over the tree's JSON — testable without MetricKit.
struct CrashDigest: Equatable {
    /// Deepest frame first, at most `maxFrames`.
    let frames: [String]
    /// The frames above that sit in the app's own binary, deepest first.
    let appFrames: [String]

    static let maxFrames = 12
    static let maxAppFrames = 6

    /// `CFBundleExecutable` — how MetricKit names our frames.
    static var appBinaryName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleExecutable") as? String ?? ""
    }

    init(frames: [String], appFrames: [String]) {
        self.frames = frames
        self.appFrames = appFrames
    }

    init(callStackJSON data: Data, appBinaryName: String = CrashDigest.appBinaryName) {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let stacks = root["callStacks"] as? [[String: Any]],
            let stack = stacks.first(where: { $0["threadAttributed"] as? Bool == true }) ?? stacks.first,
            let rootFrames = stack["callStackRootFrames"] as? [[String: Any]]
        else {
            self.init(frames: [], appFrames: [])
            return
        }

        // Root is the outermost frame (start/main); the crash is at the end
        // of the first-child chain. Walk down, then read it deepest-first.
        var chain: [(binary: String, offset: Int)] = []
        var frame = rootFrames.first
        while let current = frame {
            let binary = current["binaryName"] as? String ?? "?"
            let offset = current["offsetIntoBinaryTextSegment"] as? Int ?? 0
            chain.append((binary, offset))
            frame = (current["subFrames"] as? [[String: Any]])?.first
        }
        let deepestFirst = chain.reversed().map { "\($0.binary)+0x\(String($0.offset, radix: 16))" }
        let own = chain.reversed()
            .filter { !appBinaryName.isEmpty && $0.binary == appBinaryName }
            .map { "\($0.binary)+0x\(String($0.offset, radix: 16))" }
        self.init(
            frames: Array(deepestFirst.prefix(Self.maxFrames)),
            appFrames: Array(own.prefix(Self.maxAppFrames))
        )
    }

    var framesLine: String { frames.joined(separator: " < ") }
    var appFramesLine: String { appFrames.joined(separator: " < ") }
}
