//
//  PostHogBugReportSubmitterTests.swift
//  WXYC
//
//  Tests for the bug-report log push: the 500-line read, the 400-record push
//  cap, newest-first order, report-ID and timestamp tagging, level routing
//  (info and debug only), and the closing flush.
//
//  Created by Jake Bromberg on 10/19/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import Foundation
@testable import WXYC

@Suite("PostHogBugReportSubmitter")
struct PostHogBugReportSubmitterTests {

    @Test("info and debug lines are emitted with the report ID and category; the flush comes last")
    func tagsAndFlushes() throws {
        let emitter = RecordingPostHogEmitter()
        let submitter = PostHogBugReportSubmitter(emitter: emitter)

        submitter.submit(reportID: "r-1", logLines: [
            line("INFO", "playback", "started"),
            line("DEBUG", "network", "GET /flowsheet")
        ])

        let calls = emitter.calls
        #expect(calls.map(\.method) == [.debug, .info, .flush])
        #expect(calls.map(\.message) == ["GET /flowsheet", "started", ""])
        #expect(calls[0].attributes["report_id"] as? String == "r-1")
        #expect(calls[0].attributes["category"] as? String == "network")
        #expect(calls[1].attributes["report_id"] as? String == "r-1")
        #expect(calls[1].attributes["category"] as? String == "playback")
    }

    @Test("lines are pushed newest first, each carrying the timestamp it was logged at")
    func pushesNewestFirstWithTimestamps() {
        let emitter = RecordingPostHogEmitter()
        let submitter = PostHogBugReportSubmitter(emitter: emitter)

        submitter.submit(reportID: "r-1", logLines: [
            line("INFO", "playback", "first", at: "2026-10-19 12:00:00.000"),
            line("INFO", "playback", "second", at: "2026-10-19 12:00:01.000"),
            line("DEBUG", "playback", "third", at: "2026-10-19 12:00:02.000")
        ])

        let records = emitter.calls.filter { $0.method != .flush }
        #expect(records.map(\.message) == ["third", "second", "first"])
        #expect(records.map { $0.attributes["logged_at"] as? String } == [
            "2026-10-19 12:00:02.000",
            "2026-10-19 12:00:01.000",
            "2026-10-19 12:00:00.000"
        ])
    }

    @Test("at most 400 records are pushed, keeping the newest, so the push leaves room in the SDK's 500-per-10-s window")
    func capsPushedRecordsKeepingNewest() {
        let emitter = RecordingPostHogEmitter()
        let submitter = PostHogBugReportSubmitter(emitter: emitter)
        let lines = (0..<500).map { line("INFO", "playback", "line \($0)") }

        submitter.submit(reportID: "r-1", logLines: lines)

        let records = emitter.calls.filter { $0.method != .flush }
        #expect(PostHogBugReportSubmitter.maxRecords == 400)
        #expect(records.count == PostHogBugReportSubmitter.maxRecords)
        #expect(records.first?.message == "line 499")
        #expect(records.last?.message == "line 100")
        #expect(emitter.calls.last?.method == .flush)
    }

    @Test("warning, error, and unparseable lines are not re-emitted")
    func skipsLinesAlreadyStreamedOrUnparseable() {
        let emitter = RecordingPostHogEmitter()
        let submitter = PostHogBugReportSubmitter(emitter: emitter)

        submitter.submit(reportID: "r-1", logLines: [
            line("WARNING", "playback", "slow"),
            line("ERROR", "playback", "boom"),
            "a continuation line with no tag"
        ])

        #expect(emitter.calls.map(\.method) == [.flush])
    }

    @Test("recent lines keeps only the last 500, newest file first")
    func capsAtFiveHundredLines() {
        let older = file("wxyc-2026-10-18.log", lines: (0..<400).map { "old \($0)" })
        let newer = file("wxyc-2026-10-19.log", lines: (0..<400).map { "new \($0)" })

        let lines = BugReportLogLines.recent(from: [older, newer], limit: 500)

        #expect(lines.count == 500)
        #expect(lines.last == "new 399")
        #expect(lines.first == "old 300")
    }

    @Test("recent lines inflates zlib-compressed older files")
    func readsCompressedFiles() throws {
        let raw = Data("old 1\nold 2\n".utf8)
        let compressed = try (raw as NSData).compressed(using: .zlib) as Data

        let lines = BugReportLogLines.recent(
            from: [(logName: "wxyc-2026-10-18.log.zip", data: compressed)],
            limit: 500
        )

        #expect(lines == ["old 1", "old 2"])
    }

    // MARK: - Helpers

    private func line(
        _ level: String,
        _ category: String,
        _ body: String,
        at timestamp: String = "2026-10-19 12:00:00.000"
    ) -> String {
        "\(timestamp) File.swift:1 fn() [\(category)/\(level)] \(body)"
    }

    private func file(_ name: String, lines: [String]) -> (logName: String, data: Data) {
        (name, Data((lines.joined(separator: "\n") + "\n").utf8))
    }
}
