//
//  MockStructuredAnalytics.swift
//  AnalyticsTesting
//
//  Test double for AnalyticsService that records captured events for verification
//  in unit tests without sending data to a real analytics backend.
//
//  Created by Auto-Agent on 01/24/25.
//

import Analytics
import Foundation

public final class MockStructuredAnalytics: AnalyticsService, @unchecked Sendable {
    public private(set) var events: [AnalyticsEvent] = []
    
    public init() {}
    
    public func capture(_ event: AnalyticsEvent) {
        events.append(event)
    }
    
    public func reset() {
        events.removeAll()
    }
    
    // MARK: - Convenience Accessors

    /// All events with the given name.
    public func events(named name: String) -> [AnalyticsEvent] {
        events.filter { $0.name == name }
    }

    /// Filtered events of a specific type.
    public func typedEvents<T: AnalyticsEvent>(ofType: T.Type) -> [T] {
        events.compactMap { $0 as? T }
    }

    /// All captured event names (for filtering by name pattern).
    public func capturedEventNames() -> [String] {
        events.map { $0.name }
    }
}

// MARK: - Playback Event Accessors (Extension for Playback module tests)

public extension MockStructuredAnalytics {
    /// Represents a started event for testing.
    struct StartedEventProxy {
        public let reason: String
    }

    /// Represents a stopped event for testing.
    struct StoppedEventProxy {
        public let reason: String?
        public let duration: TimeInterval
    }

    /// All playback started events (events named "play").
    var startedEvents: [StartedEventProxy] {
        events
            .filter { $0.name == "play" }
            .compactMap { event -> StartedEventProxy? in
                guard let props = event.properties,
                      let reason = props["reason"] as? String else { return nil }
                return StartedEventProxy(reason: reason)
            }
    }

    /// All playback stopped events (events named "pause").
    var stoppedEvents: [StoppedEventProxy] {
        events
            .filter { $0.name == "pause" }
            .compactMap { event -> StoppedEventProxy? in
                guard let props = event.properties,
                      let duration = props["duration"] as? TimeInterval else { return nil }
                let reason = props["reason"] as? String
                return StoppedEventProxy(reason: reason, duration: duration)
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
        events
            .filter { $0.name == "cpu_session" }
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
