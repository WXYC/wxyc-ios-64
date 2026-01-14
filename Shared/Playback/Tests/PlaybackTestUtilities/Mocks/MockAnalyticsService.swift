//
//  MockAnalyticsService.swift
//  Playback
//
//  Mock implementation of AnalyticsService for testing.
//
//  Created by Jake Bromberg on 01/13/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Analytics

/// Mock implementation of AnalyticsService that captures events for verification in tests.
public final class MockAnalyticsService: AnalyticsService, @unchecked Sendable {
    private let lock = NSLock()
    private var _capturedEvents: [EventCapture] = []

    public init() {}

    public func capture(_ event: String, properties: [String: Any]?) {
        lock.lock()
        defer { lock.unlock() }
        _capturedEvents.append(EventCapture(event: event, properties: properties))
    }

    // MARK: - Test Helpers

    public var capturedEvents: [EventCapture] {
        lock.lock()
        defer { lock.unlock() }
        return _capturedEvents
    }

    public func capturedEventNames() -> [String] {
        capturedEvents.map(\.event)
    }

    public func capturedEvent(named name: String) -> EventCapture? {
        capturedEvents.first { $0.event == name }
    }

    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        _capturedEvents.removeAll()
    }

    // MARK: - Event Capture

    public struct EventCapture {
        public let event: String
        public let properties: [String: Any]?

        public init(event: String, properties: [String: Any]?) {
            self.event = event
            self.properties = properties
        }
    }
}
