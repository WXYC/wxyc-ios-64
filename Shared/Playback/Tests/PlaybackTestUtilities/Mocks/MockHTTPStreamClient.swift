//
//  MockHTTPStreamClient.swift
//  Playback
//
//  Mock HTTP stream client for testing MP3Streamer
//
//  Created by Jake Bromberg on 01/07/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
@testable import MP3StreamerModule

#if !os(watchOS)

/// Mock HTTP stream client that feeds test data instantly without network access
@MainActor
public final class MockHTTPStreamClient: @preconcurrency HTTPStreamClientProtocol {
    private let continuation: AsyncStream<HTTPStreamEvent>.Continuation
    public let eventStream: AsyncStream<HTTPStreamEvent>

    /// Optional test data to feed when connect() is called
    public var testData: Data?

    /// Chunk size for splitting test data
    public var chunkSize: Int = 4096

    /// Whether connect should succeed
    public var shouldSucceed = true

    /// Error to throw if shouldSucceed is false
    public var errorToThrow: Error = HTTPStreamError.connectionFailed

    /// Track whether connect was called
    public private(set) var connectCallCount = 0

    /// Number of connect() calls that ran to completion (emitted `.connected` and
    /// finished feeding data). A connect that is cancelled mid-flight via
    /// `nextConnectDelay` does NOT count — useful for asserting that a superseded
    /// reconnect was actually abandoned rather than left to complete in the background.
    public private(set) var connectCompletedCount = 0

    /// If set, the NEXT connect() call awaits this delay before emitting `.connected`,
    /// simulating a slow/in-flight connection. Consumed once (reset to nil on use). If
    /// the task is cancelled during the wait, connect() returns quietly without
    /// emitting `.connected` — matching a real invalidated URLSession.
    public var nextConnectDelay: Duration?

    /// Track whether disconnect was called
    public private(set) var disconnectCallCount = 0

    public init() {
        var cont: AsyncStream<HTTPStreamEvent>.Continuation!
        self.eventStream = AsyncStream(bufferingPolicy: .unbounded) { cont = $0 }
        self.continuation = cont
    }

    public func connect() async throws {
        connectCallCount += 1

        guard shouldSucceed else {
            throw errorToThrow
        }

        // Simulate a slow/in-flight connection for one call, if requested. If the
        // owning task is cancelled during the wait (e.g. a fresh reconnect
        // superseded this one), abandon quietly — no `.connected`, no completion —
        // matching a real invalidated URLSession rather than surfacing an error.
        if let delay = nextConnectDelay {
            nextConnectDelay = nil
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
        }

        // Emit connected event
        continuation.yield(.connected)

        // Feed test data in chunks if available
        if let data = testData {
            var offset = 0
            while offset < data.count {
                let end = min(offset + chunkSize, data.count)
                let chunk = data[offset..<end]
                continuation.yield(.data(Data(chunk)))
                offset = end
            }
        }

        connectCompletedCount += 1
    }

    public func disconnect() {
        disconnectCallCount += 1
        continuation.yield(.disconnected)
    }

    // MARK: - Test Helpers

    /// Manually yield an event for testing
    public func yield(_ event: HTTPStreamEvent) {
        continuation.yield(event)
    }

    /// Feed additional data through the stream (useful for testing mid-playback scenarios)
    public func feedData(_ data: Data) {
        var offset = 0
        while offset < data.count {
            let end = min(offset + chunkSize, data.count)
            let chunk = data[offset..<end]
            continuation.yield(.data(Data(chunk)))
            offset = end
        }
    }

    /// Finish the stream
    public func finish() {
        continuation.finish()
    }
}

#endif
