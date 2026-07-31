//
//  SSEFrameAccumulatorTests.swift
//  Playlist
//
//  Verifies SSEFrameAccumulator reassembles text/event-stream `data:` frames
//  from newline-stripped lines: single- and multi-line data, the optional
//  leading-space strip, blank-line termination, and the ignoring of `: keepalive`
//  heartbeat comments and non-`data` fields. See WXYC/wxyc-ios-64#269.
//
//  Created by Jake Bromberg on 07/31/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import Foundation
@testable import Playlist

@Suite("SSEFrameAccumulator")
struct SSEFrameAccumulatorTests {

    /// Feeds `lines` in order and returns every completed frame as a UTF-8 string.
    private func frames(from lines: [String]) -> [String] {
        var accumulator = SSEFrameAccumulator()
        return lines.compactMap { line in
            accumulator.consume(line: line).map { String(decoding: $0, as: UTF8.self) }
        }
    }

    @Test("A single data line terminated by a blank line yields one frame")
    func singleDataFrame() {
        #expect(frames(from: [#"data: {"type":"insert"}"#, ""]) == [#"{"type":"insert"}"#])
    }

    @Test("The single optional leading space after `data:` is stripped, but only one")
    func stripsOneLeadingSpace() {
        // No space and one space both yield the same content...
        #expect(frames(from: [#"data:{"a":1}"#, ""]) == [#"{"a":1}"#])
        #expect(frames(from: [#"data: {"a":1}"#, ""]) == [#"{"a":1}"#])
        // ...a second leading space is preserved (part of the value).
        #expect(frames(from: ["data:  x", ""]) == [" x"])
    }

    @Test("Multiple data lines in one frame concatenate with a newline")
    func multiLineDataConcatenates() {
        #expect(frames(from: ["data: line1", "data: line2", ""]) == ["line1\nline2"])
    }

    @Test("A `: keepalive` heartbeat comment yields no frame")
    func heartbeatCommentIgnored() {
        #expect(frames(from: [": keepalive", ""]).isEmpty)
    }

    @Test("Non-`data` SSE fields (event/id/retry) are ignored, only data survives")
    func nonDataFieldsIgnored() {
        #expect(frames(from: ["event: message", "id: 7", "retry: 1000", "data: {}", ""]) == ["{}"])
    }

    @Test("A blank line with no preceding data line yields nothing")
    func blankLineWithoutDataYieldsNothing() {
        #expect(frames(from: ["", ""]).isEmpty)
    }

    @Test("Consecutive frames each terminate independently")
    func consecutiveFrames() {
        let lines = [#"data: {"n":1}"#, "", #"data: {"n":2}"#, ""]
        #expect(frames(from: lines) == [#"{"n":1}"#, #"{"n":2}"#])
    }
}
