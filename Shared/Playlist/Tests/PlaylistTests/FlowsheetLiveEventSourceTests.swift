//
//  FlowsheetLiveEventSourceTests.swift
//  Playlist
//
//  Drives FlowsheetLiveEventSource end-to-end over a stubbed URLSession serving
//  a real `text/event-stream` byte body, covering the transport's byte-to-frame
//  seam. SSEFrameAccumulatorTests covers frame reassembly from lines; these
//  cover that the transport actually produces those lines — the gap that let
//  the stream go silent while every unit test stayed green. See
//  WXYC/wxyc-ios-64#269.
//
//  Created by Jake Bromberg on 08/05/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import Foundation
@testable import Playlist

@Suite("FlowsheetLiveEventSource")
struct FlowsheetLiveEventSourceTests {

    /// Encodes `payloads` as a `text/event-stream` body: each becomes one
    /// `data:` line terminated by the blank line the SSE spec requires, using
    /// `terminator` as the line break.
    private static func wireFormat(_ payloads: [String], terminator: String = "\n") -> Data {
        Data(payloads.map { "data: \($0)\(terminator)\(terminator)" }.joined().utf8)
    }

    /// One `insert` frame's JSON, on a single line as Backend emits it.
    private static func insertFrame(id: Int) -> String {
        """
        {"type":"insert","payload":{"id":\(id),"artist_name":"Juana Molina",\
        "album_title":"DOGA","track_title":"la paradoja","play_order":1,\
        "add_time":"2026-08-05T18:00:00Z","entry_type":"track",\
        "metadata_status":"pending"},"timestamp":"2026-08-05T18:00:00Z"}
        """
    }

    /// A session whose traffic `CapturingURLProtocol` serves.
    private static func stubbedSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CapturingURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    /// Collects every event one `connect()` yields before the body ends.
    private func events(servingBody body: Data, at url: URL) async -> [LiveFsEvent] {
        CapturingURLProtocol.stub(url: url, body: body)
        let source = FlowsheetLiveEventSource(url: url, session: Self.stubbedSession())
        var received: [LiveFsEvent] = []
        for await event in source.connect() {
            received.append(event)
        }
        return received
    }

    @Test(
        "A wire-format stream yields one event per frame, under every SSE line terminator",
        arguments: [("lf", "\n"), ("crlf", "\r\n"), ("cr", "\r")]
    )
    func yieldsOneEventPerFrame(name: String, terminator: String) async {
        let url = URL(string: "https://example.invalid/sse/one-event-per-frame-\(name)")!
        let body = Self.wireFormat(
            [Self.insertFrame(id: 90210), Self.insertFrame(id: 90211)],
            terminator: terminator
        )

        let ids = await events(servingBody: body, at: url).compactMap { event -> UInt64? in
            guard case let .insert(playcut) = event else { return nil }
            return playcut.id
        }

        #expect(ids == [90210, 90211])
    }

    @Test("Envelope frames and interleaved keepalive comments don't disturb framing")
    func survivesProductionStreamShape() async {
        let url = URL(string: "https://example.invalid/sse/production-shape")!
        // The opening two frames and the 30 s heartbeat cadence of a real
        // `live-fs-topic` connection, captured 2026-08-05.
        let body = Data(
            (
                #"data: {"type":"connection-established","payload":{"clientId":"9a39d3eb"},"timestamp":"2026-08-05T18:00:00Z"}"# + "\n\n"
                + #"data: {"type":"subscription","payload":{"client_id":"9a39d3eb","topics":["live-fs-topic"]},"timestamp":"2026-08-05T18:00:00Z"}"# + "\n\n"
                + "data: " + Self.insertFrame(id: 90210) + "\n\n"
                + ": keepalive\n\n"
                + "data: " + Self.insertFrame(id: 90211) + "\n\n"
                + ": keepalive\n\n"
            ).utf8
        )

        let ids = await events(servingBody: body, at: url).compactMap { event -> UInt64? in
            guard case let .insert(playcut) = event else { return nil }
            return playcut.id
        }

        // The two envelope frames and both heartbeats decode to nothing; only
        // the two modeled events survive, in order.
        #expect(ids == [90210, 90211])
    }
}
