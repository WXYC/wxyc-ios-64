//
//  PlaybackMetricsTests.swift
//  Playback
//
//  Tests for playback metrics collection.
//
//  Created by Jake Bromberg on 12/11/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Testing
import PlaybackTestUtilities
import Foundation
import AVFoundation
import Analytics
import AnalyticsTesting
@testable import Playback
@testable import PlaybackCore

@Suite("PlaybackMetrics Tests")
struct PlaybackMetricsTests {

    // MARK: - CPU Usage

    @Test("CPUUsageEvent captures player type and usage")
    @MainActor
    func cpuUsageEvent() async throws {
        let analytics = MockStructuredAnalytics()
        let event = CPUUsageEvent(playerType: .radioPlayer, cpuUsage: 12.5)

        analytics.capture(event)

        let cpuEvents = analytics.events.compactMap { $0 as? CPUUsageEvent }
        #expect(cpuEvents.count == 1)
        #expect(cpuEvents.first?.playerType == .radioPlayer)
        #expect(cpuEvents.first?.cpuUsage == 12.5)
    }
}
