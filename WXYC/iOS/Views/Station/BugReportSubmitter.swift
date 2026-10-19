//
//  BugReportSubmitter.swift
//  WXYC
//
//  Pushes a bug report's recent log lines to PostHog Logs, tagged with the
//  report ID, through the PostHogLogEmitter seam so the flow can be exercised
//  in tests without invoking the live SDK.
//
//  Created by Jake Bromberg on 05/30/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Logger

nonisolated protocol BugReportSubmitter: Sendable {
    /// Pushes `logLines` (raw `Logger` output, oldest first) to PostHog Logs tagged with
    /// `reportID`, newest first, then flushes.
    func submit(reportID: String, logLines: [String])
}

/// Only info and debug lines are pushed: `PostHogLogsDestination` already streams
/// warning and error lines live, so repeating them would spend the SDK's
/// 500-records-per-10-s cap on duplicates. Lines carry whatever `Logger` wrote to
/// disk, the same content the Sentry attachments carried; there is no extra scrubbing.
///
/// The SDK's cap is a tumbling window shared with that live stream, and a record
/// over the cap is dropped silently at capture, so the newest records are the ones
/// lost. Lines are therefore pushed newest first, and at most `maxRecords` of them,
/// so an overflow costs the oldest lines and a normal live stream still fits in the
/// same window. Each record carries the time `Logger` wrote it in `logged_at`
/// (`yyyy-MM-dd HH:mm:ss.SSS`, device local time), because the SDK stamps records
/// with the push time and the push order is reversed.
nonisolated struct PostHogBugReportSubmitter: BugReportSubmitter {
    /// The most records one push emits: 100 below posthog-ios's 500-per-10-s cap.
    static let maxRecords = 400

    private let emitter: any PostHogLogEmitter

    init(emitter: any PostHogLogEmitter = PostHogSDKLoggerEmitter()) {
        self.emitter = emitter
    }

    /// Pushes the newest `maxRecords` info and debug lines of `logLines` (oldest first,
    /// as `BugReportLogLines.recent` returns them), newest first, then flushes.
    func submit(reportID: String, logLines: [String]) {
        var emitted = 0
        for line in logLines.reversed() {
            if emitted >= Self.maxRecords {
                break
            }
            guard let (timestamp, category, level, body) = Self.parse(line) else { continue }
            let attributes: [String: Any] = [
                "category": category,
                "report_id": reportID,
                "logged_at": timestamp
            ]
            switch level {
            case LogLevel.info.description:
                emitter.info(body, attributes: attributes)
                emitted += 1
            case LogLevel.debug.description:
                emitter.debug(body, attributes: attributes)
                emitted += 1
            default:
                break // warning and error already streamed live
            }
        }
        emitter.flush()
    }

    /// Splits `"<date> <time> <location> [<category>/<level>] <body>"`; nil for untagged lines.
    private static func parse(
        _ line: String
    ) -> (timestamp: String, category: String, level: String, body: String)? {
        guard let close = line.range(of: "] "),
              let open = line[..<close.lowerBound].lastIndex(of: "[") else { return nil }
        let tag = line[line.index(after: open)..<close.lowerBound].split(separator: "/")
        guard tag.count == 2 else { return nil }
        let timestamp = line[..<open].split(separator: " ", maxSplits: 2).prefix(2).joined(separator: " ")
        return (timestamp, String(tag[0]), String(tag[1]), String(line[close.upperBound...]))
    }
}

nonisolated enum BugReportLogLines {
    static let maxLines = 500

    /// The last `limit` lines across `files`, oldest first. Files are read newest
    /// name first; older ones are zlib-compressed by `Logger` and inflated here.
    static func recent(from files: [(logName: String, data: Data)], limit: Int = maxLines) -> [String] {
        var collected: [String] = []
        for file in files.sorted(by: { $0.logName > $1.logName }) {
            let data = file.logName.hasSuffix(".log")
                ? file.data
                : (try? (file.data as NSData).decompressed(using: .zlib) as Data) ?? file.data
            let lines = String(decoding: data, as: UTF8.self)
                .split(separator: "\n", omittingEmptySubsequences: true)
                .map(String.init)
            collected = lines + collected
            if collected.count >= limit { break }
        }
        return Array(collected.suffix(limit))
    }
}
