//
//  HTTPStreamClientTests.swift
//  Playback
//
//  Tests for HTTPStreamClient data streaming.
//
//  Created by Jake Bromberg on 12/26/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Testing
import Foundation
@testable import MP3StreamerModule

#if !os(watchOS)

@Suite("HTTPStreamClient Tests")
@MainActor
struct HTTPStreamClientTests {

    // MARK: - Test Helpers

    private func makeTestURL() -> URL {
        URL(string: "https://example.com/stream.mp3")!
    }

    private func makeConfiguration(url: URL? = nil) -> MP3StreamerConfiguration {
        MP3StreamerConfiguration(
            url: url ?? makeTestURL(),
            connectionTimeout: 5.0
        )
    }

    // MARK: - Unit Tests

    @Test("Client can be initialized")
    func testInitialization() {
        let url = makeTestURL()
        let config = makeConfiguration(url: url)

        let client = HTTPStreamClient(
            url: url,
            configuration: config
        )

        // Client should be created without error
        _ = client
    }

    @Test("HTTPStreamError cases are distinct")
    func testErrorCases() {
        let invalidURL = HTTPStreamError.invalidURL
        let connectionFailed = HTTPStreamError.connectionFailed
        let httpError = HTTPStreamError.httpError(statusCode: 404)
        let timeout = HTTPStreamError.timeout
        let cancelled = HTTPStreamError.cancelled

        // Verify error cases exist and are usable
        #expect(String(describing: invalidURL).contains("invalidURL"))
        #expect(String(describing: connectionFailed).contains("connectionFailed"))
        #expect(String(describing: httpError).contains("404"))
        #expect(String(describing: timeout).contains("timeout"))
        #expect(String(describing: cancelled).contains("cancelled"))
    }

    @Test("HTTPStreamEvent cases are correct")
    func testEventCases() {
        let connected = HTTPStreamEvent.connected
        let data = HTTPStreamEvent.data(Data([0x01, 0x02]))
        let disconnected = HTTPStreamEvent.disconnected
        let error = HTTPStreamEvent.error(HTTPStreamError.timeout)

        // Verify event cases
        if case .connected = connected {
            // Success
        } else {
            Issue.record("Expected connected event")
        }

        if case .data(let receivedData) = data {
            #expect(receivedData.count == 2)
        } else {
            Issue.record("Expected data event")
        }

        if case .disconnected = disconnected {
            // Success
        } else {
            Issue.record("Expected disconnected event")
        }

        if case .error = error {
            // Success
        } else {
            Issue.record("Expected error event")
        }
    }
}

#endif
