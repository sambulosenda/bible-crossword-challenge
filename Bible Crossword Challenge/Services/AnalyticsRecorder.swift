//
//  AnalyticsRecorder.swift
//  Bible Crossword Challenge
//
//  DEBUG-only: appends every analytics event to a file a UI test names in its
//  launch environment, one per line as `name` or `name:source`, so a test
//  can assert on the sequence a real interaction produced — one
//  `daily_puzzle_started` per open, no `puzzle_abandoned` on a rotation. The event bugs worth catching
//  live in view lifecycles (rotation, a screen closing, a pop back), which
//  unit tests can't drive.
//
//  Simulator only in practice: the test runner and the app share the host
//  filesystem there, so the app can write to a path in the runner's tmp.
//

import Foundation

#if DEBUG
enum AnalyticsRecorder {
    /// Launch-environment key carrying the log path.
    static let environmentKey = "UI_ANALYTICS_LOG"

    private static let url: URL? = ProcessInfo.processInfo.environment[environmentKey]
        .map { URL(fileURLWithPath: $0) }

    static func record(_ name: String, source: String? = nil) {
        guard let url else { return }
        // The source tells apart asks that share an event name — the
        // return-day sheet and the inline card both log `reminder_ask_shown`.
        let entry = source.map { "\(name):\($0)" } ?? name
        let line = Data((entry + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
        } else {
            try? line.write(to: url)
        }
    }
}
#endif
