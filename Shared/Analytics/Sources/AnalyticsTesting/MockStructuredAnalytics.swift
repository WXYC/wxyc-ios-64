//
//  MockStructuredAnalytics.swift
//  AnalyticsTesting
//
//  Test double for AnalyticsService that records captured events for verification
//  in unit tests without sending data to a real analytics backend. Swift Testing
//  runs suites in parallel by default, so `capture` must tolerate concurrent
//  callers; state lives behind a `Mutex` rather than plain arrays (#816).
//
//  Created by Auto-Agent on 01/24/25.
//

import Analytics
import Foundation
import Synchronization

public final class MockStructuredAnalytics: AnalyticsService {
    /// The recorded events and their names, kept in one lock so a reader
    /// never observes the two arrays at different lengths mid-capture.
    private struct RecordedState {
        var events: [any AnalyticsEvent] = []
        var eventNames: [String] = []
    }

    private let state = Mutex<RecordedState>(RecordedState())

    public init() {}

    /// A snapshot of all captured events, in capture order.
    public var events: [any AnalyticsEvent] {
        state.withLock { $0.events }
    }

    public func capture<T: AnalyticsEvent>(_ event: T) {
        state.withLock {
            $0.events.append(event)
            $0.eventNames.append(T.name)
        }
    }

    public func reset() {
        state.withLock {
            $0.events.removeAll()
            $0.eventNames.removeAll()
        }
    }

    // MARK: - Convenience Accessors

    /// All events with the given name.
    public func events(named name: String) -> [any AnalyticsEvent] {
        state.withLock { current in
            zip(current.events, current.eventNames)
                .filter { $0.1 == name }
                .map { $0.0 }
        }
    }

    /// Filtered events of a specific type.
    public func typedEvents<T: AnalyticsEvent>(ofType: T.Type) -> [T] {
        state.withLock { $0.events.compactMap { $0 as? T } }
    }

    /// All captured event names (for filtering by name pattern).
    public func capturedEventNames() -> [String] {
        state.withLock { $0.eventNames }
    }
}

// MARK: - Error Event Accessors

public extension MockStructuredAnalytics {
    /// All captured error events.
    var errorEvents: [ErrorEvent] {
        typedEvents(ofType: ErrorEvent.self)
    }
}

// MARK: - Playback Event Accessors (Extension for Playback module tests)

public extension MockStructuredAnalytics {
    /// Represents a started event for testing.
    struct StartedEventProxy {
        public let reason: String
        /// The clean, low-cardinality attribution surface (#668), e.g. `"carPlay"` / `"siri"`.
        public let source: String?
        /// The listening-session id (#665) carried by the event, if any.
        public let sessionID: String?
    }

    /// Represents a stopped event for testing.
    struct StoppedEventProxy {
        public let reason: String?
        /// The clean, low-cardinality attribution surface (#668), e.g. `"remote"` / `"auto"`.
        public let source: String?
        public let duration: TimeInterval
        /// The listening-session id (#665) carried by the event, if any.
        public let sessionID: String?
    }

    /// All playback started events (events named "play").
    var startedEvents: [StartedEventProxy] {
        events(named: "play")
            .compactMap { event -> StartedEventProxy? in
                guard let props = event.properties,
                      let reason = props["reason"] as? String else { return nil }
                let source = props["source"] as? String
                let sessionID = props["session_id"] as? String
                return StartedEventProxy(reason: reason, source: source, sessionID: sessionID)
            }
    }

    /// All playback stopped events (events named "pause").
    var stoppedEvents: [StoppedEventProxy] {
        events(named: "pause")
            .compactMap { event -> StoppedEventProxy? in
                guard let props = event.properties,
                      let duration = props["duration"] as? TimeInterval else { return nil }
                let reason = props["reason"] as? String
                let source = props["source"] as? String
                let sessionID = props["session_id"] as? String
                return StoppedEventProxy(reason: reason, source: source, duration: duration, sessionID: sessionID)
            }
    }

    // MARK: - CPU Session Event Accessors (Extension for MP3Streamer tests)

    /// Represents a CPU session event for testing.
    struct CPUSessionEventProxy {
        public let playerType: String
        public let averageCPU: Double
        public let maxCPU: Double
        public let sampleCount: Int
        public let durationSeconds: TimeInterval
        public let context: String
        public let endReason: String
    }

    /// All CPU session events (events named "cpu_session").
    var cpuSessionEvents: [CPUSessionEventProxy] {
        events(named: "cpu_session")
            .compactMap { event -> CPUSessionEventProxy? in
                guard let props = event.properties,
                      let playerType = props["player_type"] as? String,
                      let averageCPU = props["average_cpu"] as? Double,
                      let maxCPU = props["max_cpu"] as? Double,
                      let sampleCount = props["sample_count"] as? Int,
                      let durationSeconds = props["duration_seconds"] as? TimeInterval,
                      let context = props["context"] as? String,
                      let endReason = props["end_reason"] as? String
                else { return nil }
                return CPUSessionEventProxy(
                    playerType: playerType,
                    averageCPU: averageCPU,
                    maxCPU: maxCPU,
                    sampleCount: sampleCount,
                    durationSeconds: durationSeconds,
                    context: context,
                    endReason: endReason
                )
            }
    }
}
