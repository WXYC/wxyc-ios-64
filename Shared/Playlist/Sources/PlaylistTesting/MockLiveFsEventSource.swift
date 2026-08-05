//
//  MockLiveFsEventSource.swift
//  PlaylistTesting
//
//  Test double for LiveFsEventSource: yields a scripted list of LiveFsEvents on
//  each connect, optionally finishing the stream afterwards (to exercise the
//  consumer's reconnect path) or keeping it open (to model a live connection).
//  See WXYC/wxyc-ios-64#269.
//
//  Created by Jake Bromberg on 07/31/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Synchronization
@_exported import Playlist

/// Test double for ``LiveFsEventSource`` that replays a fixed script of events.
///
/// Pass an explicit `apiVersion:` that supports live updates. Omitting it
/// resolves via `PlaylistAPIVersion.loadActive()`, which in a test process has
/// no feature flag or debug override to read and so lands on `.v1` — a version
/// with no push channel. The service then wires in no source at all, this mock
/// is never connected, and the test passes while exercising nothing.
/// See WXYC/wxyc-ios-64#749.
///
/// ```swift
/// let source = MockLiveFsEventSource(events: [.insert(.stub(id: 42))])
/// let service = PlaylistService(fetcher: fetcher, interval: 300,
///                               cacheCoordinator: coordinator,
///                               liveEventSource: source, apiVersion: .v2)
/// await service.setForegrounded(true)
/// ```
public final class MockLiveFsEventSource: LiveFsEventSource, @unchecked Sendable {
    private let script: [LiveFsEvent]
    private let finishesAfterScript: Bool
    private let connects = Mutex(0)

    /// - Parameters:
    ///   - events: The events yielded, in order, on every ``connect()``.
    ///   - finishesAfterScript: When `true` the stream finishes once the script
    ///     is drained, so a reconnecting consumer calls ``connect()`` again;
    ///     when `false` (the default) the stream stays open, modelling a live
    ///     connection that ends only when the consumer cancels.
    public init(events: [LiveFsEvent] = [], finishesAfterScript: Bool = false) {
        self.script = events
        self.finishesAfterScript = finishesAfterScript
    }

    /// The number of times ``connect()`` has been called — one per connection
    /// attempt, so a value > 1 means the consumer reconnected.
    public var connectCount: Int {
        connects.withLock { $0 }
    }

    public func connect() -> AsyncStream<LiveFsEvent> {
        connects.withLock { $0 += 1 }
        let script = self.script
        let finishes = self.finishesAfterScript
        return AsyncStream { continuation in
            for event in script {
                continuation.yield(event)
            }
            if finishes {
                continuation.finish()
            }
            // Otherwise the stream stays open; AsyncStream finishes it when the
            // consuming task is cancelled (backgrounding), which is exactly the
            // teardown `PlaylistService.setForegrounded(false)` triggers.
        }
    }
}
