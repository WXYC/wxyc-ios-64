//
//  MockPlaybackAnalytics.swift
//  Playback
//
//  Mock implementation of PlaybackAnalytics for testing.
//
//  Created by Jake Bromberg on 12/26/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Foundation
@testable import Playback

/// Mock implementation of PlaybackAnalytics that captures events for verification in tests.
@MainActor
public final class MockPlaybackAnalytics: PlaybackAnalytics {

    // MARK: - Captured Events

    public private(set) var startedEvents: [PlaybackStartedEvent] = []
    public private(set) var stoppedEvents: [PlaybackStoppedEvent] = []
    public private(set) var stallRecoveryEvents: [StallRecoveryEvent] = []
    public private(set) var interruptionEvents: [InterruptionEvent] = []
    public private(set) var errorEvents: [ErrorEvent] = []
    public private(set) var cpuUsageEvents: [CPUUsageEvent] = []
    public private(set) var cpuSessionEvents: [CPUSessionEvent] = []

    // MARK: - Initialization

    public init() {}

    // MARK: - PlaybackAnalytics

    public func capture(_ event: PlaybackStartedEvent) {
        startedEvents.append(event)
    }

    public func capture(_ event: PlaybackStoppedEvent) {
        stoppedEvents.append(event)
    }

    public func capture(_ event: StallRecoveryEvent) {
        stallRecoveryEvents.append(event)
    }

    public func capture(_ event: InterruptionEvent) {
        interruptionEvents.append(event)
    }

    public func capture(_ event: ErrorEvent) {
        errorEvents.append(event)
    }

    public func capture(_ event: CPUUsageEvent) {
        cpuUsageEvents.append(event)
    }

    public func capture(_ event: CPUSessionEvent) {
        cpuSessionEvents.append(event)
    }

    // MARK: - Test Helpers

    public func reset() {
        startedEvents.removeAll()
        stoppedEvents.removeAll()
        stallRecoveryEvents.removeAll()
        interruptionEvents.removeAll()
        errorEvents.removeAll()
        cpuUsageEvents.removeAll()
        cpuSessionEvents.removeAll()
    }
}
