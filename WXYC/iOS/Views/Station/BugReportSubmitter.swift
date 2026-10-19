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
    /// Pushes `logLines` (raw `Logger` output) to PostHog Logs tagged with `reportID`, then flushes.
    func submit(reportID: String, logLines: [String])
}

/// Only info and debug lines are pushed: `PostHogLogsDestination` already streams
/// warning and error lines live, so repeating them would spend the SDK's
/// 500-records-per-10-s cap on duplicates. Lines carry whatever `Logger` wrote to
/// disk, the same content the Sentry attachments carried; there is no extra scrubbing.
nonisolated struct PostHogBugReportSubmitter: BugReportSubmitter {
    private let emitter: any PostHogLogEmitter

    init(emitter: any PostHogLogEmitter = PostHogSDKLoggerEmitter()) {
        self.emitter = emitter
    }

    func submit(reportID: String, logLines: [String]) {
        for line in logLines {
            guard let (category, level, body) = Self.parse(line) else { continue }
            let attributes: [String: Any] = ["category": category, "report_id": reportID]
            switch level {
            case LogLevel.info.description: emitter.info(body, attributes: attributes)
            case LogLevel.debug.description: emitter.debug(body, attributes: attributes)
            default: break // warning and error already streamed live
            }
        }
        emitter.flush()
    }

    /// Splits `"<prefix> [<category>/<level>] <body>"`; nil for untagged lines.
    private static func parse(_ line: String) -> (category: String, level: String, body: String)? {
        guard let close = line.range(of: "] "),
              let open = line[..<close.lowerBound].lastIndex(of: "[") else { return nil }
        let tag = line[line.index(after: open)..<close.lowerBound].split(separator: "/")
        guard tag.count == 2 else { return nil }
        return (String(tag[0]), String(tag[1]), String(line[close.upperBound...]))
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
