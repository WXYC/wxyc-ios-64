//
//  VisualizerRefreshRateTests.swift
//  PlayerHeaderView
//
//  Tests for the high-refresh-rate opt-in: the persisted `highRefreshRateEnabled`
//  setting and the TimelineView interval it selects for a given display.
//
//  Created by Jake Bromberg on 09/10/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import Caching
@testable import PlayerHeaderView

@Suite("Visualizer refresh rate")
struct VisualizerRefreshRateTests {

    // MARK: - Persisted setting

    @Test("High refresh rate is off by default")
    func defaultsToOff() {
        let dataSource = VisualizerDataSource(defaults: InMemoryDefaults())
        #expect(dataSource.highRefreshRateEnabled == false)
    }

    @Test("Enabling high refresh rate writes through to storage")
    func persistsWhenEnabled() {
        let defaults = InMemoryDefaults()
        let dataSource = VisualizerDataSource(defaults: defaults)

        dataSource.highRefreshRateEnabled = true

        #expect(defaults.bool(forKey: "visualizer.highRefreshRateEnabled") == true)
    }

    @Test("High refresh rate restores from storage on init")
    func restoresFromStorage() {
        let defaults = InMemoryDefaults()
        defaults.set(true, forKey: "visualizer.highRefreshRateEnabled")

        let dataSource = VisualizerDataSource(defaults: defaults)

        #expect(dataSource.highRefreshRateEnabled == true)
    }

    @Test("Reset clears the high refresh rate opt-in")
    func resetClearsOptIn() {
        let dataSource = VisualizerDataSource(defaults: InMemoryDefaults())
        dataSource.highRefreshRateEnabled = true

        dataSource.reset()

        #expect(dataSource.highRefreshRateEnabled == false)
    }

    // MARK: - Interval selection

    @Test("Disabled pins the timeline to 60 FPS regardless of the display", arguments: [60, 120, 144])
    func disabledPinsTo60(displayMax: Int) {
        let interval = VisualizerRefreshRate.minimumInterval(
            highRefreshRateEnabled: false,
            displayMaximumFramesPerSecond: displayMax
        )
        #expect(abs(interval - 1.0 / 60.0) < 1e-9)
    }

    @Test("Enabled asks for the display maximum on a ProMotion display")
    func enabledUsesDisplayMaximum() {
        let interval = VisualizerRefreshRate.minimumInterval(
            highRefreshRateEnabled: true,
            displayMaximumFramesPerSecond: 120
        )
        #expect(abs(interval - 1.0 / 120.0) < 1e-9)
    }

    @Test("Enabled never asks for less than 60 FPS on a 60 Hz display", arguments: [24, 30, 60])
    func enabledNeverSlowerThan60(displayMax: Int) {
        let interval = VisualizerRefreshRate.minimumInterval(
            highRefreshRateEnabled: true,
            displayMaximumFramesPerSecond: displayMax
        )
        #expect(abs(interval - 1.0 / 60.0) < 1e-9)
    }
}
